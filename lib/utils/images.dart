import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'config.dart';

/// Client-side image prep, mirroring the web app:
/// - static avatars are cropped to a 256×256 square (<500 KB) before PUT /api/avatar
/// - animated GIF avatars are uploaded untouched (<=2 MB) to preserve animation
bool isGifBytes(List<int> b) =>
    b.length >= 6 &&
    b[0] == 0x47 &&
    b[1] == 0x49 &&
    b[2] == 0x46 &&
    b[3] == 0x38 &&
    (b[4] == 0x37 || b[4] == 0x39) &&
    b[5] == 0x61;

Future<File> _toTempJpg(img.Image image, String prefix) async {
  final dir = await getTemporaryDirectory();
  final f = File(
      '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg');
  await f.writeAsBytes(img.encodeJpg(image, quality: 85));
  return f;
}

/// Center-crop to square + resize to 256×256 (or pass through GIFs <= 2 MB).
Future<File> shrinkForAvatar(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  if (isGifBytes(bytes) || path.toLowerCase().endsWith('.gif')) {
    if (bytes.length > AppConfig.avatarGifMaxBytes) {
      throw Exception('GIF avatar must be 2 MB or smaller.');
    }
    return file;
  }
  final src = img.decodeImage(bytes);
  if (src == null) throw Exception('Could not read that image.');
  final side = src.width < src.height ? src.width : src.height;
  final cropped = img.copyCrop(src,
      x: (src.width - side) ~/ 2,
      y: (src.height - side) ~/ 2,
      width: side,
      height: side);
  return _toTempJpg(img.copyResize(cropped, width: 256, height: 256), 'avatar');
}
