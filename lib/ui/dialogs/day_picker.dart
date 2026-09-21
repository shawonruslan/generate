import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/dhaka_time.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';

/// Day picker modal (`openDayPicker` / `renderDayPicker`): pin queued files to a day,
/// unpin files already pinned there.
Future<void> openDayPicker(BuildContext context, String dateKey) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => _DayPickerDialog(dateKey: dateKey),
  );
}

class _DayPickerDialog extends StatefulWidget {
  const _DayPickerDialog({required this.dateKey});
  final String dateKey;
  @override
  State<_DayPickerDialog> createState() => _DayPickerDialogState();
}

class _DayPickerDialogState extends State<_DayPickerDialog> {
  String _term = '';

  Future<void> _set(String id, String? key) async {
    final app = context.app;
    try {
      if (key == null) {
        await app.repo.unpinItem(app.activeProject, id);
      } else {
        await app.repo.setItemScheduledDate(app.activeProject, id, key);
      }
    } catch (e) {
      app.showToast('Failed updating scheduled date: $e', 'err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final d = parseDateKey(widget.dateKey) ?? getDhakaDate(0);
    final holiday = app.specialDays.holidayFor(d);
    final queued = app.queuedItems;
    final todayKey = dhakaTodayKey();
    bool pinnedHere(QueueItem i) {
      final s = i.scheduledDate;
      return s != null && (s == widget.dateKey || (widget.dateKey == todayKey && s.compareTo(todayKey) <= 0));
    }
    final here = queued.where(pinnedHere).toList();
    final t = _term.trim().toLowerCase();
    final available = queued.where((i) => !pinnedHere(i) && (t.isEmpty || '${i.title} ${i.name}'.toLowerCase().contains(t))).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Fa('fa-thumbtack', size: 16, color: p.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${fmtLongDayFull(d)}, ${d.year}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.text)),
                  if (holiday != null) TextSpan(text: '  · ★ $holiday', style: TextStyle(fontSize: 13, color: p.warn, fontWeight: FontWeight.w700)),
                ])),
              ),
              ZIconButton('fa-times', tooltip: 'Close', onPressed: () => Navigator.of(context).pop()),
            ]),
            const SizedBox(height: 14),
            Text('Pinned to this day', style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 13)),
            const SizedBox(height: 6),
            if (here.isEmpty)
              const EmptyNote('No files pinned to this day yet.')
            else
              for (final i in here) _row(i, remove: true),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text('Queued files', style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 13))),
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Search title / file name…', isDense: true, prefixIcon: Icon(Icons.search, size: 18)),
                  onChanged: (v) => setState(() => _term = v),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Flexible(
              child: available.isEmpty
                  ? const EmptyNote('No queued files found.')
                  : ListView(shrinkWrap: true, children: [for (final i in available.take(80)) _row(i, remove: false)]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(QueueItem item, {required bool remove}) {
    final p = context.pal;
    final ui = kDayTypeUi[item.dayType] ?? kDayTypeUi['WALLPAPER']!;
    final other = item.scheduledDate != null && item.scheduledDate != widget.dateKey;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Fa(ui.icon, size: 13, color: p.primary)),
        const SizedBox(width: 10),
        Expanded(child: Text(item.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: p.text, fontSize: 13))),
        if (other) Padding(padding: const EdgeInsets.only(right: 8), child: Pill('${item.scheduledDate}${remove ? ' (overdue)' : ''}', icon: 'fa-thumbtack', small: true, color: p.tintChip, fg: p.muted)),
        if (!remove && item.scheduledDate != null) ...[
          ZButton('Unpin', icon: 'fa-times', small: true, kind: ZBtnKind.danger, onPressed: () => _set(item.id, null)),
          const SizedBox(width: 6),
        ],
        remove
            ? ZButton('Unpin', icon: 'fa-times', small: true, kind: ZBtnKind.danger, onPressed: () => _set(item.id, null))
            : ZButton(item.scheduledDate != null ? 'Move here' : 'Pin', icon: item.scheduledDate != null ? 'fa-arrows-alt' : 'fa-thumbtack', small: true, onPressed: () => _set(item.id, widget.dateKey)),
      ]),
    );
  }
}
