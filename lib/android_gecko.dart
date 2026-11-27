import 'dart:convert';

import 'package:flutter/services.dart';

import 'platform_ui.dart';

/// Android only: the built-in Firefox engine (GeckoView) sign-in screen.
///
/// Google blocks sign-in inside Android WebView, but GeckoView is a real
/// browser engine. The user signs in once; its private profile keeps the
/// Google session, and the Gemini cookies can be read again silently when
/// the app's copy expires (see android_native/ for the native side).
class AndroidGecko {
  AndroidGecko._();

  static const _ch = MethodChannel('ais/gecko');
  static const _saCh = MethodChannel('ais/stable_audio');

  static bool get supported => isAndroidUi;
  static bool _stableAudioBrowserOpen = false;

  static void _claimStableAudioBrowser() {
    if (_stableAudioBrowserOpen) {
      throw PlatformException(
        code: 'stable_audio_busy',
        message: 'Stable Audio browser is already open. Finish or close it first.',
      );
    }
    _stableAudioBrowserOpen = true;
  }

  static List<Map<String, dynamic>> _decode(String? json) {
    if (json == null || json.trim().isEmpty) return const [];
    final v = jsonDecode(json);
    if (v is! List) return const [];
    return [
      for (final c in v)
        if (c is Map) c.cast<String, dynamic>(),
    ];
  }

  /// Opens the sign-in screen; completes when it closes. Empty list = not
  /// signed in.
  static Future<List<Map<String, dynamic>>> signIn() async =>
      _decode(await _ch.invokeMethod<String>('signIn'));

  /// Loads Gemini invisibly in the signed-in profile and returns the
  /// renewed Gemini cookies (empty = profile not signed in).
  static Future<List<Map<String, dynamic>>> refresh() async => _decode(
    await _ch
        .invokeMethod<String>('refresh')
        .timeout(const Duration(seconds: 60)),
  );

  /// Runs one HTTP request inside a signed-in gemini.google.com tab of
  /// the built-in browser (see GeckoGeminiTransport). Returns the raw
  /// result map ({s,u,b,ct,x,e,error}) or null when the native side did
  /// not answer in time.
  static Future<Map<String, dynamic>?> geminiFetch({
    required String method,
    required String url,
    Map<String, String> headers = const {},
    String? body,
    String? fileBase64,
    String fileName = 'image.jpg',
    String fileMime = 'image/jpeg',
    required Duration timeout,
  }) async {
    final payload = jsonEncode({
      'm': method,
      'u': url,
      'h': headers,
      'b': body,
      'f': fileBase64,
      'fn': fileName,
      'ft': fileMime,
      't': timeout.inMilliseconds,
    });
    final raw = await _ch
        .invokeMethod<String>('geminiFetch', payload)
        .timeout(timeout + const Duration(seconds: 30));
    if (raw == null || raw.trim().isEmpty) return null;
    final v = jsonDecode(raw);
    return v is Map ? v.cast<String, dynamic>() : null;
  }

  /// Opens Stable Audio in Android WebView so the user can sign in and returns
  /// `{accessToken, refreshToken, clientId}`.
  static Future<Map<String, dynamic>?> signInStableAudio() async {
    _claimStableAudioBrowser();
    try {
      final raw = await _ch.invokeMethod<String>('stableAudioSignIn');
      if (raw == null || raw.trim().isEmpty) return null;
      final v = jsonDecode(raw);
      return v is Map ? v.cast<String, dynamic>() : null;
    } finally {
      _stableAudioBrowserOpen = false;
    }
  }

  /// Opens the Android WebView immediately. When supplied, account details
  /// are prepared after launch, so a slow mail provider cannot hide the browser.
  static Future<Map<String, dynamic>?> autoCreateStableAudio({
    String email = '',
    String password = '',
    Future<Map<String, String>> Function()? onPrepareAccount,
    required Future<String?> Function() onPollOtp,
  }) async {
    _claimStableAudioBrowser();
    _saCh.setMethodCallHandler((call) async {
      if (call.method == 'prepareStableAudioAccount') {
        if (onPrepareAccount == null) {
          return {'email': email, 'password': password};
        }
        return await onPrepareAccount();
      }
      if (call.method == 'pollStableAudioOtp') {
        return await onPollOtp();
      }
      return null;
    });
    try {
      final raw = await _ch
          .invokeMethod<String>('stableAudioAutoCreate', {
            'email': email,
            'password': password,
          })
          .timeout(const Duration(seconds: 250));
      if (raw == null || raw.trim().isEmpty) return null;
      final v = jsonDecode(raw);
      return v is Map ? v.cast<String, dynamic>() : null;
    } finally {
      _stableAudioBrowserOpen = false;
      _saCh.setMethodCallHandler(null);
    }
  }
}
