import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'account_rotation.dart';
import 'ringtone_engine.dart';

/// Legacy single-account token storage (v1.17). Kept so an existing
/// token can be migrated into the rotation pool and pre-filled in the
/// "Add account" dialog; new code uses [StableAudioPool].
class StableAudioStore {
  static const _store = FlutterSecureStorage();
  static const _kToken = 'stable_audio_token';
  static const _kRefresh = 'stable_audio_refresh_token';
  static const _kDevice = 'stable_audio_device_id';

  static Future<String> token() async =>
      (await _store.read(key: _kToken))?.trim() ?? '';
  static Future<String> refreshToken() async =>
      (await _store.read(key: _kRefresh))?.trim() ?? '';
  static Future<void> save({String? token, String? refreshToken}) async {
    if (token != null) await _store.write(key: _kToken, value: token.trim());
    if (refreshToken != null) {
      await _store.write(key: _kRefresh, value: refreshToken.trim());
    }
  }

  static Future<String> deviceId() async {
    var id = (await _store.read(key: _kDevice))?.trim() ?? '';
    if (id.isEmpty) {
      final r = Random.secure();
      String hex(int n) =>
          List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
      id = '${hex(8)}-${hex(4)}-4${hex(3)}-${['8', '9', 'a', 'b'][r.nextInt(4)]}${hex(3)}-${hex(12)}';
      await _store.write(key: _kDevice, value: id);
    }
    return id;
  }
}

class StableAudioException implements Exception {
  final String message;
  final bool auth; // 401/403 — token expired or invalid
  final bool quota; // 402/429/quota 400
  StableAudioException(this.message, {this.auth = false, this.quota = false});
  @override
  String toString() => message;
}

/// Stable Audio "Wizard" sessions API client — the audio renderer
/// behind the workflow's Ringtone Studio.
///
/// A token alone is enough to render, but a real session needs
/// rotation: every Stable Audio account only gets 50 credits, so the
/// workflow kept swapping accounts when the credits ran out or the JWT
/// was rejected. [StableAudioRotator] owns that pool; bind it with
/// [bindRotator] and this client refreshes / rotates / retries by
/// itself instead of failing the take.
class StableAudioApi {
  static const _sessions = 'https://sessions-api.stableaudio.com/agents/wizard';
  static const _workosClientId = kStableAudioWorkosClientId;

  String _token;
  String _deviceId;

  /// Optional rotation pool. When set, 401/403 and quota failures are
  /// repaired here (refresh → rotate) and the request is retried once,
  /// exactly like `generateStableAudio` does in the workflow.
  StableAudioRotator? rotator;

  StableAudioApi(this._token, this._deviceId);

  static Future<StableAudioApi> load() async => StableAudioApi(
      await StableAudioStore.token(), await StableAudioStore.deviceId());

  /// Binds the account pool that repairs auth/quota failures.
  void bindRotator(StableAudioRotator? r) => rotator = r;

  /// Switches this client to [account] (token + its own device id).
  void useAccount(StableAudioAccount account) {
    _token = account.accessToken;
    if (account.deviceId.trim().isNotEmpty) _deviceId = account.deviceId;
  }

  String get token => _token;

  bool get hasToken => _token.isNotEmpty;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'x-client': 'web',
        'x-client-platform': 'chrome-158;windows',
        'x-client-timezone': 'Asia/Dhaka',
        'x-client-version': '02-09-2026',
        'x-device-id': _deviceId,
        'Content-Type': 'application/json',
      };

  /// Refreshes the access token with the stored WorkOS refresh token
  /// (the user's own account). Returns true on success.
  Future<bool> refresh() async {
    final rt = await StableAudioStore.refreshToken();
    if (rt.isEmpty) return false;
    try {
      final resp = await http
          .post(
            Uri.parse(
                'https://api.workos.com/user_management/authenticate'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'refresh_token',
              'client_id': _workosClientId,
              'refresh_token': rt,
            },
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return false;
      final data = jsonDecode(resp.body);
      final at = (data is Map ? data['access_token'] : null)?.toString() ?? '';
      final nrt = (data is Map ? data['refresh_token'] : null)?.toString();
      if (at.isEmpty) return false;
      _token = at;
      await StableAudioStore.save(
          token: at, refreshToken: nrt != null && nrt.isNotEmpty ? nrt : null);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Remaining/total generation credits, like the workflow's balance
  /// check. Returns null when it cannot be read.
  Future<({int remaining, int total})?> balance() async {
    try {
      final resp = await http
          .get(Uri.parse('https://api.stableaudio.com/v1alpha/user/balance'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      // The API nests the numbers under `attributes` (the workflow reads
      // `data.attributes.generations_limit`); older responses put them at
      // the root, so both are accepted.
      final attrs = data['attributes'] is Map
          ? Map<String, dynamic>.from(data['attributes'] as Map)
          : const <String, dynamic>{};
      final rem = (attrs['generations_limit'] as num?)?.toInt() ??
          (data['generations_limit'] as num?)?.toInt();
      final tot = (attrs['credits_per_period'] as num?)?.toInt() ??
          (data['credits_per_period'] as num?)?.toInt() ??
          50;
      if (rem == null) return null;
      return (remaining: rem, total: tot);
    } catch (_) {
      return null;
    }
  }

  /// Repairs an auth/quota failure through the rotation pool and retries
  /// the whole operation once. Without a pool it falls back to the old
  /// single-account WorkOS refresh.
  Future<T> _withAuthRetry<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on StableAudioException catch (e) {
      final pool = rotator;
      if (e.auth) {
        if (pool != null) {
          if (await pool.handleAuthFailure()) {
            final acc = pool.current;
            if (acc != null) useAccount(acc);
            return await fn();
          }
        } else if (await refresh()) {
          return await fn();
        }
        rethrow;
      }
      if (e.quota) {
        if (pool != null && await pool.handleQuotaFailure()) {
          final acc = pool.current;
          if (acc != null) useAccount(acc);
          return await fn();
        }
        rethrow;
      }
      rethrow;
    }
  }

  /// Starts one Wizard compose job with [takes] parallel stems and
  /// returns the raw stem WAV bytes in take order.
  Future<List<Uint8List>> compose({
    required String prompt,
    required RingtoneSettings s,
    required int baseSeed,
    void Function(String status)? onStatus,
  }) async {
    return _withAuthRetry(() async {
      final isOneShot = s.audioShape == 'oneshot';
      final reqDur = (s.audioShape == 'track' &&
              s.lengthSeconds >= 6 &&
              s.trimSilence)
          ? s.lengthSeconds + 1 // +1s trim buffer, like the workflow
          : s.lengthSeconds;
      final tracks = [
        for (var i = 0; i < s.takesCount; i++)
          {
            'generation_prompt': prompt,
            'seed': baseSeed + i,
            if (isOneShot) 'is_oneshot': true,
          }
      ];
      final bpmMatch = RegExp(r'(\d{2,3})\s*BPM').firstMatch(prompt);
      final plan = <String, dynamic>{
        'source': 'generate',
        'tracks': tracks,
        'time_signature': s.timeSignature,
        if (bpmMatch != null) 'tempo': int.parse(bpmMatch.group(1)!),
        if (s.musicalKey != 'Auto') 'key': s.musicalKey,
      };
      final body = {
        'plan': plan,
        'duration_per_stem': reqDur,
        'output_format': 'wav',
        'quality_preset': 'standard',
        'apply_mix': false,
        'generation_strategy': 'parallel_t2a',
      };
      onStatus?.call('Sending to Stable Audio…');
      final resp = await http
          .post(Uri.parse('$_sessions/compose-from-plan'),
              headers: {..._headers, 'idempotency-key': _uuid()},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 60));
      _throwIfBad(resp, 'compose');
      final data = jsonDecode(resp.body);
      final jobId = (data is Map
              ? (data['job_id'] ?? data['id'] ?? data['session_id'])
              : null)
          ?.toString();
      if (jobId == null || jobId.isEmpty) {
        throw StableAudioException(
            'Stable Audio compose returned no job id: ${resp.body.substring(0, min(200, resp.body.length))}');
      }
      // Poll status, then fetch the result.
      var done = false;
      for (var i = 0; i < 90 && !done; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final st = await http
            .get(Uri.parse('$_sessions/status/$jobId'), headers: _headers)
            .timeout(const Duration(seconds: 30));
        _throwIfBad(st, 'status');
        final sd = jsonDecode(st.body);
        final status =
            (sd is Map ? (sd['status'] ?? sd['state']) : null)?.toString() ??
                '';
        onStatus?.call('Stable Audio: $status');
        if (status == 'complete' ||
            status == 'completed' ||
            status == 'succeeded' ||
            status == 'done') {
          done = true;
        } else if (status == 'failed' || status == 'error') {
          throw StableAudioException('Stable Audio job failed ($status).');
        }
      }
      if (!done) {
        throw StableAudioException(
            'Stable Audio job timed out after ~3 minutes.');
      }
      final res = await http
          .get(Uri.parse('$_sessions/result/$jobId?include_audio=false'),
              headers: _headers)
          .timeout(const Duration(seconds: 60));
      _throwIfBad(res, 'result');
      final rd = jsonDecode(res.body);
      final stems = (rd is Map ? rd['stems'] : null);
      if (stems is! List || stems.isEmpty) {
        throw StableAudioException('Stable Audio returned no stems.');
      }
      final out = <Uint8List>[];
      for (final stem in stems) {
        if (stem is! Map) continue;
        final url = (stem['audio_url'] ?? stem['url'])?.toString();
        final name = (stem['name'] ?? stem['stem_name'] ?? stem['id'])
            ?.toString();
        Uint8List? bytes;
        if (url != null && url.isNotEmpty) {
          final d = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 120));
          if (d.statusCode >= 200 && d.statusCode < 300) bytes = d.bodyBytes;
        }
        if ((bytes == null || bytes.length <= 1000) && name != null) {
          final d = await http
              .get(Uri.parse('$_sessions/stems/$jobId/$name'),
                  headers: _headers)
              .timeout(const Duration(seconds: 120));
          _throwIfBad(d, 'stem download');
          bytes = d.bodyBytes;
        }
        if (bytes != null && bytes.length > 1000) out.add(bytes);
      }
      if (out.isEmpty) {
        throw StableAudioException('Stable Audio stems could not be downloaded.');
      }
      return out;
    });
  }

  void _throwIfBad(http.Response resp, String what) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    final body = resp.body.length > 200
        ? resp.body.substring(0, 200)
        : resp.body;
    // Same classification as the workflow's generateStableAudio: 401/403
    // (or a token complaint) means rotate/refresh, 402/429 or a
    // limit/quota/credit 400 means the 50 credits are gone.
    final lower = resp.body.toLowerCase();
    final auth = resp.statusCode == 401 ||
        resp.statusCode == 403 ||
        lower.contains('unable to verify user token');
    final quota = resp.statusCode == 402 ||
        resp.statusCode == 429 ||
        (resp.statusCode == 400 &&
            RegExp(r'quota|credit|limit|rate|exceeded|insufficient')
                .hasMatch(lower));
    throw StableAudioException(
        'Stable Audio $what failed (HTTP ${resp.statusCode}): $body',
        auth: auth,
        quota: quota);
  }

  static String _uuid() {
    final r = Random.secure();
    String hex(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${['8', '9', 'a', 'b'][r.nextInt(4)]}${hex(3)}-${hex(12)}';
  }
}

/// Per-account randomized file naming, ported from the workflow's
/// generateFilename (title is deliberately NOT used for the R2 name).
String ringtoneFileName(String accountName, Random rng) {
  String pick(List<String> xs) => xs[rng.nextInt(xs.length)];
  switch (accountName) {
    case 'zedge_1':
      const rows = ['asdf', 'qwer', 'hjkl', 'zxcv', 'uiop', 'tyui', 'ghjk', 'bnm', 'poi', 'lkj'];
      return '${pick(rows)}${pick(rows)}${rng.nextInt(999)}.mp3';
    case 'zedge_2':
      return '${pick(['my', 'cool', 'new', 'best', 'fav', 'top', 'great', 'nice', 'saved', 'ringtone', 'tone', 'sound', 'audio'])}_'
          '${pick(['ring', 'tone', 'beat', 'track', 'song', 'clip', 'tune', 'sound', 'mix', 'edit'])}_'
          '${pick(['v1', 'v2', 'final', 'new', 'copy', 'edit', '2', '3', '1', 'hd'])}.mp3';
    case 'zedge_3':
      return 'audio_${10000 + rng.nextInt(90000)}.mp3';
    case 'zedge_4':
      return '${pick(['Ringtone', 'Tone', 'Sound', 'Alarm', 'Notification', 'Melody', 'Beat', 'Loop', 'Alert', 'Chime'])}-'
          '${pick(['HD', 'New', 'Best', 'Original', 'Clean'])}-${1 + rng.nextInt(99)}.mp3';
    default:
      return 'tone_${DateTime.now().millisecondsSinceEpoch}.mp3';
  }
}
