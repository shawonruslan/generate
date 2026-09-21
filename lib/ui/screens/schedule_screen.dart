import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/dhaka_time.dart';
import '../../data/models.dart';
import '../../domain/run_schedule.dart';
import '../../domain/schedule_planner.dart';
import '../../domain/special_days.dart';
import '../../state/app_state.dart';
import '../dialogs/asset_details.dart';
import '../dialogs/day_picker.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';
import '../widgets/responsive.dart';
import '../widgets/run_timeline.dart';
import '../widgets/stat_card.dart';

/// Schedule Calendar tab: per-account upload schedule + cron health, Mix Mode,
/// today's uploads overview, publishing calendar with drag & drop pinning.
class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    return PageBody(children: [
      Text('All accounts, queue summary & schedule settings', style: TextStyle(fontSize: 12.5, color: p.muted, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      const SizedBox(height: 10),
      GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('Upload Schedule & Cron Health', icon: 'fa-clock'),
          const SizedBox(height: 8),
          Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.5), children: const [
            TextSpan(text: 'Each account uploads '),
            TextSpan(text: '3 times a day', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: '. For every slot pick '),
            TextSpan(text: 'Window', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: ' (bot uploads at one random minute between your From and To times, picked fresh each day) or '),
            TextSpan(text: 'Exact', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: ' (the bot starts ~6 min early and holds the '),
            TextSpan(text: 'Publish', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: ' click until that minute sharp; change the lead via Firebase dashboardSettings/exactLeadMinutes). Times are Dhaka. The bot picks up a saved schedule on its next cron ping.'),
          ])),
          const SizedBox(height: 14),
          AutoGrid(minTile: 330, gap: 12, children: [for (final k in app.accountKeys) _SchedCard(key: ValueKey('sched-$k'), account: k)]),
        ]),
      ),
      const SizedBox(height: 16),
      GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('Mix Mode — 3 slots, 3 different content types', icon: 'fa-shuffle'),
          const SizedBox(height: 8),
          Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.5), children: const [
            TextSpan(text: 'OFF', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: ' (default): the bot keeps the normal rotation - one content type per day (Ringtone day, Wallpaper day, 24H set day ...). '),
            TextSpan(text: 'ON', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: ': the 3 daily upload slots of that account each upload a '),
            TextSpan(text: 'different', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: ' content type (e.g. slot 1 Ringtone, slot 2 Wallpaper, slot 3 Live wallpaper). The order rotates daily; only types that have queued files are used. Pinned files always win.'),
          ])),
          const SizedBox(height: 14),
          AutoGrid(minTile: 330, gap: 12, children: [for (final k in app.accountKeys) _VarietyCard(key: ValueKey('vty-$k'), account: k)]),
        ]),
      ),
      const SizedBox(height: 16),
      const RunTimeline(),
      const SizedBox(height: 16),
      const _CalendarCard(),
    ]);
  }
}

// ---------------------------------------------------------------- schedule settings card
class _SchedCard extends StatefulWidget {
  const _SchedCard({super.key, required this.account});
  final String account;
  @override
  State<_SchedCard> createState() => _SchedCardState();
}

class _SchedCardState extends State<_SchedCard> {
  bool _saving = false;

  List<RunSlot> _draft(AppState app) => app.schedDraft[widget.account] ??= cloneSlots(app.schedule.slotsFor(widget.account));

  Future<void> _pickTime(AppState app, int idx, bool end) async {
    final d = _draft(app);
    final sl = d[idx];
    final init = TimeOfDay(hour: end ? sl.endHour : sl.hour, minute: end ? sl.endMinute : sl.minute);
    final t = await showTimePicker(context: context, initialTime: init, builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!));
    if (t == null) return;
    final hh = t.hour.clamp(0, 23).toInt(), mm = t.minute.clamp(0, 59).toInt();
    if (end) {
      sl.endHour = hh;
      sl.endMinute = mm;
    } else {
      final len = sl.endMin - sl.startMin;
      sl.hour = hh;
      sl.minute = mm;
      if (!sl.exact && len > 0) {
        final e2 = (hh * 60 + mm + len).clamp(0, 23 * 60 + 59).toInt();
        sl.endHour = e2 ~/ 60;
        sl.endMinute = e2 % 60;
      }
    }
    if (sl.exact) {
      sl.endHour = sl.hour;
      sl.endMinute = sl.minute;
    }
    app.touch();
  }

  void _mode(AppState app, int idx, bool exact) {
    final sl = _draft(app)[idx];
    if (sl.exact == exact) return;
    sl.exact = exact;
    if (!exact) {
      final e2 = (sl.startMin + kRunWindowHours * 60).clamp(0, 23 * 60 + 59).toInt();
      sl.endHour = e2 ~/ 60;
      sl.endMinute = e2 % 60;
    } else {
      sl.endHour = sl.hour;
      sl.endMinute = sl.minute;
    }
    app.touch();
  }

  Future<void> _save(AppState app) async {
    final slots = cloneSlots(_draft(app))..sort((a, b) => a.startMin.compareTo(b.startMin));
    final err = validateSlots(slots);
    if (err != null) {
      app.showToast(err, 'error');
      return;
    }
    setState(() => _saving = true);
    try {
      await app.repo.saveSchedule(widget.account, slots);
      app.schedDraft.remove(widget.account);
      app.showToast('${app.accountSpaced(widget.account)} schedule saved - bot uses it from the next ping', 'ok');
    } catch (e) {
      app.showToast('Save failed: ${e.toString().replaceFirst('Exception: ', '')}', 'error');
    }
    if (mounted) setState(() => _saving = false);
    app.touch();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final key = widget.account;
    final live = app.schedule.slotsFor(key);
    final draft = _draft(app);
    final dirty = !slotsEqual(draft, live);
    final meta = app.schedule.meta[key];
    final g = app.gateHealth[key];
    final ago = g == null ? null : minutesAgo(g.lastPing);
    Color pingColor = p.danger;
    var pingTxt = 'no ping yet - check cron-job.org';
    if (ago != null) {
      if (ago <= 45) {
        pingColor = p.ok;
        pingTxt = '$ago min ago (${g!.lastPingDhaka ?? ''})';
      } else if (ago <= 120) {
        pingColor = p.warn;
        pingTxt = '$ago min ago - a ping was missed';
      } else {
        pingTxt = '${(ago / 60).round()} h ago - cron-job.org ping missing!';
      }
    }
    final runs = g?.runsFor(dhakaTodayKey()) ?? const <int, Map<String, dynamic>>{};
    final runTxt = runs.isEmpty
        ? 'none yet'
        : (runs.keys.toList()..sort()).map((w) => 'W${w + 1} ${runs[w]!['dhaka'] ?? ''}${gateRunState(runs[w])}').join(' · ');
    final decision = g?.lastDecision ?? '-';
    final err = validateSlots(draft);
    final liveHours = live.map((x) => x.hour).toList();
    final wu = g?.windowsUsed;
    final slotsUsed = g?.slotsUsed;
    final isActive = key == app.activeProject;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? p.primary.withValues(alpha: 0.07) : p.tintSoft,
        borderRadius: BorderRadius.circular(p.radiusMd),
        border: Border.all(color: isActive ? p.primary.withValues(alpha: 0.55) : p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(app.accountSpaced(key), style: TextStyle(fontWeight: FontWeight.w900, color: p.text, fontSize: 15, letterSpacing: 0.3))),
          Text(meta?.source == 'firebase' ? 'saved in Firebase' : 'default (from yml)', style: TextStyle(fontSize: 11, color: p.muted)),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < draft.length; i++) _slotTile(app, p, draft[i], i),
        if (err != null) ...[
          const SizedBox(height: 6),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: p.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Text(err, style: TextStyle(fontSize: 12, color: p.danger, fontWeight: FontWeight.w700))),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ZButton('Save schedule', icon: 'fa-save', small: true, busy: _saving, onPressed: dirty && err == null && !_saving ? () => _save(app) : null),
          ZButton('Default', small: true, kind: ZBtnKind.ghost, tooltip: 'Reset to yml default', onPressed: () {
            app.schedDraft[key] = slotsFromWindows(app.profile.defaultUploadWindows[key] ?? app.schedule.defaultWindows[key] ?? const [9, 14, 19]);
            app.touch();
          }),
          if (meta?.updatedAt != null) Text('updated ${fmtDhaka(meta!.updatedAt)} via ${meta.updatedBy ?? '?'}', style: TextStyle(fontSize: 11, color: p.muted)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.surface.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border.withValues(alpha: 0.6))),
          child: DefaultTextStyle(
            style: TextStyle(fontSize: 12, color: p.text, height: 1.5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [const TextSpan(text: 'Cron ping: '), TextSpan(text: pingTxt, style: TextStyle(color: pingColor, fontWeight: FontWeight.w800))])),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Last decision: '),
                TextSpan(text: decision, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (g?.lastRunDhaka != null) ...[const TextSpan(text: ' · last run '), TextSpan(text: g!.lastRunDhaka!, style: const TextStyle(fontWeight: FontWeight.w800))],
              ])),
              Text.rich(TextSpan(children: [const TextSpan(text: 'Runs today: '), TextSpan(text: runTxt, style: const TextStyle(fontWeight: FontWeight.w800))])),
              if (wu != null && wu.join(',') != liveHours.join(','))
                Text('Bot last used [${wu.join(',')}] - it picks up the new schedule on its next ping.', style: TextStyle(color: p.warn, fontWeight: FontWeight.w700)),
              if (slotsUsed != null)
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Bot slots: '),
                  TextSpan(
                    text: [for (var i = 0; i < slotsUsed.length; i++) 'S${i + 1} ${slotsUsed[i].exact ? '${slotsUsed[i].clock} (exact)' : '${slotsUsed[i].clock}–${slotsUsed[i].endClock}'}'].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ])),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _slotTile(AppState app, dynamic p, RunSlot sl, int i) {
    Widget timeBtn(String label, String value, bool end) => InkWell(
          onTap: () => _pickTime(app, i, end),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('$label ', style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w700)),
              Text(value, style: TextStyle(fontSize: 14, color: p.text, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: sl.exact ? p.accent.withValues(alpha: 0.08) : p.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sl.exact ? p.accent.withValues(alpha: 0.5) : p.border.withValues(alpha: 0.7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Slot ${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 12.5))),
          Segmented<bool>(options: const [(false, 'Window'), (true, 'Exact')], value: sl.exact, small: true, onChanged: (v) => _mode(app, i, v)),
        ]),
        const SizedBox(height: 8),
        if (sl.exact) ...[
          timeBtn('At', sl.timeValue, false),
          const SizedBox(height: 6),
          Row(children: [Fa('fa-dot-circle', size: 11, color: p.muted), const SizedBox(width: 6), Text.rich(TextSpan(style: TextStyle(fontSize: 11.5, color: p.muted), children: [const TextSpan(text: 'Uploads at '), TextSpan(text: sl.clock, style: const TextStyle(fontWeight: FontWeight.w800)), const TextSpan(text: ' sharp')]))]),
        ] else ...[
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            timeBtn('From', sl.timeValue, false),
            Fa('fa-arrow-right', size: 11, color: p.muted),
            timeBtn('To', sl.endTimeValue, true),
          ]),
          const SizedBox(height: 6),
          Row(children: [Fa('fa-shuffle', size: 11, color: p.muted), const SizedBox(width: 6), Expanded(child: Text.rich(TextSpan(style: TextStyle(fontSize: 11.5, color: p.muted), children: [const TextSpan(text: 'Random minute between '), TextSpan(text: sl.clock, style: const TextStyle(fontWeight: FontWeight.w800)), const TextSpan(text: ' – '), TextSpan(text: sl.endClock, style: const TextStyle(fontWeight: FontWeight.w800))])))]),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- Mix mode card
class _VarietyCard extends StatefulWidget {
  const _VarietyCard({super.key, required this.account});
  final String account;
  @override
  State<_VarietyCard> createState() => _VarietyCardState();
}

class _VarietyCardState extends State<_VarietyCard> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final key = widget.account;
    final live = VarietyConfig.live(app.varietyCfg[key]);
    final d = app.varietyDraft[key] ?? live.copy();
    final dirty = !d.sameAs(live);
    final used = app.varietyUsed[key];
    final todayKey = dhakaTodayString();
    final usedTypes = (used != null && used['date'] == todayKey && used['types'] is List) ? (used['types'] as List).map((e) => '$e').toList() : <String>[];
    final order = varietyOrderToday(d.types);
    String label(String t) => kVarietyTypes.where((x) => x.key == t).map((x) => x.value).firstOrNull ?? t;
    final metaTxt = live.updatedAt != null ? 'saved ${minutesAgo(live.updatedAt)} min ago by ${live.updatedBy ?? '?'}' : 'not saved yet (normal mode)';
    final isActive = key == app.activeProject;

    void edit(void Function(VarietyConfig) f) {
      final draft = app.varietyDraft[key] ??= live.copy();
      f(draft);
      app.touch();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? p.primary.withValues(alpha: 0.07) : p.tintSoft,
        borderRadius: BorderRadius.circular(p.radiusMd),
        border: Border.all(color: isActive ? p.primary.withValues(alpha: 0.55) : p.border),
      ),
      child: Opacity(
        opacity: d.enabled ? 1 : 0.92,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${app.accountSpaced(key)}${isActive ? ' · active' : ''}', style: TextStyle(fontWeight: FontWeight.w900, color: p.text, fontSize: 15))),
            Text(metaTxt, style: TextStyle(fontSize: 11, color: p.muted)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: p.text, fontWeight: FontWeight.w600), children: [
                const TextSpan(text: 'Mix mode '),
                d.enabled ? const TextSpan(text: 'ON', style: TextStyle(color: Color(0xff1f8f3a), fontWeight: FontWeight.w900)) : const TextSpan(text: 'OFF (normal day-type rotation)'),
              ])),
            ),
            Switch(value: d.enabled, onChanged: (v) => edit((x) => x.enabled = v)),
          ]),
          Text('Content types to mix (need at least 2; only types with queued files are used)', style: TextStyle(fontSize: 11.5, color: p.muted)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in kVarietyTypes)
              FilterChip(
                label: Text(e.value),
                selected: d.types.contains(e.key),
                onSelected: (on) => edit((x) => x.types = kVarietyAll.where((t) => t == e.key ? on : x.types.contains(t)).toList()),
              ),
          ]),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => edit((x) => x.strict = !x.strict),
            borderRadius: BorderRadius.circular(8),
            child: Row(children: [
              Checkbox(value: d.strict, onChanged: (v) => edit((x) => x.strict = v ?? false)),
              Expanded(child: Text('Strict: prefer a different type for every slot (repeats only when no other type has stock - a slot is never left empty)', style: TextStyle(fontSize: 12, color: p.text))),
            ]),
          ),
          const SizedBox(height: 6),
          Text.rich(TextSpan(style: TextStyle(fontSize: 12, color: p.muted), children: [const TextSpan(text: 'Order today: '), TextSpan(text: order.map(label).join(' › '), style: TextStyle(fontWeight: FontWeight.w800, color: p.text))])),
          Text.rich(TextSpan(style: TextStyle(fontSize: 12, color: p.muted), children: [const TextSpan(text: 'Uploaded today: '), TextSpan(text: usedTypes.isEmpty ? '-' : usedTypes.map(label).join(', '), style: TextStyle(fontWeight: FontWeight.w800, color: p.text))])),
          const SizedBox(height: 10),
          Row(children: [
            ZButton(dirty ? 'Save to Firebase' : 'Saved', icon: 'fa-save', small: true, busy: _saving, onPressed: dirty && !_saving
                ? () async {
                    if (d.enabled && d.types.length < 2) {
                      app.showToast('Mix mode needs at least 2 content types', 'error');
                      return;
                    }
                    setState(() => _saving = true);
                    try {
                      await app.repo.saveVariety(key, enabled: d.enabled, strict: d.strict, types: d.types);
                      app.varietyDraft.remove(key);
                      app.showToast('${app.accountSpaced(key)}: Mix mode ${d.enabled ? 'ON' : 'OFF'} saved - bot uses it from the next run', 'ok');
                    } catch (e) {
                      app.showToast('Save failed: ${e.toString().replaceFirst('Exception: ', '')}', 'error');
                    }
                    if (mounted) setState(() => _saving = false);
                    app.touch();
                  }
                : null),
            const SizedBox(width: 8),
            ZButton('Reset', small: true, kind: ZBtnKind.ghost, onPressed: dirty
                ? () {
                    app.varietyDraft.remove(key);
                    app.touch();
                  }
                : null),
          ]),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- calendar
class _CalendarCard extends StatelessWidget {
  const _CalendarCard();

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final plan = app.plan;
    final rule = plan.rule;
    final b = plan.buckets;
    final days = plan.days;
    final perPage = app.scheduleDaysPerPage;
    final total = (days.length / perPage).ceil().clamp(1, 1 << 30).toInt();
    var page = app.schedulePage.clamp(0, total - 1).toInt();
    final start = page * perPage;
    final pageDays = days.skip(start).take(perPage).toList();
    final first = pageDays.isNotEmpty ? pageDays.first : null;
    final last = pageDays.isNotEmpty ? pageDays.last : null;
    final waiting = plan.waitingTypes;
    final waitingTxt = waiting.isEmpty ? 'None ✓' : waiting.map((t) => '${kDayTypeUi[t]?.label ?? t} ${b[t]?.length ?? 0}/3').join(' · ');

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Schedule calendar', icon: 'fa-calendar-alt', subtitle: 'Plan your files, profiles and upload windows. Times are estimates in Dhaka; timers do not confirm an upload.'),
        const SizedBox(height: 14),
        // legend / stats
        AutoGrid(minTile: 170, gap: 10, children: [
          StatCard(compact: true, label: 'Active DB', value: app.accountUpper(app.activeProject), icon: 'fa-database'),
          StatCard(compact: true, label: 'Calendar Time', value: RealTime.instance.synced ? 'REAL SYNC ✓' : 'DEVICE CLOCK', icon: 'fa-satellite-dish', tone: RealTime.instance.synced ? 'ok' : 'warn'),
          StatCard(compact: true, label: 'Remaining Today', value: '${rule.remaining} slot(s)', icon: 'fa-hourglass-half', tone: 'accent'),
          StatCard(compact: true, label: 'Uploaded Today', value: '${rule.uploadedToday} / 3', icon: 'fa-cloud-upload-alt', tone: 'ok'),
          _NextRunStat(plan: plan),
          StatCard(compact: true, label: 'Audio Queue', value: '${b['AUDIO']?.length ?? 0} items', icon: 'fa-music', tone: 'accent'),
          StatCard(compact: true, label: 'Wallpapers', value: '${b['WALLPAPER']?.length ?? 0} items', icon: 'fa-image', tone: 'info'),
          StatCard(compact: true, label: '24H Sets', value: '${b['WALLPAPER_24H']?.length ?? 0} sets', icon: 'fa-clock'),
          StatCard(compact: true, label: 'Dual Sets', value: '${b['WALLPAPER_DUAL']?.length ?? 0} sets', icon: 'fa-mobile-alt'),
          StatCard(compact: true, label: 'Battery Sets', value: '${b['WALLPAPER_BATTERY']?.length ?? 0} sets', icon: 'fa-battery-three-quarters'),
          StatCard(compact: true, label: 'Live Videos', value: '${b['LIVE_WALLPAPER']?.length ?? 0} items', icon: 'fa-film'),
          StatCard(compact: true, label: 'Charging Videos', value: '${b['CHARGING_ANIMATION']?.length ?? 0} items', icon: 'fa-bolt'),
          StatCard(compact: true, label: 'Special Days', value: app.specialDays.onlineCountries.isNotEmpty ? '${app.specialDays.onlineCountries.length} COUNTRIES ✓' : 'BUILT-IN LIST', icon: 'fa-gift', tone: 'warn'),
          if (plan.mixMode)
            Tooltip(
              message: 'Mix mode is ON for this account (Schedule tab > Mix Mode). Every slot of a day uploads a different content type in this order; the order rotates daily, empty types are skipped, pinned files always win. The calendar below follows exactly that.${plan.mixStrict ? ' Strict: a type never repeats on the same day (slot waits instead).' : ''}',
              child: StatCard(compact: true, label: 'Mix Mode ON · order today', value: plan.mixOrderToday.map((t) => kDayTypeUi[t == 'RINGTONE' ? 'AUDIO' : t]?.label ?? varietyLabel(t)).join(' › '), icon: 'fa-palette', tone: 'accent'),
            )
          else
            Tooltip(
              message: 'A content type only gets a day when it has 3 files. These types are waiting for restock (or pin them manually).',
              child: StatCard(compact: true, label: 'Waiting For Stock (need 3)', value: waitingTxt, icon: 'fa-hourglass-half', tone: waiting.isEmpty ? 'ok' : 'warn'),
            ),
        ]),
        const SizedBox(height: 16),
        // toolbar
        if (first != null && last != null)
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 10, spacing: 10, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(12)), child: Fa('fa-calendar-days', size: 16, color: p.onPrimary)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${kMonthLong[first.date.month - 1]} ${first.date.year}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: p.text)),
                Text('${first.date.day} ${kMonthShort[first.date.month - 1]} — ${last.date.day} ${kMonthShort[last.date.month - 1]} · Dhaka', style: TextStyle(fontSize: 12, color: p.muted)),
              ]),
            ]),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                ZIconButton('fa-chevron-left', tooltip: 'Previous days', onPressed: page == 0 ? null : () => _setPage(app, page - 1)),
                const SizedBox(width: 4),
                ZButton('Today', small: true, kind: ZBtnKind.soft, onPressed: () => _setPage(app, 0)),
                const SizedBox(width: 4),
                ZIconButton('fa-chevron-right', tooltip: 'Next days', onPressed: page >= total - 1 ? null : () => _setPage(app, page + 1)),
              ]),
              ZButton('Jump to date', icon: 'fa-calendar-day', small: true, kind: ZBtnKind.soft, onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: first.date, firstDate: days.first.date, lastDate: days.last.date);
                if (d == null) return;
                final idx = days.indexWhere((x) => x.dateKey == fmtDateKey(d));
                if (idx >= 0) _setPage(app, idx ~/ perPage);
              }),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Days in view ', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w700)),
                Segmented<int>(options: const [(7, '7'), (14, '14'), (28, '28')], value: perPage, small: true, onChanged: (n) {
                  final firstIndex = page * perPage;
                  app.scheduleDaysPerPage = n;
                  app.schedulePage = firstIndex ~/ n;
                  app.touch();
                }),
              ]),
            ]),
          ]),
        const SizedBox(height: 14),
        ValueListenableBuilder<int>(
          valueListenable: app.clockTick,
          builder: (context, _, __) => AutoGrid(
            minTile: 250,
            gap: 12,
            maxCols: 7,
            children: [for (final d in pageDays) _DayColumn(day: d, uploadedToday: d.isToday ? rule.uploadedToday : 0, now: RealTime.instance.nowMs())],
          ),
        ),
        if (total > 1) ...[
          const SizedBox(height: 14),
          Pagination(page: page + 1, pages: total, onPage: (n) => _setPage(app, n - 1)),
        ],
      ]),
    );
  }

  void _setPage(AppState app, int n) {
    app.schedulePage = n;
    app.touch();
  }
}

class _NextRunStat extends StatelessWidget {
  const _NextRunStat({required this.plan});
  final PlannerResult plan;
  @override
  Widget build(BuildContext context) {
    final nx = plan.nextRun;
    if (nx == null) return const StatCard(compact: true, label: 'Next Upload', value: '-', icon: 'fa-stopwatch', tone: 'info');
    final when = nx.day.isToday ? 'Today' : nx.day.dateKey.substring(5);
    final what = nx.item?.displayTitle ?? 'empty slot';
    return Tooltip(
      message: nx.run.exact ? 'Exactly at ${nx.run.start} (Dhaka)' : '${nx.run.start} (Dhaka) - random minute inside ${nx.run.windowLabel}',
      child: StatCard(compact: true, label: 'Next Upload', value: '$when ${nx.run.start}', sub: '${nx.run.profileLabel} · $what', icon: 'fa-stopwatch', tone: 'info'),
    );
  }
}

// ---------------------------------------------------------------- day column
class _DayColumn extends StatefulWidget {
  const _DayColumn({required this.day, required this.uploadedToday, required this.now});
  final PlannedDay day;
  final int uploadedToday;
  final int now;
  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  bool _over = false;
  bool _holidaysOpen = false;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.pal;
    final d = widget.day;
    final planned = d.slots.whereType<QueueItem>().length;
    final ui = kDayTypeUi[d.dayType] ?? kDayTypeUi['WALLPAPER']!;
    final label = d.isToday ? 'TODAY' : weekdayShort(d.date).toUpperCase();
    final specials = [...d.specialDays]..sort((a, b) => a.rank.compareTo(b.rank));
    // v27.10 mix mode: the strip shows the planned type sequence instead of a single day type
    String typeLabel(String t) => kDayTypeUi[t == 'RINGTONE' ? 'AUDIO' : t]?.label ?? varietyLabel(t);
    final mixPlanned = d.mixMode ? d.mixPlannedTypes.map(typeLabel).toList() : const <String>[];
    final stripIcon = d.mixMode ? 'fa-palette' : ui.icon;
    final stripText = d.mixMode
        ? (mixPlanned.isEmpty ? 'Mix mode · waiting for stock' : 'Mix mode · ${mixPlanned.join(' › ')}')
        : ui.label + (d.switchedFrom != null ? ' (from ${kDayTypeUi[d.switchedFrom!]?.short ?? d.switchedFrom})' : '');
    final stripTip = d.mixMode
        ? 'Mix mode ON · order for this day: ${d.mixOrder.map(typeLabel).join(' › ')} (rotates daily). Each slot takes the next type that still has a queued file; pinned files always win.${d.mixStrict ? ' Strict: never repeats a type on the same day.' : ''}'
        : '${ui.title} · one content type per day (normal rotation)';
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) {
        setState(() => _over = true);
        return true;
      },
      onLeave: (_) => setState(() => _over = false),
      onAcceptWithDetails: (det) async {
        setState(() => _over = false);
        try {
          await app.repo.setItemScheduledDate(app.activeProject, det.data, d.dateKey);
        } catch (e) {
          app.showToast('Drag-drop pin failed: $e', 'err');
        }
      },
      builder: (context, cand, rej) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _over ? p.primary.withValues(alpha: 0.14) : (d.isToday ? p.primary.withValues(alpha: 0.07) : (d.isWeekend ? p.accent.withValues(alpha: 0.05) : p.tintSoft)),
          borderRadius: BorderRadius.circular(p.radiusMd),
          border: Border.all(color: _over ? p.primary : (d.isToday ? p.primary.withValues(alpha: 0.6) : p.border), width: _over || d.isToday ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d.date.day}', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: d.isToday ? p.primary : p.text, height: 1)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: d.isToday ? p.primary : p.muted)),
                Text(kMonthShort[d.date.month - 1], style: TextStyle(fontSize: 11.5, color: p.muted)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$planned / ${d.slotCount}', style: TextStyle(fontWeight: FontWeight.w900, color: p.text, fontSize: 13)),
              Text('files planned', style: TextStyle(fontSize: 10, color: p.muted)),
            ]),
          ]),
          const SizedBox(height: 10),
          Tooltip(
            message: stripTip,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(9)),
              child: Row(children: [
                Fa(stripIcon, size: 11, color: p.onPrimary),
                const SizedBox(width: 6),
                Expanded(child: Text(stripText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.onPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(d.mixMode ? 'mix · Dhaka' : '0–14 min delay · Dhaka', style: TextStyle(fontSize: 9.5, color: p.onPrimary.withValues(alpha: 0.85))),
              ]),
            ),
          ),
          if (specials.isNotEmpty) ...[
            const SizedBox(height: 8),
            _holidayNote(specials),
          ],
          const SizedBox(height: 8),
          if (d.slotCount == 0)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(color: p.ok.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                Fa('fa-check-circle', size: 26, color: p.ok),
                const SizedBox(height: 6),
                Text('All Uploads Done! 🎉', style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
              ]),
            )
          else
            for (var i = 0; i < d.slots.length; i++) _slot(context, d, i),
          if (d.slotCount > 0 && d.slots.length < 3) _filler(p, d.slots.length),
          if (d.slotCount > 0) ...[
            const SizedBox(height: 6),
            Text('Open a file to edit · Drag to move / pin', style: TextStyle(fontSize: 10, color: p.muted), textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }

  Widget _filler(dynamic p, int actual) {
    final done = widget.uploadedToday;
    final title = done > 0 ? '$done uploaded today' : 'No additional planned files';
    final note = done > 0 ? '$actual scheduled ${actual == 1 ? 'slot remains' : 'slots remain'} above.' : 'Only the files shown above are planned for this day.';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border.withValues(alpha: 0.6))),
      child: Column(children: [
        Text(done > 0 ? '✓' : '—', style: TextStyle(color: done > 0 ? p.ok : p.muted, fontWeight: FontWeight.w900)),
        Text(title, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: p.text), textAlign: TextAlign.center),
        Text(note, style: TextStyle(fontSize: 10.5, color: p.muted), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _holidayNote(List<SpecialDay> items) {
    final p = context.pal;
    Widget row(SpecialDay e) {
      final codes = holidayCountryCodes(e);
      final country = codes.isNotEmpty ? codes.map((c) => kHolidayCountryNames[c] ?? c).join(' · ') : (e.kind == 'global' ? 'Worldwide' : 'Country not listed');
      final kind = const {'holiday': 'Public holiday', 'festival': 'Festival', 'bd': 'Special day', 'global': 'Observance'}[e.kind] ?? 'Special day';
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          codes.isNotEmpty ? Text(countryFlagEmoji(codes.first), style: const TextStyle(fontSize: 14)) : Fa(e.icon, size: 12, color: p.warn),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: p.text), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('$country · $kind', style: TextStyle(fontSize: 10, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );
    }
    final multi = items.length > 1;
    return InkWell(
      onTap: multi ? () => setState(() => _holidaysOpen = !_holidaysOpen) : null,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: p.warn.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9), border: Border.all(color: p.warn.withValues(alpha: 0.35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(multi ? 'Holidays & observances' : 'Holiday & observance', style: TextStyle(fontSize: 9.5, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: p.warn))),
            if (multi) Text('${items.length} events ${_holidaysOpen ? '▴' : '▾'}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: p.warn)),
          ]),
          row(items.first),
          if (multi && _holidaysOpen) for (final e in items.skip(1)) row(e),
        ]),
      ),
    );
  }

  Widget _slot(BuildContext context, PlannedDay d, int idx) {
    final app = context.app;
    final p = context.pal;
    final item = d.slots[idx];
    final run = idx < d.runs.length ? d.runs[idx] : null;
    final now = widget.now;
    // live state (tickCountdowns re-evaluates passed/live from real time)
    var passed = run?.passed ?? false, live = run?.live ?? false;
    if (run != null && !run.overflow && now >= run.startMs) {
      passed = now > run.windowEndMs;
      live = !passed;
    }
    final state = run == null || run.overflow ? '' : (passed ? 'passed' : (live ? 'live' : (run.isNext ? 'next' : '')));
    final stateColor = switch (state) { 'passed' => p.muted, 'live' => p.warn, 'next' => p.primary, _ => p.border };

    Widget flag() {
      if (run == null || run.overflow) return const SizedBox.shrink();
      if (passed) return Pill('closed', icon: 'fa-clock', small: true, color: p.muted.withValues(alpha: 0.18), fg: p.muted);
      if (live) return Pill('due', icon: 'fa-clock', small: true, color: p.warn.withValues(alpha: 0.18), fg: p.warn);
      if (run.isNext) return Pill('next up', icon: 'fa-step-forward', small: true, color: p.primary.withValues(alpha: 0.18), fg: p.primary);
      return Pill('scheduled', small: true, outline: true);
    }

    Widget runMeta(bool hasItem) {
      if (run == null) return const SizedBox.shrink();
      if (run.overflow) return Padding(padding: const EdgeInsets.only(top: 6), child: Text('Daily limit reached · Move this file to another day', style: TextStyle(fontSize: 10.5, color: p.danger, fontWeight: FontWeight.w700)));
      return Tooltip(
        message: 'Scheduled window ${run.windowLabel} (Dhaka). Actual run may be delayed.',
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(run.start, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: passed ? p.muted : p.text)),
              const SizedBox(width: 4),
              Tooltip(message: run.exact ? 'Exact upload time' : 'Random minute inside ${run.windowLabel}', child: Fa(run.exact ? 'fa-dot-circle' : 'fa-shuffle', size: 10, color: p.muted)),
              const SizedBox(width: 8),
              Expanded(child: Text('${run.profileLabel} · Dhaka', style: TextStyle(fontSize: 10.5, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            if (!hasItem)
              Text('Tap to pin a queued file to this day', style: TextStyle(fontSize: 10.5, color: p.muted))
            else if (passed)
              Text('Window closed · Check run status in the overview', style: TextStyle(fontSize: 10.5, color: p.muted))
            else
              _Countdown(run: run, now: now),
          ]),
        ),
      );
    }

    if (item == null) {
      final noneHave = d.slots.every((x) => x == null);
      return Tooltip(
        message: 'Pin a queued file to this day',
        child: InkWell(
          onTap: () => openDayPicker(context, d.dateKey),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: stateColor, width: state.isEmpty ? 1 : 1.5, style: BorderStyle.solid)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Pill('Empty slot', icon: 'fa-plus', small: true, outline: true),
                const Spacer(),
                Text('Slot ${idx + 1}', style: TextStyle(fontSize: 10, color: p.muted, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                flag(),
              ]),
              const SizedBox(height: 6),
              Text(
                d.mixMode
                    ? 'Click to pin a file · mix mode: no queued file of any type'
                    : 'Click to pin a file${noneHave ? ' · no type has 3 files' : ''}',
                style: TextStyle(fontSize: 11.5, color: p.muted),
              ),
              runMeta(false),
            ]),
          ),
        ),
      );
    }

    final slotType = item.contentType;
    final sui = kDayTypeUi[item.dayType] ?? kDayTypeUi['WALLPAPER']!;
    final chipColor = slotType == 'RINGTONE' ? p.accent : (slotType == 'WALLPAPER' ? p.info : p.primary);
    final pinned = item.scheduledDate != null;
    final card = Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: passed ? 0.35 : 0.75),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: state.isEmpty ? p.border : stateColor, width: state.isEmpty ? 1 : 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Pill(sui.label, icon: sui.icon, small: true, color: chipColor.withValues(alpha: 0.18), fg: chipColor),
          const Spacer(),
          Text('Slot ${idx + 1}', style: TextStyle(fontSize: 10, color: p.muted, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          flag(),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          if (pinned)
            Tooltip(
              message: '${item.scheduledDate!.compareTo(d.dateKey) < 0 ? 'Pinned to ${item.scheduledDate} (overdue - moved to today). ' : 'Pinned to this day. '}Click to UNPIN and return it to the normal rotation.',
              child: InkWell(
                onTap: () async {
                  final label = item.displayTitle == 'Unnamed' ? 'this file' : item.displayTitle;
                  final ok = await confirmDialog(context, 'Unpin "$label"?\nIt will go back to the normal rotation (its own content-type day).', title: 'Unpin', okLabel: 'Unpin');
                  if (!ok) return;
                  try {
                    await app.repo.unpinItem(app.activeProject, item.id);
                    app.showToast('Unpinned: $label');
                  } catch (e) {
                    app.showToast('Unpin failed: $e', 'err');
                  }
                },
                child: Padding(padding: const EdgeInsets.only(right: 6), child: Fa('fa-thumbtack', size: 12, color: p.warn)),
              ),
            ),
          Expanded(child: Text(item.displayTitle, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
        runMeta(true),
      ]),
    );
    return Tooltip(
      message: 'Drag to another day to pin it there - or click to edit',
      child: Draggable<String>(
        data: item.id,
        feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.9, child: SizedBox(width: 230, child: card))),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: InkWell(onTap: () => openAssetDetails(context, item.id), borderRadius: BorderRadius.circular(10), child: card),
      ),
    );
  }
}

/// `countdownHtml` / `tickCountdowns` - compact live countdown for a slot.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.run, required this.now});
  final RunPrediction run;
  final int now;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (run.overflow || run.startMs == 0) return const SizedBox.shrink();
    String label;
    String icon = 'fa-hourglass-half';
    Color c = p.muted;
    int left;
    if (now < run.startMs) {
      left = run.startMs - now;
      label = 'scheduled in';
      if (left <= 15 * 60 * 1000) c = p.warn;
    } else if (now <= run.endMs) {
      left = run.endMs - now;
      label = 'slot due';
      icon = 'fa-bolt';
      c = p.ok;
    } else if (now <= run.windowEndMs) {
      left = run.windowEndMs - now;
      label = 'catch-up left';
      icon = 'fa-arrows-rotate';
      c = p.warn;
    } else {
      left = 0;
      label = 'window closed';
      icon = 'fa-clock';
    }
    final cd = Countdown.fromMs(left);
    final core = '${two(cd.hours)}:${two(cd.minutes)}:${two(cd.seconds)}';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Fa(icon, size: 10, color: c),
        const SizedBox(width: 5),
        Text('$label ', style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.w700)),
        Text(cd.days > 0 ? '${cd.days}d $core' : core, style: TextStyle(fontSize: 11.5, color: p.text, fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}
