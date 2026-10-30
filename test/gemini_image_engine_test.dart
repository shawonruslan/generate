import 'dart:async';
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
    expect(p, contains('9:16 portrait frame'));
    expect(p, contains('AVOID: cartoonish'));
    expect(geminiDrawPrompt('cute anime cat', '9:16', 0),
        isNot(contains('cartoonish')));
    expect(p, contains('Keep attached image 1 but at night'));
    expect(geminiDrawPrompt('a cat', '1:1', 0), contains('square frame'));
  });

  test('result is centre-cropped to the asked ratio', () {
    final src = Uint8List.fromList(
        img.encodePng(img.Image(width: 1024, height: 1024)));
    final r = fitToAspect(src, '9:16')!;
    expect([r.width, r.height], [1620, 2880]); // cropped + upscaled
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

  test('background crop works from inside a closure holding unsendables',
      () async {
    final src = Uint8List.fromList(
        img.encodePng(img.Image(width: 400, height: 400)));
    final pending = Completer<void>(); // unsendable, like screen state
    Future<int?> job() async {
      final f = pending.future;
      final r = await fitToAspectInBackground(src, '9:16', false);
      f.ignore();
      return r?.width;
    }

    expect(await job(), 1620);
    expect(await fillCropInBackground(src, 90, 160, true), isNotNull);
  });

  test('crop follows the detailed subject, plain scenes stay centred', () {
    final im = img.Image(width: 1000, height: 1000);
    // busy checkerboard "subject" on the far left
    for (var y = 300; y < 700; y++) {
      for (var x = 20; x < 250; x++) {
        if (((x ~/ 8) + (y ~/ 8)).isEven) im.setPixelRgb(x, y, 255, 255, 255);
      }
    }
    final off = cropOffset(im, cutWidth: true, window: 563);
    expect(off, lessThan(120));
    final plain = img.Image(width: 1000, height: 1000);
    final c = cropOffset(plain, cutWidth: true, window: 563);
    expect(c, closeTo((1000 - 563) / 2, 30));
  });
}
