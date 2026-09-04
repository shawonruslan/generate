import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../app_config.dart';

class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Pure-Dart image pipeline (works identically on Windows and Android).
class MediaService {
  /// Cover-crops and resizes any image to 1620x2880 JPEG (quality 92) - the
  /// exact output of the canvas resize in the web dashboard.
  static Future<ProcessedImage> resizeWallpaper(Uint8List source) {
    return compute<Uint8List, ProcessedImage>(_resizeWorker, source);
  }

  static ProcessedImage _resizeWorker(Uint8List source) {
    final img.Image? decoded = img.decodeImage(source);
    if (decoded == null) {
      throw Exception('Could not decode image');
    }
    final img.Image cropped = _coverCrop(decoded, kImageTargetWidth, kImageTargetHeight);
    final Uint8List out = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
    return ProcessedImage(
      bytes: out,
      width: kImageTargetWidth,
      height: kImageTargetHeight,
    );
  }

  static img.Image _coverCrop(img.Image src, int targetW, int targetH) {
    final double scale = (targetW / src.width) > (targetH / src.height)
        ? targetW / src.width
        : targetH / src.height;
    final int scaledW = (src.width * scale).ceil();
    final int scaledH = (src.height * scale).ceil();
    final img.Image scaled = img.copyResize(
      src,
      width: scaledW,
      height: scaledH,
      interpolation: img.Interpolation.cubic,
    );
    final int x = ((scaledW - targetW) / 2).floor().clamp(0, scaledW);
    final int y = ((scaledH - targetH) / 2).floor().clamp(0, scaledH);
    return img.copyCrop(
      scaled,
      x: x,
      y: y,
      width: targetW.clamp(1, scaledW - x),
      height: targetH.clamp(1, scaledH - y),
    );
  }

  /// Small JPEG cover used for videos when no frame could be captured.
  static Future<Uint8List> placeholderCover(String label) {
    return compute<String, Uint8List>(_placeholderWorker, label);
  }

  static Uint8List _placeholderWorker(String label) {
    final img.Image canvas = img.Image(width: 540, height: 960);
    for (int y = 0; y < canvas.height; y++) {
      final double t = y / canvas.height;
      final int r = (255 * (1 - t) + 255 * t).round();
      final int g = (212 * (1 - t) + 138 * t).round();
      final int b = (0 * (1 - t) + 0 * t).round();
      for (int x = 0; x < canvas.width; x++) {
        canvas.setPixelRgb(x, y, r, g, b);
      }
    }
    img.fillCircle(canvas,
        x: 270, y: 440, radius: 90, color: img.ColorRgb8(33, 29, 18));
    img.drawString(
      canvas,
      label.length > 24 ? label.substring(0, 24) : label,
      font: img.arial24,
      x: 24,
      y: 880,
      color: img.ColorRgb8(33, 29, 18),
    );
    return Uint8List.fromList(img.encodeJpg(canvas, quality: 85));
  }

  /// Reads width/height of an encoded image without full decode when possible.
  static Future<Size?> imageSize(Uint8List bytes) async {
    try {
      final img.Image? decoded = await compute<Uint8List, img.Image?>(
          (Uint8List b) => img.decodeImage(b), bytes);
      if (decoded == null) return null;
      return Size(decoded.width.toDouble(), decoded.height.toDouble());
    } catch (_) {
      return null;
    }
  }

  static bool isImageName(String name) {
    final String l = name.toLowerCase();
    return l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.png') ||
        l.endsWith('.webp');
  }

  static bool isVideoName(String name) {
    final String l = name.toLowerCase();
    return l.endsWith('.mp4') || l.endsWith('.mov') || l.endsWith('.webm');
  }

  static bool isAudioName(String name) {
    final String l = name.toLowerCase();
    return l.endsWith('.mp3');
  }
}
