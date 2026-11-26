import 'dart:io';

import 'package:ai_image_studio/compare/colour_match.dart';
import 'package:ai_image_studio/compare/similarity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Platform.environment['AIS_CALIB'];
  test('colour transfer pulls the look towards the reference', () {
    final a = File('$dir/boatA.jpg').readAsBytesSync();
    final b = File('$dir/boatB.jpg').readAsBytesSync();
    final before = compareImages(a, b)!;
    final fixed = matchColours(b, a, colourAmountFor(90))!;
    File('$dir/boatB_fixed.jpg').writeAsBytesSync(fixed);
    final after = compareImages(a, fixed)!;
    String m(SimilarityReport r) => '${r.similarity.toStringAsFixed(1)} '
        '${r.metrics.map((m) => '${m.key}=${(m.similarity * 100).round()}').join(' ')}';
    // ignore: avoid_print
    print('before: ${m(before)}\nafter:  ${m(after)}');
    final look = referenceLook(a)!;
    // ignore: avoid_print
    print('look: ${look.paletteHex} ${look.tone}');
    double col(SimilarityReport r) =>
        r.metrics.firstWhere((m) => m.key == 'colour').similarity;
    expect(col(after), greaterThan(col(before) + 0.08));
    expect(after.similarity, greaterThan(before.similarity));
    expect(look.paletteHex, isNotEmpty);
  }, skip: dir == null);

  test('amount mapping', () {
    expect(colourAmountFor(90), closeTo(0.9, 0.01));
    expect(colourAmountFor(30), 0);
  });
}
