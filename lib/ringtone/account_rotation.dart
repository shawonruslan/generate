import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// WorkOS client id used by stableaudio.com (same value as the workflow's
/// `currentWorkosClientId`).
const String kStableAudioWorkosClientId = 'client_01M5FKRSSZMYNTGJZ7SF9WXKH6';

const String _kWorkosAuthUrl =
    'https://api.workos.com/user_management/authenticate';
const String _kBalanceUrl =
    'https://api.stableaudio.com/v1alpha/user/balance';

/// RFC-4122 v4 id (the workflow uses `crypto.randomUUID()` for the device
/// id and the idempotency key).
String newStableAudioId() {
  final r = Random.secure();
  String hex(int n) =>
      List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  final variant = ['8', '9', 'a', 'b'][r.nextInt(4)];
  return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
}

/// Seconds from a JWT's `exp` claim (null when the token is opaque or
/// malformed) — the workflow's `getJwtExpSeconds`.
int? stableAudioJwtExpSeconds(String jwt) {
  try {
    final parts = jwt.trim().split('.');
    if (parts.length != 3) return null;
    final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    if (payload is! Map) return null;
    final exp = payload['exp'];
    return exp is num ? exp.toInt() : null;
  } catch (_) {
    return null;
  }
}

/// One Stable Audio (WorkOS) account in the rotation pool.
///
/// The cloud workflow kept these as module-level variables
/// (`currentToken` / `currentRefreshToken` / `currentWorkosClientId` /
/// `currentCredits`) and threw the account away when the 50 credits were
/// gone. Here they are persisted, so an exhausted account stays in the
/// pool (it can be refreshed or topped up later) and rotation just moves
/// the cursor to the next one.
class StableAudioAccount {
  String id;
  String email;
  String accessToken;
  String refreshToken;
  String workosClientId;
  String deviceId;
  int creditsRemaining; // -1 = not read yet
  int creditsTotal;
  int addedAt;
  int lastUsedAt;
  int jobsRun;
  bool autoCreated;

  StableAudioAccount({
    String? id,
    this.email = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.workosClientId = kStableAudioWorkosClientId,
    String? deviceId,
    this.creditsRemaining = -1,
    this.creditsTotal = 50,
    int? addedAt,
    this.lastUsedAt = 0,
    this.jobsRun = 0,
    this.autoCreated = false,
  })  : id = (id == null || id.isEmpty) ? newStableAudioId() : id,
        deviceId =
            (deviceId == null || deviceId.isEmpty) ? newStableAudioId() : deviceId,
        addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  factory StableAudioAccount.fromJson(Map<String, dynamic> m) =>
      StableAudioAccount(
        id: (m['id'] ?? '').toString(),
        email: (m['email'] ?? '').toString(),
        accessToken: (m['accessToken'] ?? m['token'] ?? '').toString(),
        refreshToken: (m['refreshToken'] ?? '').toString(),
        workosClientId: (m['workosClientId'] ?? '').toString().isEmpty
            ? kStableAudioWorkosClientId
            : m['workosClientId'].toString(),
        deviceId: (m['deviceId'] ?? '').toString(),
        creditsRemaining: (m['creditsRemaining'] as num?)?.toInt() ?? -1,
        creditsTotal: (m['creditsTotal'] as num?)?.toInt() ?? 50,
        addedAt: (m['addedAt'] as num?)?.toInt(),
        lastUsedAt: (m['lastUsedAt'] as num?)?.toInt() ?? 0,
        jobsRun: (m['jobsRun'] as num?)?.toInt() ?? 0,
        autoCreated: m['autoCreated'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'workosClientId': workosClientId,
        'deviceId': deviceId,
        'creditsRemaining': creditsRemaining,
        'creditsTotal': creditsTotal,
        'addedAt': addedAt,
        'lastUsedAt': lastUsedAt,
        'jobsRun': jobsRun,
        'autoCreated': autoCreated,
      };

  String get label {
    if (email.isNotEmpty) return email;
    return id.length >= 4 ? 'Account ${id.substring(0, 4)}' : 'Account';
  }

  String get creditsLabel =>
      creditsRemaining < 0 ? '?/$creditsTotal cr' : '$creditsRemaining/$creditsTotal cr';

  /// True when the account can still pay for one 4-take job.
  bool get hasCredits => creditsRemaining < 0 || creditsRemaining >= 4;

  bool get hasRefresh => refreshToken.trim().isNotEmpty;

  /// Expired or about to expire (45 s of slack, like the workflow).
  bool get needsRefresh {
    final exp = stableAudioJwtExpSeconds(accessToken);
    if (accessToken.isEmpty) return true;
    if (exp == null) return false;
    return (DateTime.now().millisecondsSinceEpoch ~/ 1000) >= (exp - 45);
  }
}

/// Secure-storage backed account pool + active-account cursor.
class StableAudioPool {
  StableAudioPool._();

  static const _storage = FlutterSecureStorage();
  static const _kAccounts = 'stable_audio_accounts_v1';
  static const _kCursor = 'stable_audio_account_cursor';

  // v1.17 keys — migrated into the pool on first load so nobody loses the
  // token they already pasted.
  static const _kLegacyToken = 'stable_audio_token';
  static const _kLegacyRefresh = 'stable_audio_refresh_token';
  static const _kLegacyDevice = 'stable_audio_device_id';

  static Future<List<StableAudioAccount>> load() async {
    final out = <StableAudioAccount>[];
    final raw = await _storage.read(key: _kAccounts);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              out.add(StableAudioAccount.fromJson(
                  Map<String, dynamic>.from(e)));
            }
          }
        }
      } catch (_) {}
    }
    if (out.isEmpty) {
      final legacy = (await _storage.read(key: _kLegacyToken))?.trim() ?? '';
      if (legacy.isNotEmpty) {
        out.add(StableAudioAccount(
          email: 'My account',
          accessToken: legacy,
          refreshToken:
              (await _storage.read(key: _kLegacyRefresh))?.trim() ?? '',
          deviceId: (await _storage.read(key: _kLegacyDevice))?.trim() ?? '',
        ));
        await save(out);
      }
    }
    return out;
  }

  static Future<void> save(List<StableAudioAccount> accounts) async {
    await _storage.write(
        key: _kAccounts,
        value: jsonEncode([for (final a in accounts) a.toJson()]));
  }

  static Future<int> cursor() async {
    final raw = await _storage.read(key: _kCursor);
    return int.tryParse((raw ?? '').trim()) ?? 0;
  }

  static Future<void> setCursor(int value) async =>
      _storage.write(key: _kCursor, value: '$value');
}

/// Automatic Stable Audio account rotation — the app-side port of the
/// workflow's `getJwtExpSeconds` / `refreshStableAudioToken` /
/// `fetchStableAudioCredits` / `ensureStableAudioTokenAndCredits` /
/// `createStableAudioAccount` block, plus the retry-on-401/429 logic that
/// lived inside `generateStableAudio`.
///
/// Behaviour, in the same order as the workflow:
///  1. no account at all      → create one (when auto-create is on)
///  2. JWT within 45 s of exp → WorkOS refresh (same account kept)
///  3. refresh impossible     → rotate to the next account
///  4. credits < takes*4      → rotate to the next account
///  5. every account empty    → create a fresh 50-credit account
class StableAudioRotator {
  StableAudioRotator({this.onLog});

  /// Status lines, surfaced in the Ringtone Studio log box.
  final void Function(String line)? onLog;

  /// Injected by the UI: performs the browser/temp-mail signup. Kept as a
  /// callback so this file stays pure HTTP (no browser dependency).
  Future<StableAudioAccount?> Function(void Function(String) log)? creator;

  final List<StableAudioAccount> _accounts = [];
  int _index = 0;
  bool autoRotate = true;
  bool autoCreate = false;
  bool _busy = false;

  List<StableAudioAccount> get accounts => List.unmodifiable(_accounts);
  int get index => _index;
  bool get isEmpty => _accounts.isEmpty;
  bool get busy => _busy;

  StableAudioAccount? get current =>
      (_index >= 0 && _index < _accounts.length) ? _accounts[_index] : null;

  void _log(String line) {
    final f = onLog;
    if (f != null) f(line);
  }

  Future<void> load() async {
    _accounts
      ..clear()
      ..addAll(await StableAudioPool.load());
    _index = await StableAudioPool.cursor();
    if (_index < 0 || _index >= _accounts.length) _index = 0;
  }

  Future<void> _persist() async {
    await StableAudioPool.save(_accounts);
    await StableAudioPool.setCursor(_index);
  }

  // ── pool editing ────────────────────────────────────────────────
  Future<StableAudioAccount> addAccount({
    required String token,
    String refreshToken = '',
    String email = '',
    bool autoCreated = false,
  }) async {
    final acc = StableAudioAccount(
      email: email.trim(),
      accessToken: token.trim(),
      refreshToken: refreshToken.trim(),
      autoCreated: autoCreated,
    );
    _accounts.add(acc);
    if (_accounts.length == 1) _index = 0;
    await _persist();
    await credits(acc);
    return acc;
  }

  Future<void> removeAt(int i) async {
    if (i < 0 || i >= _accounts.length) return;
    _accounts.removeAt(i);
    if (_index >= _accounts.length) _index = 0;
    if (_index < 0) _index = 0;
    await _persist();
  }

  Future<void> activate(int i) async {
    if (i < 0 || i >= _accounts.length) return;
    _index = i;
    await _persist();
  }

  // ── WorkOS refresh (refreshStableAudioToken) ────────────────────
  Future<bool> refreshCurrent() async {
    final acc = current;
    if (acc == null) return false;
    return refreshAccount(acc);
  }

  /// Refreshes one specific account (not necessarily the active one).
  Future<bool> refreshAccount(StableAudioAccount acc) async {
    if (!acc.hasRefresh) {
      _log('  ⚠️ No refresh token for ${acc.label} — cannot refresh.');
      return false;
    }
    try {
      _log('  🔄 Refreshing access token via WorkOS refresh_token '
          '(same 50-credit account kept)…');
      final resp = await http
          .post(
            Uri.parse(_kWorkosAuthUrl),
            headers: {
              'Accept': 'application/json, text/plain, */*',
              'Content-Type': 'application/json',
              'Origin': 'https://stableaudio.com',
              'Referer': 'https://stableaudio.com/',
            },
            body: jsonEncode({
              'client_id': acc.workosClientId.isEmpty
                  ? kStableAudioWorkosClientId
                  : acc.workosClientId,
              'grant_type': 'refresh_token',
              'refresh_token': acc.refreshToken,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _log('  ⚠️ WorkOS token refresh failed (${resp.statusCode}).');
        return false;
      }
      final data = jsonDecode(resp.body);
      if (data is! Map) return false;
      final at = (data['access_token'] ?? '').toString();
      if (at.isEmpty) return false;
      acc.accessToken = at;
      final nrt = (data['refresh_token'] ?? '').toString();
      if (nrt.isNotEmpty) acc.refreshToken = nrt;
      await _persist();
      _log('  ✅ Token refreshed cleanly (same account kept).');
      return true;
    } catch (e) {
      _log('  ⚠️ WorkOS refresh error: $e');
      return false;
    }
  }

  // ── balance (fetchStableAudioCredits) ───────────────────────────
  Future<({int remaining, int total})?> credits([
    StableAudioAccount? account,
  ]) async {
    final acc = account ?? current;
    if (acc == null || acc.accessToken.isEmpty) return null;
    try {
      final resp = await http.get(
        Uri.parse(_kBalanceUrl),
        headers: {
          'Accept': '*/*',
          'Authorization': 'Bearer ${acc.accessToken}',
          'Origin': 'https://stableaudio.com',
          'Referer': 'https://stableaudio.com/',
        },
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      final attrs = data['attributes'] is Map
          ? Map<String, dynamic>.from(data['attributes'] as Map)
          : const <String, dynamic>{};
      final rem = (attrs['generations_limit'] as num?)?.toInt() ??
          (data['generations_limit'] as num?)?.toInt();
      final tot = (attrs['credits_per_period'] as num?)?.toInt() ??
          (data['credits_per_period'] as num?)?.toInt() ??
          acc.creditsTotal;
      if (rem == null) return null;
      acc.creditsRemaining = rem;
      acc.creditsTotal = tot;
      await _persist();
      return (remaining: rem, total: tot);
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshAllCredits() async {
    for (final acc in _accounts) {
      if (acc.needsRefresh) await refreshAccount(acc);
      await credits(acc);
    }
    await _persist();
  }

  // ── account creation (createStableAudioAccount) ─────────────────
  Future<StableAudioAccount?> createAccount() async {
    final make = creator;
    if (make == null) {
      _log('  ⚠️ Auto account creation is not available on this platform.');
      return null;
    }
    if (_busy) {
      _log('  ⏳ Account creation already running.');
      return null;
    }
    _busy = true;
    try {
      _log('🤖 AUTO ACCOUNT CREATION STARTED (browser + temp-mail OTP)…');
      final acc = await make(_log);
      if (acc == null) {
        _log('❌ Account creation did not complete.');
        return null;
      }
      _accounts.add(acc);
      _index = _accounts.length - 1;
      await _persist();
      await credits(acc);
      _log('✅ New Stable Audio account added: ${acc.label} '
          '(${acc.creditsLabel}).');
      return acc;
    } catch (e) {
      _log('❌ Account creation failed: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  // ── ensureStableAudioTokenAndCredits ────────────────────────────
  Future<bool> ensureReady(int takesCount) async {
    if (_accounts.isEmpty) {
      if (!autoCreate) {
        _log('❌ No Stable Audio account yet — add one in Accounts.');
        return false;
      }
      if (await createAccount() == null) return false;
    }
    if (_index < 0 || _index >= _accounts.length) _index = 0;

    final acc = current;
    if (acc == null) return false;

    if (acc.needsRefresh) {
      final ok = await refreshCurrent();
      if (!ok) {
        _log('  ⚠️ JWT expired and refresh unavailable — rotating account…');
        if (!await rotate(reason: 'JWT expired')) return false;
      }
    }

    final need = max(4, takesCount * 4);
    final bal = await credits();
    if (bal != null && bal.remaining < need) {
      _log('  💳 Credits low (${bal.remaining}/${bal.total} < $need) — '
          'rotating account…');
      if (!await rotate(reason: 'low credits')) return false;
      await credits();
    } else if (bal != null) {
      _log('  💳 ${acc.label}: ${bal.remaining}/${bal.total} credits '
          'remaining (need ~$need for $takesCount take'
          '${takesCount == 1 ? '' : 's'})');
    }

    final used = current;
    if (used == null) return false;
    used.lastUsedAt = DateTime.now().millisecondsSinceEpoch;
    used.jobsRun += 1;
    await _persist();
    return true;
  }

  // ── rotation ────────────────────────────────────────────────────
  Future<bool> rotate({String reason = 'manual'}) async {
    if (_accounts.isEmpty) {
      if (autoCreate) return await createAccount() != null;
      return false;
    }
    _log('🔄 Rotating Stable Audio account ($reason)…');
    final start = _index;
    for (var step = 1; step <= _accounts.length; step++) {
      final i = (start + step) % _accounts.length;
      _index = i;
      final acc = _accounts[i];
      if (acc.needsRefresh) await refreshAccount(acc);
      final bal = await credits();
      if (bal == null || bal.remaining >= 4) {
        await _persist();
        _log('✅ Active account → ${acc.label} (${acc.creditsLabel})');
        return true;
      }
      _log('   ${acc.label}: ${bal.remaining}/${bal.total} credits — skipping');
    }
    if (autoCreate) {
      _log('🆕 Every account is out of credits — creating a fresh '
          '50-credit account…');
      if (await createAccount() != null) return true;
    }
    _log('❌ No account left with credits. Add another account.');
    return false;
  }

  /// Called by the API client on 401/403.
  Future<bool> handleAuthFailure() async {
    if (await refreshCurrent()) return true;
    _log('  🔑 Auth rejected and refresh failed — rotating account…');
    return rotate(reason: 'auth rejected');
  }

  /// Called by the API client on 402/429/quota 400.
  Future<bool> handleQuotaFailure() async {
    final acc = current;
    if (acc != null) {
      acc.creditsRemaining = 0;
      await _persist();
    }
    return rotate(reason: 'credits/quota exhausted');
  }
}
