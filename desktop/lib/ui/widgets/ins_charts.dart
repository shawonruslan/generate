import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'world_map_data.dart';

/// v40.1: donut chart for "Split by revenue type" - hover a slice (or legend row) to see its amount in the middle.
class InsDonut extends StatelessWidget {
  const InsDonut({super.key, required this.values, required this.colors, required this.labelColor, required this.labels, required this.money, this.selected, this.onHover, this.size = 230});
  final List<double> values;
  final List<Color> colors;
  final Color labelColor;
  final List<String> labels;
  final String Function(double) money;
  final int? selected;
  final ValueChanged<int?>? onHover;
  final double size;

  int? _hit(Offset p) {
    final tot = values.fold<double>(0, (s, v) => s + (v > 0 ? v : 0));
    if (tot <= 0) return null;
    final c = Offset(size / 2, size / 2);
    final d = p - c;
    final outer = size / 2 - 34;
    final inner = outer * 0.52;
    if (d.distance < inner - 2 || d.distance > outer + 10) return null;
    var ang = math.atan2(d.dy, d.dx) + math.pi / 2;
    if (ang < 0) ang += 2 * math.pi;
    var acc = 0.0;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      acc += values[i] / tot * 2 * math.pi;
      if (ang <= acc) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tot = values.fold<double>(0, (s, v) => s + (v > 0 ? v : 0));
    final sel = selected;
    return MouseRegion(
      onHover: (e) { final h = _hit(e.localPosition); if (h != selected) onHover?.call(h); },
      onExit: (_) => onHover?.call(null),
      child: GestureDetector(
        onTapDown: (e) => onHover?.call(_hit(e.localPosition)),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: CustomPaint(painter: _DonutPainter(values, colors, labelColor, sel))),
            if (sel != null && sel < values.length && tot > 0)
              IgnorePointer(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(money(values[sel]), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: labelColor)),
                  Text(labels[sel], style: TextStyle(fontSize: 10, color: labelColor.withValues(alpha: 0.65))),
                  Text('${(values[sel] / tot * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: labelColor.withValues(alpha: 0.65))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values, this.colors, this.labelColor, this.selected);
  final List<double> values;
  final List<Color> colors;
  final Color labelColor;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final tot = values.fold<double>(0, (s, v) => s + (v > 0 ? v : 0));
    if (tot <= 0) return;
    final c = Offset(size.width / 2, size.height / 2);
    final outer = size.shortestSide / 2 - 34;
    final stroke = outer * 0.48;
    final r = outer - stroke / 2;
    final n = values.where((v) => v > 0).length;
    const gap = 0.025;
    final labs = <List<dynamic>>[]; // [mid, right?, y, text]
    var a0 = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v <= 0) continue;
      final sweep = v / tot * 2 * math.pi;
      final g = n > 1 ? math.min(gap, sweep / 2) : 0.0;
      final mid = a0 + sweep / 2;
      final on = selected == i;
      final off = on ? Offset(math.cos(mid) * 7, math.sin(mid) * 7) : Offset.zero;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = colors[i % colors.length].withValues(alpha: selected == null || on ? 0.9 : 0.4);
      canvas.drawArc(Rect.fromCircle(center: c + off, radius: r), a0 + g / 2, sweep - g, false, paint);
      labs.add([mid, math.cos(mid) >= 0, c.dy + (outer + 18) * math.sin(mid), '${(v / tot * 100).toStringAsFixed(1)}%']);
      a0 += sweep;
    }
    // keep labels apart: per side sort by y and push down (no more overlapping % texts)
    final lead = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = labelColor.withValues(alpha: 0.35);
    for (final side in [true, false]) {
      final ls = labs.where((l) => l[1] == side).toList()..sort((x, y) => (x[2] as double).compareTo(y[2] as double));
      for (var k = 1; k < ls.length; k++) {
        if ((ls[k][2] as double) - (ls[k - 1][2] as double) < 15) ls[k][2] = (ls[k - 1][2] as double) + 15;
      }
      for (final l in ls) {
        final mid = l[0] as double, y = l[2] as double;
        final e = c + Offset(math.cos(mid) * (outer + 3), math.sin(mid) * (outer + 3));
        final kx = c.dx + math.cos(mid) * (outer + 14);
        final tx = side ? math.max(kx, c.dx + 6) + 9 : math.min(kx, c.dx - 6) - 9;
        canvas.drawPath(Path()..moveTo(e.dx, e.dy)..lineTo(kx, y)..lineTo(side ? tx - 3 : tx + 3, y), lead);
        final tp = TextPainter(
          text: TextSpan(text: l[3] as String, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: labelColor)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(side ? tx : tx - tp.width, y - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.values != values || old.labelColor != labelColor || old.selected != selected;
}

/// v39: world map coloured by revenue per country (hover shows the country + amount).
class InsWorldMap extends StatefulWidget {
  const InsWorldMap({super.key, required this.values, required this.names, required this.emptyColor, required this.borderColor, required this.textColor, required this.money});
  final Map<String, double> values; // ISO-2 -> revenue
  final Map<String, String> names; // ISO-2 -> name
  final Color emptyColor;
  final Color borderColor;
  final Color textColor;
  final String Function(double) money;

  @override
  State<InsWorldMap> createState() => _InsWorldMapState();
}

Map<String, Path>? _worldPaths;
Map<String, Path> _paths() {
  if (_worldPaths != null) return _worldPaths!;
  final out = <String, Path>{};
  kWorldMap.forEach((k, v) {
    final path = Path();
    for (final ring in v.split('|')) {
      final pts = ring.split(' ');
      for (var i = 0; i < pts.length; i++) {
        final xy = pts[i].split(',');
        if (xy.length != 2) continue;
        final x = double.tryParse(xy[0]) ?? 0, y = double.tryParse(xy[1]) ?? 0;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
    }
    out[k] = path;
  });
  _worldPaths = out;
  return out;
}

Color insMapColor(double t) => Color.lerp(const Color(0xFFC9E3FF), const Color(0xFF008CDF), t.clamp(0.0, 1.0))!;

class _InsWorldMapState extends State<InsWorldMap> {
  String? _hover;
  Offset _pos = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: kWorldMapW / kWorldMapH,
      child: LayoutBuilder(builder: (ctx, box) {
        final scale = box.maxWidth / kWorldMapW;
        return MouseRegion(
          onExit: (_) => setState(() => _hover = null),
          onHover: (e) {
            final p = e.localPosition / scale;
            String? hit;
            final paths = _paths();
            for (final k in widget.values.keys) {
              final path = paths[k];
              if (path != null && path.contains(p)) { hit = k; break; }
            }
            if (hit != _hover || (hit != null && (e.localPosition - _pos).distance > 4)) {
              setState(() { _hover = hit; _pos = e.localPosition; });
            }
          },
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: _MapPainter(widget.values, widget.emptyColor, widget.borderColor, scale, _hover))),
            if (_hover != null)
              Positioned(
                left: math.min(_pos.dx + 12, box.maxWidth - 170),
                top: math.max(0, _pos.dy - 34),
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF008CDF), borderRadius: BorderRadius.circular(6)),
                    child: Text('${widget.names[_hover] ?? _hover}  ${widget.money(widget.values[_hover] ?? 0)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.values, this.empty, this.border, this.scale, this.hover);
  final Map<String, double> values;
  final Color empty, border;
  final double scale;
  final String? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final paths = _paths();
    final mx = values.values.fold<double>(0, math.max);
    final lmx = math.log(1 + mx * 100);
    canvas.save();
    canvas.scale(scale);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = border;
    paths.forEach((k, path) {
      final v = values[k];
      Color col = empty;
      if (v != null) {
        final t = lmx > 0 ? math.log(1 + v * 100) / lmx : 0.0;
        col = insMapColor(t);
        if (k == hover) col = Color.lerp(col, Colors.black, 0.18)!;
      }
      canvas.drawPath(path, Paint()..color = col);
      canvas.drawPath(path, line);
    });
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.values != values || old.hover != hover || old.scale != scale || old.empty != empty;
}
