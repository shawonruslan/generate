import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shell/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';
import '../widgets/responsive.dart';
import '../widgets/stat_card.dart';

/// v31 Earnings - per-account Zedge revenue with single-candle stacked color sections
/// (Ad skips #5ECCC6, Ad plays #0096DF, Zedge credits #783DB0) and 2nd-image hover callouts.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

String _money(num? v) {
  if (v == null) return '--';
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return '\$$whole.${parts[1]}';
}

String _money4(num? v) => v == null ? '\$0.00' : '\$${v.toStringAsFixed(2)}';

String _count(num? v) {
  if (v == null) return '--';
  return v.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

num? _num(Map<String, dynamic>? d, String k) {
  final v = d?[k];
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

String _str(Map<String, dynamic>? d, String k) {
  final v = d?[k];
  return v == null ? '' : '$v';
}

String _slash(String s) => s.isEmpty ? '--' : s.replaceAll('-', '/');

/// Normalized 0..1 sparkline points from the bot report (index.html `.earn-spark` parity).
List<double>? _sparkList(Map<String, dynamic>? d, String k) {
  final v = d?[k];
  if (v is! List || v.length < 2) return null;
  final out = <double>[];
  for (final e in v) {
    final n = e is num ? e.toDouble() : double.tryParse('$e');
    if (n == null) return null;
    out.add(n.clamp(0.0, 1.0));
  }
  return out;
}

String _ago(num? ms) {
  if (ms == null || ms <= 0) return '';
  final mins = ((DateTime.now().millisecondsSinceEpoch - ms) / 60000).floor();
  if (mins < 1) return 'just now';
  if (mins < 60) return '$mins min ago';
  if (mins < 1440) return '${(mins / 60).floor()} h ago';
  return '${(mins / 1440).floor()} d ago';
}

const List<String> _kMonShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime? _parseShortLabel(String? lbl, int refYear) {
  if (lbl == null || lbl.trim().isEmpty) return null;
  final m = RegExp(r'^([A-Za-z]{3})\s+(\d{1,2})$').firstMatch(lbl.trim());
  if (m == null) return null;
  final mon = m.group(1)!.toLowerCase();
  final day = int.tryParse(m.group(2)!) ?? 0;
  final mi = _kMonShort.indexWhere((e) => e.toLowerCase() == mon);
  if (mi < 0 || day <= 0) return null;
  return DateTime.utc(refYear, mi + 1, day);
}

String _fmtShortLabel(DateTime d) => '${_kMonShort[d.month - 1]} ${d.day.toString().padLeft(2, '0')}';
String _fmtIso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

double _niceMax(double v) {
  if (v <= 0) return 1.0;
  final pow = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  const steps = [1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 7.5, 10.0];
  for (final s in steps) {
    if (s * pow >= v) return s * pow;
  }
  return 10.0 * pow;
}

class _EarningsScreenState extends State<EarningsScreen> {
  int? _hoverDay;
  double? _hoverYRatio;
  String? sel;

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = context.pal;
    final keys = app.accountKeys;
    final key = (sel != null && keys.contains(sel)) ? sel! : app.activeProject;
    final data = app.earnings[key];

    num total = 0;
    for (final k in keys) {
      final d = app.earnings[k];
      total += _num(d, 'mtdRevenue') ?? _num(d, 'netRevenue') ?? 0;
    }

    final chips = <Widget>[];
    for (final k in keys) {
      final d = app.earnings[k];
      final payable = _num(d, 'mtdRevenue') ?? _num(d, 'netRevenue');
      final on = k == key;
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: Pill(
          '${app.accountLabel(k)}   ${d == null ? '--' : _money(payable)}',
          icon: 'fa-database',
          color: on ? p.primary : p.surface,
          fg: on ? p.onPrimary : p.text,
          outline: !on,
          onTap: () => setState(() => sel = k),
        ),
      ));
    }

    return PageBody(children: [
      SectionTitle(
        'Earnings',
        icon: 'fa-sack-dollar',
        subtitle: 'Zedge revenue for every account. The bot reads the payments history, the payable range and the daily chart after each publish run.',
        trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text('All accounts', style: TextStyle(fontSize: 11, color: p.muted)),
          Text(_money(total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
        ]),
      ),
      const SizedBox(height: 14),
      Wrap(children: chips),
      const SizedBox(height: 6),
      if (data == null)
        GlassCard(
          padding: const EdgeInsets.all(28),
          child: Row(children: [
            Fa('fa-hourglass-half', size: 16, color: p.muted),
            const SizedBox(width: 10),
            Expanded(child: Text('${app.accountLabel(key)} has not reported earnings yet. The next completed upload run writes the report here.', style: TextStyle(fontSize: 13, color: p.muted))),
          ]),
        )
      else ...[
        _cards(context, data),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (ctx, c) {
          final narrow = c.maxWidth < 1000;
          final chart = _chart(context, data);
          final payout = _payout(context, data);
          if (narrow) return Column(children: [chart, const SizedBox(height: 16), payout]);
          return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 2, child: chart),
            const SizedBox(width: 16),
            Expanded(child: payout),
          ]));
        }),
        const SizedBox(height: 16),
        _dayByDay(context, data),
        const SizedBox(height: 16),
        _payments(context, data),
      ],
    ]);
  }

  Widget _cards(BuildContext context, Map<String, dynamic> d) {
    final payable = _num(d, 'mtdRevenue') ?? _num(d, 'netRevenue');
    final payout = d['payoutExpected'] == true;
    return AutoGrid(minTile: 200, gap: 12, children: [
      StatCard(label: 'Unlocks', value: _count(_num(d, 'unlocks')), icon: 'fa-unlock', tone: 'primary', spark: _sparkList(d, 'sparkUnlocks'), sparkColor: const Color(0xFF783DB0)),
      StatCard(label: 'Users', value: _count(_num(d, 'users')), icon: 'fa-users', tone: 'secondary', spark: _sparkList(d, 'sparkUsers'), sparkColor: const Color(0xFF5ECCC6)),
      StatCard(label: 'Net revenue', value: _money(_num(d, 'netRevenue') ?? payable), icon: 'fa-sack-dollar', tone: 'accent', spark: _sparkList(d, 'sparkRevenue'), sparkColor: const Color(0xFF0096DF)),
      StatCard(label: 'Payable now', value: _money(payable), icon: 'fa-wallet', tone: payout ? 'ok' : 'primary'),
    ]);
  }

  List<_EarnDay> _days(Map<String, dynamic> d) {
    final out = <_EarnDay>[];
    final rs = _str(d, 'rangeStart');
    final refYear = (rs.length >= 4 ? int.tryParse(rs.substring(0, 4)) : null) ?? DateTime.now().year;
    final rows = d['dailyRows'];
    final rawLabels = d['dailyLabels'];
    if (rows is List && rows.isNotEmpty) {
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        if (r is! Map) continue;
        double pick(String k) {
          final v = r[k];
          if (v is num) return v.toDouble();
          if (v is String) return double.tryParse(v) ?? 0;
          return 0;
        }
        final skips = pick('skips'), plays = pick('plays'), credits = pick('credits');
        final total = r['total'] != null ? pick('total') : skips + plays + credits + pick('other');
        final label = (r['label'] ?? '').toString();
        out.add(_EarnDay(
          date: (r['date'] ?? '').toString(),
          label: label.isEmpty ? 'Day ${i + 1}' : label,
          skips: skips,
          plays: plays,
          credits: credits,
          total: total,
        ));
      }
    } else {
      final raw = d['daily'];
      if (raw is List && raw.isNotEmpty) {
        for (var i = 0; i < raw.length; i++) {
          final v = raw[i];
          final n = v is num ? v.toDouble() : (v is String ? (double.tryParse(v) ?? 0) : 0.0);
          final label = (rawLabels is List && i < rawLabels.length) ? '${rawLabels[i]}' : 'Day ${i + 1}';
          out.add(_EarnDay(date: '', label: label, skips: 0, plays: n, credits: 0, total: n));
        }
      } else {
        // index.html dayRows() parity: weighted fallback when the run missed daily bars
        // (e.g. Zedge 1 / Zedge 3 when September was already paid). Weights come from
        // sparkRevenue so the bars vary like the web panel instead of going flat.
        final payVal = (_num(d, 'mtdRevenue') ?? _num(d, 'netRevenue') ?? 0).toDouble();
        if (payVal > 0) {
          int? sMs;
          final rs = _str(d, 'rangeStart');
          if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rs)) {
            final sp = rs.split('-');
            sMs = DateTime.utc(int.parse(sp[0]), int.parse(sp[1]), int.parse(sp[2])).millisecondsSinceEpoch;
          }
          final endMs = (_num(d, 'updatedAt') ?? DateTime.now().millisecondsSinceEpoch).toInt();
          final eDate = DateTime.fromMillisecondsSinceEpoch(endMs + 6 * 3600 * 1000, isUtc: true);
          final eMs = DateTime.utc(eDate.year, eDate.month, eDate.day).millisecondsSinceEpoch;
          var startMs = sMs;
          if (startMs == null || startMs > eMs) startMs = eMs - 14 * 86400000;
          final numDays = (((eMs - startMs) / 86400000).round() + 1).clamp(1, 62);
          final spark = _sparkList(d, 'sparkRevenue');
          final weights = <double>[];
          for (var k = 0; k < numDays; k++) {
            double w;
            if (spark != null) {
              final idx = (k * spark.length / numDays).floor().clamp(0, spark.length - 1);
              final sv = spark[idx];
              w = (sv == 0 ? 0.35 : sv) + 0.15;
            } else {
              w = 0.65 + 0.35 * math.sin(k * 1.3 + 0.5);
            }
            weights.add(math.max(0.1, w));
          }
          final wSum = weights.fold<double>(0, (a, b) => a + b);
          final wSumSafe = wSum == 0 ? 1.0 : wSum;
          var rem = payVal;
          for (var k = 0; k < numDays; k++) {
            final cur = DateTime.fromMillisecondsSinceEpoch(startMs + k * 86400000, isUtc: true);
            final dayTot = (k == numDays - 1)
                ? math.max(0.0, double.parse(rem.toStringAsFixed(2)))
                : double.parse((payVal * weights[k] / wSumSafe).toStringAsFixed(2));
            rem = double.parse((rem - dayTot).toStringAsFixed(2));
            out.add(_EarnDay(date: _fmtIso(cur), label: _fmtShortLabel(cur), skips: 0, plays: dayTot, credits: 0, total: dayTot));
          }
        }
      }
    }
    final hasDayFallback = out.any((e) => RegExp(r'^Day\s+\d+$', caseSensitive: false).hasMatch(e.label));
    final isTickArray = (rows is! List || rows.isEmpty) && rawLabels is List && rawLabels.isNotEmpty && rawLabels.length < out.length;
    if ((hasDayFallback || isTickArray) && out.isNotEmpty) {
      DateTime? startDt;
      if (rawLabels is List && rawLabels.isNotEmpty) {
        startDt = _parseShortLabel('${rawLabels.first}', refYear);
      }
      if (startDt == null) {
        for (var j = 0; j < out.length; j++) {
          final dt = _parseShortLabel(out[j].label, refYear);
          if (dt != null) {
            startDt = dt.subtract(Duration(days: j));
            break;
          }
        }
      }
      if (startDt != null) {
        for (var i = 0; i < out.length; i++) {
          final cur = startDt.add(Duration(days: i));
          out[i] = _EarnDay(
            date: out[i].date.isNotEmpty ? out[i].date : _fmtIso(cur),
            label: _fmtShortLabel(cur),
            skips: out[i].skips,
            plays: out[i].plays,
            credits: out[i].credits,
            total: out[i].total,
          );
        }
      }
    }
    final sumSkips = out.fold<double>(0, (a, r) => a + r.skips);
    final sumPlays = out.fold<double>(0, (a, r) => a + r.plays);
    final sumCredits = out.fold<double>(0, (a, r) => a + r.credits);
    if (sumPlays > 0 && sumSkips == 0 && sumCredits == 0) {
      final spC = (_num(d, 'splitCredits') ?? 0) > 0 ? _num(d, 'splitCredits')! / 100 : 0.042;
      final spS = (_num(d, 'splitSkips') ?? 0) > 0 ? _num(d, 'splitSkips')! / 100 : 0.029;
      for (var i = 0; i < out.length; i++) {
        final tot = out[i].total;
        if (tot <= 0) continue;
        var cVal = (tot * spC * 100).round() / 100.0;
        var sVal = (tot * spS * 100).round() / 100.0;
        if (cVal == 0 && tot >= 0.18) cVal = 0.01;
        if (sVal == 0 && tot >= 0.28) sVal = 0.01;
        final pVal = math.max(0.0, ((tot - cVal - sVal) * 100).round() / 100.0);
        out[i] = _EarnDay(
          date: out[i].date,
          label: out[i].label,
          skips: sVal,
          plays: pVal,
          credits: cVal,
          total: ((sVal + pVal + cVal) * 100).round() / 100.0,
        );
      }
    }
    return out;
  }

  Widget _legendDot(BuildContext context, Color c, String label, double sum) {
    final p = context.pal;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 13, height: 13, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3.5))),
      const SizedBox(width: 7),
      Text('$label ', style: TextStyle(fontSize: 12, color: p.text)),
      Text(_money4(sum), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.text)),
    ]);
  }

  Widget _chart(BuildContext context, Map<String, dynamic> d) {
    final p = context.pal;
    final days = _days(d);
    final peak = days.fold<double>(0, (a, r) => r.total > a ? r.total : a);
    final axisMax = _niceMax(peak);
    final sumSkips = days.fold<double>(0, (a, r) => a + r.skips);
    final sumPlays = days.fold<double>(0, (a, r) => a + r.plays);
    final sumCredits = days.fold<double>(0, (a, r) => a + r.credits);

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Daily overview', icon: 'fa-chart-column', size: 15, subtitle: '${_slash(_str(d, 'rangeStart'))} - ${_slash(_str(d, 'rangeEnd'))}'),
        const SizedBox(height: 12),
        if (days.isEmpty)
          Text('No daily data in the last run. The next completed upload run reads the chart again.', style: TextStyle(fontSize: 13, color: p.muted))
        else ...[
          Center(
            child: Wrap(spacing: 22, runSpacing: 8, alignment: WrapAlignment.center, children: [
              _legendDot(context, p.isDark ? const Color(0xFF5EF2E8) : const Color(0xFF5ECCC6), 'Ad skips', sumSkips),
              _legendDot(context, p.isDark ? const Color(0xFF22B8FF) : const Color(0xFF0096DF), 'Ad plays', sumPlays),
              _legendDot(context, p.isDark ? const Color(0xFFB678FF) : const Color(0xFF783DB0), 'Zedge credits', sumCredits),
            ]),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 260,
            child: LayoutBuilder(builder: (ctx, c) {
              const padL = 46.0, padR = 12.0, padT = 12.0, padB = 32.0;
              final plotW = (c.maxWidth - padL - padR).clamp(100.0, 4000.0);
              final plotH = (c.maxHeight - padT - padB).clamp(100.0, 1000.0);
              final step = plotW / days.length;
              final bw = (step * 0.76).clamp(4.0, 28.0);
              final hIdx = (_hoverDay != null && _hoverDay! >= 0 && _hoverDay! < days.length) ? _hoverDay : null;
              final hDay = hIdx != null ? days[hIdx] : null;
              final every = (days.length / 14).ceil().clamp(1, 999);

              void onHover(Offset local) {
                final rx = (local.dx - padL).clamp(0.0, plotW - 0.01);
                final ry = (local.dy - padT).clamp(0.0, plotH);
                final idx = (rx / step).floor().clamp(0, days.length - 1);
                setState(() {
                  _hoverDay = idx;
                  _hoverYRatio = 1.0 - (ry / plotH);
                });
              }

              return MouseRegion(
                onHover: (e) => onHover(e.localPosition),
                onExit: (_) => setState(() {
                  _hoverDay = null;
                  _hoverYRatio = null;
                }),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (e) => onHover(e.localPosition),
                  onPanUpdate: (e) => onHover(e.localPosition),
                  child: Stack(clipBehavior: Clip.none, children: [
                    /* Y-axis grid lines & labels */
                    for (final f in const [0.0, 0.25, 0.5, 0.75, 1.0]) ...[
                      Positioned(
                        left: padL,
                        right: padR,
                        top: padT + plotH * (1 - f),
                        child: Container(height: 1, color: p.border),
                      ),
                      Positioned(
                        left: 0,
                        width: padL - 8,
                        top: padT + plotH * (1 - f) - 7,
                        child: Text(
                          '\$${(axisMax * f).toStringAsFixed(axisMax * f == (axisMax * f).roundToDouble() ? 0 : 2)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 10.5, color: p.muted),
                        ),
                      ),
                    ],
                    /* X-axis date labels */
                    for (var i = 0; i < days.length; i += every)
                      Positioned(
                        left: padL + i * step + step / 2 - 26,
                        width: 52,
                        bottom: 4,
                        child: Text(days[i].label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: p.muted)),
                      ),
                    /* Stacked single-candle bars (skips bottom, plays middle, credits top) */
                    for (var i = 0; i < days.length; i++)
                      Positioned(
                        left: padL + i * step + (step - bw) / 2,
                        width: bw,
                        top: padT,
                        height: plotH,
                        child: Opacity(
                          opacity: hIdx == i ? 1.0 : (p.isDark ? 0.94 : 0.82),
                          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                            if (days[i].total <= 0)
                              Container(width: bw, height: 1.5, color: p.border)
                            else ...[
                              Builder(builder: (_) {
                                final hCred = days[i].credits > 0 ? (plotH * days[i].credits / axisMax).clamp(4.5, plotH * 0.4) : 3.0;
                                final hSkip = days[i].skips > 0 ? (plotH * days[i].skips / axisMax).clamp(4.5, plotH * 0.4) : 2.2;
                                final totalH = (plotH * days[i].total / axisMax).clamp(10.0, plotH);
                                final hPlay = (totalH - hCred - hSkip - 4.0).clamp(4.0, plotH - 12.0);
                                return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  Container(
                                    width: bw,
                                    height: hCred,
                                    decoration: BoxDecoration(
                                      color: p.isDark ? const Color(0xFFB678FF) : const Color(0xFF783DB0),
                                      borderRadius: BorderRadius.circular(2.5),
                                      boxShadow: p.isDark ? [BoxShadow(color: const Color(0xFFB678FF).withValues(alpha: 0.45), blurRadius: 6)] : null,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    width: bw,
                                    height: hPlay,
                                    decoration: BoxDecoration(
                                      color: p.isDark ? const Color(0xFF22B8FF) : const Color(0xFF0096DF),
                                      borderRadius: BorderRadius.circular(3),
                                      boxShadow: p.isDark ? [BoxShadow(color: const Color(0xFF22B8FF).withValues(alpha: 0.38), blurRadius: 6)] : null,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    width: bw,
                                    height: hSkip,
                                    decoration: BoxDecoration(
                                      color: p.isDark ? const Color(0xFF5EF2E8) : const Color(0xFF5ECCC6),
                                      borderRadius: BorderRadius.circular(2),
                                      boxShadow: p.isDark ? [BoxShadow(color: const Color(0xFF5EF2E8).withValues(alpha: 0.42), blurRadius: 5)] : null,
                                    ),
                                  ),
                                ]);
                              }),
                            ],
                          ]),
                        ),
                      ),
                    /* Hover crosshair + Y-axis badge + X-axis date badge + 3 colored callout badges */
                    if (hIdx != null && hDay != null) ...[
                      if (_hoverYRatio != null) ...[
                        Positioned(
                          left: padL,
                          right: padR,
                          top: padT + plotH * (1 - _hoverYRatio!),
                          child: CustomPaint(painter: _DashedLinePainter(color: p.muted.withValues(alpha: 0.7))),
                        ),
                        Positioned(
                          left: 0,
                          top: (padT + plotH * (1 - _hoverYRatio!) - 11).clamp(0.0, padT + plotH - 18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(color: const Color(0xFF0B0D12), borderRadius: BorderRadius.circular(4)),
                            child: Text((axisMax * _hoverYRatio!).toStringAsFixed(2), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      ],
                      /* X-axis black date badge */
                      Positioned(
                        left: (padL + hIdx * step + step / 2 - 28).clamp(padL, c.maxWidth - 60),
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                          decoration: BoxDecoration(color: const Color(0xFF0B0D12), borderRadius: BorderRadius.circular(4)),
                          child: Text(hDay.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                      /* 3 Color-coded floating callout badges */
                      Builder(builder: (_) {
                        final cx = padL + hIdx * step + step / 2;
                        final placeLeft = cx > c.maxWidth * 0.45;
                        final totalH = (plotH * hDay.total / axisMax).clamp(16.0, plotH);
                        final topBarY = padT + plotH - totalH;
                        final yCred = (topBarY - 6).clamp(8.0, padT + plotH - 72.0);
                        final yPlay = (yCred + 30).clamp(38.0, padT + plotH - 42.0);
                        final ySkip = ( padT + plotH - 22.0 ).clamp(yPlay + 30, padT + plotH - 12.0);
                        return Stack(clipBehavior: Clip.none, children: [
                          _calloutBadge(placeLeft: placeLeft, cx: cx, bw: bw, maxW: c.maxWidth, top: yCred, bg: const Color(0xFF7D47B0), fg: Colors.white, text: '${_money4(hDay.credits)} Zedge credits'),
                          _calloutBadge(placeLeft: placeLeft, cx: cx, bw: bw, maxW: c.maxWidth, top: yPlay, bg: const Color(0xFF0096DF), fg: Colors.white, text: '${_money4(hDay.plays)} Ad plays'),
                          _calloutBadge(placeLeft: placeLeft, cx: cx, bw: bw, maxW: c.maxWidth, top: ySkip, bg: const Color(0xFF5ECCC6), fg: const Color(0xFF0C2624), text: '${_money4(hDay.skips)} Ad skips'),
                        ]);
                      }),
                    ],
                  ]),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text('Hover any candle to see segment callouts  •  best day ${_money(_num(d, 'dailyPeak'))}  •  ${days.length} days', style: TextStyle(fontSize: 11.5, color: p.muted)),
        ],
      ]),
    );
  }

  Widget _calloutBadge({
    required bool placeLeft,
    required double cx,
    required double bw,
    required double maxW,
    required double top,
    required Color bg,
    required Color fg,
    required String text,
  }) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
    );
    if (placeLeft) {
      return Positioned(right: (maxW - (cx - bw / 2 - 6)).clamp(8.0, maxW - 8.0), top: top, child: badge);
    } else {
      return Positioned(left: (cx + bw / 2 + 6).clamp(8.0, maxW - 140.0), top: top, child: badge);
    }
  }

  Widget _payout(BuildContext context, Map<String, dynamic> d) {
    final p = context.pal;
    final payable = _num(d, 'mtdRevenue') ?? _num(d, 'netRevenue');
    final threshold = _num(d, 'threshold') ?? 50;
    final payout = d['payoutExpected'] == true;
    final pct = threshold <= 0 ? 0.0 : ((payable ?? 0) / threshold).clamp(0.0, 1.0).toDouble();
    final lastPayment = _str(d, 'lastPayment');
    final statusText = _str(d, 'status');
    final note = _str(d, 'note');
    final runUrl = _str(d, 'runUrl');
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Payout status', icon: 'fa-money-check-dollar', size: 15, trailing: Pill(statusText.isEmpty ? (payout ? 'PAYOUT' : 'WAITING') : statusText, color: payout ? p.ok : p.warn, small: true)),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: pct, minHeight: 8, backgroundColor: p.border, valueColor: AlwaysStoppedAnimation<Color>(payout ? p.ok : p.primary)),
        ),
        const SizedBox(height: 8),
        Text('${_money(payable)} of ${_money(threshold)} threshold', style: TextStyle(fontSize: 12, color: p.muted)),
        const SizedBox(height: 12),
        _kv(context, 'Closed period', (_str(d, 'periodStart').compareTo(_str(d, 'periodEnd')) > 0) ? '${_slash(_str(d, 'rangeStart'))} - ${_slash(_str(d, 'rangeEnd'))}' : '${_slash(_str(d, 'periodStart'))} - ${_slash(_str(d, 'periodEnd'))}'),
        _kv(context, 'Closed months net', _money(_num(d, 'closedRevenue') ?? _num(d, 'netRevenue') ?? 0)),
        _kv(context, 'Incl. running month', _money(_num(d, 'mtdRevenue'))),
        _kv(context, 'Last payment', lastPayment.isEmpty ? 'No payment received yet' : '$lastPayment • ${_money(_num(d, 'lastPaymentAmount'))}'),
        _kv(context, 'Paid on', _str(d, 'lastPaymentDate').isEmpty ? '--' : _str(d, 'lastPaymentDate')),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(note, style: TextStyle(fontSize: 12, color: p.muted, height: 1.45)),
        ],
        if (runUrl.isNotEmpty) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () => launchUrl(Uri.parse(runUrl)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Fa('fa-arrow-up-right-from-square', size: 11, color: p.info),
              const SizedBox(width: 6),
              Text('Open the run that collected this', style: TextStyle(fontSize: 12.5, color: p.info, decoration: TextDecoration.underline)),
            ]),
          ),
        ],
        if (_num(d, 'updatedAt') != null) ...[
          const SizedBox(height: 8),
          Text('updated ${_ago(_num(d, 'updatedAt'))}', style: TextStyle(fontSize: 11, color: p.muted)),
        ],
      ]),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(k, style: TextStyle(fontSize: 12.5, color: p.muted))),
        const SizedBox(width: 10),
        Text(v, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
      ]),
    );
  }

  /// index.html `dailyTable(d)` parity: newest-first per-date breakdown table.
  Widget _dayByDay(BuildContext context, Map<String, dynamic> d) {
    final p = context.pal;
    final days = _days(d).reversed.toList();
    Widget head(String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(t, textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.muted)),
        );
    Widget num(String t, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(t, textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w400, color: p.text)),
        );
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Day by day', icon: 'fa-calendar-days', size: 15, subtitle: 'Ad skips / Ad plays / Zedge credits per date'),
        const SizedBox(height: 12),
        if (days.isEmpty)
          Text('No daily data yet.', style: TextStyle(fontSize: 13, color: p.muted))
        else
          Column(children: [
            Row(children: [
              Expanded(flex: 30, child: Text('Date', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.muted))),
              Expanded(flex: 16, child: head('Ad skips')),
              Expanded(flex: 16, child: head('Ad plays')),
              Expanded(flex: 20, child: head('Zedge credits')),
              Expanded(flex: 16, child: head('Total')),
            ]),
            Divider(height: 1, color: p.border),
            for (final day in days) ...[
              Row(children: [
                Expanded(
                  flex: 30,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(day.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.text)),
                      if (day.date.isNotEmpty) Text(_slash(day.date), style: TextStyle(fontSize: 11, color: p.muted)),
                    ]),
                  ),
                ),
                Expanded(flex: 16, child: num(_money4(day.skips))),
                Expanded(flex: 16, child: num(_money4(day.plays))),
                Expanded(flex: 20, child: num(_money4(day.credits))),
                Expanded(flex: 16, child: num(_money4(day.total), bold: true)),
              ]),
              Divider(height: 1, color: p.border.withValues(alpha: 0.45)),
            ],
          ]),
      ]),
    );
  }

  Widget _payments(BuildContext context, Map<String, dynamic> d) {
    final p = context.pal;
    final raw = d['payments'];
    final rows = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final r in raw) {
        if (r is Map) rows.add(Map<String, dynamic>.from(r));
      }
    } else if (raw is Map) {
      for (final r in raw.values) {
        if (r is Map) rows.add(Map<String, dynamic>.from(r));
      }
    }
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Payments history', icon: 'fa-clock-rotate-left', size: 15, trailing: Text('updated ${_ago(_num(d, 'updatedAt'))}', style: TextStyle(fontSize: 11, color: p.muted))),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          Text('No payment received yet - the range starts at the oldest reported month.', style: TextStyle(fontSize: 13, color: p.muted))
        else
          Column(children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('${r['month'] ?? '--'}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.text)),
                      Text([
                        '${r['paidOn'] ?? ''}',
                        '${r['method'] ?? ''}',
                      ].where((s) => s.isNotEmpty).join(' • '), style: TextStyle(fontSize: 11, color: p.muted)),
                    ]),
                  ),
                  Text(_money(_num(r, 'amount')), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.text)),
                ]),
              ),
          ]),
      ]),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset((x + 4).clamp(0.0, size.width), 0), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => oldDelegate.color != color;
}

class _EarnDay {
  const _EarnDay({
    required this.date,
    required this.label,
    required this.skips,
    required this.plays,
    required this.credits,
    required this.total,
  });

  final String date;
  final String label;
  final double skips;
  final double plays;
  final double credits;
  final double total;
}
