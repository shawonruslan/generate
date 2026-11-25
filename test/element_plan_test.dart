import 'package:ai_image_studio/compare/element_plan.dart';
import 'package:ai_image_studio/compare/target_match.dart';
import 'package:flutter_test/flutter_test.dart';

const reply = r'''Here you go:
\[ELEMENTS\]
name | category | impact | identity
--- | --- | --- | ---
- wooden canoe, lower centre, pointing up-left | subject | 9 | 9
**tall coconut palms on both sides** | background | 8 | 8
glowing green palm reflections on the water | effect | 7 | 7
calm dark water | background | 7 | 5
starry night sky | background | 5 | 4
small island with lit beach, mid distance | background | 4 | 5
low eye-level shot, symmetric framing | camera | 6 | 7
central vanishing-point composition | composition | 7 | 8
neon green + deep blue palette | colour | 8 | 7
night, clear weather | time | 4 | 3
glossy digital illustration | style | 6 | 6
calm, dreamy mood | mood | 3 | 3
\[/ELEMENTS\]''';

void main() {
  test('parses the inventory', () {
    final els = parseElements(reply);
    expect(els.length, 12);
    expect(els.first.name, startsWith('wooden canoe'));
    expect(els[1].name, 'tall coconut palms on both sides');
    expect(els.first.impact, 9);
  });

  test('kept weight follows the target', () {
    for (final t in [90, 65, 40, 20]) {
      final els = planElements(parseElements(reply), t);
      final kept = keptShare(els) * 100;
      // ignore: avoid_print
      print('$t% -> kept ${kept.round()}% '
          'changed: ${els.where((e) => e.change).map((e) => e.name).join('; ')}');
      expect((kept - t).abs(), lessThan(10));
      expect(els.any((e) => e.change), isTrue);
    }
    // Low-identity things change first.
    final p90 = planElements(parseElements(reply), 90);
    expect(p90.firstWhere((e) => e.name.startsWith('wooden')).change, isFalse);
  });

  test('brief + guided prompt name the elements', () {
    final els = planElements(parseElements(reply), 65);
    final b = elementBrief(els, 65);
    expect(b, contains('SIMILARITY TARGET: 65%'));
    expect(b, contains('KEEP IDENTICAL'));
    final g = guidedPrompt('new prompt', 65, elements: els);
    expect(g, contains('[1]'));
    expect(g, contains('new prompt'));
    expect(g, contains('CHANGE'));
    // A corrected brief re-plans without touching the stored plan.
    final before = els.where((e) => e.change).length;
    guidedPrompt('x', 30, elements: els);
    expect(els.where((e) => e.change).length, before);
  });
}
