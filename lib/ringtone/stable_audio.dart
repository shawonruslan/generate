import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'ringtone_models.dart';

/// Why a Stable Audio call failed, so the studio can say what to do.
enum StableAudioFailure { auth, credits, job, network, other }

class StableAudioException implements Exception {
  final String message;
  final StableAudioFailure kind;
  const StableAudioException(this.message,
      [this.kind = StableAudioFailure.other]);
  @override
  String toString() => message;
}

/// The account tokens (the workflow's currentToken / currentRefreshToken
/// / currentWorkosClientId / STABLE_AUDIO_DEVICE_ID).
class StableAudioAuth {
  String accessToken;
  String refreshToken;
  String clientId;
  String deviceId;

  StableAudioAuth({
    this.accessToken = '',
    this.refreshToken = '',
    this.clientId = StableAudioClient.defaultClientId,
    this.deviceId = '',
  });

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'clientId': clientId,
        'deviceId': deviceId,
      };

  static StableAudioAuth fromJson(Map<String, dynamic> m) => StableAudioAuth(
        accessToken: (m['accessToken'] ?? '').toString(),
        refreshToken: (m['refreshToken'] ?? '').toString(),
        clientId: (m['clientId'] ?? '').toString().isEmpty
            ? StableAudioClient.defaultClientId
            : m['clientId'].toString(),
        deviceId: (m['deviceId'] ?? '').toString(),
      );
}

/// Where the tokens are kept. The app uses the OS secure storage; tests
/// use [MemoryStableAudioStore].
abstract class StableAudioTokenStore {
  Future<StableAudioAuth> load();
  Future<void> save(StableAudioAuth auth);
}

class SecureStableAudioStore implements StableAudioTokenStore {
  const SecureStableAudioStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'stable_audio_auth_v1';

  @override
  Future<StableAudioAuth> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return StableAudioAuth();
      return StableAudioAuth.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return StableAudioAuth();
    }
  }

  @override
  Future<void> save(StableAudioAuth auth) =>
      _storage.write(key: _key, value: jsonEncode(auth.toJson()));
}

class MemoryStableAudioStore implements StableAudioTokenStore {
  StableAudioAuth auth;
  MemoryStableAudioStore([StableAudioAuth? auth])
      : auth = auth ?? StableAudioAuth();
  @override
  Future<StableAudioAuth> load() async => auth;
  @override
  Future<void> save(StableAudioAuth a) async => auth = a;
}

class StableAudioCredits {
  final int remaining;
  final int total;
  const StableAudioCredits(this.remaining, this.total);
}

class StableAudioJob {
  final String jobId;
  final int baseSeed;
  final String finalPrompt;
  final int takesCount;
  final int durSec;
  final int requestDurSec;
  const StableAudioJob({
    required this.jobId,
    required this.baseSeed,
    required this.finalPrompt,
    required this.takesCount,
    required this.durSec,
    required this.requestDurSec,
  });
}

class StableAudioStem {
  final String name;
  final String audioUrl;
  final double? durationSeconds;
  final int? seed;
  const StableAudioStem(
      {required this.name, this.audioUrl = '', this.durationSeconds, this.seed});

  static StableAudioStem fromJson(Map<String, dynamic> m, int index) {
    final gs = m['generation_settings'];
    final seed = gs is Map ? gs['seed'] : null;
    final dur = m['duration_seconds'];
    final name = (m['name'] ?? '').toString();
    return StableAudioStem(
      name: name.isEmpty ? 'item-$index' : name,
      audioUrl: (m['audio_url'] ?? '').toString(),
      durationSeconds: dur is num ? dur.toDouble() : null,
      seed: seed is num ? seed.toInt() : null,
    );
  }
}

/// Stable Audio "Wizard" client - the same calls the workflow makes
/// (generator.yml: refreshStableAudioToken, fetchStableAudioCredits,
/// buildWizardHeaders, buildStableAudioPrompt, generateStableAudio,
/// pollStableAudioResult, downloadStableAudioStem).
///
/// One difference, on purpose: the workflow signs up a new throw-away
/// account whenever a token dies or credits run low. The app never
/// creates accounts - it works with the account the user connected and
/// says plainly when that account needs a new sign-in or more credits.
class StableAudioClient {
  static const defaultClientId = 'client_01M5FKRSSZMYNTGJZ7SF9WXKH6';
  static const wizardBase = 'https://sessions-api.stableaudio.com/agents/wizard';
  static const _balanceUrl = 'https://api.stableaudio.com/v1alpha/user/balance';
  static const _workosUrl = 'https://api.workos.com/user_management/authenticate';

  final http.Client _http;
  final StableAudioTokenStore _store;
  final Duration pollInterval;
  final int maxPolls;
  final Random _rnd;
  final String timezone;

  StableAudioClient({
    http.Client? httpClient,
    StableAudioTokenStore? store,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPolls = 90,
    Random? random,
    this.timezone = 'Asia/Dhaka',
  })  : _http = httpClient ?? http.Client(),
        _store = store ?? const SecureStableAudioStore(),
        _rnd = random ?? Random();

  StableAudioAuth _auth = StableAudioAuth();
  bool _loaded = false;
  StableAudioCredits? credits;

  /// Lines for the studio log.
  void Function(String line)? onLog;
  void _log(String s) => onLog?.call(s);

  bool get hasToken => _auth.accessToken.isNotEmpty;
  bool get hasRefreshToken => _auth.refreshToken.isNotEmpty;
  String get accessToken => _auth.accessToken;

  Future<void> load() async {
    if (_loaded) return;
    _auth = await _store.load();
    if (_auth.deviceId.isEmpty) {
      _auth.deviceId = uuid(_rnd);
      if (_auth.accessToken.isNotEmpty) await _store.save(_auth);
    }
    _loaded = true;
  }

  /// RFC 4122 v4.
  static String uuid(Random r) {
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  static final _jwt = RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');

  /// Reads what the user pasted: a bare token, `Bearer <token>`, an
  /// `Authorization: Bearer ...` header line, or the JSON of the
  /// sign-in response (`access_token` + `refresh_token`).
  static ({String access, String refresh}) parsePasted(String raw) {
    final text = raw.trim();
    var access = '';
    var refresh = '';
    if (text.startsWith('{')) {
      try {
        final m = jsonDecode(text);
        if (m is Map) {
          access = (m['access_token'] ?? m['accessToken'] ?? '').toString();
          refresh = (m['refresh_token'] ?? m['refreshToken'] ?? '').toString();
        }
      } catch (_) {}
    }
    if (access.isEmpty) {
      access = _jwt.firstMatch(text)?.group(0) ?? '';
    }
    return (access: access.trim(), refresh: refresh.trim());
  }

  Future<void> setTokens({String? accessToken, String? refreshToken}) async {
    await load();
    if (accessToken != null) _auth.accessToken = accessToken.trim();
    if (refreshToken != null) _auth.refreshToken = refreshToken.trim();
    credits = null;
    await _store.save(_auth);
  }

  Future<void> disconnect() async {
    await load();
    _auth.accessToken = '';
    _auth.refreshToken = '';
    credits = null;
    await _store.save(_auth);
  }

  /// `exp` (epoch seconds) of a JWT, null when it is not a JWT.
  static int? jwtExpSeconds(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map ? payload['exp'] : null;
      return exp is num ? exp.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  /// When the saved access token stops working (null = unknown).
  DateTime? get tokenExpiry {
    final exp = jwtExpSeconds(_auth.accessToken);
    return exp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  }

  bool get tokenExpired {
    final exp = jwtExpSeconds(_auth.accessToken);
    return exp != null &&
        DateTime.now().millisecondsSinceEpoch / 1000 >= exp - 45;
  }

  static const _origin = {
    'Origin': 'https://stableaudio.com',
    'Referer': 'https://stableaudio.com/',
  };

  Future<http.Response> _send(Future<http.Response> Function() f,
      Duration timeout, String what) async {
    try {
      return await f().timeout(timeout);
    } on TimeoutException {
      throw StableAudioException(
          '$what timed out. Check the internet connection.',
          StableAudioFailure.network);
    } on StableAudioException {
      rethrow;
    } catch (e) {
      throw StableAudioException(
          'Network error ($what): $e', StableAudioFailure.network);
    }
  }

  /// Swaps the refresh token for a new access token (same account).
  Future<bool> refreshToken() async {
    await load();
    if (_auth.refreshToken.isEmpty) return false;
    try {
      final res = await _http
          .post(Uri.parse(_workosUrl),
              headers: {
                'Accept': 'application/json, text/plain, */*',
                'Content-Type': 'application/json',
                ..._origin,
              },
              body: jsonEncode({
                'client_id': _auth.clientId.isEmpty
                    ? defaultClientId
                    : _auth.clientId,
                'grant_type': 'refresh_token',
                'refresh_token': _auth.refreshToken,
              }))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _log('Stable Audio token refresh failed (HTTP ${res.statusCode}).');
        return false;
      }
      final data = jsonDecode(res.body);
      final at = data is Map ? (data['access_token'] ?? '').toString() : '';
      if (at.isEmpty) return false;
      _auth.accessToken = at;
      final rt = (data as Map)['refresh_token'];
      // Refresh tokens are single-use: keep the rotated one or the
      // next refresh fails.
      if (rt is String && rt.isNotEmpty) _auth.refreshToken = rt;
      await _store.save(_auth);
      _log('Stable Audio token refreshed.');
      return true;
    } catch (e) {
      _log('Stable Audio token refresh error: $e');
      return false;
    }
  }

  /// Remaining / total credits, null when they cannot be read.
  Future<StableAudioCredits?> fetchCredits() async {
    await load();
    if (!hasToken) return null;
    try {
      final res = await _http.get(Uri.parse(_balanceUrl), headers: {
        'Accept': '*/*',
        'Authorization': 'Bearer ${_auth.accessToken}',
        ..._origin,
      }).timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final data = jsonDecode(res.body);
      final attrs = data is Map ? data['attributes'] : null;
      if (attrs is! Map) return null;
      final remaining = attrs['generations_limit'];
      final total = attrs['credits_per_period'];
      if (remaining is! num) return null;
      return credits = StableAudioCredits(
          remaining.toInt(), total is num ? total.toInt() : 50);
    } catch (_) {
      return null;
    }
  }

  static const _connectHint =
      'Open Ringtone Studio > Stable Audio account and connect again.';

  /// Fresh token + enough credits for [takesCount] takes, or a clear
  /// error (workflow `ensureStableAudioTokenAndCredits`).
  Future<void> ensureReady(int takesCount) async {
    await load();
    if (!hasToken) {
      if (!await refreshToken()) {
        throw const StableAudioException(
            'No Stable Audio account connected. $_connectHint',
            StableAudioFailure.auth);
      }
    }
    if (tokenExpired) {
      if (!await refreshToken()) {
        throw StableAudioException(
            hasRefreshToken
                ? 'The Stable Audio sign-in expired and could not be renewed. $_connectHint'
                : 'The Stable Audio access token expired (it only lasts a few minutes) and no refresh token is saved to renew it. $_connectHint',
            StableAudioFailure.auth);
      }
    }
    final needed = max(4, takesCount * 4);
    final bal = await fetchCredits();
    if (bal != null) {
      _log('Stable Audio credits: ${bal.remaining}/${bal.total} '
          '(need about $needed for $takesCount take${takesCount == 1 ? '' : 's'}).');
      if (bal.remaining < needed) {
        throw StableAudioException(
            'Not enough Stable Audio credits: ${bal.remaining} left, about $needed needed for $takesCount take${takesCount == 1 ? '' : 's'}. '
            'Lower "Takes", wait for the credits to renew, or connect another account.',
            StableAudioFailure.credits);
      }
    }
  }

  Map<String, String> wizardHeaders([Map<String, String> extra = const {}]) => {
        'Accept': '*/*',
        'Authorization': 'Bearer ${_auth.accessToken}',
        ..._origin,
        'x-client': 'web',
        'x-client-platform': 'chrome-158;windows',
        'x-client-timezone': timezone,
        'x-client-version': '02-09-2026',
        'x-device-id': _auth.deviceId,
        ...extra,
      };

  static int? explicitBpm(int bpm) => (bpm >= 40 && bpm <= 240) ? bpm : null;

  /// The exact text rendered by Stable Audio (workflow
  /// `buildStableAudioPrompt`).
  static String buildPrompt(String basePrompt,
      {String shape = 'track', String musicalKey = 'Auto', int bpm = 0}) {
    var p = basePrompt.trim().replaceFirst(RegExp(r'\.+$'), '').trim();
    shape = shape.toLowerCase();
    final key = musicalKey.trim();
    final bpmNum = explicitBpm(bpm);
    if (bpmNum != null) {
      p = p
          .replaceAll(
              RegExp(r',?\s*(?:at\s+)?\b\d{2,3}\s*bpm\b', caseSensitive: false),
              '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .replaceAll(RegExp(r',\s*,'), ',')
          .trim();
      p += ', $bpmNum BPM';
    }
    if (shape != 'oneshot' &&
        !RegExp(r'continuous|full length', caseSensitive: false).hasMatch(p)) {
      p += ', continuous full-length music with no silence';
    }
    if (shape == 'loop' &&
        !RegExp(r'\bloop\b', caseSensitive: false).hasMatch(p)) {
      p += ', loop';
    } else if (shape == 'oneshot' &&
        !RegExp(r'\bone[- ]?shot\b', caseSensitive: false).hasMatch(p)) {
      p += ', one-shot';
    }
    if (key.isNotEmpty &&
        key != 'Auto' &&
        !RegExp('\\bin\\s+${RegExp.escape(key)}(?![A-Za-z0-9_#])',
                caseSensitive: false)
            .hasMatch(p)) {
      p += ', in $key';
    }
    return '$p.';
  }

  /// Seconds asked from the renderer: one spare second on tracks so the
  /// silence trim still leaves the full target length.
  static int requestSeconds(RingtoneConfig cfg) {
    final target = cfg.lengthSeconds.clamp(1, 60);
    return (cfg.trimSilence && cfg.audioShape == 'track' && target >= 6)
        ? min(60, target + 1)
        : target;
  }

  /// The compose-from-plan body for [prompt] under [cfg].
  Map<String, dynamic> buildPayload(
      String finalPrompt, RingtoneConfig cfg, int baseSeed) {
    final shape = cfg.audioShape.toLowerCase();
    final takes = cfg.takesCount.clamp(1, 4);
    final bpmNum = explicitBpm(cfg.bpm);
    final key = cfg.musicalKey.trim();
    final sig = cfg.timeSignature.trim().isEmpty ? '4/4' : cfg.timeSignature.trim();
    return {
      'plan': {
        'source': 'generate',
        'tracks': [
          for (var i = 0; i < takes; i++)
            {
              'generation_prompt': finalPrompt,
              'seed': baseSeed + i,
              if (shape == 'oneshot') 'is_oneshot': true,
            }
        ],
        'time_signature': sig,
        if (bpmNum != null) 'tempo': bpmNum,
        if (key.isNotEmpty && key != 'Auto') 'key': key,
      },
      'duration_per_stem': requestSeconds(cfg),
      'output_format': 'wav',
      'quality_preset': 'standard',
      'apply_mix': false,
      'generation_strategy': 'parallel_t2a',
    };
  }

  /// Starts a render of `cfg.takesCount` takes. Returns the job.
  Future<StableAudioJob> compose(String prompt, RingtoneConfig cfg,
      {bool isRetry = false, int? seedOverride}) async {
    final shape = cfg.audioShape.toLowerCase();
    final takes = cfg.takesCount.clamp(1, 4);
    final baseSeed = seedOverride ??
        (cfg.seed >= 0 ? cfg.seed : 100000000 + _rnd.nextInt(800000000));
    final finalPrompt = buildPrompt(prompt,
        shape: shape, musicalKey: cfg.musicalKey, bpm: cfg.bpm);
    final payload = buildPayload(finalPrompt, cfg, baseSeed);

    if (!isRetry) await ensureReady(takes);

    final res = await _send(
        () => _http.post(Uri.parse('$wizardBase/compose-from-plan'),
            headers: wizardHeaders({
              'Content-Type': 'application/json',
              'idempotency-key': uuid(_rnd),
            }),
            body: jsonEncode(payload)),
        const Duration(seconds: 60),
        'Starting the Stable Audio render');

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final err = res.body;
      final low = err.toLowerCase();
      final isLimit = res.statusCode == 429 ||
          res.statusCode == 402 ||
          (res.statusCode == 400 &&
              RegExp(r'limit|quota|credit|rate|exceeded|insufficient')
                  .hasMatch(low));
      final isAuth = !isLimit &&
          (res.statusCode == 401 ||
              res.statusCode == 403 ||
              low.contains('unauthorized') ||
              low.contains('unable to verify user token'));
      if (isAuth) {
        if (!isRetry && await refreshToken()) {
          // Same seed: the retry renders the takes the user asked for.
          return compose(prompt, cfg, isRetry: true, seedOverride: baseSeed);
        }
        throw StableAudioException(
            'Stable Audio rejected the sign-in (HTTP ${res.statusCode}). $_connectHint',
            StableAudioFailure.auth);
      }
      if (isLimit) {
        throw StableAudioException(
            'Stable Audio refused the render (HTTP ${res.statusCode}): out of credits or rate limited. '
            'Wait for the credits to renew or connect another account.'
            '${err.isEmpty ? '' : ' [${_cut(err, 160)}]'}',
            StableAudioFailure.credits);
      }
      throw StableAudioException(
          'Stable Audio error (HTTP ${res.statusCode}): ${_cut(err, 260)}');
    }

    dynamic data;
    try {
      data = jsonDecode(res.body);
    } catch (_) {}
    final jobId = data is Map ? (data['job_id'] ?? '').toString() : '';
    if (jobId.isEmpty) {
      throw StableAudioException(
          'Stable Audio returned no job id: ${_cut(res.body, 200)}');
    }
    return StableAudioJob(
      jobId: jobId,
      baseSeed: baseSeed,
      finalPrompt: finalPrompt,
      takesCount: takes,
      durSec: cfg.lengthSeconds.clamp(1, 60),
      requestDurSec: requestSeconds(cfg),
    );
  }

  static String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

  /// Waits for the render and returns its stems. [cancelled] is polled
  /// between status checks; a cancelled wait throws.
  Future<List<StableAudioStem>> waitForStems(String jobId,
      {bool Function()? cancelled,
      void Function(int done, int total)? onProgress}) async {
    final id = Uri.encodeComponent(jobId);
    var refreshed = false;
    for (var i = 0; i < maxPolls; i++) {
      if (cancelled?.call() ?? false) {
        throw const StableAudioException('Stopped.', StableAudioFailure.job);
      }
      // Long renders can outlive the short-lived access token.
      if (tokenExpired && !refreshed) {
        refreshed = true;
        await refreshToken();
      }
      final st = await _send(
          () => _http.get(Uri.parse('$wizardBase/status/$id'),
              headers: wizardHeaders({'Content-Type': 'application/json'})),
          const Duration(seconds: 30),
          'Checking the render');
      if (st.statusCode < 200 || st.statusCode >= 300) {
        if ((st.statusCode == 401 || st.statusCode == 403) &&
            !refreshed &&
            await refreshToken()) {
          refreshed = true;
          continue;
        }
        throw StableAudioException(
            'Render status check failed (HTTP ${st.statusCode}): ${_cut(st.body, 200)}',
            st.statusCode == 401 || st.statusCode == 403
                ? StableAudioFailure.auth
                : StableAudioFailure.job);
      }
      dynamic data;
      try {
        data = jsonDecode(st.body);
      } catch (_) {}
      final m = data is Map ? data : const {};
      final status = (m['status'] ?? '').toString().toLowerCase();
      final sc = m['stems_completed'], stt = m['stems_total'];
      if (sc is num && stt is num) onProgress?.call(sc.toInt(), stt.toInt());
      if (status == 'complete' || status == 'completed') break;
      if (status == 'failed' || status == 'error' || status == 'cancelled') {
        throw StableAudioException(
            'Stable Audio render failed: ${m['error'] ?? status}',
            StableAudioFailure.job);
      }
      if (i == maxPolls - 1) {
        throw StableAudioException(
            'Timed out waiting for the Stable Audio render '
            '(${(pollInterval.inMilliseconds * maxPolls / 60000).toStringAsFixed(0)} minutes).',
            StableAudioFailure.job);
      }
      await Future<void>.delayed(pollInterval);
    }

    final res = await _send(
        () => _http.get(
            Uri.parse('$wizardBase/result/$id?include_audio=false'),
            headers: wizardHeaders({'Content-Type': 'application/json'})),
        const Duration(seconds: 30),
        'Reading the render result');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StableAudioException(
          'Render result fetch failed (HTTP ${res.statusCode}): ${_cut(res.body, 200)}',
          StableAudioFailure.job);
    }
    dynamic data;
    try {
      data = jsonDecode(res.body);
    } catch (_) {}
    final raw = data is Map && data['stems'] is List ? data['stems'] as List : [];
    final stems = <StableAudioStem>[];
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] is Map) {
        stems.add(StableAudioStem.fromJson(
            (raw[i] as Map).cast<String, dynamic>(), i));
      }
    }
    if (stems.isEmpty) {
      throw const StableAudioException(
          'The Stable Audio render returned no audio.', StableAudioFailure.job);
    }
    unawaited(fetchCredits());
    return stems;
  }

  /// WAV bytes of one stem.
  Future<Uint8List> downloadStem(String jobId, StableAudioStem stem) async {
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(stem.audioUrl)) {
      try {
        final r = await _http.get(Uri.parse(stem.audioUrl), headers: {
          'Accept': 'audio/*, */*'
        }).timeout(const Duration(seconds: 60));
        if (r.statusCode >= 200 &&
            r.statusCode < 300 &&
            r.bodyBytes.length > 1000) {
          return r.bodyBytes;
        }
      } catch (_) {}
    }
    final url =
        '$wizardBase/stems/${Uri.encodeComponent(jobId)}/${Uri.encodeComponent(stem.name)}';
    final r2 = await _send(
        () => _http.get(Uri.parse(url),
            headers: wizardHeaders({'Accept': 'audio/*'})),
        const Duration(seconds: 60),
        'Downloading ${stem.name}');
    if (r2.statusCode < 200 || r2.statusCode >= 300) {
      throw StableAudioException(
          'Take download failed (HTTP ${r2.statusCode}) for ${stem.name}',
          StableAudioFailure.job);
    }
    if (r2.bodyBytes.length < 1000) {
      throw StableAudioException(
          'Downloaded take ${stem.name} is too small (${r2.bodyBytes.length} bytes)',
          StableAudioFailure.job);
    }
    return r2.bodyBytes;
  }
}
