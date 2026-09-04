import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/queue_item.dart';
import '../services/holiday_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/item_editor.dart';

/// Month planner. Each day is a card with the same professional border +
/// layered shadow treatment as the web dashboard, and unscheduled items can be
/// dragged straight onto a day.
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final DateFormat keyFormat = DateFormat('yyyy-MM-dd');

    final int daysInMonth =
        DateTime(_month.year, _month.month + 1, 0).day;
    final int leading = DateTime(_month.year, _month.month, 1).weekday % 7;
    final List<DateTime?> cells = <DateTime?>[
      ...List<DateTime?>.filled(leading, null),
      ...List<DateTime?>.generate(
        daysInMonth,
        (int index) => DateTime(_month.year, _month.month, index + 1),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              onPressed: () => _shiftMonth(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Text(
              DateFormat('MMMM yyyy').format(_month),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Zc.ink,
              ),
            ),
            IconButton(
              onPressed: () => _shiftMonth(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => setState(() => _month = DateTime(
                    DateTime.now().year,
                    DateTime.now().month,
                  )),
              icon: const Icon(Icons.today_rounded, size: 15),
              label: const Text('Today'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: const <String>['S', 'M', 'T', 'W', 'T', 'F', 'S']
              .map(
                (String label) => Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w900,
                          color: Zc.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemCount: cells.length,
          itemBuilder: (BuildContext context, int index) {
            final DateTime? day = cells[index];
            if (day == null) return const SizedBox.shrink();
            final String dateKey = keyFormat.format(day);
            return _DayCard(
              day: day,
              dateKey: dateKey,
              isToday: dateKey == state.todayKey,
              items: state.itemsForDateKey(dateKey),
              holidays: state.holidays.forDateKey(dateKey),
              onDrop: (QueueItem item) =>
                  state.setScheduledDate(item.id, dateKey),
              onOpen: () => _openDay(context, dateKey, state),
            );
          },
        ),
        const SizedBox(height: 22),
        Row(
          children: <Widget>[
            const Text(
              'UNSCHEDULED',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w900,
                color: Zc.muted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(drag a chip onto a day)',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Zc.muted.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: state.unscheduledItems
              .take(40)
              .map((QueueItem item) => _DraggableChip(item: item))
              .toList(),
        ),
      ],
    );
  }

  Future<void> _openDay(
    BuildContext context,
    String dateKey,
    AppState state,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final List<QueueItem> items = state.itemsForDateKey(dateKey);
        final List<SpecialDay> holidays = state.holidays.forDateKey(dateKey);
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            shrinkWrap: true,
            children: <Widget>[
              Text(
                DateFormat('EEEE, dd MMMM yyyy')
                    .format(DateTime.parse(dateKey)),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Zc.ink,
                ),
              ),
              if (holidays.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: holidays
                      .map(
                        (SpecialDay holiday) => Chip(
                          label: Text(
                            '${holiday.flag} ${holiday.name} - ${holiday.countryName}',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'Nothing scheduled for this day yet.',
                    style: TextStyle(color: Zc.muted, fontWeight: FontWeight.w700),
                  ),
                )
              else
                ...items.map(
                  (QueueItem item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Zc.typeIcon(item.contentType),
                        color: Zc.goldDeep),
                    title: Text(
                      item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('${item.typeLabel} - ${item.status}'),
                    trailing: IconButton(
                      tooltip: 'Unschedule',
                      icon: const Icon(Icons.event_busy_rounded, size: 18),
                      onPressed: () {
                        state.setScheduledDate(item.id, null);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      showItemEditor(context, item);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DraggableChip extends StatelessWidget {
  const _DraggableChip({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context) {
    final Widget chip = Chip(
      avatar: Icon(Zc.typeIcon(item.contentType), size: 14, color: Zc.goldDeep),
      label: Text(
        item.displayTitle.length > 22
            ? '${item.displayTitle.substring(0, 22)}...'
            : item.displayTitle,
      ),
    );
    return Draggable<QueueItem>(
      data: item,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: chip),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: chip),
      child: chip,
    );
  }
}

class _DayCard extends StatefulWidget {
  const _DayCard({
    required this.day,
    required this.dateKey,
    required this.isToday,
    required this.items,
    required this.holidays,
    required this.onDrop,
    required this.onOpen,
  });

  final DateTime day;
  final String dateKey;
  final bool isToday;
  final List<QueueItem> items;
  final List<SpecialDay> holidays;
  final ValueChanged<QueueItem> onDrop;
  final VoidCallback onOpen;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool special = widget.holidays.isNotEmpty;

    return DragTarget<QueueItem>(
      onWillAcceptWithDetails: (DragTargetDetails<QueueItem> details) => true,
      onAcceptWithDetails: (DragTargetDetails<QueueItem> details) =>
          widget.onDrop(details.data),
      builder: (
        BuildContext context,
        List<QueueItem?> candidate,
        List<dynamic> rejected,
      ) {
        final bool dragging = candidate.isNotEmpty;
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onOpen,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.isToday
                    ? Zc.creamDeep
                    : (special ? const Color(0xFFFFFBEA) : Zc.panel),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: dragging
                      ? Zc.ok
                      : widget.isToday
                          ? Zc.goldDeep
                          : (_hover ? Zc.amber : const Color(0xFFEBE2CB)),
                  width: dragging || widget.isToday ? 2 : 1.5,
                ),
                boxShadow: kSoftShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        '${widget.day.day}',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: widget.isToday ? Zc.goldDeep : Zc.ink,
                        ),
                      ),
                      const Spacer(),
                      if (widget.items.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: Zc.goldGradient,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${widget.items.length}',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: Zc.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (special) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '${widget.holidays.first.flag} ${widget.holidays.first.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8.8,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Zc.warn,
                      ),
                    ),
                    if (widget.holidays.length > 1)
                      Text(
                        '+${widget.holidays.length - 1} more',
                        style: const TextStyle(
                          fontSize: 8.2,
                          fontWeight: FontWeight.w700,
                          color: Zc.muted,
                        ),
                      ),
                  ],
                  const Spacer(),
                  Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    children: widget.items
                        .take(4)
                        .map(
                          (QueueItem item) => Icon(
                            Zc.typeIcon(item.contentType),
                            size: 11,
                            color: Zc.statusColor(item.status),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
