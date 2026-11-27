import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'cloudinary_api.dart';

/// Credential-free Cloudinary AI upscale - the exact route the
/// Gemini HD Studio Chrome extension uses (background.js
/// upscaleViaCloudinary), ported to Dart.
///
/// Why no user credentials are needed: the extension ships with a
/// public tools cloud (dtz0urit6) + public API key + the
/// "cloudinary-tools" upload preset, and the upload SIGNATURE comes
/// from a public Netlify function that holds the secret server-side.
/// The user never enters anything - same here.
///
/// Flow: sign -> upload -> poll the e_upscale delivery URL until
/// Cloudinary finishes super-resolution -> return the JPG bytes.
/// Live-verified 2026-11-27: a 540x960 test image came back
/// 2048x3640 through this exact flow.
class ExtensionUpscaler {
  static const _signUrl =
      'https://cloudinary-tools.netlify.app/.netlify/functions/sign-upload-params';
  static const _cloud = 'dtz0urit6';
  static const _apiKey = '985946268373735';
  static const _preset = 'cloudinary-tools';
  static const _source = 'ml';

  Future<Uint8List> upscale(Uint8List image) async {
    // 1) Signature from the public signing function.
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signResp = await http
        .post(Uri.parse(_signUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'paramsToSign': {
                'timestamp': ts,
                'upload_preset': _preset,
                'source': _source,
              }
            }))
        .timeout(const Duration(seconds: 30));
    if (signResp.statusCode != 200) {
      throw CloudinaryApiException(
          category: 'upscale_error',
          code: 'SIGN_${signResp.statusCode}',
          message: 'Upscale signing failed (HTTP ${signResp.statusCode}).');
    }
    final signature =
        (jsonDecode(signResp.body) as Map<String, dynamic>)['signature'];
    if (signature is! String || signature.isEmpty) {
      throw const CloudinaryApiException(
          category: 'upscale_error',
          code: 'SIGN_INVALID',
          message: 'Upscale signing returned no signature.');
    }

    // 2) Signed upload to the tools cloud.
    final req = http.MultipartRequest(
        'POST', Uri.parse('https://api.cloudinary.com/v1_1/$_cloud/auto/upload'))
      ..fields['upload_preset'] = _preset
      ..fields['source'] = _source
      ..fields['signature'] = signature
      ..fields['timestamp'] = '$ts'
      ..fields['api_key'] = _apiKey
      ..files.add(http.MultipartFile.fromBytes('file', image,
          filename: 'gemini_${ts}.jpg'));
    final streamed =
        await req.send().timeout(const Duration(seconds: 60));
    final upBody = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw CloudinaryApiException(
          category: 'upscale_error',
          code: 'UPLOAD_${streamed.statusCode}',
          message: 'Upscale upload failed (HTTP ${streamed.statusCode}).');
    }
    final up = jsonDecode(upBody) as Map<String, dynamic>;
    final publicId = up['public_id'] as String?;
    final version = up['version'];
    if (publicId == null || publicId.isEmpty) {
      throw const CloudinaryApiException(
          category: 'upscale_error',
          code: 'UPLOAD_INVALID',
          message: 'Upscale upload returned no public_id.');
    }

    // 3) Poll the AI-upscale delivery URL (the extension's chain:
    // width 512 first, then e_upscale super-resolution) until the
    // derived image is ready - 423/404 mean "still processing".
    const trans = 'f_jpg,w_512,e_upscale,q_auto';
    final plain =
        'https://res.cloudinary.com/$_cloud/image/upload/$trans/$publicId.jpg';
    final versioned = version == null
        ? plain
        : 'https://res.cloudinary.com/$_cloud/image/upload/$trans/v$version/$publicId.jpg';
    for (var attempt = 0; attempt < 14; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      final base = attempt.isOdd ? versioned : plain;
      final url = '$base?_cb=${DateTime.now().millisecondsSinceEpoch}_$attempt';
      http.Response r;
      try {
        r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      } catch (_) {
        continue;
      }
      if (r.statusCode == 200 &&
          (r.headers['content-type'] ?? '').startsWith('image/') &&
          r.bodyBytes.length > 4096 &&
          img.decodeImage(r.bodyBytes) != null) {
        return r.bodyBytes;
      }
      if (r.statusCode == 423 || r.statusCode == 404 || r.statusCode >= 500) {
        continue; // still processing
      }
      throw CloudinaryApiException(
          category: 'upscale_error',
          code: 'DELIVERY_${r.statusCode}',
          message: 'Upscale delivery failed (HTTP ${r.statusCode}).');
    }
    throw const CloudinaryApiException(
        category: 'upscale_error',
        code: 'UPSCALE_TIMEOUT',
        message: 'AI upscale did not finish in time.');
  }
}
