import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../utils/config.dart';

/// Holds the session: API client, logged-in user, and a cached DriveData
/// snapshot (refreshed by screens). Persists token + worker URL on device.
class SessionProvider extends ChangeNotifier {
  final ApiClient api = ApiClient();
  SessionUser? _user;
  DriveData? _drive;
  bool _ready = false;

  SessionUser? get user => _user;
  DriveData? get drive => _drive;
  bool get isLoggedIn => _user != null;
  bool get ready => _ready;
  bool get isAdmin => _user?.isAdmin ?? false;

  SessionProvider() {
    api.onUnauthorized = () {
      // Session died server-side — drop it locally.
      logout(silent: true);
    };
  }

  /// Restore a saved session (token + worker URL) and validate it with /api/me.
  Future<bool> restore() async {
    final prefs = await SharedPreferences.getInstance();
    var url = prefs.getString('worker_url');
    // Self-heal: if the saved URL is truncated/invalid, fall back to default.
    // (An old build saved a truncated URL the user typed by mistake.)
    if (url == null ||
        url.isEmpty ||
        !url.contains('jonchristiangarcia.workers.dev')) {
      url = AppConfig.workerBaseUrl;
      await prefs.setString('worker_url', url);
    }
    api.baseUrl = url;
    final token = prefs.getString('session_token');
    if (token == null || token.isEmpty) {
      _ready = true;
      notifyListeners();
      return false;
    }
    api.token = token;
    try {
      final me = await api.me();
      _user = me;
      _ready = true;
      notifyListeners();
      return true;
    } catch (_) {
      await logout(silent: true);
      _ready = true;
      notifyListeners();
      return false;
    }
  }

  Future<SessionUser> login({
    required String role,
    String? username,
    required String password,
    String? workerUrl,
    bool persist = true,
  }) async {
    if (workerUrl != null && workerUrl.trim().isNotEmpty) {
      api.baseUrl = workerUrl.trim();
    }
    final u = await api.login(role: role, username: username, password: password);
    _user = u;
    final prefs = await SharedPreferences.getInstance();
    if (persist) {
      await prefs.setString('session_token', u.token);
    } else {
      await prefs.remove('session_token');
    }
    await prefs.setString('worker_url', api.baseUrl);
    await prefs.setString('username', u.username);
    await prefs.setString('role', u.role);
    notifyListeners();
    return u;
  }

  Future<void> logout({bool silent = false}) async {
    _user = null;
    _drive = null;
    api.token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_token');
    if (!silent) notifyListeners(); else notifyListeners();
  }

  Future<void> setWorkerUrl(String url) async {
    api.baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('worker_url', api.baseUrl);
    notifyListeners();
  }

  /// Refresh the shared drive snapshot (folders/files/stats/announcements).
  Future<void> refreshDrive() async {
    _drive = await api.getData();
    notifyListeners();
  }

  void setDrive(DriveData d) {
    _drive = d;
    notifyListeners();
  }
}

/// Night (dark gray) vs day (off-white glassy) theme mode. Persisted.
class ThemeProvider extends ChangeNotifier {
  bool _night = true;
  bool get night => _night;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _night = prefs.getBool('theme_night') ?? true;
    notifyListeners();
  }

  Future<void> setNight(bool v) async {
    _night = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme_night', v);
    notifyListeners();
  }

  Future<void> toggle() => setNight(!_night);
}
