import 'dart:typed_data';

import 'package:ai_image_studio/screens/batch_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _noise(int w, int h) {
  final im = img.Image(width: w, height: h);
  var s = 7;
  for (final p in im) {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    p.setRgb(s & 255, (s >> 8) & 255, (s >> 16) & 255);
  }
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  for (final size in const [(2048, 1536), (2000, 2000)]) {
    test('companion ${size.$1}x${size.$2} -> 2800x2400 JPEG <= 8 MB', () {
      final out = finalizeFoldableCompanion(_noise(size.$1, size.$2));
      final d = img.decodeJpg(out)!;
      expect(d.width, 2800);
      expect(d.height, 2400);
      expect(d.width * d.height <= 25000000, isTrue);
      expect(out.length <= 8 * 1024 * 1024, isTrue);
      expect(out[0] == 0xFF && out[1] == 0xD8, isTrue);
    });
  }
  test('portrait is rejected / untouched', () {
    expect(isFoldableCompanionShape(1536, 2048), isFalse);
    expect(isFoldableCompanionShape(2048, 1536), isTrue);
    expect(isFoldableCompanionShape(1920, 1080), isFalse);
  });
}
