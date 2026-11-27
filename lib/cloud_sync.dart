import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'widgets/ui_kit.dart';

/// MH STUDIO cloud account + cross-device sync (v1.21.0).
///
/// Built on plain Firebase REST - NO native Firebase SDK, no
/// google-services.json, no Gradle plugin - so the exact same code
/// runs on Android and Windows and CI needs no extra setup:
///
/// * Auth: Firebase Authentication REST (email/password) on his
///   project `mh-studio-official`. The API key below is the public
///   client key from the project's web config (it identifies the
///   project; it is not a secret - access is controlled by the
///   Realtime Database security rules, see CLOUD_SYNC_SETUP.md).
/// * Data: Firebase Realtime Database (free Spark plan), one JSON
///   node per user: /users/<uid>/sync.
///
/// TEXT ONLY, by design (his instruction): what syncs is the small
/// text state the app keeps in secure storage / preferences -
/// the Gemini browser session, Zedge distribution accounts + R2
/// worker URL, Stable Audio account, Cloudinary credentials,
/// ringtone settings and a few app preferences. Images, audio
/// files and any other binaries NEVER sync.
class CloudSync {
  CloudSync._();

  static const _apiKey = 'AIzaSyBeJ6dnCHj36vBXB1-M_jOaE0sOLBtHK-s';
  static const defaultDbUrl =
      'https://mh-studio-official-default-rtdb.firebaseio.com';

  static const _storage = FlutterSecureStorage();
  static const _kUid = 'cloud_uid';
  static const _kEmail = 'cloud_email';
  static const _kRefresh = 'cloud_refresh_token';
  static const _pLastPush = 'cloud_last_push_ms';
  static const _pLastSync = 'cloud_last_sync_ms';

  /// Secure-storage keys that sync (all small text values).
  static const secureKeys = [
    'gemini_web_session', // browser session (cookies JSON)
    'cloud_name', 'api_key', 'api_secret', // Cloudinary credentials
    'dist_config_v2', // Zedge accounts + R2 worker URL + queue path
    'stable_audio_auth_v1', // Stable Audio account tokens
  ];

  /// Preference keys that sync (text only). Device-specific values
  /// (browser exe path, ffmpeg path) deliberately do NOT sync.
  static const prefKeys = [
    'ringtone_config_v1',
    'image_engine',
    'theme_mode',
  ];

  static String? _idToken;
  static DateTime _idTokenExpiry = DateTime.fromMillisecondsSinceEpoch(0);
  static Timer? _debounce;

  // ---------------------------------------------------------- state

  /// The database is BUILT INTO the project (his rule, v1.22.0):
  /// the URL is never shown in the UI and users cannot connect
  /// their own Firebase - this project is the only backend.
  static Future<String> dbUrl() async => defaultDbUrl;

  /// Login gate state: true while a user is signed in. The app's
  /// root listens to this and shows the login screen or the main
  /// interface - the interface is never visible before login.
  static final ValueNotifier<bool> authState = ValueNotifier<bool>(false);

  /// Startup session restore for the login gate. A stored refresh
  /// token means "signed in"; it is validated once against Firebase
  /// when the network allows. Offline -> still enters (the token
  /// refreshes on the next sync); a rejected token -> signed out.
  static Future<bool> restoreSession() async {
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh == null || refresh.isEmpty) {
      authState.value = false;
      return false;
    }
    try {
      await _token();
      authState.value = true;
      return true;
    } on CloudSyncException {
      await signOut();
      return false;
    } catch (_) {
      // Network unreachable etc.: keep the session, enter offline.
      authState.value = true;
      return true;
    }
  }

  static Future<String?> get email async => _storage.read(key: _kEmail);
  static Future<String?> get uid async => _storage.read(key: _kUid);

  static Future<bool> get isSignedIn async =>
      (await _storage.read(key: _kRefresh))?.isNotEmpty ?? false;

  static Future<DateTime?> get lastSync async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_pLastSync) ?? 0;
    return ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // ---------------------------------------------------------- auth

  static Future<void> signUp(String email, String password) =>
      _auth('signUp', email, password);

  static Future<void> signIn(String email, String password) =>
      _auth('signInWithPassword', email, password);

  static Future<void> _auth(String method, String email, String password) async {
    final r = await http
        .post(
          Uri.parse(
              'https://identitytoolkit.googleapis.com/v1/accounts:$method?key=$_apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
            'returnSecureToken': true,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final body = _decode(r);
    if (r.statusCode != 200) throw CloudSyncException(_authError(body));
    await _storage.write(key: _kUid, value: body['localId'] as String?);
    await _storage.write(key: _kEmail, value: body['email'] as String? ?? email.trim());
    await _storage.write(
        key: _kRefresh, value: body['refreshToken'] as String?);
    _idToken = body['idToken'] as String?;
    final exp = int.tryParse('${body['expiresIn']}') ?? 3600;
    _idTokenExpiry =
        DateTime.now().add(Duration(seconds: exp - 60));
    authState.value = true;
  }

  static Future<void> sendPasswordReset(String email) async {
    final r = await http
        .post(
          Uri.parse(
              'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$_apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'requestType': 'PASSWORD_RESET', 'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw CloudSyncException(_authError(_decode(r)));
    }
  }

  static Future<void> signOut() async {
    authState.value = false;
    _idToken = null;
    await _storage.delete(key: _kUid);
    await _storage.delete(key: _kEmail);
    await _storage.delete(key: _kRefresh);
    final p = await SharedPreferences.getInstance();
    await p.remove(_pLastPush);
    await p.remove(_pLastSync);
  }

  static Future<String> _token() async {
    if (_idToken != null && DateTime.now().isBefore(_idTokenExpiry)) {
      return _idToken!;
    }
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh == null || refresh.isEmpty) {
      throw const CloudSyncException('Not signed in.');
    }
    final r = await http
        .post(
          Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'grant_type': 'refresh_token', 'refresh_token': refresh},
        )
        .timeout(const Duration(seconds: 30));
    final body = _decode(r);
    if (r.statusCode != 200) {
      throw const CloudSyncException(
          'Session expired - please sign in again.');
    }
    _idToken = body['id_token'] as String?;
    final exp = int.tryParse('${body['expires_in']}') ?? 3600;
    _idTokenExpiry = DateTime.now().add(Duration(seconds: exp - 60));
    final newRefresh = body['refresh_token'] as String?;
    if (newRefresh != null && newRefresh.isNotEmpty) {
      await _storage.write(key: _kRefresh, value: newRefresh);
    }
    return _idToken!;
  }

  static Map<String, dynamic> _decode(http.Response r) {
    try {
      final v = jsonDecode(r.body);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  static String _authError(Map<String, dynamic> body) {
    final code =
        ((body['error'] as Map?)?['message'] ?? '').toString();
    return switch (code) {
      'EMAIL_EXISTS' => 'An account with this email already exists - sign in instead.',
      'EMAIL_NOT_FOUND' || 'INVALID_LOGIN_CREDENTIALS' || 'INVALID_PASSWORD' =>
        'Email or password is wrong.',
      'USER_DISABLED' => 'This account has been disabled.',
      'INVALID_EMAIL' => 'That email address looks invalid.',
      'TOO_MANY_ATTEMPTS_TRY_LATER' =>
        'Too many attempts - wait a bit and try again.',
      _ when code.startsWith('WEAK_PASSWORD') =>
        'Password is too weak - use at least 6 characters.',
      _ => 'Sign-in failed ($code). Check your internet connection.',
    };
  }

  // ---------------------------------------------------------- sync

  static Future<Map<String, dynamic>> _collect(int updatedAt) async {
    final secure = <String, dynamic>{};
    for (final k in secureKeys) {
      final v = await _storage.read(key: k);
      if (v != null && v.isNotEmpty) secure[k] = v;
    }
    final prefs = await SharedPreferences.getInstance();
    final prefMap = <String, dynamic>{};
    for (final k in prefKeys) {
      final v = prefs.get(k);
      if (v is String && v.isNotEmpty) prefMap[k] = v;
    }
    return {
      'v': 1,
      'updatedAt': updatedAt,
      'device': Platform.operatingSystem,
      'secure': secure,
      'prefs': prefMap,
    };
  }

  static Future<void> _apply(Map<String, dynamic> payload) async {
    final secure = payload['secure'];
    if (secure is Map) {
      for (final k in secureKeys) {
        final v = secure[k];
        if (v is String && v.isNotEmpty) {
          await _storage.write(key: k, value: v);
        }
      }
    }
    final prefMap = payload['prefs'];
    if (prefMap is Map) {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefKeys) {
        final v = prefMap[k];
        if (v is String && v.isNotEmpty) await prefs.setString(k, v);
      }
    }
  }

  static Future<Uri> _syncUri() async {
    final token = await _token();
    final base = await dbUrl();
    final id = await uid;
    return Uri.parse('$base/users/$id/sync.json?auth=$token');
  }

  /// One sync pass. Returns 'uploaded' when local state was pushed,
  /// 'restored' when newer cloud state was applied locally.
  /// Newest-wins: whichever side carries the later updatedAt is
  /// kept; auto-push on every local change (see [notifyChanged])
  /// keeps that window tiny.
  static Future<String> syncNow() async {
    final uri = await _syncUri();
    Map<String, dynamic>? remote;
    final gr = await http.get(uri).timeout(const Duration(seconds: 30));
    if (gr.statusCode == 200 && gr.body != 'null') {
      final v = jsonDecode(gr.body);
      if (v is Map<String, dynamic>) remote = v;
    } else if (gr.statusCode == 401 || gr.statusCode == 403) {
      throw const CloudSyncException(
          'Cloud denied access - check the Realtime Database rules (see setup doc) or sign in again.');
    }
    final prefs = await SharedPreferences.getInstance();
    final localAt = prefs.getInt(_pLastPush) ?? 0;
    final remoteAt = (remote?['updatedAt'] as num?)?.toInt() ?? 0;
    if (remote != null && remoteAt > localAt) {
      await _apply(remote);
      await prefs.setInt(_pLastPush, remoteAt);
      await prefs.setInt(
          _pLastSync, DateTime.now().millisecondsSinceEpoch);
      return 'restored';
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = await _collect(now);
    final encoded = jsonEncode(payload);
    if (encoded.length > 900000) {
      throw const CloudSyncException(
          'Sync data is too large for the free database (text-only sync).');
    }
    final pr = await http
        .put(uri, headers: {'Content-Type': 'application/json'}, body: encoded)
        .timeout(const Duration(seconds: 30));
    if (pr.statusCode != 200) {
      throw CloudSyncException('Upload failed (HTTP ${pr.statusCode}).');
    }
    await prefs.setInt(_pLastPush, now);
    await prefs.setInt(_pLastSync, now);
    return 'uploaded';
  }

  /// Push-only (used by the change hooks): uploads the current
  /// local state without pulling.
  static Future<void> pushNow() async {
    final uri = await _syncUri();
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = await _collect(now);
    final encoded = jsonEncode(payload);
    if (encoded.length > 900000) return;
    final pr = await http
        .put(uri, headers: {'Content-Type': 'application/json'}, body: encoded)
        .timeout(const Duration(seconds: 30));
    if (pr.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pLastPush, now);
      await prefs.setInt(_pLastSync, now);
    }
  }

  /// Called by the app's data stores after every save (Gemini
  /// session, distribution config, Stable Audio account, Cloudinary
  /// credentials). Debounced; silently does nothing when signed out
  /// or offline.
  static void notifyChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 6), () async {
      try {
        if (await isSignedIn) await pushNow();
      } catch (_) {}
    });
  }

  /// Fire-and-forget sync at app start (no-op when signed out).
  static Future<void> autoSyncOnStart() async {
    try {
      if (await isSignedIn) await syncNow();
    } catch (_) {}
  }
}

class CloudSyncException implements Exception {
  const CloudSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Full-screen login / register gate (v1.22.0, his rule): the app
/// opens HERE. The main interface is only reachable after a
/// successful sign-in - there is no way around it, and nothing
/// about the backend (no database URL, no project settings) is
/// shown anywhere on this screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _status;
  bool _statusOk = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || _passCtrl.text.isEmpty) {
      setState(() {
        _statusOk = false;
        _status = 'Enter your email and password.';
      });
      return;
    }
    if (_register && _passCtrl.text.length < 6) {
      setState(() {
        _statusOk = false;
        _status = 'Password must be at least 6 characters.';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      if (_register) {
        await CloudSync.signUp(email, _passCtrl.text);
      } else {
        await CloudSync.signIn(email, _passCtrl.text);
      }
      // Signed in: sync in the background (restores this device's
      // state from the cloud when the cloud copy is newer). The
      // root gate swaps to the main interface via authState.
      unawaited(CloudSync.autoSyncOnStart());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusOk = false;
        _status = e is CloudSyncException ? e.message : 'Failed: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() {
        _statusOk = false;
        _status = 'Enter your email first, then tap Forgot password.';
      });
      return;
    }
    try {
      await CloudSync.sendPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _statusOk = true;
        _status = 'Password reset email sent - check your inbox.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusOk = false;
        _status = e is CloudSyncException ? e.message : 'Failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset('assets/icon/app_icon.png',
                        width: 84, height: 84),
                  ),
                ),
                const SizedBox(height: 16),
                Text('MH STUDIO',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                    _register
                        ? 'Create your account to start'
                        : 'Sign in to continue to your workspace',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 28),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (!_register)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: _busy ? null : _forgot,
                        child: const Text('Forgot password?')),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50)),
                  child: Text(_register ? 'Create account' : 'Sign in'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 14),
                  HintText(_status!,
                      icon: _statusOk
                          ? Icons.check_circle_outline
                          : Icons.error_outline),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_register
                        ? 'Already have an account?'
                        : 'New to MH STUDIO?'),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _status = null;
                              }),
                      child: Text(_register ? 'Sign in' : 'Create account'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const HintText(
                    'Your session, accounts and settings sync securely '
                    'to your account, so you can continue on any device.',
                    icon: Icons.cloud_sync_outlined),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings card shown while signed in (login itself happens at
/// the app gate): account email, last sync, Sync now, Sign out.
/// No backend details are shown anywhere - the Firebase project
/// is built in and cannot be changed by the user.
class CloudSyncCard extends StatefulWidget {
  const CloudSyncCard({super.key});

  @override
  State<CloudSyncCard> createState() => _CloudSyncCardState();
}

class _CloudSyncCardState extends State<CloudSyncCard> {
  bool _busy = false;
  String? _email;
  String? _status;
  bool _statusOk = false;
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final email = await CloudSync.email;
    final last = await CloudSync.lastSync;
    if (!mounted) return;
    setState(() {
      _email = email;
      _lastSync = last;
    });
  }

  Future<void> _sync() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await CloudSync.syncNow();
      final last = await CloudSync.lastSync;
      if (!mounted) return;
      setState(() {
        _lastSync = last;
        _statusOk = true;
        _status = result == 'restored'
            ? 'Cloud data restored to this device. Restart the app to apply everything.'
            : 'All synced - your data is up to date on this device and in the cloud.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusOk = false;
        _status = e is CloudSyncException ? e.message : 'Sync failed: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      icon: Icons.cloud_sync_outlined,
      title: 'Cloud sync',
      subtitle: 'Signed in - your data syncs across devices',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.account_circle_outlined,
                color: scheme.primary),
            title: Text(_email ?? 'Signed in'),
            subtitle: Text(_lastSync == null
                ? 'Not synced yet'
                : 'Last sync: ${_lastSync!.toLocal()}'),
          ),
          const HintText(
              'Syncs TEXT data only: browser (Gemini) session, Zedge '
              'accounts + R2 settings, Stable Audio account, Cloudinary '
              'credentials and ringtone settings. Images and audio '
              'files never sync.'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _sync,
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Sync now'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await CloudSync.signOut();
                          if (!context.mounted) return;
                          // Back to the login gate: drop every pushed
                          // route; the root swaps home -> login.
                          Navigator.of(context)
                              .popUntil((r) => r.isFirst);
                        },
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Sign out'),
                ),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            HintText(_status!,
                icon: _statusOk
                    ? Icons.check_circle_outline
                    : Icons.error_outline),
          ],
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}
