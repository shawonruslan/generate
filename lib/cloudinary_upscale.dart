import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloudinary_api.dart';

/// Uploads an image to the user's Cloudinary account and requests its
/// four-times-per-dimension AI super-resolution derivative.
class CloudinaryUpscaler {
  CloudinaryUpscaler(this.creds, {this.pollDelay = const Duration(seconds: 3),
      this.maxAttempts = 25});
  final CloudinaryCredentials creds;
  final Duration pollDelay;
  final int maxAttempts;

  Future<Uint8List> upscale(Uint8List image) async {
    if (!creds.isComplete) {
      throw const CloudinaryApiException(
          category: 'upscale_error', code: 'CREDENTIALS_REQUIRED',
          message: 'Cloudinary credentials are required for Gemini AI upscale. Add them in Settings.');
    }
    final uploaded = await CloudinaryApi(creds).uploadImage(image,
        folder: 'ais_gemini_upscale');
    const marker = '/image/upload/';
    if (!uploaded.startsWith('https://res.cloudinary.com/') ||
        !uploaded.contains(marker)) {
      throw const CloudinaryApiException(category: 'upscale_error',
          code: 'INVALID_UPLOAD_URL', message: 'Cloudinary returned an invalid image URL.');
    }
    // The input is pre-cropped on device. Limit its size before e_upscale
    // (4x per axis), then limit the derived image before downloading it.
    final url = transformImageUrl(uploaded,
        'c_limit,w_1024,h_1024/e_upscale/c_limit,w_2880,h_2880/f_jpg,q_95');
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      http.Response response;
      try {
        response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      } on TimeoutException {
        if (attempt + 1 < maxAttempts) {
          await Future<void>.delayed(pollDelay);
          continue;
        }
        break;
      } catch (e) {
        throw CloudinaryApiException(category: 'network_error',
            code: 'UPSCALE_NETWORK', message: 'Cloudinary AI upscale connection failed: $e');
      }
      final mime = (response.headers['content-type'] ?? '').toLowerCase();
      if (response.statusCode == 200 && mime.startsWith('image/') && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      if (response.statusCode == 420 || response.statusCode == 423 ||
          response.statusCode == 429 || response.statusCode >= 500) {
        if (attempt + 1 < maxAttempts) await Future<void>.delayed(pollDelay);
        continue;
      }
      throw CloudinaryApiException(category: 'upscale_error',
          code: 'UPSCALE_${response.statusCode}',
          message: 'Cloudinary AI upscale failed (HTTP ${response.statusCode}). '
              'Check your account, credits and transformation permissions.');
    }
    throw const CloudinaryApiException(category: 'upscale_error',
        code: 'UPSCALE_TIMEOUT', message: 'Cloudinary AI upscale did not finish in time. Please retry.');
  }
}
