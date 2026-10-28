import 'dart:io';
import 'dart:typed_data';

import 'package:ai_image_studio/compare/similarity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Platform.environment['AIS_CALIB'];
  test('calibration', () {
    Uint8List f(String n) => File('$dir/$n').readAsBytesSync();
    final pairs = [
      ['p10.jpg', 'p10.jpg'], ['p10.jpg', 'p10_copy.jpg'], ['p10.jpg', 'p10_zoom.jpg'],
      ['p10.jpg', 'p10_flip.jpg'], ['p10.jpg', 'p20.jpg'], ['p10.jpg', 'p30.jpg'],
      ['p20.jpg', 'p40.jpg'], ['p30.jpg', 'p50.jpg'], ['p40.jpg', 'p60.jpg'], ['p50.jpg', 'p60.jpg'],
    ];
    for (final p in pairs) {
      final r = compareImages(f(p[0]), f(p[1]))!;
      // ignore: avoid_print
      print('${p[0]} vs ${p[1]}: ${r.similarity.toStringAsFixed(1)}  '
          '${r.metrics.map((m) => '${m.key}=${(m.similarity * 100).round()}').join(' ')}');
      final same = p[0].substring(0, 3) == p[1].substring(0, 3);
      expect(same ? r.similarity > 70 : r.similarity < 30, isTrue);
    }
    // Same palette, different picture: colour must be clearly shared.
    final u = compareImages(f('userA.jpg'), f('userB.jpg'))!;
    final colour = u.metrics.firstWhere((m) => m.key == 'colour').similarity;
    // ignore: avoid_print
    print('userA vs userB: ${u.similarity.toStringAsFixed(1)} colour=${(colour * 100).round()}');
    expect(colour, greaterThan(0.3));
    for (final v in ['userA_hue.jpg', 'userA_dark.jpg']) {
      final r = compareImages(f('userA.jpg'), f(v))!;
      // ignore: avoid_print
      print('userA vs $v: ${r.similarity.toStringAsFixed(1)}  '
          '${r.metrics.map((m) => '${m.key}=${(m.similarity * 100).round()}').join(' ')}');
    }
  }, skip: dir == null);
}
