import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_image_studio/gemini_image.dart';

void main() {
  test('toHdUrl', () {
    expect(GeminiImageClient.toHdUrl('https://lh3.googleusercontent.com/gg-dl/abc=w1024?x=1'),
        'https://lh3.googleusercontent.com/gg-dl/abc=s0');
  });
  test('parseStream extracts image url + text', () {
    final url = 'https://lh3.googleusercontent.com/gg-dl/AOI_d_${'x' * 60}=w1024';
    final inner = jsonEncode([null, ['c_1', 'r_1'], null, null, [
      ['rc_1', ['Here is your image'], null, null, null, null, null, null, null, null, null, null, [[[null, [null, null, null, null, null, null, null, [url]]]]]]
    ]]);
    final raw = ")]}'\n\n123\n${jsonEncode([['wrb.fr', null, inner]])}\n";
    final r = GeminiImageClient.parseStream(raw);
    expect(r.text, 'Here is your image');
    expect(r.urls.single, startsWith('https://lh3.googleusercontent.com/gg-dl/AOI_d_'));
    expect(r.urls.single.endsWith('=w1024'), isFalse);
  });
  test('prompt helpers', () {
    expect(GeminiImageClient.buildImagePrompt('a cat', '9:16'), 'Generate an image of: a cat (aspect ratio 9:16)');
    expect(GeminiImageClient.cleanPrompt('Prompt: "a red fox"'), 'a red fox');
  });
}
