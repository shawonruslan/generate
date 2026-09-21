import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dhaka_time.dart';
import '../../domain/run_schedule.dart';
import '../../state/nav.dart';
import 'common.dart';
import 'fa.dart';
import 'responsive.dart';

/// "Today's uploads" live overview (`renderRunTimeline` / `tickOverviewClocks`).
/// Rebuilds every second from `AppState.clockTick`.
class RunTimeline extends StatelessWidget {
  const RunTimeline({super.key, this.showCalendarLink = false});
  final bool showCalendarLink;

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    return ValueListenableBuilder<int>(
      valueListenable: app.clockTick,
      builder: (context, _, __) {
        final now = RealTime.instance.nowMs();
        final cards = app.overview(now);
        final totalDone = cards.fold<int>(0, (a, c) => a + c.doneCount);
        final totalSlots = cards.fold<int>(0, (a, c) => a + c.slots.length);
        return GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
              SectionTitle("Today's uploads", icon: 'fa-clock', subtitle: 'Dhaka · All ${app.accountKeys.length} accounts · Live overview'),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Pill('$totalDone / $totalSlots done', icon: 'fa-check-double', color: p.tintChip, fg: p.text),
                if (showCalendarLink) ...[
                  const SizedBox(width: 8),
                  TextButton(onPressed: () => context.read<NavState>().go(AppTab.schedule), child: const Text('Open calendar ↗')),
                ],
              ]),
            ]),
            const SizedBox(height: 14),
            AutoGrid(minTile: 300, gap: 12, children: [for (final c in cards) _OverviewCardView(card: c, now: now)]),
            const SizedBox(height: 10),
            Text('Scheduled times · 0–14 min random delay · Missed ping? The existing catch-up rule applies.', style: TextStyle(fontSize: 11.5, color: p.muted)),
          ]),
        );
      },
    );
  }
}

class _OverviewCardView extends StatelessWidget {
  const _OverviewCardView({required this.card, required this.now});
  final OverviewCard card;
  final int now;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final next = card.next;
    final complete = card.complete;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card.isActive ? p.primary.withValues(alpha: 0.08) : p.tintSoft,
        borderRadius: BorderRadius.circular(p.radiusMd),
        border: Border.all(color: card.isActive ? p.primary.withValues(alpha: 0.55) : p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(10)),
            child: Text((card.accountIndex + 1).toString().padLeft(2, '0'), style: TextStyle(fontWeight: FontWeight.w900, color: p.onPrimary, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(children: [
              Text(card.key.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, color: p.text, letterSpacing: 0.4)),
              if (card.isActive) ...[
                const SizedBox(width: 6),
                Tooltip(message: 'Active account', child: Container(width: 8, height: 8, decoration: BoxDecoration(color: p.ok, shape: BoxShape.circle))),
              ],
            ]),
          ),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${card.doneCount}', style: TextStyle(fontWeight: FontWeight.w900, color: p.text)),
            TextSpan(text: ' / ${card.slots.length} done', style: TextStyle(color: p.muted, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 12),
        _Focus(next: next, complete: complete, now: now),
        const SizedBox(height: 10),
        for (var i = 0; i < card.slots.length; i++) _row(context, card.slots[i], i, card.slots[i] == next),
      ]),
    );
  }

  Widget _row(BuildContext context, OverviewSlot s, int index, bool isNext) {
    final p = context.pal;
    final state = s.done ? 'done' : (s.passed ? 'passed' : (s.due ? 'due' : (isNext ? 'next' : 'later')));
    final flag = const {'done': 'DONE', 'passed': 'CLOSED', 'due': 'DUE', 'next': 'NEXT', 'later': 'LATER'}[state]!;
    final color = switch (state) { 'done' => p.ok, 'passed' => p.muted, 'due' => p.warn, 'next' => p.primary, _ => p.muted };
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isNext ? p.primary.withValues(alpha: 0.1) : p.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isNext ? p.primary.withValues(alpha: 0.5) : p.border.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(7)),
          child: Text(s.done ? '✓' : (index + 1).toString().padLeft(2, '0'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.run.start, style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 13)),
            Tooltip(message: s.detail, child: Text(s.detail, style: TextStyle(fontSize: 11.5, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        Pill(flag, small: true, color: color.withValues(alpha: 0.18), fg: color),
      ]),
    );
  }
}

class _Focus extends StatelessWidget {
  const _Focus({required this.next, required this.complete, required this.now});
  final OverviewSlot? next;
  final bool complete;
  final int now;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final n = next;
    if (n == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: (complete ? p.ok : p.muted).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(complete ? 'Today’s progress' : 'Today’s windows', style: TextStyle(fontSize: 10.5, letterSpacing: 1, fontWeight: FontWeight.w700, color: p.muted)),
              Text(complete ? 'All slots done' : 'Windows ended', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: p.text)),
            ]),
          ),
          Fa(complete ? 'fa-check-circle' : 'fa-clock', size: 26, color: complete ? p.ok : p.muted),
        ]),
      );
    }
    final r = n.run;
    final phase = now < r.startMs ? 'next' : (now <= r.endMs ? 'due' : (now <= r.windowEndMs ? 'catch' : 'passed'));
    final label = const {'next': 'Next slot in', 'due': 'Slot due · delay', 'catch': 'Catch-up left', 'passed': 'Window closed'}[phase]!;
    final target = phase == 'next' ? r.startMs : (phase == 'due' ? r.endMs : r.windowEndMs);
    final left = ((target - now) / 1000).floor().clamp(0, 1 << 40).toInt();
    final h = left ~/ 3600, m = (left ~/ 60) % 60, s = left % 60;
    Widget digit(int v, String l) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(v.toString().padLeft(2, '0'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: p.text, fontFeatures: const [FontFeature.tabularFigures()])),
          Text(l, style: TextStyle(fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w700, color: p.muted)),
        ]);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [p.primary.withValues(alpha: 0.16), p.accent.withValues(alpha: 0.08)]), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 10.5, letterSpacing: 1, fontWeight: FontWeight.w700, color: p.muted)),
            Text(r.start, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: p.text)),
          ]),
        ),
        digit(h, 'HRS'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: TextStyle(fontSize: 18, color: p.muted))),
        digit(m, 'MIN'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: TextStyle(fontSize: 18, color: p.muted))),
        digit(s, 'SEC'),
      ]),
    );
  }
}
