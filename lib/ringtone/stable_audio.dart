import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../browser/chromium_browser.dart';
import 'ringtone_engine.dart';
import 'stable_audio_rotator.dart';

/// Stable Audio "Wizard" sessions API client — the audio renderer
/// behind the workflow's Ringtone Studio. Supports both the user's own
/// Stable Audio token (with WorkOS refresh) and automatic 50-credit
/// account rotation on desktop, matching the workflow.
class StableAudioStore {
  static const _store = FlutterSecureStorage();
  static const _kToken = 'stable_audio_token';
  static const _kRefresh = 'stable_audio_refresh_token';
  static const _kClientId = 'stable_audio_workos_client_id';
  static const _kAutoRotate = 'stable_audio_auto_rotate';
  static const _kDevice = 'stable_audio_device_id';

  static Future<String> token() async =>
      (await _store.read(key: _kToken))?.trim() ?? '';
  static Future<String> refreshToken() async =>
      (await _store.read(key: _kRefresh))?.trim() ?? '';
  static Future<String> workosClientId() async =>
      (await _store.read(key: _kClientId))?.trim() ?? '';
  static Future<bool> autoRotate() async {
    final v = (await _store.read(key: _kAutoRotate))?.trim();
    if (v == null || v.isEmpty) return ChromiumBrowser.supported;
    return v == 'true';
  }

  static Future<void> save({
    String? token,
    String? refreshToken,
    String? workosClientId,
    bool? autoRotate,
  }) async {
    if (token != null) await _store.write(key: _kToken, value: token.trim());
    if (refreshToken != null) {
      await _store.write(key: _kRefresh, value: refreshToken.trim());
    }
    if (workosClientId != null) {
      await _store.write(key: _kClientId, value: workosClientId.trim());
    }
    if (autoRotate != null) {
      await _store.write(key: _kAutoRotate, value: autoRotate ? 'true' : 'false');
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

/// Decodes the `exp` claim (Unix seconds) from a JWT, or null if unreadable.
int? getJwtExpSeconds(String jwt) {
  try {
    final parts = jwt.trim().split('.');
    if (parts.length != 3) return null;
    final normalized = base64Url.normalize(parts[1]);
    final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (payload is Map && payload['exp'] is num) {
      return (payload['exp'] as num).toInt();
    }
    return null;
  } catch (_) {
    return null;
  }
}

class StableAudioApi {
  static const _sessions = 'https://sessions-api.stableaudio.com/agents/wizard';
  static const _defaultWorkosClientId = 'client_01M5FKRSSZMYNTGJZ7SF9WXKH6';

  String _token;
  final String _deviceId;
  StableAudioApi(this._token, this._deviceId);

  static Future<StableAudioApi> load() async => StableAudioApi(
      await StableAudioStore.token(), await StableAudioStore.deviceId());

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
  /// (keeping the same 50-credit account). Returns true on success.
  Future<bool> refresh() async {
    final rt = await StableAudioStore.refreshToken();
    if (rt.isEmpty) return false;
    final savedClientId = await StableAudioStore.workosClientId();
    final clientId =
        savedClientId.isNotEmpty ? savedClientId : _defaultWorkosClientId;
    try {
      final resp = await http
          .post(
            Uri.parse(
                'https://api.workos.com/user_management/authenticate'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'refresh_token',
              'client_id': clientId,
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

  /// Auto-creates a fresh 50-credit Stable Audio account and persists its
  /// token & refresh token, returning the new account details.
  Future<RotatedStableAudioAccount> rotateAccount({
    String? preferredBrowser,
    void Function(String status)? onStatus,
  }) async {
    final acc = await createStableAudioAccount(
      preferredBrowser: preferredBrowser,
      onStatus: onStatus,
    );
    _token = acc.token;
    await StableAudioStore.save(
      token: acc.token,
      refreshToken: acc.refreshToken,
      workosClientId: acc.workosClientId,
    );
    return acc;
  }

  /// Ensures a non-expired token and sufficient credits (~4 credits per take)
  /// before starting a compose job, mirroring `ensureStableAudioTokenAndCredits`.
  Future<void> ensureTokenAndCredits(
    int takesCount, {
    bool autoRotate = true,
    String? preferredBrowser,
    void Function(String status)? onStatus,
  }) async {
    final exp = getJwtExpSeconds(_token);
    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000;
    if (_token.isNotEmpty && exp != null && nowSec >= (exp - 45)) {
      onStatus?.call('Refreshing Stable Audio token…');
      final refreshed = await refresh();
      if (!refreshed) {
        if (!autoRotate) {
          throw StableAudioException(
            'Stable Audio token expired and refresh failed.',
            auth: true,
          );
        }
        onStatus?.call('Token expired — rotating Stable Audio account…');
        await rotateAccount(
          preferredBrowser: preferredBrowser,
          onStatus: onStatus,
        );
      }
    }
    if (_token.isEmpty) {
      if (!autoRotate) {
        throw StableAudioException(
          'No Stable Audio token configured.',
          auth: true,
        );
      }
      onStatus?.call('No token — auto-creating Stable Audio account…');
      await rotateAccount(
        preferredBrowser: preferredBrowser,
        onStatus: onStatus,
      );
    }

    final neededCredits = max(4, takesCount * 4);
    final bal = await balance();
    if (bal != null && bal.remaining < neededCredits) {
      if (!autoRotate) {
        throw StableAudioException(
          'Stable Audio credits low (${bal.remaining}/${bal.total} < $neededCredits).',
          quota: true,
        );
      }
      onStatus?.call(
          'Credits low (${bal.remaining}/${bal.total} < $neededCredits) — rotating account…');
      await rotateAccount(
        preferredBrowser: preferredBrowser,
        onStatus: onStatus,
      );
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
      final rem = (data['generations_limit'] as num?)?.toInt();
      final tot = (data['credits_per_period'] as num?)?.toInt() ?? 50;
      if (rem == null) return null;
      return (remaining: rem, total: tot);
    } catch (_) {
      return null;
    }
  }

  Future<T> _withAuthRetry<T>(
    Future<T> Function() fn, {
    bool autoRotate = true,
    String? preferredBrowser,
    void Function(String status)? onStatus,
  }) async {
    try {
      return await fn();
    } on StableAudioException catch (e) {
      if (e.auth) {
        if (await refresh()) return await fn();
        if (autoRotate) {
          onStatus?.call('Auth error — rotating Stable Audio account…');
          await rotateAccount(
            preferredBrowser: preferredBrowser,
            onStatus: onStatus,
          );
          return await fn();
        }
      } else if (e.quota && autoRotate) {
        onStatus?.call('Credits/quota exhausted — rotating Stable Audio account…');
        await rotateAccount(
          preferredBrowser: preferredBrowser,
          onStatus: onStatus,
        );
        return await fn();
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
    bool autoRotate = true,
    String? preferredBrowser,
    void Function(String status)? onStatus,
  }) async {
    await ensureTokenAndCredits(
      s.takesCount,
      autoRotate: autoRotate,
      preferredBrowser: preferredBrowser,
      onStatus: onStatus,
    );
    return _withAuthRetry(
      () async {
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
    },
        autoRotate: autoRotate,
        preferredBrowser: preferredBrowser,
        onStatus: onStatus);
  }

  void _throwIfBad(http.Response resp, String what) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    final body = resp.body.length > 200
        ? resp.body.substring(0, 200)
        : resp.body;
    final auth = resp.statusCode == 401 || resp.statusCode == 403;
    final quota = resp.statusCode == 402 ||
        resp.statusCode == 429 ||
        (resp.statusCode == 400 &&
            RegExp(r'quota|credit|insufficient', caseSensitive: false)
                .hasMatch(resp.body));
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
