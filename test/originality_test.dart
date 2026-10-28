import 'package:ai_image_studio/browser/image_prompt_service.dart';
import 'package:ai_image_studio/compare/originality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('variation brief sizes and randomness', () {
    expect(variationBrief(CreativityLevel.faithful, 1), isEmpty);
    final b = variationBrief(CreativityLevel.bold, 1);
    expect('\n- '.allMatches(b).length, 7);
    expect(variationBrief(CreativityLevel.creative, 1),
        isNot(variationBrief(CreativityLevel.creative, 2)));
    expect('\n- '.allMatches(variationBrief(CreativityLevel.balanced, 3)).length, 3);
  });
  test('prompt similarity', () {
    const a = 'A lone astronaut walking on a glowing violet desert under twin moons, cinematic';
    expect(promptSimilarity(a, a), 1);
    expect(promptSimilarity(a, 'A bowl of ramen on a wooden table, steam rising, food photo') < 0.1, isTrue);
  });
  test('AI review parsing', () {
    final r = AiCompareReview.parse('Sure!\n\\[REVIEW\\]\nsimilarity: 34\nrisk: Low\n'
        'verdict: Clearly a new picture.\nkept: teal palette; misty mood\n'
        'changed: new subject; new angle; night\nadvice: none\n\\[/REVIEW\\]');
    expect(r.similarity, 34);
    expect(r.risk, 'low');
    expect(r.kept.length, 2);
    expect(r.changed.length, 3);
  });
}
