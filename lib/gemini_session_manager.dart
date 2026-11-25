import 'dart:io';

import 'android_gecko.dart';
import 'browser/chromium_browser.dart';
import 'browser/image_prompt_service.dart';
import 'gemini_web.dart';
import 'secure_store.dart';

/// One place that keeps the Gemini web cookies alive:
///
/// * every client renews `__Secure-1PSIDTS` itself (RotateCookies) and the
///   renewed cookies are saved back to Settings automatically - Android and
///   Windows;
/// * on Windows, when Google really ends the session, fresh cookies are
///   pulled silently from the app's own browser profile where the user
///   signed in once ("Sign in with Google"). No password is asked again.
class GeminiSessionManager {
  GeminiSessionManager._();

  /// Desktop: Chrome/Edge profile. Android: built-in Firefox engine.
  static bool get browserRefreshSupported =>
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS ||
      AndroidGecko.supported;

  static Future<void>? _refreshing;
  static GeminiWebSession? _lastRefreshed;

  /// Builds a client for [session] that persists renewed cookies and (on
  /// desktop) falls back to the signed-in browser profile.
  static GeminiWebClient clientFor(GeminiWebSession session,
      {void Function(String json)? onSaved}) {
    return GeminiWebClient(
      session,
      onSessionUpdated: (s) async {
        final json = s.toStorageJson();
        await GeminiWebStore.save(json);
        onSaved?.call(json);
      },
      refreshSession: browserRefreshSupported
          ? () async {
              final s = await refreshFromBrowser();
              if (s != null) onSaved?.call(s.toStorageJson());
              return s;
            }
          : null,
    );
  }

  /// Loads the saved session and wraps it with [clientFor]; null when no
  /// session is saved.
  static Future<GeminiWebClient?> savedClient(
      {void Function(String json)? onSaved}) async {
    final raw = await GeminiWebStore.load();
    if (raw.trim().isEmpty) {
      if (!browserRefreshSupported) return null;
      // Signed in once in the browser but nothing saved yet: try silently.
      try {
        final s = await refreshFromBrowser();
        if (s == null) return null;
        return clientFor(s, onSaved: onSaved);
      } catch (_) {
        return null;
      }
    }
    return clientFor(GeminiWebSession.parse(raw), onSaved: onSaved);
  }

  /// Reads fresh Google cookies from the app's browser profile (open
  /// controlled window, or a hidden headless start of the same profile),
  /// saves them in Settings and returns the session. Null when the
  /// profile is not signed in to Google.
  static Future<GeminiWebSession?> refreshFromBrowser({bool visit = true}) async {
    // Several callers at once share one browser start.
    final running = _refreshing;
    if (running != null) {
      await running;
      return _lastRefreshed;
    }
    final done = _doRefresh(visit: visit);
    _refreshing = done;
    try {
      await done;
      return _lastRefreshed;
    } finally {
      _refreshing = null;
    }
  }

  static Future<void> _doRefresh({bool visit = true}) async {
    _lastRefreshed = null;
    final svc = ImagePromptService.instance;
    List<Map<String, dynamic>> cookies;
    final live = svc.browser;
    if (AndroidGecko.supported) {
      cookies = await AndroidGecko.refresh();
    } else if (live != null && live.isConnected) {
      cookies = await live.refreshGoogleCookies();
    } else {
      cookies = await ChromiumBrowser.harvestGoogleCookies(
          preferredExecutable: svc.browserPath, visit: visit);
    }
    cookies = geminiCookiesOnly(cookies);
    if (cookies.isEmpty) return;
    final s = GeminiWebSession.fromCookieList(cookies,
        format: AndroidGecko.supported ? 'Built-in browser' : 'Browser profile');
    if (!s.authCookies.contains('__Secure-1PSID')) return;
    await GeminiWebStore.save(s.toStorageJson());
    _lastRefreshed = s;
  }

  /// One-time sign-in: opens the app's browser profile as a normal browser
  /// on the Google sign-in page for Gemini. When the user closes the
  /// window the cookies are taken over automatically.
  static Future<GeminiWebSession?> signInWithBrowser() async {
    if (AndroidGecko.supported) {
      final c = geminiCookiesOnly(await AndroidGecko.signIn());
      if (!c.any((x) => x['name'] == '__Secure-1PSID')) return null;
      final s = GeminiWebSession.fromCookieList(c, format: 'Built-in browser');
      await GeminiWebStore.save(s.toStorageJson());
      return s;
    }
    final svc = ImagePromptService.instance;
    await svc.closeBrowserForSignIn();
    // The window closes by itself once Gemini has opened after sign-in.
    await ChromiumBrowser.launchPlain(preferredExecutable: svc.browserPath);
    await Future.delayed(const Duration(milliseconds: 400));
    // Fresh sign-in: the cookies are already on disk, just read them
    // (about 2 s). Only when that finds nothing, visit Gemini once.
    return await refreshFromBrowser(visit: false) ?? await refreshFromBrowser();
  }
}

/// Google session cookies gemini.google.com needs - nothing else is kept.
const geminiSessionCookieNames = {
  'SID', 'HSID', 'SSID', 'APISID', 'SAPISID', 'SIDCC', 'NID', 'AEC',
  '__Secure-1PSID', '__Secure-3PSID',
  '__Secure-1PSIDTS', '__Secure-3PSIDTS',
  '__Secure-1PSIDCC', '__Secure-3PSIDCC',
  '__Secure-1PAPISID', '__Secure-3PAPISID',
};

/// Keeps only the Gemini session cookies of .google.com / gemini.google.com.
List<Map<String, dynamic>> geminiCookiesOnly(List<Map<String, dynamic>> all) {
  bool domainOk(String d) {
    final x = d.startsWith('.') ? d.substring(1) : d;
    return x == 'google.com' || x == 'gemini.google.com';
  }

  return [
    for (final c in all)
      if (geminiSessionCookieNames.contains(c['name']) &&
          domainOk((c['domain'] ?? '').toString()))
        c
  ];
}
