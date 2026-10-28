import 'package:ai_image_studio/browser/image_prompt_service.dart';
import 'package:ai_image_studio/compare/originality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('similarity target plans', () {
    final p90 = planFor(90), p60 = planFor(60), p30 = planFor(30), p20 = planFor(20);
    expect(p90.change.length, 1);
    expect(p60.change.length, 5);
    expect(planFor(65).change, containsAll(['Camera & framing', 'Background details']));
    expect(p30.change.length, 9);
    expect(p20.change.length, 9);
    expect(p20.keep, contains('Style & medium'));
    expect(p60.keep, containsAll(['Subject type', 'Subject design', 'Colour palette']));
    final b = similarityBrief(60, 1);
    expect(b, contains('SIMILARITY TARGET: 60%'));
    expect(RegExp(r'^- ', multiLine: true).allMatches(b).length, 11);
    expect(similarityBrief(45, 1), isNot(similarityBrief(45, 2)));
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
