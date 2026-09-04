import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../app_config.dart';

/// Uploads media through the Cloudflare Worker that fronts the R2 bucket.
///
/// Contract matches the existing dashboard exactly: raw body + `X-File-Name`
/// (destination key) + `X-File-Type`, and the worker replies with `{ url }`.
class R2Service {
  static Future<String> upload({
    required Uint8List bytes,
    required String key,
    required String contentType,
  }) async {
    final http.Response res = await http.post(
      Uri.parse(kR2WorkerUrl),
      headers: <String, String>{
        'X-File-Name': key,
        'X-File-Type': contentType,
      },
      body: bytes,
    );
    if (res.statusCode >= 400) {
      throw Exception('R2 gateway upload failed (${res.statusCode})');
    }
    final Object? decoded = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (decoded is Map && decoded['url'] != null) {
      return decoded['url'].toString();
    }
    throw Exception('R2 gateway returned no url');
  }

  /// `folder/1725480000000_clean_name.jpg`
  static String buildKey(String folder, String originalName) {
    final String cleaned =
        originalName.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_');
    return '$folder/${DateTime.now().millisecondsSinceEpoch}_$cleaned';
  }

  static String guessContentType(String fileName) {
    final String lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'image/jpeg';
  }

  static bool isAudioName(String fileName) {
    final String lower = fileName.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.wav');
  }

  static bool isVideoName(String fileName) {
    final String lower = fileName.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.webm');
  }
}
