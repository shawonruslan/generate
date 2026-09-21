import '../core/constants.dart';
import '../core/dhaka_time.dart';
import '../data/models.dart';

/// `gateHash(seed)` - same 31-multiplier hash the workflow gate job uses.
int gateHash(String seed) {
  var hash = 0;
  for (final c in seed.codeUnits) {
    hash = ((hash * 31) + c) & 0xFFFFFFFF;
  }
  return hash;
}

/// One predicted run (`predictRun`).
class RunPrediction {
  RunPrediction({
    required this.windowIdx,
    required this.dateKey,
    required this.exact,
    required this.chosen,
    required this.startMin,
    required this.endMin,
    required this.windowEndMin,
    required this.startMs,
    required this.endMs,
    required this.windowEndMs,
    required this.start,
    required this.end,
    required this.windowLabel,
  });

  final int windowIdx;
  final String dateKey;
  final bool exact;
  final int chosen;
  final int startMin, endMin, windowEndMin;
  final int startMs, endMs, windowEndMs;
  final String start, end, windowLabel;

  // annotateRuns() extras
  int profile = -1;
  bool profileKnown = false;
  bool passed = false;
  bool live = false;
  bool isNext = false;
  bool overflow = false;

  static RunPrediction overflowRun() => RunPrediction(
        windowIdx: -1, dateKey: '', exact: false, chosen: 0, startMin: 0, endMin: 0, windowEndMin: 0,
        startMs: 0, endMs: 0, windowEndMs: 0, start: '', end: '', windowLabel: '',
      )..overflow = true;

  /// `runProfileLabel(r)`
  String get profileLabel => profile < 0 ? 'Profile ?' : 'Profile #${profile + 1}${profileKnown ? '' : ' (est.)'}';

  /// `slotStateCls(r)` -> passed | live | next | ''
  String get stateCls {
    if (overflow) return '';
    if (passed) return 'passed';
    if (live) return 'live';
    if (isNext) return 'next';
    return '';
  }

  /// `runFlagHtml(r)` label
  String get flagText {
    if (overflow) return '';
    if (passed) return 'closed';
    if (live) return 'due';
    if (isNext) return 'next up';
    return 'scheduled';
  }
}

/// Live schedule for every account (`UPLOAD_WINDOWS`, `UPLOAD_SLOTS`).
class RunSchedule {
  RunSchedule({required this.defaultWindows});

  final Map<String, List<int>> defaultWindows;
  final Map<String, List<int>> windows = {};
  final Map<String, List<RunSlot>> slots = {};
  final Map<String, ScheduleMeta> meta = {};

  List<String> get keys => defaultWindows.keys.toList();

  List<int> windowsFor(String key) => windows[key] ?? defaultWindows[key] ?? defaultWindows.values.first;

  List<RunSlot> slotsFor(String key) => slots[key] ?? slotsFromWindows(windowsFor(key));

  /// Apply a `dashboardSettings/schedule` snapshot.
  void applySnapshot(String key, dynamic v) {
    final map = v is Map ? Map<String, dynamic>.from(v) : null;
    final sl = normalizeSlots(map?['slots']);
    final w = sl != null ? sl.map((x) => x.hour).toList() : normalizeWindows(map?['windows']);
    windows[key] = w ?? List<int>.from(defaultWindows[key] ?? const [10, 15, 20]);
    slots[key] = sl ?? slotsFromWindows(windows[key]!);
    meta[key] = ScheduleMeta(
      source: (sl != null || w != null) ? 'firebase' : 'default',
      updatedAt: map?['updatedAt'] is num ? map!['updatedAt'] as num : null,
      updatedBy: map?['updatedBy']?.toString(),
    );
  }

  /// `predictRun(dateKey, wIdx, projectKey)` - pure math, no DB needed.
  RunPrediction? predictRun(String dateKey, int wIdx, String projectKey) {
    final wins = windowsFor(projectKey);
    if (wIdx < 0 || wIdx >= wins.length) return null;
    final sl = slotsFor(projectKey);
    final slot = (wIdx < sl.length ? sl[wIdx] : RunSlot(hour: wins[wIdx], minute: 0, exact: false)).normalized();
    final exact = slot.exact;
    final wStart = slot.startMin, wEnd = slot.endMin;
    final startMin = exact ? wStart : wStart + (gateHash('$dateKey#$wIdx#${projectKey.toUpperCase()}') % (wEnd - wStart).clamp(1, 1 << 30).toInt());
    final endMin = startMin;
    final windowEndMin = wEnd > startMin ? wEnd : startMin;
    return RunPrediction(
      windowIdx: wIdx,
      dateKey: dateKey,
      exact: exact,
      chosen: ((startMin - wStart) / kRunSlotMin).floor(),
      startMin: startMin,
      endMin: endMin,
      windowEndMin: windowEndMin,
      startMs: dhakaEpochMs(dateKey, startMin),
      endMs: dhakaEpochMs(dateKey, endMin),
      windowEndMs: dhakaEpochMs(dateKey, windowEndMin),
      start: clock12(startMin),
      end: clock12(endMin),
      windowLabel: exact ? '${clock12(wStart)} (exact)' : '${clock12(wStart)} - ${clock12(wEnd)}',
    );
  }
}

/// Round-robin state machine == getNextAvailableProfile() in the workflow.
class ProfileRotation {
  ProfileRotation(UploadState? state) : known = state != null {
    final today = dhakaTodayString();
    total = (state?.totalProfilesAvailable ?? 3).clamp(1, 1 << 30).toInt();
    limit = (kRunsPerDay / total).ceil();
    if (state != null && state.lastUploadDate == today) {
      counts.addAll(state.profileUploadCounts);
    }
    lastUsed = state?.lastUsedProfileIndex ?? -1;
  }

  final bool known;
  late int total;
  late int limit;
  final Map<int, int> counts = {};
  int lastUsed = -1;

  int next() {
    var n = ((lastUsed + 1) % total + total) % total;
    for (var i = 0; i < total; i++) {
      if ((counts[n] ?? 0) < limit) return n;
      n = (n + 1) % total;
    }
    return -1;
  }

  void use(int p) {
    counts[p] = (counts[p] ?? 0) + 1;
    lastUsed = p;
  }

  void newDay() => counts.clear();
}

/// `computeScheduleStats()`
class ScheduleRule {
  const ScheduleRule({required this.type, required this.remaining, required this.uploadedToday});
  final String type;
  final int remaining;
  final int uploadedToday;

  static ScheduleRule compute(UploadState? uploadState) {
    final today = dhakaTodayString();
    var type = 'AUDIO';
    var remaining = 3;
    var uploadedToday = 0;
    if (uploadState != null) {
      if (uploadState.lastUploadDate == today) {
        type = uploadState.uploadDayType ?? 'AUDIO';
        uploadedToday = uploadState.totalUploadsToday;
        remaining = (3 - uploadedToday).clamp(0, 3).toInt();
      } else {
        final prev = kTypeCycle.contains(uploadState.uploadDayType) ? uploadState.uploadDayType! : kTypeCycle.last;
        type = kTypeCycle[(kTypeCycle.indexOf(prev) + 1) % kTypeCycle.length];
        uploadedToday = 0;
        remaining = 3;
      }
    }
    return ScheduleRule(type: type, remaining: remaining, uploadedToday: uploadedToday);
  }
}

/// `gateRunLabel(e)`
String gateRunLabel(Map<String, dynamic>? e) {
  if (e == null) return 'uploaded';
  final dh = e['dhaka']?.toString().trim() ?? '';
  final t = dh.isEmpty ? '' : dh.split(' ').last;
  return 'uploaded${t.isNotEmpty ? ' $t' : ''}${e['catchUp'] == true ? ' (catch-up)' : ''}';
}

/// One row of the "Today's uploads" overview.
class OverviewSlot {
  OverviewSlot({required this.run, required this.done, required this.passed, required this.due, required this.detail, this.gateRun});
  final RunPrediction run;
  final bool done;
  final bool passed;
  final bool due;
  final String detail;
  final Map<String, dynamic>? gateRun;
}

class OverviewCard {
  OverviewCard({required this.key, required this.accountIndex, required this.isActive, required this.slots});
  final String key;
  final int accountIndex;
  final bool isActive;
  final List<OverviewSlot> slots;
  int get doneCount => slots.where((s) => s.done).length;
  bool get complete => doneCount == slots.length;
  OverviewSlot? get next {
    for (final s in slots) {
      if (!s.done && !s.passed) return s;
    }
    return null;
  }
}
