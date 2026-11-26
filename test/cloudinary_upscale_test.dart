import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_image_studio/cloudinary_api.dart';
import 'package:ai_image_studio/cloudinary_upscale.dart';
import 'package:ai_image_studio/gemini_image_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

const creds = CloudinaryCredentials(cloudName: 'demo', apiKey: 'key', apiSecret: 'secret');

void main() {
  test('crop for AI input does not locally enlarge a small image', () async {
    final bytes = Uint8List.fromList(img.encodeJpg(img.Image(width: 90, height: 160)));
    final out = await cropForUpscaleInBackground(bytes, '9:16');
    expect(out, isNotNull);
    expect(out!.width, 90);
    expect(out.height, 160);
  });

  test('uploads signed image, requests AI derivative and polls pending', () async {
    var polls = 0;
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        expect(req.url.toString(), 'https://api.cloudinary.com/v1_1/demo/image/upload');
        expect(req.body, contains('ais_gemini_upscale'));
        expect(req.body, contains('signature'));
        expect(req.body, isNot(contains('secret')));
        return http.Response(jsonEncode({'secure_url': 'https://res.cloudinary.com/demo/image/upload/v123/ais_gemini_upscale/x.jpg'}), 200);
      }
      expect(req.url.toString(), contains('/c_limit,w_1024,h_1024/e_upscale/c_limit,w_2880,h_2880/f_jpg,q_95/'));
      polls++;
      if (polls == 1) return http.Response('', 423);
      return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'image/jpeg'});
    });
    final bytes = await http.runWithClient(
        () => CloudinaryUpscaler(creds, pollDelay: Duration.zero).upscale(Uint8List.fromList([1])),
        () => client);
    expect(bytes, [1, 2, 3]);
    expect(polls, 2);
  });

  test('fails visibly without credentials rather than silently using local upscale', () async {
    final svc = CloudinaryUpscaler(const CloudinaryCredentials(cloudName: '', apiKey: '', apiSecret: ''));
    await expectLater(svc.upscale(Uint8List.fromList([1])),
        throwsA(isA<CloudinaryApiException>().having((e) => e.code, 'code', 'CREDENTIALS_REQUIRED')));
  });

  test('reports transformation errors rather than pretending success', () async {
    final client = MockClient((req) async => req.method == 'POST'
        ? http.Response(jsonEncode({'secure_url': 'https://res.cloudinary.com/demo/image/upload/v1/x.jpg'}), 200)
        : http.Response('not allowed', 400));
    await expectLater(http.runWithClient(
        () => CloudinaryUpscaler(creds, pollDelay: Duration.zero).upscale(Uint8List.fromList([1])),
        () => client), throwsA(isA<CloudinaryApiException>().having((e) => e.code, 'code', 'UPSCALE_400')));
  });
}
