import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../domain/theme_engine.dart';
import 'common.dart';

/// Meta Hawladar brand mark ("MH" logo, 1024x1024 art board).
///
/// Uses the official purple rounded-square badge (#6835BD) and white "MH"
/// monogram (#FFFFFF), matching `index.html` and Android's `BrandLogo.kt`.
class BrandPaths {
  BrandPaths._();
  static const double board = 1024;
  static const Color badgeColor = Color(0xFF6835BD);
  static const Color monogramColor = Color(0xFFFFFFFF);

  static const String mh = 'M967.39 291.58L964.72 287.96L961.48 285.30L957.42 283.43L952.76 282.46L884.51 282.27L877.19 282.96L8'
      '69.53 285.22L862.86 288.78L857.91 292.97L852.54 299.61L848.93 306.93L799.33 458.55L796.60 462.25L793'
      '.37 462.90L641.50 463.05L633.47 462.54L632.19 461.01L632.40 458.55L689.68 303.60L689.85 297.61L688.1'
      '8 292.25L684.81 288.09L679.78 284.87L675.12 283.31L670.79 282.92L596.89 283.66L588.23 285.12L579.58 '
      '288.94L572.59 294.06L515.99 346.78L476.71 381.98L423.09 428.22L419.13 430.20L417.16 429.44L415.55 42'
      '7.35L345.18 306.27L340.56 299.92L335.60 294.92L329.90 290.81L324.24 287.96L317.59 285.75L312.93 285.'
      '03L267.32 285.69L261.99 286.51L256.33 288.66L248.78 294.58L244.39 301.61L185.62 458.90L184.05 461.49'
      'L180.19 462.89L84.56 462.26L76.90 462.85L69.58 464.86L62.53 469.11L57.22 474.68L54.02 481.04L35.45 5'
      '32.31L35.39 537.63L36.87 542.96L39.69 548.01L43.56 552.04L50.27 555.94L58.26 557.86L145.98 557.11L14'
      '8.74 557.77L149.75 559.52L149.19 562.52L84.45 735.38L83.17 743.03L84.94 750.05L87.58 753.73L90.83 75'
      '6.43L94.21 758.12L98.54 759.12L166.45 759.32L174.44 758.36L180.76 755.99L185.80 752.35L190.91 746.69'
      'L193.96 741.37L295.88 471.12L297.72 468.31L299.62 468.31L301.86 470.75L358.36 558.61L366.16 566.76L3'
      '69.52 568.53L373.85 569.33L379.17 568.37L384.83 565.68L419.45 542.21L470.05 504.65L519.79 465.47L523'
      '.17 463.86L524.08 464.91L523.49 467.91L425.21 735.04L424.14 740.04L424.34 745.03L425.67 749.37L428.4'
      '7 753.41L434.10 757.56L440.76 759.25L508.67 759.32L515.33 758.35L521.65 755.96L526.69 752.79L531.07 '
      '748.65L535.53 742.37L538.78 735.04L599.23 561.47L601.95 557.59L605.48 556.78L762.13 556.78L765.95 55'
      '7.97L766.50 559.48L766.12 561.83L707.33 733.05L706.11 738.04L706.15 743.70L708.10 749.38L712.01 754.'
      '22L717.07 757.35L723.72 758.97L786.98 759.29L795.30 758.11L801.29 755.91L807.66 751.75L812.57 747.04'
      'L816.43 741.37L819.48 734.71L967.99 306.93L969.15 298.61Z';

  static const String h = mh;
  static const String m1 = mh;
  static const String m2 = '';

  static Path? _mhPath;
  static Path get mhPath => _mhPath ??= parseSvgPath(mh);
  static Path get hPath => mhPath;
  static Path get m1Path => mhPath;
  static Path get m2Path => Path();
}

/// Minimal SVG path-data parser (M/L/H/V/C/S/Q/Z, absolute + relative).
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLHVCSQZmlhvcsqz]|-?\d*\.?\d+(?:e-?\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = '';
  double cx = 0, cy = 0, sx = 0, sy = 0, pcx = 0, pcy = 0;
  double next() => double.parse(tokens[i++]);
  bool numAhead() => i < tokens.length && !RegExp(r'^[A-Za-z]$').hasMatch(tokens[i]);
  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'^[A-Za-z]$').hasMatch(t)) {
      cmd = t;
      i++;
      if (cmd == 'Z' || cmd == 'z') {
        path.close();
        cx = sx;
        cy = sy;
        continue;
      }
    }
    if (cmd.isEmpty || !numAhead()) {
      if (cmd.isEmpty) i++;
      continue;
    }
    final rel = cmd.toLowerCase() == cmd;
    switch (cmd.toUpperCase()) {
      case 'M': {
        var x = next(), y = next();
        if (rel) { x += cx; y += cy; }
        path.moveTo(x, y);
        cx = sx = x; cy = sy = y; pcx = x; pcy = y;
        cmd = rel ? 'l' : 'L';
        break;
      }
      case 'L': {
        var x = next(), y = next();
        if (rel) { x += cx; y += cy; }
        path.lineTo(x, y);
        cx = x; cy = y; pcx = x; pcy = y;
        break;
      }
      case 'H': {
        var x = next();
        if (rel) x += cx;
        path.lineTo(x, cy);
        cx = x; pcx = x; pcy = cy;
        break;
      }
      case 'V': {
        var y = next();
        if (rel) y += cy;
        path.lineTo(cx, y);
        cy = y; pcx = cx; pcy = y;
        break;
      }
      case 'C': {
        var x1 = next(), y1 = next(), x2 = next(), y2 = next(), x = next(), y = next();
        if (rel) { x1 += cx; y1 += cy; x2 += cx; y2 += cy; x += cx; y += cy; }
        path.cubicTo(x1, y1, x2, y2, x, y);
        pcx = x2; pcy = y2; cx = x; cy = y;
        break;
      }
      case 'S': {
        var x2 = next(), y2 = next(), x = next(), y = next();
        if (rel) { x2 += cx; y2 += cy; x += cx; y += cy; }
        final x1 = 2 * cx - pcx, y1 = 2 * cy - pcy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        pcx = x2; pcy = y2; cx = x; cy = y;
        break;
      }
      case 'Q': {
        var x1 = next(), y1 = next(), x = next(), y = next();
        if (rel) { x1 += cx; y1 += cy; x += cx; y += cy; }
        path.quadraticBezierTo(x1, y1, x, y);
        pcx = x1; pcy = y1; cx = x; cy = y;
        break;
      }
      default:
        i++;
    }
  }
  return path;
}

/// Paints the MH logo into [size] (square).
class BrandLogoPainter extends CustomPainter {
  const BrandLogoPainter({
    this.tile = BrandPaths.badgeColor,
    this.ink = BrandPaths.monogramColor,
    this.mark = BrandPaths.monogramColor,
    this.radiusFactor = 0.5,
    this.drawTile = true,
  });
  final Color? tile;
  final Color ink;
  final Color mark;
  final double radiusFactor;
  final bool drawTile;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final dx = (size.width - s) / 2, dy = (size.height - s) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    if (drawTile && tile != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * radiusFactor)),
        Paint()..color = tile!..isAntiAlias = true,
      );
    }
    final k = s / BrandPaths.board * 0.86;
    canvas.translate(s * 0.07, s * 0.07);
    canvas.scale(k, k);
    final pMark = Paint()
      ..color = mark
      ..isAntiAlias = true;
    canvas.drawPath(BrandPaths.mhPath, pMark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandLogoPainter o) =>
      o.tile != tile || o.ink != ink || o.mark != mark || o.radiusFactor != radiusFactor || o.drawTile != drawTile;
}

/// Official MH brand mark widget.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 42,
    this.glow = true,
    this.radiusFactor = 0.5,
    this.tile,
    this.ink,
    this.mark,
    this.drawTile = true,
  });
  final double size;
  final bool glow;
  final double radiusFactor;
  final Color? tile, ink, mark;
  final bool drawTile;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tileC = tile ?? BrandPaths.badgeColor;
    final markC = mark ?? BrandPaths.monogramColor;
    return Container(
      width: size,
      height: size,
      decoration: glow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(size * radiusFactor),
              boxShadow: [BoxShadow(color: p.primary.withValues(alpha: 0.35), blurRadius: size * 0.45, offset: Offset(0, size * 0.15))],
            )
          : null,
      child: CustomPaint(
        painter: BrandLogoPainter(
          tile: drawTile ? tileC : null,
          ink: ink ?? markC,
          mark: markC,
          radiusFactor: radiusFactor,
          drawTile: drawTile,
        ),
      ),
    );
  }
}

String? _lastIconKey;

/// Windows: render the official MH icon on the taskbar / title-bar.
Future<void> syncWindowIcon(ZedgePalette p) async {
  if (!Platform.isWindows) return;
  const key = 'mh_official_logo_v1';
  if (key == _lastIconKey) return;
  _lastIconKey = key;
  try {
    const double sz = 256;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const BrandLogoPainter(
      tile: BrandPaths.badgeColor,
      ink: BrandPaths.monogramColor,
      mark: BrandPaths.monogramColor,
      radiusFactor: 0.5,
    ).paint(canvas, const Size(sz, sz));
    final img = await rec.endRecording().toImage(sz.toInt(), sz.toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (png == null) return;
    final pngBytes = png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    final header = ByteData(22);
    header.setUint16(0, 0, Endian.little);
    header.setUint16(2, 1, Endian.little);
    header.setUint16(4, 1, Endian.little);
    header.setUint8(6, 0);
    header.setUint8(7, 0);
    header.setUint8(8, 0);
    header.setUint8(9, 0);
    header.setUint16(10, 1, Endian.little);
    header.setUint16(12, 32, Endian.little);
    header.setUint32(14, pngBytes.length, Endian.little);
    header.setUint32(18, 22, Endian.little);
    final out = BytesBuilder()..add(header.buffer.asUint8List())..add(pngBytes);
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}automation_hub_mh_icon.ico');
    await file.writeAsBytes(out.toBytes(), flush: true);
    await windowManager.setIcon(file.path);
  } catch (_) {
    // ignore - static runner icon stays
  }
}
