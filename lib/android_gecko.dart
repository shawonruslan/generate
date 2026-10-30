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

  static bool get supported => isAndroidUi;

  static List<Map<String, dynamic>> _decode(String? json) {
    if (json == null || json.trim().isEmpty) return const [];
    final v = jsonDecode(json);
    if (v is! List) return const [];
    return [
      for (final c in v)
        if (c is Map) c.cast<String, dynamic>()
    ];
  }

  /// Opens the sign-in screen; completes when it closes. Empty list = not
  /// signed in.
  static Future<List<Map<String, dynamic>>> signIn() async =>
      _decode(await _ch.invokeMethod<String>('signIn'));

  /// Loads Gemini invisibly in the signed-in profile and returns the
  /// renewed Gemini cookies (empty = profile not signed in).
  static Future<List<Map<String, dynamic>>> refresh() async =>
      _decode(await _ch.invokeMethod<String>('refresh')
          .timeout(const Duration(seconds: 60)));
}
