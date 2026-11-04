import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Client-side image prep, mirroring the web app:
/// - avatars are cropped to a 256×256 square (<480 KB) before PUT /api/avatar
Future<File> _toTempJpg(img.Image image, String prefix) async {
  final dir = await getTemporaryDirectory();
  final f = File(
      '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg');
  await f.writeAsBytes(img.encodeJpg(image, quality: 85));
  return f;
}

/// Center-crop to square + resize to 256×256.
Future<File> shrinkForAvatar(String path) async {
  final bytes = await File(path).readAsBytes();
  final src = img.decodeImage(bytes);
  if (src == null) throw Exception('Could not read that image.');
  final side = src.width < src.height ? src.width : src.height;
  final cropped = img.copyCrop(src,
      x: (src.width - side) ~/ 2, y: (src.height - side) ~/ 2,
      width: side, height: side);
  return _toTempJpg(img.copyResize(cropped, width: 256, height: 256), 'avatar');
}
