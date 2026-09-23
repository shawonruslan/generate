import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../domain/theme_engine.dart';
import 'common.dart';

/// Meta Hawladar brand mark ("Mh" logo, 1024x1024 art board).
///
/// The three shapes are drawn natively so the colours follow the live theme:
/// tile = surface, "M" = text/ink, "h" = primary. The same path data is used by
/// the web panel (`index.html` zedgeLogo) and the Android app (`BrandLogo.kt`).
class BrandPaths {
  BrandPaths._();
  static const double board = 1024;

  static const String h = 'M749.547 234.206C756.75 233.409 766.278 234.079 773.235 235.857C789.058 240.021 802.63 250.197 811.063 264.218'
      'C821.523 282.001 819.448 300.508 819.449 320.249L819.466 370.718L819.436 529.333L819.416 669.942L819.405 707.5'
      '46C819.399 719.15 820.359 733.486 817.34 744.578C799.856 809.06 699.119 803.933 689.687 737.127C688.014 725.28'
      '2 688.94 709.127 688.964 696.86L689.117 637.954C689.118 621.174 690.382 607.111 681.619 591.993C674.206 579.29'
      '7 662.016 570.1 647.773 566.458C633.987 562.934 597.272 563.88 583.066 566.73C554.859 572.389 533.788 596.679 '
      '526.701 624.121C524.352 636.205 524.694 649.929 524.453 662.277L523.546 710.309C523.422 720.468 523.799 733.11'
      '2 521.559 742.819C519.57 751.586 515.597 759.779 509.946 766.769C499.314 779.757 483.977 788.011 467.281 789.7'
      '33C449.692 791.585 432.53 787.201 418.795 775.858C405.815 765.277 397.674 749.889 396.228 733.205C395.563 725.'
      '929 396.117 715.614 396.258 708.046C396.406 696.693 396.487 685.34 396.503 673.986C396.852 606.483 395.686 555'
      '.077 441.785 499.569C474.871 459.729 522.165 436.926 573.731 436.147C594.637 435.832 616.468 436.98 637.284 43'
      '5.88C648.639 435.279 661.65 429.978 670.13 422.246C691.288 402.953 690.105 384.978 690.113 359.498L690.102 316'
      '.86C690.103 306.105 689.504 290.831 691.848 280.681C693.882 271.731 697.995 263.387 703.852 256.321C715.987 24'
      '1.965 731.177 235.753 749.547 234.206Z';
  static const String m1 = 'M304.965 233.706C322.057 233.899 337.188 237.722 350.032 249.45C371.171 268.752 369.974 285.028 371.143 310.53'
      'C372.318 336.191 377.024 376.701 396.944 394.242C404.657 401.033 413.894 403.847 424.249 403.103C464.773 400.1'
      '92 468.559 340.658 472.26 310.103C473.48 300.028 473.314 288.553 475.907 278.625C478.042 270.547 481.958 263.0'
      '49 487.37 256.684C510.812 229.218 554.273 225.859 581.56 249.353C600.976 266.068 601.752 283.801 603.536 307.3'
      '25L605.982 338.953C608.122 365.176 610.95 392.853 612.589 418.951C580.627 419.413 556.29 417.266 524.746 425.7'
      '29C471.285 440.074 436.249 471.231 408.791 517.793C405.162 524.437 401.875 530.43 399.089 537.504C372.333 537.'
      '253 349.166 548.531 340.431 575.376C336.46 587.583 337.568 604.368 337.511 617.413L336.669 702.34C336.53 712.9'
      '46 337.342 732.244 335.395 741.898C333.572 751.311 329.358 760.097 323.157 767.411C311.853 780.717 295.68 788.'
      '928 278.267 790.202C260.401 791.642 240.794 786.827 226.98 775.04C214.479 764.425 206.724 749.264 205.434 732.'
      '914C204.873 725.231 206.084 713.531 206.728 705.51L210.316 662.683L223.671 504.647L235.349 363.487C236.666 346'
      '.746 238.078 330.013 239.582 313.288C241.357 291.904 240.506 272.339 256.092 255.273C269.604 240.478 285.318 2'
      '34.928 304.965 233.706Z';
  static const String m2 = 'M602.396 581.24C619.906 580.998 637.42 581.066 654.928 581.444C657.632 617.208 662.3 652.875 665.028 688.716C6'
      '67.206 717.325 673.871 745.873 652.179 769.496C638.671 784.207 623.545 789.378 603.978 790.433C587.008 790.764'
      ' 568.989 784.741 556.373 773.374C551.478 768.965 538.207 754.028 538.3 747.434C538.409 739.751 539.333 730.666'
      ' 539.467 722.742L540.649 662.896C540.899 652.909 540.887 635.517 542.889 626.538C544.939 617.099 549.473 608.3'
      '77 556.023 601.277C568.536 587.735 584.344 581.862 602.396 581.24Z';

  static Path? _hPath, _m1Path, _m2Path;
  static Path get hPath => _hPath ??= parseSvgPath(h);
  static Path get m1Path => _m1Path ??= parseSvgPath(m1);
  static Path get m2Path => _m2Path ??= parseSvgPath(m2);
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
      if (cmd.isEmpty) i++;   // stray token before any command
      continue;
    }
    final rel = cmd.toLowerCase() == cmd;
    switch (cmd.toUpperCase()) {
      case 'M': {
        var x = next(), y = next();
        if (rel) { x += cx; y += cy; }
        path.moveTo(x, y);
        cx = sx = x; cy = sy = y; pcx = x; pcy = y;
        cmd = rel ? 'l' : 'L';   // subsequent pairs are implicit line-tos
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

/// Paints the logo into [size] (square). Colours are explicit so the same
/// painter renders the in-app mark and the Windows taskbar icon.
class BrandLogoPainter extends CustomPainter {
  const BrandLogoPainter({required this.tile, required this.ink, required this.mark, this.radiusFactor = 0.22, this.drawTile = true});
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
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * radiusFactor)), Paint()..color = tile!);
    }
    final k = s / BrandPaths.board;
    canvas.scale(k, k);
    final pInk = Paint()..color = ink..isAntiAlias = true;
    final pMark = Paint()..color = mark..isAntiAlias = true;
    canvas.drawPath(BrandPaths.m1Path, pInk);
    canvas.drawPath(BrandPaths.m2Path, pInk);
    canvas.drawPath(BrandPaths.hPath, pMark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandLogoPainter o) => o.tile != tile || o.ink != ink || o.mark != mark || o.radiusFactor != radiusFactor || o.drawTile != drawTile;
}

/// Theme-aware brand mark. Re-colours instantly when the Theme Studio changes
/// primary / surface / text (it watches [AppState.palette]).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 42, this.glow = true, this.radiusFactor = 0.3, this.tile, this.ink, this.mark, this.drawTile = true});
  final double size;
  final bool glow;
  final double radiusFactor;
  final Color? tile, ink, mark;
  final bool drawTile;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tileC = tile ?? p.surface;
    return Container(
      width: size,
      height: size,
      decoration: glow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(size * radiusFactor),
              boxShadow: [BoxShadow(color: p.primary.withValues(alpha: 0.42), blurRadius: size * 0.5, offset: Offset(0, size * 0.18))],
              border: Border.all(color: p.primary.withValues(alpha: 0.35), width: 1),
            )
          : null,
      child: CustomPaint(
        painter: BrandLogoPainter(tile: drawTile ? tileC : null, ink: ink ?? p.text, mark: mark ?? p.primary, radiusFactor: radiusFactor, drawTile: drawTile),
      ),
    );
  }
}

String? _lastIconKey;

/// Windows: re-render the taskbar / title-bar icon in the live theme colours.
/// (macOS / Linux use the static icon baked into the runner; a failure here is
/// silently ignored so it can never break the app.)
Future<void> syncWindowIcon(ZedgePalette p) async {
  if (!Platform.isWindows) return;
  final key = '${p.cfg.primary}|${p.cfg.surface}|${p.cfg.text}';
  if (key == _lastIconKey) return;
  _lastIconKey = key;
  try {
    const double sz = 256;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    BrandLogoPainter(tile: p.surface, ink: p.text, mark: p.primary, radiusFactor: 0.22).paint(canvas, const Size(sz, sz));
    final img = await rec.endRecording().toImage(sz.toInt(), sz.toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (png == null) return;
    final pngBytes = png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    // Minimal ICO container with one PNG-compressed 256x256 entry (Vista+).
    final header = ByteData(22);
    header.setUint16(0, 0, Endian.little);      // reserved
    header.setUint16(2, 1, Endian.little);      // type: icon
    header.setUint16(4, 1, Endian.little);      // one image
    header.setUint8(6, 0);                      // width  0 = 256
    header.setUint8(7, 0);                      // height 0 = 256
    header.setUint8(8, 0);                      // palette
    header.setUint8(9, 0);                      // reserved
    header.setUint16(10, 1, Endian.little);     // colour planes
    header.setUint16(12, 32, Endian.little);    // bits per pixel
    header.setUint32(14, pngBytes.length, Endian.little);
    header.setUint32(18, 22, Endian.little);    // data offset
    final out = BytesBuilder()..add(header.buffer.asUint8List())..add(pngBytes);
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}automation_hub_icon_${key.hashCode.toRadixString(16)}.ico');
    await file.writeAsBytes(out.toBytes(), flush: true);
    await windowManager.setIcon(file.path);
  } catch (_) {
    // ignore - static runner icon stays
  }
}
