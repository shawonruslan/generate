import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/queue_item.dart';
import '../models/schedule.dart';
import '../services/holiday_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'stat_card.dart';
import 'ui.dart';

/// Bottom sheet that pins / unpins queued files on one calendar day.
Future<void> showPinDaySheet(BuildContext context, ScheduleDay day) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => DayPickerSheet(dateKey: day.dateKey),
  );
}

class DayPickerSheet extends StatefulWidget {
  const DayPickerSheet({super.key, required this.dateKey});

  final String dateKey;

  @override
  State<DayPickerSheet> createState() => _DayPickerSheetState();
}

class _DayPickerSheetState extends State<DayPickerSheet> {
  String _query = '';
  String? _busyId;

  Future<void> _set(AppState state, String id, String? date) async {
    setState(() => _busyId = id);
    try {
      await state.setScheduledDate(id, date);
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final DateTime date = parseDateKey(widget.dateKey) ?? state.todayDhaka;
    final List<QueueItem> pinned = state.pinnedOn(widget.dateKey);
    final List<SpecialDay> holidays = state.holidays.forDateKey(widget.dateKey);
    final String q = _query.trim().toLowerCase();
    final List<QueueItem> candidates = state.unpinnedQueued
        .where((QueueItem i) => q.isEmpty ||
            i.displayTitle.toLowerCase().contains(q) ||
            i.name.toLowerCase().contains(q) ||
            i.tags.toLowerCase().contains(q) ||
            i.typeLabel.toLowerCase().contains(q))
        .take(80)
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext ctx, ScrollController controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Zc.canvas,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                decoration: const BoxDecoration(
                  gradient: Zc.headerGradient,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.push_pin_rounded, color: Zc.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            DateFormat('EEEE, d MMMM yyyy').format(date),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: Zc.ink,
                            ),
                          ),
                          Text(
                            holidays.isEmpty
                                ? 'Pin queued files to this day'
                                : holidays
                                    .map((SpecialDay h) => h.name)
                                    .join(' \u00b7 '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Zc.ink.withOpacity(0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: Zc.ink),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    Text(
                      'PINNED ON THIS DAY (${pinned.length})',
                      style: const TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w900,
                        color: Zc.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (pinned.isEmpty)
                      const Panel(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'Nothing pinned yet - the rolling cycle fills this day.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Zc.muted,
                          ),
                        ),
                      )
                    else
                      ...pinned.map(
                        (QueueItem item) => _Row(
                          item: item,
                          busy: _busyId == item.id,
                          actionLabel: 'Unpin',
                          actionIcon: Icons.close_rounded,
                          danger: true,
                          onAction: () => _set(state, item.id, null),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      'QUEUED FILES (${state.unpinnedQueued.length})',
                      style: const TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w900,
                        color: Zc.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (String v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search title, tags, type...',
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (candidates.isEmpty)
                      const Panel(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'No unpinned queued files match.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Zc.muted,
                          ),
                        ),
                      )
                    else
                      ...candidates.map(
                        (QueueItem item) => _Row(
                          item: item,
                          busy: _busyId == item.id,
                          actionLabel: 'Pin',
                          actionIcon: Icons.push_pin_rounded,
                          onAction: () => _set(state, item.id, widget.dateKey),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.busy,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    this.danger = false,
  });

  final QueueItem item;
  final bool busy;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.all(10),
        radius: 16,
        shadow: false,
        child: Row(
          children: <Widget>[
            SizedBox(width: 44, height: 60, child: ItemThumb(item: item)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: Zc.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    children: <Widget>[
                      TagPill(
                        text: item.shortLabel,
                        color: Zc.typeColor(item.contentType),
                        icon: Zc.typeIcon(item.contentType),
                      ),
                      if (item.tags.isNotEmpty)
                        TagPill(
                          text: item.tagList.take(2).join(', '),
                          color: Zc.muted,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : GradientButton(
                    label: actionLabel,
                    icon: actionIcon,
                    dense: true,
                    gradient: danger ? Zc.dangerGradient : Zc.goldGradient,
                    foreground: danger ? Colors.white : Zc.ink,
                    onPressed: onAction,
                  ),
          ],
        ),
      ),
    );
  }
}
