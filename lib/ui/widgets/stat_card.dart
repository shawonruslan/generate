import 'package:flutter/material.dart';

import 'common.dart';
import 'fa.dart';

/// Dashboard stat card (`.stat-card`) with animated number.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.tone = 'primary', this.sub, this.onTap, this.compact = false, this.spark, this.sparkColor});
  final String label;
  final String value;
  final String icon;
  final String tone; // primary | accent | danger | ok | warn | info
  final String? sub;
  final VoidCallback? onTap;
  final bool compact;
  /// Normalized 0..1 sparkline points rendered under the value (index.html `.earn-spark` parity).
  final List<double>? spark;
  final Color? sparkColor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = switch (tone) {
      'danger' => p.danger,
      'ok' => const Color(0xFF0096DF),
      'warn' => p.warn,
      'info' => p.info,
      'secondary' || 'teal' => const Color(0xFF5ECCC6),
      'accent' => const Color(0xFF0096DF),
      'primary' || 'purple' => const Color(0xFF783DB0),
      _ => p.primary,
    };
    final numeric = num.tryParse(value.replaceAll(RegExp(r'[^\d.-]'), '')) != null && !RegExp(r'[a-zA-Z/]').hasMatch(value);
    final valueText = numeric
        ? _AnimatedNumber(value: num.parse(value.replaceAll(RegExp(r'[^\d.-]'), '')), style: TextStyle(fontSize: compact ? 20 : 24, fontWeight: FontWeight.w800, color: p.text, height: 1))
        : Text(value, maxLines: 1, softWrap: false, style: TextStyle(fontSize: compact ? 15 : 17, fontWeight: FontWeight.w800, color: p.text, height: 1.1));
    final card = GlassCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Row(children: [
        Container(
          width: compact ? 38 : 46,
          height: compact ? 38 : 46,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(compact ? 11 : 14),
          ),
          child: Center(child: Fa(icon, size: compact ? 15 : 18, color: p.onPrimary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            // label + value shrink to fit instead of being cut with "..."
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label.toUpperCase(), maxLines: 1, softWrap: false, style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: p.muted)),
              ),
            ),
            const SizedBox(height: 3),
            Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: valueText)),
            if (spark != null && spark!.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SizedBox(
                  height: 30,
                  width: double.infinity,
                  child: CustomPaint(painter: _SparklinePainter(spark!, sparkColor ?? c)),
                ),
              ),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted))),
          ]),
        ),
      ]),
    );
    final tip = sub == null ? '$label: $value' : '$label: $value\n$sub';
    return Tooltip(message: tip, waitDuration: const Duration(milliseconds: 600), child: card);
  }
}

/// index.html `.earn-spark` parity: normalized 0..1 polyline with 0.18-alpha area fill.
class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.points, this.color);
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;
    final step = size.width / (points.length - 1);
    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final v = points[i].clamp(0.0, 1.0);
      final dx = i * step;
      final dy = size.height - v * (size.height - 6) - 3;
      if (i == 0) {
        line.moveTo(dx, dy);
      } else {
        line.lineTo(dx, dy);
      }
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.18)..style = PaintingStyle.fill);
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.points != points || oldDelegate.color != color;
}

class _AnimatedNumber extends StatelessWidget {
  const _AnimatedNumber({required this.value, required this.style});
  final num value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(value is int || value == value.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1), style: style),
    );
  }
}

/// Small legend stat (`.legend-item` / calendar legend cards).
class MiniStat extends StatelessWidget {
  const MiniStat({super.key, required this.label, required this.value, required this.icon, this.color, this.sub});
  final String label;
  final String value;
  final String icon;
  final Color? color;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = color ?? p.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.cardColor.withValues(alpha: p.isDark ? 0.6 : 0.9),
        borderRadius: BorderRadius.circular(p.radiusSm),
        border: Border.all(color: p.border),
      ),
      child: Row(children: [
        Container(width: 30, height: 30, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(9)), child: Center(child: Fa(icon, size: 12, color: p.onPrimary))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: p.muted)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
            if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: p.muted)),
          ]),
        ),
      ]),
    );
  }
}
