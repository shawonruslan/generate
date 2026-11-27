import 'dart:convert';
import 'dart:typed_data';

import '../android_gecko.dart';
import '../gemini_web.dart';

/// Android twin of the Windows Chromium page transport: Gemini requests
/// run INSIDE a gemini.google.com tab of the app's built-in browser
/// (GeckoView), exactly like the Gemini HD Studio extension runs them
/// inside Chrome. The browser sends its own cookies - nothing is copied
/// out - so Google cannot refuse the session the way it refuses copied
/// cookies replayed over plain HTTP on Android.
///
/// Used as the client's browser fallback: the copied-cookie handshake
/// runs first, and only when Google refuses it does the work move into
/// the signed-in browser tab.
class GeckoGeminiTransport implements GeminiPageTransport {
  @override
  bool get isAvailable => AndroidGecko.supported;

  @override
  Future<GeminiPageResponse> request(
    String method,
    String url, {
    Map<String, String> headers = const {},
    String? body,
    Uint8List? file,
    String fileName = 'image.jpg',
    String fileMime = 'image/jpeg',
    Duration timeout = const Duration(seconds: 120),
  }) async {
    // The hidden Gemini tab may still be loading (first call): the
    // extension answers "no_gemini_tab" until its content script has
    // connected, so retry for a while before giving up.
    Map<String, dynamic>? r;
    for (var attempt = 0; attempt < 6; attempt++) {
      r = await AndroidGecko.geminiFetch(
        method: method,
        url: url,
        headers: headers,
        body: body,
        fileBase64: file == null ? null : base64Encode(file),
        fileName: fileName,
        fileMime: fileMime,
        timeout: timeout,
      );
      if (r == null) {
        throw GeminiWebException(
            'The built-in browser did not answer the Gemini request.');
      }
      if (r['error'] != 'no_gemini_tab') break;
      await Future.delayed(const Duration(seconds: 3));
    }
    final err = (r?['e'] ?? r?['error'])?.toString();
    if (err != null && err.isNotEmpty) {
      throw GeminiWebException(
          'Gemini request in the built-in browser failed: $err');
    }
    final x = r?['x'];
    return GeminiPageResponse(
      (r?['s'] as num?)?.toInt() ?? 0,
      (r?['u'] ?? url).toString(),
      (r?['b'] ?? '').toString(),
      bytes: x is String && x.isNotEmpty ? base64Decode(x) : null,
      contentType: (r?['ct'] ?? '').toString(),
    );
  }
}
