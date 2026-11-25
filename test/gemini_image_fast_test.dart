import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_image_studio/gemini_web.dart';

void main() {
  test('image payload matches the page shape', () {
    final p = GeminiWebClient.imageRequestPayload('draw a cat', const []);
    expect(p[0], ['draw a cat', 0, null, null, null, null, 0]);
    expect(p[1], ['en']);
    expect(p.length, 12);
    final up = GeminiWebClient.imageRequestPayload(
        'edit', const [GeminiWebUpload('/contrib_service/x', 'ref1.jpg')],
        aspectRatio: '9:16');
    expect(up.length, 42);
    expect(up[41], [1]);
    expect(jsonEncode(up[0][3][0][0]), '["/contrib_service/x",1,null,"image/jpeg"]');
    expect(jsonEncode(up[0][9]), '[null,null,null,null,null,null,[null,[null,"9:16"]]]');
  });

  test('finds image links in candidates and dedupes, HD link', () {
    const u = 'https://lh3.googleusercontent.com/gg-dl/AOI_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG=s1024';
    final inner = jsonEncode([null, ['c_123456789abc', 'r_1'], null, null,
      [['rc_1', ['here'], null, null, null, null, null, null, null, null, null, null, [[[[null, null, null, [null, null, u]]], [[null, null, null, [null, null, '$u-rj']]]]]]]]);
    final raw = ")]}'\n\n${jsonEncode([['wrb.fr', null, inner]])}\n";
    final urls = GeminiWebClient.generatedImageUrls(raw);
    expect(urls.length, 1);
    expect(GeminiWebClient.hdImageUrl(urls.first),
        'https://lh3.googleusercontent.com/gg-dl/AOI_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG=s0');
  });
}
