import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/dhaka_time.dart';
import '../../data/models.dart';
import '../dialogs/asset_details.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';
import '../widgets/queue_card.dart';
import '../widgets/responsive.dart';
import '../widgets/stat_card.dart';

/// Pin Manager (`renderPinManager`): stats, pinned list grouped by date, picker of unpinned files.
class PinsScreen extends StatefulWidget {
  const PinsScreen({super.key});
  @override
  State<PinsScreen> createState() => _PinsScreenState();
}

class _PinsScreenState extends State<PinsScreen> {
  late final TextEditingController _search = TextEditingController(text: context.app.pinSearch);
  late final TextEditingController _pick = TextEditingController(text: context.app.pinPickerSearch);

  @override
  void dispose() {
    _search.dispose();
    _pick.dispose();
    super.dispose();
  }

  Future<String?> _pickDate(String initial, String min) async {
    final d = await showDatePicker(context: context, initialDate: parseDateKey(initial) ?? getDhakaDate(0), firstDate: parseDateKey(min) ?? DateTime(2020), lastDate: DateTime(2100));
    return d == null ? null : fmtDateKey(d);
  }

  Future<void> _bulk(List<QueueItem> items, String? value, String verb) async {
    final app = context.app;
    if (items.isEmpty) {
      app.showToast('Nothing to do', 'warn');
      return;
    }
    final what = value == null ? 'Unpin' : 'Re-date to ${fmtPinDate(value)}';
    final ok = await confirmDialog(context, '$what ${items.length} file(s) ($verb)?${value == null ? '\nThey go back to their own content-type day.' : ''}', title: 'Bulk pin update', okLabel: what);
    if (!ok) return;
    try {
      await app.repo.bulkPinUpdate(app.activeProject, items.map((i) => i.id).toList(), value);
      app.showToast('${value == null ? 'Unpinned' : 'Re-dated'} ${items.length} file(s)');
    } catch (e) {
      if (mounted) await alertDialog(context, 'Bulk update failed - $e');
    }
  }

  Future<void> _unpin(QueueItem item) async {
    final app = context.app;
    final label = item.displayTitle;
    final ok = await confirmDialog(context, 'Unpin "$label"?\nIt will go back to the normal rotation (its own content-type day).', title: 'Unpin', okLabel: 'Unpin');
    if (!ok) return;
    try {
      await app.repo.unpinItem(app.activeProject, item.id);
      app.showToast('Unpinned: $label');
    } catch (e) {
      app.showToast('Unpin failed: $e', 'err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final today = dhakaTodayKey();
    final queued = app.queuedItems;
    final pinned = queued.where((i) => i.scheduledDate != null).toList()
      ..sort((a, b) {
        final c = a.scheduledDate!.compareTo(b.scheduledDate!);
        if (c != 0) return c;
        return (a.timeMs ?? 0).compareTo(b.timeMs ?? 0);
      });
    final overdue = pinned.where((i) => i.scheduledDate!.compareTo(today) < 0).toList();
    final todayPins = pinned.where((i) => i.scheduledDate == today).toList();
    final upcoming = pinned.where((i) => i.scheduledDate!.compareTo(today) > 0).toList();
    final days = pinned.map((i) => i.scheduledDate!.compareTo(today) < 0 ? today : i.scheduledDate!).toSet();
    bool typeOk(QueueItem i) => app.pinFilterType == 'ALL' || i.dayType == app.pinFilterType;
    final term = app.pinSearch.trim().toLowerCase();
    final shown = pinned.where((i) => typeOk(i) && (term.isEmpty || '${i.title} ${i.name}'.toLowerCase().contains(term))).toList();
    final predicted = app.predictedDates;
    final pterm = app.pinPickerSearch.trim().toLowerCase();
    final unpinned = queued.where((i) => i.scheduledDate == null && typeOk(i) && (pterm.isEmpty || '${i.title} ${i.name}'.toLowerCase().contains(pterm))).toList()
      ..sort((a, b) => (a.timeMs ?? 0).compareTo(b.timeMs ?? 0));

    return PageBody(children: [
      AutoGrid(minTile: 170, gap: 10, children: [
        StatCard(compact: true, label: 'Active DB', value: app.accountUpper(app.activeProject), icon: 'fa-database'),
        StatCard(compact: true, label: 'Pinned Files', value: '${pinned.length}', icon: 'fa-thumbtack'),
        StatCard(compact: true, label: 'Pinned Days', value: '${days.length}', icon: 'fa-calendar-day', tone: 'accent'),
        StatCard(compact: true, label: 'Overdue (run today)', value: '${overdue.length}', icon: 'fa-triangle-exclamation', tone: overdue.isNotEmpty ? 'warn' : 'ok'),
        StatCard(compact: true, label: 'Pinned For Today', value: '${todayPins.length}', icon: 'fa-sun', tone: 'accent'),
        StatCard(compact: true, label: 'Upcoming Pins', value: '${upcoming.length}', icon: 'fa-forward', tone: 'info'),
        StatCard(compact: true, label: 'Unpinned In Queue', value: '${queued.length - pinned.length}', icon: 'fa-list', tone: 'warn'),
      ]),
      const SizedBox(height: 16),
      GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('Pinned Files (date overrides)', icon: 'fa-thumbtack', subtitle: 'Pinned files skip the rotation and upload on the exact day you chose (overdue pins run today, first). Change the date inline, or unpin to send a file back to its own content-type day.'),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ZDropdown<String>(
              value: app.pinFilterType,
              width: 190,
              items: [('ALL', 'All types'), for (final t in kTypeCycle) (t, kDayTypeUi[t]?.label ?? t)],
              onChanged: (v) {
                app.pinFilterType = v;
                app.touch();
              },
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(hintText: 'Search pinned files…', isDense: true, prefixIcon: Icon(Icons.search, size: 18)),
                onChanged: (v) {
                  app.pinSearch = v;
                  app.touch();
                },
              ),
            ),
            ZButton('Overdue → Today', icon: 'fa-calendar-check', small: true, kind: ZBtnKind.soft, onPressed: () => _bulk(shown.where((i) => i.scheduledDate!.compareTo(today) < 0).toList(), today, 'overdue')),
            ZButton('Unpin Overdue', icon: 'fa-link', small: true, kind: ZBtnKind.ghost, onPressed: () => _bulk(shown.where((i) => i.scheduledDate!.compareTo(today) < 0).toList(), null, 'overdue')),
            ZButton('Unpin All Shown', icon: 'fa-times', small: true, kind: ZBtnKind.danger, onPressed: () => _bulk(shown, null, 'all shown')),
          ]),
          const SizedBox(height: 14),
          if (shown.isEmpty)
            EmptyNote(pinned.isNotEmpty ? 'No pinned files match this filter.' : 'No pinned files. Everything follows the normal rotation. Pin a file below or from the calendar.', icon: 'fa-thumbtack', big: true)
          else
            ..._groupedRows(shown, today, p),
        ]),
      ),
      const SizedBox(height: 16),
      GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle('Pin a Queued File', icon: 'fa-calendar-plus', subtitle: 'Every unpinned file shows its Auto date - where the rotation will place it (or "waiting for stock" if its type has fewer than 3 files). Pick a date and press Pin to override.', trailing: SizedBox(
            width: 260,
            child: TextField(
              controller: _pick,
              decoration: const InputDecoration(hintText: 'Search queued files…', isDense: true, prefixIcon: Icon(Icons.search, size: 18)),
              onChanged: (v) {
                app.pinPickerSearch = v;
                app.touch();
              },
            ),
          )),
          const SizedBox(height: 14),
          if (unpinned.isEmpty)
            EmptyNote('No unpinned queued files${pterm.isNotEmpty ? ' match your search' : ''}.', icon: 'fa-inbox')
          else ...[
            for (final i in unpinned.take(60)) _PickerRow(item: i, predicted: predicted[i.id], today: today, onPickDate: _pickDate),
            if (unpinned.length > 60) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Showing 60 of ${unpinned.length} - use the search box to narrow down.', style: TextStyle(fontSize: 12, color: p.muted))),
          ],
        ]),
      ),
    ]);
  }

  List<Widget> _groupedRows(List<QueueItem> shown, String today, dynamic p) {
    final out = <Widget>[];
    String? lastKey;
    for (final i in shown) {
      final key = i.scheduledDate!;
      if (key != lastKey) {
        final cnt = shown.where((x) => x.scheduledDate == key).length;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(children: [
            Fa('fa-calendar-alt', size: 12, color: p.primary),
            const SizedBox(width: 8),
            Text(fmtPinDate(key), style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 13)),
            const SizedBox(width: 8),
            Pill(relDayLabel(key, today), small: true, color: key.compareTo(today) < 0 ? p.warn.withValues(alpha: 0.18) : p.tintChip, fg: key.compareTo(today) < 0 ? p.warn : p.muted),
            const SizedBox(width: 8),
            Text('$cnt file${cnt > 1 ? 's' : ''}', style: TextStyle(fontSize: 11.5, color: p.muted)),
          ]),
        ));
        lastKey = key;
      }
      out.add(_PinRow(item: i, today: today, onPickDate: _pickDate, onUnpin: () => _unpin(i)));
    }
    return out;
  }
}

class _PinRow extends StatelessWidget {
  const _PinRow({required this.item, required this.today, required this.onPickDate, required this.onUnpin});
  final QueueItem item;
  final String today;
  final Future<String?> Function(String initial, String min) onPickDate;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.pal;
    final ui = kDayTypeUi[item.dayType] ?? kDayTypeUi['WALLPAPER']!;
    final sd = item.scheduledDate!;
    final overdue = sd.compareTo(today) < 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: overdue ? p.warn.withValues(alpha: 0.08) : p.tintSoft,
        borderRadius: BorderRadius.circular(p.radiusSm),
        border: Border.all(color: overdue ? p.warn.withValues(alpha: 0.5) : p.border),
      ),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
        ItemThumb(item, width: 52, height: 52, radius: 10, showBadge: false),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Tooltip(message: item.displayTitle, child: Text(item.displayTitle, style: TextStyle(fontWeight: FontWeight.w800, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 4),
            Wrap(spacing: 10, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [Fa(ui.icon, size: 11, color: p.muted), const SizedBox(width: 4), Text(ui.label, style: TextStyle(fontSize: 11.5, color: p.muted))]),
              Row(mainAxisSize: MainAxisSize.min, children: [Fa('fa-hdd', size: 11, color: p.muted), const SizedBox(width: 4), Text(formatBytes(item.size), style: TextStyle(fontSize: 11.5, color: p.muted))]),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('PINNED DATE', style: TextStyle(fontSize: 9.5, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: p.muted)),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            ZButton(sd, icon: 'fa-thumbtack', small: true, kind: ZBtnKind.soft, onPressed: () async {
              final v = await onPickDate(sd, today);
              if (v == null) return;
              await app.repo.setItemScheduledDate(app.activeProject, item.id, v);
              app.showToast('Moved "${item.displayTitle}" → ${fmtPinDate(v)}');
            }),
            const SizedBox(width: 8),
            if (overdue) Pill('Overdue → runs today', small: true, color: p.warn.withValues(alpha: 0.18), fg: p.warn) else if (sd == today) Pill('Today', small: true, color: p.ok.withValues(alpha: 0.18), fg: p.ok),
          ]),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          ZIconButton('fa-eye', tooltip: 'Open details', onPressed: () => openAssetDetails(context, item.id)),
          const SizedBox(width: 6),
          ZButton('Unpin', icon: 'fa-times', small: true, kind: ZBtnKind.danger, onPressed: onUnpin),
        ]),
      ]),
    );
  }
}

class _PickerRow extends StatefulWidget {
  const _PickerRow({required this.item, required this.predicted, required this.today, required this.onPickDate});
  final QueueItem item;
  final String? predicted;
  final String today;
  final Future<String?> Function(String initial, String min) onPickDate;
  @override
  State<_PickerRow> createState() => _PickerRowState();
}

class _PickerRowState extends State<_PickerRow> {
  String? _value;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.pal;
    final item = widget.item;
    final ui = kDayTypeUi[item.dayType] ?? kDayTypeUi['WALLPAPER']!;
    final pk = widget.predicted;
    final autoTxt = pk != null ? 'Auto: ${fmtPinDate(pk)}' : 'Auto: waiting for stock (type has < 3 files)';
    final value = _value ?? ((pk != null && pk.compareTo(widget.today) >= 0) ? pk : widget.today);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: p.border)),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
        ItemThumb(item, width: 52, height: 52, radius: 10, showBadge: false),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Tooltip(message: item.displayTitle, child: Text(item.displayTitle, style: TextStyle(fontWeight: FontWeight.w800, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 4),
            Wrap(spacing: 10, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [Fa(ui.icon, size: 11, color: p.muted), const SizedBox(width: 4), Text(ui.label, style: TextStyle(fontSize: 11.5, color: p.muted))]),
              Row(mainAxisSize: MainAxisSize.min, children: [Fa('fa-arrows-rotate', size: 11, color: p.muted), const SizedBox(width: 4), Text(autoTxt, style: TextStyle(fontSize: 11.5, color: p.muted))]),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('PIN TO', style: TextStyle(fontSize: 9.5, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: p.muted)),
          const SizedBox(height: 3),
          ZButton(value, icon: 'fa-calendar-plus', small: true, kind: ZBtnKind.soft, onPressed: () async {
            final v = await widget.onPickDate(value, widget.today);
            if (v != null) setState(() => _value = v);
          }),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          ZIconButton('fa-eye', tooltip: 'Open details', onPressed: () => openAssetDetails(context, item.id)),
          const SizedBox(width: 6),
          ZButton('Pin', icon: 'fa-thumbtack', small: true, onPressed: () async {
            await app.repo.setItemScheduledDate(app.activeProject, item.id, value);
            app.showToast('Pinned "${item.displayTitle}" → ${fmtPinDate(value)}');
          }),
        ]),
      ]),
    );
  }
}
