import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'ai_upscale.dart';
import 'cloudinary_api.dart';

/// Gemini HD Studio style upscale for local / Gemini bytes:
/// pre-crop to target aspect -> upload to *your* Cloudinary ->
/// `f_jpg,w_512,e_upscale,q_auto` (fast 4x, same as the extension) ->
/// final cover resize to the exact target JPG (e.g. 1620x2880, <=8 MB).
class LocalUpscale {
  LocalUpscale(this.creds);
  final CloudinaryCredentials creds;

  static const int maxBytes = 8 * 1024 * 1024;

  Future<String> _upload(Uint8List bytes, String filename) async =>
      (await uploadBytes(bytes, filename: filename))['secure_url'] as String;

  /// Signed upload of raw bytes to your Cloudinary; returns the upload JSON
  /// (secure_url, width, height, bytes, format, public_id...).
  Future<Map<String, dynamic>> uploadBytes(Uint8List bytes,
      {String filename = 'image.jpg'}) async {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final sig = sha1
        .convert('timestamp=$ts${creds.apiSecret.trim()}'.codeUnits)
        .toString();
    final req = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/'
            '${creds.cloudName.trim()}/image/upload'))
      ..fields['api_key'] = creds.apiKey.trim()
      ..fields['timestamp'] = ts
      ..fields['signature'] = sig
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename));
    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 90)));
    if (res.statusCode != 200) {
      throw StateError('Cloudinary upload failed (HTTP ${res.statusCode}).');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (j['secure_url'] is! String) {
      throw StateError('Cloudinary upload returned no URL.');
    }
    return j;
  }

  /// [fast] = extension mode (w_512 then 4x AI upscale, a few seconds).
  /// Otherwise full e_upscale on the original (source must be < 4.2 MP).
  Future<Uint8List> upscale(
    Uint8List source, {
    int targetWidth = 1620,
    int targetHeight = 2880,
    bool fast = true,
    String filename = 'upscale.jpg',
    void Function(String)? onStatus,
  }) async {
    if (!creds.isComplete) {
      throw StateError('Add Cloudinary credentials in Settings for AI Upscale.');
    }
    onStatus?.call('Matching aspect ratio...');
    final cropped = await Isolate.run(
        _CoverJob(source, targetWidth, targetHeight, null).run);
    onStatus?.call('Uploading to Cloudinary...');
    final url = await _upload(cropped, filename);
    final upUrl = fast
        ? transformImageUrl(url, 'f_jpg,w_512,e_upscale,q_auto')
        : AiUpscale.url(url, after: 'f_jpg,q_auto');
    onStatus?.call('Cloudinary AI upscaling...');
    final up = await _waitFetch(upUrl, onStatus);
    onStatus?.call('Resizing to ${targetWidth}x$targetHeight JPG...');
    return Isolate.run(_CoverJob(up, targetWidth, targetHeight, maxBytes).run);
  }

  Future<Uint8List> _waitFetch(String url, void Function(String)? onStatus) async {
    final watch = Stopwatch()..start();
    var n = 0;
    while (watch.elapsed < const Duration(minutes: 3)) {
      n++;
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      final type = (r.headers['content-type'] ?? '').toLowerCase();
      if (r.statusCode == 200 && type.startsWith('image/')) return r.bodyBytes;
      if (r.statusCode != 423 && r.statusCode != 420) {
        throw StateError('Cloudinary AI Upscale failed (HTTP ${r.statusCode})'
            '${r.headers['x-cld-error'] == null ? '.' : ': ${r.headers['x-cld-error']}'}');
      }
      onStatus?.call('Cloudinary is upscaling... ($n)');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw TimeoutException('Cloudinary AI Upscale is still processing.');
  }

  /// Center cover-crop + resize, JPG; steps quality down to fit [limit].
  static Uint8List coverJpg(Uint8List bytes, int w, int h, int? limit) {
    final src = img.decodeImage(bytes);
    if (src == null) throw StateError('Could not decode image.');
    final targetAspect = w / h;
    var cw = src.width, ch = src.height;
    if (cw / ch > targetAspect) {
      cw = (ch * targetAspect).round();
    } else {
      ch = (cw / targetAspect).round();
    }
    final crop = img.copyCrop(src,
        x: (src.width - cw) ~/ 2, y: (src.height - ch) ~/ 2,
        width: cw, height: ch);
    final out = limit == null
        ? crop
        : img.copyResize(crop,
            width: w, height: h, interpolation: img.Interpolation.cubic);
    for (final q in const [100, 97, 94, 90, 86]) {
      final jpg = Uint8List.fromList(img.encodeJpg(out, quality: q));
      if (limit == null || jpg.length <= limit) return jpg;
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: 82));
  }
}

class _CoverJob {
  const _CoverJob(this.bytes, this.w, this.h, this.limit);
  final Uint8List bytes;
  final int w, h;
  final int? limit;
  Uint8List run() => LocalUpscale.coverJpg(bytes, w, h, limit);
}
