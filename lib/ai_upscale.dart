import 'dart:async';

import 'package:http/http.dart' as http;

import 'cloudinary_api.dart';

/// Cloudinary's AI super-resolution on an existing managed image.
/// Cloudinary may return 423 while a derived image is being created.
class AiUpscale {
  static String url(String imageUrl, {String? after}) {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || uri.scheme != 'https' ||
        uri.host != 'res.cloudinary.com' ||
        !uri.path.contains('/image/upload/')) {
      throw ArgumentError('AI Upscale requires a Cloudinary managed image URL.');
    }
    return transformImageUrl(imageUrl,
        after == null ? 'e_upscale' : 'e_upscale/$after');
  }

  static Future<void> prepare(String imageUrl, {
    http.Client? client,
    Duration timeout = const Duration(minutes: 2),
    void Function(int attempt)? onWaiting,
  }) async {
    final target = Uri.parse(url(imageUrl));
    final ownClient = client == null;
    final c = client ?? http.Client();
    final watch = Stopwatch()..start();
    var attempt = 0;
    try {
      while (watch.elapsed < timeout) {
        attempt++;
        final remaining = timeout - watch.elapsed;
        final limit = remaining < const Duration(seconds: 30)
            ? remaining : const Duration(seconds: 30);
        final response = await c.get(target).timeout(limit);
        if (response.statusCode == 200) {
          final type = (response.headers['content-type'] ?? '').toLowerCase();
          if (!type.startsWith('image/') || response.bodyBytes.isEmpty) {
            throw StateError('Cloudinary did not return an image.');
          }
          return;
        }
        if (response.statusCode != 423 && response.statusCode != 420) {
          final detail = response.headers['x-cld-error'];
          throw StateError('Cloudinary AI Upscale failed (HTTP ${response.statusCode})'
              '${detail == null ? "." : ": $detail"}');
        }
        onWaiting?.call(attempt);
        final left = timeout - watch.elapsed;
        if (left <= Duration.zero) break;
        await Future<void>.delayed(left < const Duration(seconds: 3)
            ? left : const Duration(seconds: 3));
      }
      throw TimeoutException('Cloudinary AI Upscale is still processing. Try again later.');
    } finally {
      if (ownClient) c.close();
    }
  }
}
