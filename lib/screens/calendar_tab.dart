import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/queue_item.dart';
import '../models/schedule.dart';
import '../services/holiday_service.dart';
import '../services/time_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/day_picker.dart';
import '../widgets/item_editor.dart';
import '../widgets/stat_card.dart';
import '../widgets/ui.dart';

/// Schedule Calendar - the rolling upload plan of the active account with
/// pinned dates, special days and drag & drop pinning (desktop).
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  int _page = 0;
  bool _showTray = false;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<ScheduleDay> days = state.buildScheduleDays();
    final ScheduleStats stats = state.scheduleStats;
    final int pages = (days.length / kScheduleDaysPerPage).ceil().clamp(1, 1 << 20);
    if (_page >= pages) _page = pages - 1;
    final List<ScheduleDay> visible = days
        .skip(_page * kScheduleDaysPerPage)
        .take(kScheduleDaysPerPage)
        .toList();

    final String rangeLabel = visible.isEmpty
        ? ''
        : '${DateFormat('d MMM').format(visible.first.date)} - '
            '${DateFormat('d MMM yyyy').format(visible.last.date)}';

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool wide = c.maxWidth >= 900;
        final int cols = c.maxWidth >= 1500
            ? 7
            : c.maxWidth >= 1250
                ? 6
                : c.maxWidth >= 1000
                    ? 4
                    : c.maxWidth >= 720
                        ? 3
                        : c.maxWidth >= 480
                            ? 2
                            : 1;

        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 8, wide ? 24 : 14, 32),
          children: <Widget>[
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionTitle(
                    icon: Icons.calendar_month_rounded,
                    title: 'Schedule Calendar',
                    subtitle:
                        'Cycle: ${kTypeCycle.map((String t) => metaFor(t).short).join(' > ')}  -  $kUploadsPerDay uploads / day (Dhaka time)',
                    trailing: Wrap(
                      spacing: 6,
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Re-sync clock & holidays',
                          onPressed: state.holidaysLoading
                              ? null
                              : () async {
                                  await state.time.sync(state.account.databaseUrl);
                                  await state.refreshHolidays();
                                },
                          icon: state.holidaysLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded),
                        ),
                        if (wide)
                          OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _showTray = !_showTray),
                            icon: Icon(
                              _showTray
                                  ? Icons.visibility_off_rounded
                                  : Icons.drag_indicator_rounded,
                              size: 15,
                            ),
                            label: Text(_showTray
                                ? 'Hide drag tray'
                                : 'Drag & drop tray'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      LegendCard(
                        label: 'Active DB',
                        value: state.account.label,
                        icon: Icons.storage_rounded,
                        accent: Zc.ink,
                        hint: state.account.projectId,
                      ),
                      LegendCard(
                        label: 'Calendar time',
                        value: state.timeSynced ? 'REAL SYNC' : 'DEVICE CLOCK',
                        icon: Icons.access_time_filled_rounded,
                        accent: state.timeSynced ? Zc.okDeep : Zc.warn,
                        hint: dhakaStamp(state.dhakaNow),
                      ),
                      LegendCard(
                        label: 'Today',
                        value: metaFor(stats.todayType).dayLabel,
                        icon: Zc.typeIcon(stats.todayType),
                        accent: Zc.typeColor(stats.todayType),
                        hint: state.todayKey,
                      ),
                      LegendCard(
                        label: 'Remaining today',
                        value: '${stats.remainingToday}',
                        icon: Icons.hourglass_bottom_rounded,
                        accent: stats.remainingToday == 0 ? Zc.danger : Zc.goldDeep,
                        hint: 'slots left',
                      ),
                      LegendCard(
                        label: 'Uploaded today',
                        value: '${stats.uploadedToday}/$kUploadsPerDay',
                        icon: Icons.check_circle_rounded,
                        accent: Zc.okDeep,
                        hint: state.uploadState.lastUploadDate.isEmpty
                            ? 'no uploads yet'
                            : 'last ${state.uploadState.lastUploadDate}',
                      ),
                      for (final String type in kTypeCycle)
                        LegendCard(
                          label: metaFor(type).short,
                          value: '${state.countBucket(type)}',
                          icon: Zc.typeIcon(type),
                          accent: Zc.typeColor(type),
                          hint: 'queued',
                        ),
                      LegendCard(
                        label: 'Special days',
                        value: state.holidays.onlineReady
                            ? '${state.holidays.onlineCountryCount} COUNTRIES'
                            : 'BUILT-IN LIST',
                        icon: Icons.celebration_rounded,
                        accent: state.holidays.onlineReady ? Zc.okDeep : Zc.warn,
                        hint: state.holidaysLoading
                            ? 'loading feeds...'
                            : (state.holidays.onlineReady
                                ? 'Nager + Google'
                                : 'world days only'),
                      ),
                    ],
                  ),
                  if (_showTray && wide) ...<Widget>[
                    const SizedBox(height: 14),
                    _DragTray(items: state.unpinnedQueued),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: _page == 0 ? null : () => setState(() => _page--),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '$rangeLabel   -   page ${_page + 1} / $pages   -   ${days.length} days planned',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: Zc.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      _page >= pages - 1 ? null : () => setState(() => _page++),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.connecting && state.items.isEmpty)
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: cols == 1 ? 1.35 : 0.72,
                children: visible
                    .map((ScheduleDay day) => _DayCard(
                          key: ValueKey<String>(day.dateKey),
                          day: day,
                        ))
                    .toList(),
              ),
          ],
        );
      },
    );
  }
}

/// Horizontal strip of unpinned queued items that can be dragged onto days.
class _DragTray extends StatelessWidget {
  const _DragTray({required this.items});

  final List<QueueItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        'Every queued file is pinned already.',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Zc.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'DRAG A FILE ONTO A DAY TO PIN IT',
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w900,
            color: Zc.muted,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length.clamp(0, 60),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              final QueueItem item = items[index];
              final Widget tile = SizedBox(
                width: 64,
                child: Column(
                  children: <Widget>[
                    SizedBox(width: 56, height: 80, child: ItemThumb(item: item)),
                    const SizedBox(height: 4),
                    Text(
                      item.shortLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: Zc.typeColor(item.contentType),
                      ),
                    ),
                  ],
                ),
              );
              return Draggable<QueueItem>(
                data: item,
                feedback: Material(
                  color: Colors.transparent,
                  child: Opacity(opacity: 0.9, child: tile),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: tile),
                child: Tooltip(message: item.displayTitle, child: tile),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({super.key, required this.day});

  final ScheduleDay day;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.read<AppState>();
    final List<SpecialDay> holidays = state.holidays.forDateKey(day.dateKey);
    final Color typeColor = Zc.typeColor(day.type);
    final TypeMeta meta = metaFor(day.type);

    return DragTarget<QueueItem>(
      onWillAcceptWithDetails: (DragTargetDetails<QueueItem> d) => true,
      onAcceptWithDetails: (DragTargetDetails<QueueItem> d) async {
        try {
          await state.setScheduledDate(d.data.id, day.dateKey);
          if (context.mounted) {
            showSnack(context, 'Pinned "${d.data.displayTitle}" to ${day.dateKey}');
          }
        } catch (e) {
          if (context.mounted) showSnack(context, 'Error: $e', error: true);
        }
      },
      builder: (BuildContext context, List<QueueItem?> cand, List<dynamic> rej) {
        final bool hover = cand.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: day.isToday
                ? Zc.creamDeep
                : (day.isWeekend ? const Color(0xFFFFFBEE) : Zc.panel),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hover
                  ? Zc.okDeep
                  : day.isToday
                      ? Zc.goldDeep
                      : Zc.line,
              width: hover || day.isToday ? 2 : 1.5,
            ),
            boxShadow: day.isToday ? kLiftShadow : kSoftShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- header
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
                decoration: BoxDecoration(
                  gradient: day.isToday ? Zc.headerGradient : null,
                  color: day.isToday ? null : typeColor.withOpacity(0.08),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              '${day.date.day}',
                              style: const TextStyle(
                                fontSize: 24,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                color: Zc.ink,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  DateFormat('EEE').format(day.date).toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    letterSpacing: 1,
                                    fontWeight: FontWeight.w900,
                                    color: day.isWeekend ? Zc.orange : Zc.inkSoft,
                                  ),
                                ),
                                Text(
                                  DateFormat('MMM yyyy').format(day.date),
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Zc.muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (day.isToday)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Zc.ink,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Text(
                                'TODAY',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w900,
                                  color: Zc.gold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: typeColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Zc.typeIcon(day.type), size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            meta.short,
                            style: const TextStyle(
                              fontSize: 9.5,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ---- holidays ribbon
              if (holidays.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  color: const Color(0xFFFFF1BF),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: holidays.take(2).map((SpecialDay h) {
                      return Tooltip(
                        message: '${h.name} - ${h.countryLabel}',
                        child: Row(
                          children: <Widget>[
                            Text(
                              h.flags.isEmpty ? '\u{1F30D}' : h.flags,
                              style: const TextStyle(fontSize: 10),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                h.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Zc.inkSoft,
                                ),
                              ),
                            ),
                            if (h.countries.length > 1)
                              Text(
                                '+${h.countries.length}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Zc.muted,
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              // ---- slots
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: <Widget>[
                      for (final ScheduleSlot slot in day.slots.take(day.slotLimit))
                        Expanded(child: _SlotTile(slot: slot, day: day)),
                      for (int i = 0; i < day.emptySlots; i++)
                        Expanded(child: _EmptySlot(day: day)),
                      if (day.slotLimit == 0)
                        const Expanded(
                          child: Center(
                            child: Text(
                              'Daily quota reached',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Zc.muted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (day.hasFallback)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: Zc.warn.withOpacity(0.12),
                  child: const Text(
                    'FALLBACK - queue empty for this day type',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w900,
                      color: Zc.warn,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.slot, required this.day});

  final ScheduleSlot slot;
  final ScheduleDay day;

  @override
  Widget build(BuildContext context) {
    final QueueItem item = slot.item;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showItemEditor(context, item),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Zc.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: slot.pinned ? Zc.goldDeep : Zc.line,
              width: slot.pinned ? 1.8 : 1.2,
            ),
          ),
          child: Row(
            children: <Widget>[
              AspectRatio(
                aspectRatio: 9 / 16,
                child: ItemThumb(item: item, radius: 8),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Zc.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        TagPill(
                          text: item.shortLabel,
                          color: Zc.typeColor(item.contentType),
                        ),
                        if (slot.pinned) ...<Widget>[
                          const SizedBox(width: 4),
                          const Icon(Icons.push_pin_rounded,
                              size: 11, color: Zc.goldDeep),
                        ],
                        if (slot.fallback) ...<Widget>[
                          const SizedBox(width: 4),
                          const Icon(Icons.swap_horiz_rounded,
                              size: 12, color: Zc.warn),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.day});

  final ScheduleDay day;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showPinDaySheet(context, day),
        child: Container(
          decoration: BoxDecoration(
            color: Zc.cream,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE6DCBE), width: 1.2),
          ),
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.add_circle_outline_rounded, size: 14, color: Zc.muted),
                SizedBox(width: 5),
                Text(
                  'Tap to pin a file',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Zc.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
