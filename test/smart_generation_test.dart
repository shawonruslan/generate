import 'package:flutter_test/flutter_test.dart';
import 'package:ai_image_studio/browser/image_prompt_service.dart';
import 'package:ai_image_studio/compare/element_plan.dart';
import 'package:ai_image_studio/compare/target_generator.dart';

void main() {
  ImagePromptItem item(int t) => ImagePromptItem(
      id: 'a', src: 'https://x/y.jpg', pageUrl: '', state: ImagePromptState.done,
      prompt: 'a red fox in snow')
    ..target = t
    ..palette = ['#112233', '#ffffff']
    ..tone = 'bright, high contrast';

  test('smart prompt adds the source look only when the % keeps it', () {
    expect(smartPrompt('p', null), 'p');
    expect(smartPrompt('p', item(30)), 'p');
    final mid = smartPrompt('p', item(45));
    expect(mid, contains('#112233'));
    expect(mid, isNot(contains('exposure')));
    expect(smartPrompt('p.', item(80)), contains('exposure: bright'));
  });

  test('one-shot brief asks for elements and prompt in one answer', () {
    final b = oneShotElementBrief(60);
    expect(b, contains('[ELEMENTS]'));
    expect(b, contains('[/PROMPT]'));
    expect(b, contains('60%'));
    const reply = '[ELEMENTS]\nfox | subject | 9 | 9\nsnow | background | 7 | 5\n'
        'trees | background | 4 | 3\nsky | background | 3 | 2\n'
        'light | lighting | 5 | 4\n[/ELEMENTS]\n[PROMPT]A fox[/PROMPT]';
    expect(parseElements(reply).length, 5);
    expect(ImagePromptService.extractPrompt(reply), 'A fox');
  });

  test('look survives save/load', () {
    final j = item(70).toJson();
    final back = ImagePromptItem.fromJson(j)!;
    expect(back.palette, ['#112233', '#ffffff']);
    expect(back.tone, 'bright, high contrast');
  });
}
