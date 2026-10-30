import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ai_image_studio/cloudinary_api.dart';
import 'package:ai_image_studio/gemini_image_api.dart';
import 'package:ai_image_studio/gemini_web.dart';
import 'package:ai_image_studio/local_image_server.dart';

String _stream(dynamic body) {
  final chunk = jsonEncode([
    ['wrb.fr', null, jsonEncode(body)]
  ]);
  return ")]}'\n\n${chunk.length}\n$chunk\n";
}

void main() {
  test('generated image links are found anywhere in the reply', () {
    const u1 = 'https://lh3.googleusercontent.com/gg-dl/AHiVA1abc';
    const u2 = 'https://lh3.googleusercontent.com/gg-dl/AHiVA1def';
    final raw = _stream([
      null,
      ['c_1', 'r_1'],
      null,
      null,
      [
        [
          'rc_1',
          ['Here you go'],
          null, null, null, null, null, null, null, null, null, null,
          [
            null, null, null, null, null, null, null,
            [
              [
                [
                  [null, null, null, [null, null, null, u1]]
                ],
                [
                  [null, null, null, [null, null, null, u2]]
                ]
              ]
            ]
          ]
        ]
      ]
    ]);
    expect(GeminiWebClient.generatedImageUrls(raw), [u1, u2]);
    expect(GeminiWebClient.generatedImageUrls(_stream(['no image here'])),
        isEmpty);
  });

  test('download link asks for the size like the Gemini page', () {
    expect(
        GeminiWebClient.sizedImageUrl(
            'https://lh3.googleusercontent.com/gg-dl/AB12', 2048),
        'https://lh3.googleusercontent.com/gg-dl/AB12=s2048-rj?alr=yes');
    expect(
        GeminiWebClient.sizedImageUrl(
            'https://lh3.googleusercontent.com/gg-dl/AB12=s1024-rj?authuser=2&alr=yes',
            2048),
        'https://lh3.googleusercontent.com/gg-dl/AB12=s2048-rj?alr=yes');
  });

  test('draw prompt asks for an image with ratio and references', () {
    final p = geminiDrawPrompt('Keep [1] but at night', '9:16', 1);
    expect(p, startsWith('Generate an image based on the attached image.'));
    expect(p, contains('Aspect ratio 9:16 (portrait)'));
    expect(p, contains('Keep attached image 1 but at night'));
    expect(geminiDrawPrompt('a cat', '1:1', 0), contains('(square)'));
  });

  test('result is centre-cropped to the asked ratio', () {
    final src = Uint8List.fromList(
        img.encodePng(img.Image(width: 1024, height: 1024)));
    final r = fitToAspect(src, '9:16')!;
    expect(r.width / r.height, closeTo(9 / 16, 0.01));
    expect(r.height, 1024);
    final f = fillCrop(src, 162, 288)!;
    final d = img.decodeImage(f)!;
    expect([d.width, d.height], [162, 288]);
  });

  test('export preset on a local image goes to the local server', () {
    const local = 'http://127.0.0.1:47823/g/g_1_a.jpg';
    expect(ExportPresets.displayUrl(local, 1),
        '$local?fill=1620x2880&f=jpg');
    expect(ExportPresets.displayUrl(local, 0), local);
    expect(LocalImageServer.isLocal(local), isTrue);
  });

  test('image link inside a nested JSON string, old gg/ links, chat id', () {
    const u = 'https://lh3.googleusercontent.com/gg/AAbbCC123';
    final inner = jsonEncode([
      [null, [null, null, null, u]]
    ]);
    final raw = _stream([
      null,
      ['c_0123456789abcdef', 'r_1'],
      inner
    ]);
    expect(GeminiWebClient.generatedImageUrls(raw), [u]);
    expect(GeminiWebClient.conversationIdFrom(raw), 'c_0123456789abcdef');
    // placeholder link in the text is not an image
    expect(
        GeminiWebClient.generatedImageUrls(_stream([
          'http://googleusercontent.com/image_generation_content/0'
        ])),
        isEmpty);
  });
}
