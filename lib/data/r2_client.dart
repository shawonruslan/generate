import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Cloudflare Worker gateway in front of the R2 bucket (`r2-worker/worker.js`).
class R2Client {
  R2Client(this.workerUrl);
  final String workerUrl;

  /// `uploadToR2(blob, originalName, prefixFolder)` -> public URL.
  Future<String> upload(Uint8List bytes, String originalName, String prefixFolder, {String? mimeType, void Function(double)? onProgress}) async {
    final cleanedName = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_');
    final destinationKey = '$prefixFolder/${DateTime.now().millisecondsSinceEpoch}_$cleanedName';
    final req = http.Request('POST', Uri.parse(workerUrl))
      ..headers['X-File-Name'] = destinationKey
      ..headers['X-File-Type'] = mimeType ?? 'image/jpeg'
      ..bodyBytes = bytes;
    final streamed = await req.send().timeout(const Duration(minutes: 10));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Gateway R2 Upload failed with status: ${res.statusCode}');
    }
    final json = jsonDecode(res.body);
    final url = json is Map ? json['url'] : null;
    if (url is! String || url.isEmpty) throw Exception('Gateway R2 Upload returned no url');
    return url;
  }

  /// `r2KeyFromUrl`
  static String keyFromUrl(String value) {
    final u = Uri.tryParse(value);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) throw Exception('Invalid media URL');
    final key = Uri.decodeComponent(u.path.replaceFirst(RegExp(r'^/+'), ''));
    if (key.isEmpty) throw Exception('Media URL has no object key');
    return key;
  }

  /// v19 verified delete (`r2DeleteFile`). Fails closed.
  Future<Map<String, dynamic>> deleteFile(String url) async {
    final key = keyFromUrl(url);
    final res = await http
        .delete(Uri.parse(workerUrl),
            headers: {'Content-Type': 'application/json', 'X-R2-Delete-Protocol': 'r2-delete-v1'}, body: jsonEncode({'url': url}))
        .timeout(const Duration(seconds: 30));
    Map<String, dynamic> body;
    try {
      final j = jsonDecode(res.body);
      body = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    } catch (_) {
      throw Exception('R2 HTTP ${res.statusCode}: unverified response. Deploy the v19 Worker.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('R2 HTTP ${res.statusCode}: ${body['error'] ?? 'delete failed'}');
    if (body['ok'] != true || body['absent'] != true || body['deleteProtocol'] != 'r2-delete-v1' || body['key'] != key || body['sourceUrl'] != url) {
      throw Exception('R2 deletion not verified. Deploy the v19 Worker with the correct bucket binding.');
    }
    return body;
  }
}

class NetworkBlockedException implements Exception {
  NetworkBlockedException(this.message);
  final String message;
  @override
  String toString() => message;
}
