import '../app_config.dart';
import 'queue_item.dart';

/// One filled slot on a schedule day.
class ScheduleSlot {
  const ScheduleSlot({
    required this.item,
    this.pinned = false,
    this.fallback = false,
  });

  final QueueItem item;

  /// The user pinned this row to the day (scheduledDate).
  final bool pinned;

  /// The day's own bucket was empty, so the bot will publish this type instead.
  final bool fallback;
}

/// One day card of the schedule calendar.
class ScheduleDay {
  ScheduleDay({
    required this.date,
    required this.dateKey,
    required this.type,
    required this.slotLimit,
    required this.isToday,
  });

  final DateTime date;
  final String dateKey;

  /// Content type the bot rotates to on this day.
  final String type;

  /// How many uploads still fit on this day (3, or fewer for today).
  final int slotLimit;
  final bool isToday;
  final List<ScheduleSlot> slots = <ScheduleSlot>[];

  bool get isWeekend =>
      date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

  int get emptySlots =>
      (slotLimit - slots.length) < 0 ? 0 : slotLimit - slots.length;

  bool get hasFallback => slots.any((ScheduleSlot s) => s.fallback);
}

/// Stats shown in the calendar legend.
class ScheduleStats {
  const ScheduleStats({
    required this.todayType,
    required this.remainingToday,
    required this.uploadedToday,
    required this.startIndex,
  });

  final String todayType;
  final int remainingToday;
  final int uploadedToday;
  final int startIndex;
}

String dateKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `M/D/YYYY` - the format the uploader bot writes into `uploadState`.
String usDateKeyOf(DateTime d) => '${d.month}/${d.day}/${d.year}';

DateTime? parseDateKey(String key) {
  final RegExpMatch? m =
      RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(key.trim());
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

/// Port of `computeScheduleStats()`.
ScheduleStats computeScheduleStats(UploadState state, DateTime todayDhaka) {
  final String todayUs = usDateKeyOf(todayDhaka);
  final String todayIso = dateKeyOf(todayDhaka);
  final bool sameDay =
      state.lastUploadDate == todayUs || state.lastUploadDate == todayIso;
  final int savedIdx = kTypeCycle.indexOf(state.uploadDayType);

  if (sameDay) {
    final int idx = savedIdx < 0 ? 0 : savedIdx;
    final int remaining = kUploadsPerDay - state.totalUploadsToday;
    return ScheduleStats(
      todayType: kTypeCycle[idx],
      remainingToday: remaining < 0 ? 0 : remaining,
      uploadedToday: state.totalUploadsToday,
      startIndex: idx,
    );
  }
  final int idx = savedIdx < 0 ? 0 : (savedIdx + 1) % kTypeCycle.length;
  return ScheduleStats(
    todayType: kTypeCycle[idx],
    remainingToday: kUploadsPerDay,
    uploadedToday: 0,
    startIndex: idx,
  );
}

/// Port of the day-filling loop in `buildScheduleCalendar()`.
///
/// * Day 0 is today (Dhaka clock), every following day rotates the type cycle.
/// * Pinned rows (scheduledDate) always land on their day; past dates roll to
///   today.
/// * Free slots take rows from the day's own type bucket, then fall back to the
///   next non-empty type so the bot never idles.
List<ScheduleDay> buildSchedule({
  required List<QueueItem> items,
  required UploadState uploadState,
  required DateTime todayDhaka,
  int minDays = kScheduleDaysPerPage,
  int maxDays = 700,
}) {
  final ScheduleStats stats = computeScheduleStats(uploadState, todayDhaka);
  final DateTime today =
      DateTime(todayDhaka.year, todayDhaka.month, todayDhaka.day);
  final String todayKey = dateKeyOf(today);

  final List<QueueItem> queued =
      items.where((QueueItem i) => i.isQueued).toList()
        ..sort((QueueItem a, QueueItem b) => a.id.compareTo(b.id));

  final Map<String, List<QueueItem>> buckets = <String, List<QueueItem>>{
    for (final String t in kTypeCycle) t: <QueueItem>[],
  };
  final Map<String, List<QueueItem>> pinned = <String, List<QueueItem>>{};

  for (final QueueItem item in queued) {
    final String sd = item.scheduledDate;
    if (sd.isNotEmpty) {
      final DateTime? d = parseDateKey(sd);
      String key = d == null ? sd : dateKeyOf(d);
      if (d != null && d.isBefore(today)) key = todayKey;
      pinned.putIfAbsent(key, () => <QueueItem>[]).add(item);
      continue;
    }
    final String bucket = item.bucket;
    if (buckets.containsKey(bucket)) {
      buckets[bucket]!.add(item);
    } else {
      buckets['WALLPAPER']!.add(item);
    }
  }

  bool bucketsLeft() =>
      buckets.values.any((List<QueueItem> l) => l.isNotEmpty);
  int pinnedLeft() => pinned.values.fold<int>(
      0, (int acc, List<QueueItem> l) => acc + l.length);

  final List<ScheduleDay> days = <ScheduleDay>[];
  int dayIdx = 0;
  while (dayIdx < maxDays &&
      (dayIdx < minDays || bucketsLeft() || pinnedLeft() > 0)) {
    final DateTime date = today.add(Duration(days: dayIdx));
    final String key = dateKeyOf(date);
    final String type =
        kTypeCycle[(stats.startIndex + dayIdx) % kTypeCycle.length];
    final int limit = dayIdx == 0 ? stats.remainingToday : kUploadsPerDay;
    final ScheduleDay day = ScheduleDay(
      date: date,
      dateKey: key,
      type: type,
      slotLimit: limit,
      isToday: dayIdx == 0,
    );

    // Pinned first - all of them, even above the limit.
    final List<QueueItem>? pins = pinned.remove(key);
    if (pins != null) {
      for (final QueueItem p in pins) {
        day.slots.add(ScheduleSlot(item: p, pinned: true));
      }
    }

    // Own type bucket.
    final List<QueueItem> own = buckets[type]!;
    while (day.slots.length < limit && own.isNotEmpty) {
      day.slots.add(ScheduleSlot(item: own.removeAt(0)));
    }

    // Smart fallback: next non-empty type in cycle order.
    if (day.slots.length < limit) {
      final int typeIdx = kTypeCycle.indexOf(type);
      for (int step = 1; step < kTypeCycle.length; step++) {
        final List<QueueItem> other =
            buckets[kTypeCycle[(typeIdx + step) % kTypeCycle.length]]!;
        if (other.isEmpty) continue;
        while (day.slots.length < limit && other.isNotEmpty) {
          day.slots.add(ScheduleSlot(item: other.removeAt(0), fallback: true));
        }
        if (day.slots.length >= limit) break;
      }
    }

    days.add(day);
    dayIdx++;
  }

  // Anything pinned far in the future beyond maxDays - append on the last day.
  if (pinned.isNotEmpty && days.isNotEmpty) {
    for (final List<QueueItem> rest in pinned.values) {
      for (final QueueItem p in rest) {
        days.last.slots.add(ScheduleSlot(item: p, pinned: true));
      }
    }
  }
  return days;
}
