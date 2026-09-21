import '../core/constants.dart';
import '../core/dhaka_time.dart';
import '../data/models.dart';
import 'run_schedule.dart';
import 'special_days.dart';

/// One planned calendar day (`daysOut[]` in `buildScheduleCalendar`).
class PlannedDay {
  PlannedDay({
    required this.index,
    required this.date,
    required this.dateKey,
    required this.specialDays,
    required this.isToday,
    required this.dayType,
    required this.switchedFrom,
    required this.slotCount,
    required this.slots,
  });
  final int index;
  final DateTime date;
  final String dateKey;
  final List<SpecialDay> specialDays;
  final bool isToday;
  final String dayType;
  final String? switchedFrom;
  final int slotCount;
  final List<QueueItem?> slots;
  List<RunPrediction> runs = [];

  int get planned => slots.where((s) => s != null).length;
  bool get isWeekend => date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
}

class PlannerResult {
  PlannerResult({required this.days, required this.rule, required this.buckets, required this.pinnedCount});
  final List<PlannedDay> days;
  final ScheduleRule rule;
  final Map<String, List<QueueItem>> buckets;
  final int pinnedCount;

  /// `nextRunOf(daysOut)`
  ({PlannedDay day, RunPrediction run, QueueItem? item})? get nextRun {
    for (final d in days) {
      for (var i = 0; i < d.runs.length; i++) {
        final r = d.runs[i];
        if (!r.overflow && r.isNext) return (day: d, run: r, item: i < d.slots.length ? d.slots[i] : null);
      }
    }
    return null;
  }

  /// Types that have stock but fewer than the full-day minimum.
  List<String> get waitingTypes => kTypeCycle.where((t) => (buckets[t]?.length ?? 0) > 0 && (buckets[t]?.length ?? 0) < kMinStockForDay).toList();
}

/// Publishing Layout Planner - mirrors `buildScheduleCalendar()` steps 1 + 3
/// and `annotateRuns()`. Pure function of queue + uploadState + schedule.
PlannerResult buildPlan({
  required List<QueueItem> queueItems,
  required UploadState? uploadState,
  required RunSchedule schedule,
  required String activeProject,
  required SpecialDaysEngine specialDays,
}) {
  // 1. Separate queued elements
  final queued = queueItems.where((i) => i.isQueued).toList()
    ..sort((a, b) {
      num ca = a.createdAt is num ? a.createdAt as num : 0;
      num cb = b.createdAt is num ? b.createdAt as num : 0;
      return ca.compareTo(cb);
    });

  final buckets = <String, List<QueueItem>>{for (final t in kTypeCycle) t: <QueueItem>[]};
  final todayPinKey = fmtDateKey(getDhakaDate(0));
  final pinnedByDate = <String, List<QueueItem>>{};
  var pinnedCount = 0;
  for (final i in queued) {
    final sd = i.scheduledDate;
    if (sd != null) {
      final k = sd.compareTo(todayPinKey) <= 0 ? todayPinKey : sd;
      pinnedByDate.putIfAbsent(k, () => []).add(i);
      pinnedCount++;
      continue;
    }
    final dt = i.dayType;
    buckets[dt]?.add(i);
  }

  final rule = ScheduleRule.compute(uploadState);

  // 3. Build scheduled days
  var currentDayType = rule.type;
  final typeIdx = <String, int>{for (final t in kTypeCycle) t: 0};
  var dayIdx = 0;
  final daysOut = <PlannedDay>[];
  const maxDays = 700;
  int remainingOf(String t) => (buckets[t]?.length ?? 0) - (typeIdx[t] ?? 0);
  final todayStr = dhakaTodayString();
  final lockedTodayType = (uploadState != null && uploadState.lastUploadDate == todayStr && uploadState.dayTypeLockedDate == todayStr)
      ? uploadState.uploadDayType
      : null;

  bool anyPinned() => pinnedByDate.values.any((l) => l.isNotEmpty);

  while ((dayIdx < 28 || kTypeCycle.any((t) => remainingOf(t) >= kMinStockForDay) || anyPinned()) && dayIdx < maxDays) {
    if (dayIdx > 0) {
      currentDayType = kTypeCycle[(kTypeCycle.indexOf(currentDayType) + 1) % kTypeCycle.length];
    }
    final slotLimit = dayIdx == 0 ? rule.remaining : 3;
    final dayDate = getDhakaDate(dayIdx);
    final dayKey = fmtDateKey(dayDate);
    final dayPinned = pinnedByDate[dayKey] ?? <QueueItem>[];
    final slots = <QueueItem?>[];
    String? daySwitchedFrom;
    var dayLocked = dayIdx == 0 && lockedTodayType != null && lockedTodayType.isNotEmpty;
    if (dayLocked) currentDayType = lockedTodayType!;

    for (var s = 0; s < slotLimit; s++) {
      QueueItem? allocated;
      if (dayPinned.isNotEmpty) {
        allocated = dayPinned.removeAt(0);
      } else if (dayLocked) {
        if (remainingOf(currentDayType) > 0) {
          allocated = buckets[currentDayType]![typeIdx[currentDayType]!];
          typeIdx[currentDayType] = typeIdx[currentDayType]! + 1;
        }
      } else {
        String? chosenType;
        if (remainingOf(currentDayType) >= kMinStockForDay) {
          chosenType = currentDayType;
        } else {
          final startIdx = kTypeCycle.indexOf(currentDayType).clamp(0, kTypeCycle.length - 1).toInt();
          for (var step = 1; step < kTypeCycle.length; step++) {
            final t = kTypeCycle[(startIdx + step) % kTypeCycle.length];
            if (remainingOf(t) >= kMinStockForDay) {
              chosenType = t;
              break;
            }
          }
        }
        if (chosenType != null) {
          if (chosenType != currentDayType) {
            daySwitchedFrom = currentDayType;
            currentDayType = chosenType;
          }
          dayLocked = true;
          allocated = buckets[chosenType]![typeIdx[chosenType]!];
          typeIdx[chosenType] = typeIdx[chosenType]! + 1;
        }
      }
      slots.add(allocated);
    }
    while (dayPinned.isNotEmpty) {
      slots.add(dayPinned.removeAt(0));
    }
    if (pinnedByDate[dayKey] != null && pinnedByDate[dayKey]!.isEmpty) pinnedByDate.remove(dayKey);

    daysOut.add(PlannedDay(
      index: dayIdx,
      date: dayDate,
      dateKey: dayKey,
      specialDays: specialDays.forDate(dayKey),
      isToday: dayIdx == 0,
      dayType: currentDayType,
      switchedFrom: daySwitchedFrom,
      slotCount: slotLimit > slots.length ? slotLimit : slots.length,
      slots: slots,
    ));
    dayIdx++;
  }

  _annotateRuns(daysOut, uploadState, schedule, activeProject, rule.uploadedToday);
  return PlannerResult(days: daysOut, rule: rule, buckets: buckets, pinnedCount: pinnedCount);
}

/// `annotateRuns(daysOut)` - adds runs[] parallel to slots on every day.
void _annotateRuns(List<PlannedDay> days, UploadState? uploadState, RunSchedule schedule, String activeProject, int uploadedToday) {
  final rot = ProfileRotation(uploadState);
  final nowMin = dhakaNowMinutes();
  var nextMarked = false;
  for (final d in days) {
    if (!d.isToday) rot.newDay();
    final used = d.isToday ? uploadedToday : 0;
    d.runs = List.generate(d.slots.length, (sIdx) {
      final w = used + sIdx;
      if (w >= kRunsPerDay) return RunPrediction.overflowRun();
      final r = schedule.predictRun(d.dateKey, w, activeProject);
      if (r == null) return RunPrediction.overflowRun();
      final p = rot.next();
      if (p >= 0) rot.use(p);
      r.profile = p;
      r.profileKnown = rot.known;
      r.passed = d.isToday && nowMin > r.windowEndMin;
      r.live = d.isToday && nowMin >= r.startMin && nowMin <= r.windowEndMin;
      r.isNext = !nextMarked && !r.passed;
      if (r.isNext) nextMarked = true;
      return r;
    });
  }
}

/// `predictedDateMap()` - id -> dateKey for every un-pinned planned item.
Map<String, String> predictedDateMap(PlannerResult plan) {
  final map = <String, String>{};
  for (final d in plan.days) {
    for (final it in d.slots) {
      if (it != null && it.scheduledDate == null) map[it.id] = d.dateKey;
    }
  }
  return map;
}

/// "Today's uploads" strip for every account (`renderRunTimeline`).
List<OverviewCard> buildOverview({
  required List<String> accountKeys,
  required String activeProject,
  required RunSchedule schedule,
  required Map<String, GateHealth?> gateHealth,
  required PlannerResult? plan,
  required int nowMs,
}) {
  final todayKey = dhakaTodayKey();
  final today = plan?.days.where((d) => d.isToday).firstOrNull;
  final uploadedToday = plan?.rule.uploadedToday ?? 0;
  final cards = <OverviewCard>[];
  for (var accountIndex = 0; accountIndex < accountKeys.length; accountIndex++) {
    final key = accountKeys[accountIndex];
    final isActive = key == activeProject;
    final wins = schedule.windowsFor(key);
    final gr = gateHealth[key]?.runsFor(todayKey) ?? const <int, Map<String, dynamic>>{};
    final gDone = gr.length;
    final upDone = isActive ? (gDone > uploadedToday ? gDone : uploadedToday) : gDone;
    final slots = <OverviewSlot>[];
    for (var w = 0; w < wins.length; w++) {
      final r = schedule.predictRun(todayKey, w, key);
      if (r == null) continue;
      final gRun = gr[w];
      final done = gRun != null || (isActive && gDone == 0 && w < uploadedToday);
      final passed = !done && nowMs > r.windowEndMs;
      final due = !done && !passed && nowMs >= r.startMs;
      final idx = w - upDone;
      final item = (isActive && idx >= 0 && today != null && idx < today.slots.length) ? today.slots[idx] : null;
      final pr = (isActive && idx >= 0 && today != null && idx < today.runs.length) ? today.runs[idx] : null;
      var detail = done
          ? gateRunLabel(gRun)
          : passed
              ? 'No run recorded in window'
              : due
                  ? 'Awaiting run confirmation'
                  : 'Scheduled · Dhaka time';
      if (!done && isActive && item != null) {
        detail = '${item.displayTitle}${pr != null ? ' · ${pr.profileLabel}' : ''}';
      } else if (!done && isActive && pr != null && !pr.overflow) {
        detail = 'Empty slot · ${pr.profileLabel}';
      }
      slots.add(OverviewSlot(run: r, done: done, passed: passed, due: due, detail: detail, gateRun: gRun));
    }
    cards.add(OverviewCard(key: key, accountIndex: accountIndex, isActive: isActive, slots: slots));
  }
  return cards;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
