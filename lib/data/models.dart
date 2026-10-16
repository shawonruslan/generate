import '../core/constants.dart';
import '../core/dhaka_time.dart';

/// Firebase push IDs encode their creation time in the first 8 chars.
const String kPushChars = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

int? pushIdToMs(String? id) {
  if (id == null || id.length < 8) return null;
  var ts = 0;
  for (var i = 0; i < 8; i++) {
    final idx = kPushChars.indexOf(id[i]);
    if (idx < 0) return null;
    ts = ts * 64 + idx;
  }
  return ts;
}

/// One row of `wallpaperQueue/<id>`. Kept as a thin wrapper around the raw
/// map so that unknown fields written by the bots are never lost on update.
class QueueItem {
  QueueItem(this.id, Map<String, dynamic> raw) : raw = Map<String, dynamic>.from(raw);

  final String id;
  final Map<String, dynamic> raw;

  String? _s(String k) {
    final v = raw[k];
    if (v == null) return null;
    if (v is String) return v;
    if (v is List) return v.map((e) => '${e ?? ''}'.trim()).where((e) => e.isNotEmpty).join(',');
    return '$v';
  }

  num? _n(String k) {
    final v = raw[k];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  String get name => _s('name') ?? '';
  String get title => _s('title') ?? '';
  String get tags => _s('tags') ?? '';
  String get category => _s('category') ?? '';
  String get description => _s('description') ?? '';
  String get prompt => _s('prompt') ?? '';
  String get status => (_s('status') ?? 'queued').isEmpty ? 'queued' : _s('status')!;
  String get fileUrl => _s('fileUrl') ?? '';
  String get thumbUrl => _s('thumbUrl') ?? '';
  String? get scheduledDate {
    final s = _s('scheduledDate');
    return (s == null || s.isEmpty) ? null : s;
  }
  num? get size => _n('size');
  num? get failedAt => _n('failedAt');
  num? get processingAt => _n('processingAt');
  num? get requeuedAt => _n('requeuedAt');
  num? get uploadedAt => _n('uploadedAt');
  dynamic get createdAt => raw['createdAt'];
  String get error => _s('error') ?? '';
  String? get deleteState => _s('deleteState');
  String? get deleteError => _s('deleteError');
  String? get contentTypeRaw => _s('contentType');
  bool get isMp3Flag => raw['isMp3'] == true;
  String? get uploadedBy => _s('uploadedBy');
  String? get sourceAccount => _s('sourceAccount');
  num? get durationSec => _n('durationSec') ?? _n('duration');
  Map<String, dynamic>? get files => raw['files'] is Map ? Map<String, dynamic>.from(raw['files'] as Map) : null;
  Map<String, dynamic>? get audioProcessing => raw['audioProcessing'] is Map ? Map<String, dynamic>.from(raw['audioProcessing'] as Map) : null;

  bool get isMp3 => isMp3Flag || name.toLowerCase().endsWith('.mp3');

  /// `getContentType(item)`
  String get contentType {
    final ct = contentTypeRaw;
    if (ct != null && ct.isNotEmpty) return ct;
    return isMp3 ? 'RINGTONE' : 'WALLPAPER';
  }

  bool get isSetType => kSetTypeMeta.containsKey(contentType);
  bool get isVideoType => kVideoTypeMeta.containsKey(contentType);
  bool get is24h => contentType == 'WALLPAPER_24H';
  List<String> get setSlots => kSetTypeMeta[contentType]?.slots ?? const [];

  String get typeShort => kSetTypeMeta[contentType]?.short ?? kVideoTypeMeta[contentType]?.short ?? '';
  String get typeShortIcon => kSetTypeMeta[contentType]?.icon ?? kVideoTypeMeta[contentType]?.icon ?? 'fa-image';

  /// `slotUrl24h(item, slot)`
  String slotUrl(String slot) {
    final f = files?[slot];
    if (f is String) return f;
    if (f is Map) return '${f['fileUrl'] ?? ''}';
    return '';
  }

  /// Slot record (may hold name/size/fileUrl).
  Map<String, dynamic>? slotRecord(String slot) {
    final f = files?[slot];
    if (f is Map) return Map<String, dynamic>.from(f);
    if (f is String) return {'fileUrl': f};
    return null;
  }

  String get displayTitle => title.trim().isNotEmpty ? title.trim() : (name.isNotEmpty ? name : 'Unnamed');
  String get displayTitleOrId => title.trim().isNotEmpty ? title.trim() : (name.isNotEmpty ? name : id);

  /// `itemDayType` - RINGTONE maps to AUDIO in the day cycle.
  String get dayType => contentType == 'RINGTONE' ? 'AUDIO' : contentType;

  /// `item.fileUrl || item.fileBase64 || item.imageBase64` (legacy inline previews).
  String get mediaSrc {
    if (fileUrl.isNotEmpty) return fileUrl;
    final b = _s('fileBase64') ?? _s('imageBase64') ?? '';
    return b;
  }

  /// Audio processing audit trail written by the ringtone generator.
  bool get hasAutoProcessFlag => raw.containsKey('autoProcess');
  bool get autoProcess => raw['autoProcess'] != false;
  bool get processed => raw['processed'] == true;
  String get processError => _s('processError') ?? '';
  Map<String, dynamic> get processing => raw['processing'] is Map ? Map<String, dynamic>.from(raw['processing'] as Map) : const {};

  /// Preview URL for cards: set -> first slot, video -> thumb, else fileUrl.
  String get previewUrl {
    if (isSetType) return slotUrl(setSlots.first);
    if (isVideoType) return thumbUrl.isNotEmpty ? thumbUrl : fileUrl;
    return fileUrl;
  }

  List<String> get tagList => tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  bool get isFailed {
    final s = status.toLowerCase();
    return s == 'failed' || s == 'error';
  }

  bool get isQueued => status == 'queued';

  /// v23 metadata guard: title + tags + category are required.
  List<String> get metadataMissingFields {
    final missing = <String>[];
    if (title.trim().isEmpty) missing.add('title');
    if (tags.trim().isEmpty) missing.add('tags');
    if (category.trim().isEmpty) missing.add('category');
    return missing;
  }

  bool get hasRequiredMetadata => metadataMissingFields.isEmpty;

  /// `itemTimeMs`
  int? get timeMs {
    final c = createdAt;
    if (c is num && c > 0) return c.round();
    if (c is String && c.isNotEmpty) {
      final t = DateTime.tryParse(c);
      if (t != null) return t.millisecondsSinceEpoch;
      final n = num.tryParse(c);
      if (n != null && n > 0) return n.round();
    }
    return pushIdToMs(id);
  }
}

/// `uploadState` node written by the bot.
class UploadState {
  UploadState(Map<String, dynamic> raw) : raw = Map<String, dynamic>.from(raw);
  final Map<String, dynamic> raw;

  String? get lastUploadDate => raw['lastUploadDate']?.toString();
  String? get uploadDayType => raw['uploadDayType']?.toString();
  String? get dayTypeLockedDate => raw['dayTypeLockedDate']?.toString();
  int get totalUploadsToday => (raw['totalUploadsToday'] as num?)?.toInt() ?? 0;
  int? get totalProfilesAvailable => (raw['totalProfilesAvailable'] as num?)?.toInt();
  int? get lastUsedProfileIndex {
    final v = raw['lastUsedProfileIndex'];
    return v is num ? v.toInt() : null;
  }
  Map<int, int> get profileUploadCounts {
    final out = <int, int>{};
    final m = raw['profileUploadCounts'];
    if (m is Map) {
      m.forEach((k, v) {
        final kk = int.tryParse('$k');
        if (kk != null) out[kk] = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      });
    } else if (m is List) {
      for (var i = 0; i < m.length; i++) {
        final v = m[i];
        if (v != null) out[i] = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      }
    }
    return out;
  }
}

/// v23.1 schedule slot = { hour, minute, exact, endHour, endMinute }.
class RunSlot {
  RunSlot({required this.hour, this.minute = 0, this.exact = false, int? endHour, int? endMinute}) {
    final okEnd = endHour != null && endHour >= 0 && endHour <= 23 && endMinute != null && endMinute >= 0 && endMinute <= 59 && endHour * 60 + endMinute > hour * 60 + minute;
    if (exact) {
      this.endHour = hour;
      this.endMinute = minute;
    } else if (!okEnd) {
      final e = (hour * 60 + minute + kRunWindowHours * 60).clamp(0, 23 * 60 + 59).toInt();
      this.endHour = e ~/ 60;
      this.endMinute = e % 60;
    } else {
      this.endHour = endHour;
      this.endMinute = endMinute;
    }
  }

  int hour;
  int minute;
  bool exact;
  late int endHour;
  late int endMinute;

  /// `withEnd(x)` from a loose map.
  static RunSlot? fromMap(dynamic x) {
    if (x is! Map) return null;
    final h = num.tryParse('${x['hour']}');
    if (h == null || h != h.roundToDouble() || h < 0 || h > 23) return null;
    final m = num.tryParse('${x['minute'] ?? 0}') ?? 0;
    if (m != m.roundToDouble() || m < 0 || m > 59) return null;
    return RunSlot(
      hour: h.toInt(),
      minute: m.toInt(),
      exact: x['exact'] == true,
      endHour: num.tryParse('${x['endHour']}')?.toInt(),
      endMinute: num.tryParse('${x['endMinute'] ?? 0}')?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute, 'exact': exact, 'endHour': endHour, 'endMinute': endMinute};

  RunSlot clone() => RunSlot(hour: hour, minute: minute, exact: exact, endHour: endHour, endMinute: endMinute);

  int get startMin => hour * 60 + minute;
  int get endMin => exact ? startMin : endHour * 60 + endMinute;
  String get clock => clock12(startMin);
  String get endClock => clock12(endMin);
  String get timeValue => '${two(hour)}:${two(minute)}';
  String get endTimeValue => '${two(endHour)}:${two(endMinute)}';

  /// Re-normalise after edits (keeps exact end == start, fixes bad ends).
  RunSlot normalized() => RunSlot(hour: hour, minute: minute, exact: exact, endHour: endHour, endMinute: endMinute);

  @override
  bool operator ==(Object other) =>
      other is RunSlot && other.hour == hour && other.minute == minute && other.exact == exact && other.endHour == endHour && other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(hour, minute, exact, endHour, endMinute);
}

List<RunSlot> slotsFromWindows(List<int> wins) => wins.map((h) => RunSlot(hour: h, minute: 0, exact: false)).toList();

List<RunSlot>? normalizeSlots(dynamic arr) {
  if (arr is! List) return null;
  final out = arr.map(RunSlot.fromMap).whereType<RunSlot>().toList();
  return out.isEmpty ? null : out;
}

List<int>? normalizeWindows(dynamic arr) {
  if (arr is! List) return null;
  final w = arr.map((x) => num.tryParse('$x')).where((x) => x != null && x == x.roundToDouble() && x >= 0 && x <= 23).map((x) => x!.toInt()).toList();
  return w.isEmpty ? null : w;
}

List<RunSlot> cloneSlots(List<RunSlot> a) => a.map((s) => s.normalized()).toList();

bool slotsEqual(List<RunSlot> a, List<RunSlot> b) {
  final x = cloneSlots(a), y = cloneSlots(b);
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

String? validateSlots(List<RunSlot> slots) {
  if (slots.length != kRunsPerDay) return 'Need $kRunsPerDay upload slots';
  for (final sl in slots) {
    if (sl.hour < 0 || sl.hour > 23) return 'Hour out of range';
    if (sl.minute < 0 || sl.minute > 59) return 'Minute out of range';
    if (!sl.exact && sl.endMin - sl.startMin < kRunSlotMin) return 'Window too short - keep at least $kRunSlotMin min between From and To';
  }
  final sorted = cloneSlots(slots)..sort((a, b) => a.startMin.compareTo(b.startMin));
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].startMin - sorted[i - 1].endMin < kRunSlotMin) return 'Slot $i and ${i + 1} overlap - keep at least $kRunSlotMin min between them';
  }
  return null;
}

String? validateWindows(List<int> w) {
  if (w.length != kRunsPerDay) return 'Need $kRunsPerDay windows';
  final sorted = List<int>.from(w)..sort();
  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i] < 0 || sorted[i] > 23) return 'Hour out of range';
    if (i > 0 && sorted[i] - sorted[i - 1] < kRunWindowHours) return 'Windows overlap - keep at least $kRunWindowHours h between start hours';
  }
  if (sorted.last + kRunWindowHours > 24) return 'Last window must end before midnight (start ≤ 9 PM)';
  return null;
}

class ScheduleMeta {
  ScheduleMeta({this.source = 'default', this.updatedAt, this.updatedBy});
  final String source; // firebase | default
  final num? updatedAt;
  final String? updatedBy;
}

/// `dashboardSettings/gate` written by the workflow gate job.
class GateHealth {
  GateHealth(Map<String, dynamic> raw) : raw = Map<String, dynamic>.from(raw);
  final Map<String, dynamic> raw;
  num? get lastPing => raw['lastPing'] is num ? raw['lastPing'] as num : num.tryParse('${raw['lastPing'] ?? ''}');
  String? get lastPingDhaka => raw['lastPingDhaka']?.toString();
  String? get lastDecision => raw['lastDecision']?.toString();
  String? get lastRunDhaka => raw['lastRunDhaka']?.toString();
  List<int>? get windowsUsed => normalizeWindows(raw['windowsUsed']);
  List<RunSlot>? get slotsUsed => normalizeSlots(raw['slotsUsed']);

  /// `gateRunsToday(key)` -> windowIdx -> { dhaka, catchUp, ... }
  Map<int, Map<String, dynamic>> runsFor(String dateKey) {
    final runs = raw['runs'];
    final out = <int, Map<String, dynamic>>{};
    if (runs is Map) {
      final day = runs[dateKey];
      if (day is Map) {
        day.forEach((k, v) {
          final n = int.tryParse('$k');
          if (n != null) out[n] = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
        });
      } else if (day is List) {
        for (var i = 0; i < day.length; i++) {
          if (day[i] != null) out[i] = day[i] is Map ? Map<String, dynamic>.from(day[i] as Map) : <String, dynamic>{};
        }
      }
    }
    return out;
  }
}

/// v25 Mix mode (`dashboardSettings/variety`).
class VarietyConfig {
  VarietyConfig({required this.enabled, required this.strict, required this.types, this.updatedAt, this.updatedBy});
  bool enabled;
  bool strict;
  List<String> types;
  final num? updatedAt;
  final String? updatedBy;

  static VarietyConfig live(Map<String, dynamic>? raw) {
    final v = raw ?? const {};
    var types = <String>[];
    if (v['types'] is List) types = (v['types'] as List).map((e) => '$e').where(kVarietyAll.contains).toList();
    if (types.isEmpty) types = List<String>.from(kVarietyAll);
    return VarietyConfig(
      enabled: v['enabled'] == true,
      strict: v['strict'] == true,
      types: types,
      updatedAt: v['updatedAt'] is num ? v['updatedAt'] as num : null,
      updatedBy: v['updatedBy']?.toString(),
    );
  }

  VarietyConfig copy() => VarietyConfig(enabled: enabled, strict: strict, types: List<String>.from(types), updatedAt: updatedAt, updatedBy: updatedBy);

  bool sameAs(VarietyConfig o) => enabled == o.enabled && strict == o.strict && types.join(',') == o.types.join(',');
}

/// `varietyOrderToday(types)` - rotation start shifts by Dhaka day number.
List<String> varietyOrderToday(List<String> types) => varietyOrderForDay(types, 0);

/// Mix-mode order for the Dhaka day [dayOffset] days from today (0 = today).
/// Mirrors the bot: `types` rotated by `floor((now + 6h) / 86400000)` evaluated on that day.
List<String> varietyOrderForDay(List<String> types, int dayOffset) {
  if (types.isEmpty) return const [];
  final dayNo = ((RealTime.instance.nowMs() + 6 * 3600 * 1000) / 86400000).floor() + dayOffset;
  final s = dayNo % types.length;
  return List.generate(types.length, (i) => types[(s + i) % types.length]);
}

/// `dashboardSettings/metadataAlerts` bot report.
class MetaAlertReport {
  MetaAlertReport(Map<String, dynamic> raw) : raw = Map<String, dynamic>.from(raw);
  final Map<String, dynamic> raw;
  int get count => (raw['count'] as num?)?.toInt() ?? int.tryParse('${raw['count'] ?? ''}') ?? 0;
  String? get updatedDhaka => raw['updatedDhaka']?.toString();
}

/// Result of a verified permanent deletion (`purgeItems`).
class PurgeResult {
  int rows = 0;
  int files = 0;
  int kept = 0;
  int failed = 0;
  int retained = 0;
  bool verifyFailed = false;
  bool corsBlocked = false;
  final List<String> errors = [];
  final List<String> deletedIds = [];

  bool get ok => !(failed > 0 || verifyFailed || retained > 0 || kept > 0);
  String get kind => ok ? 'ok' : 'err';

  String summary([String? what]) {
    var msg = 'Deleted $rows ${what ?? 'item(s)'} · $files R2 object(s) verified absent';
    if (retained > 0) msg += ' · $retained record(s) kept — retry/review required';
    if (kept > 0) msg += ' · $kept shared/in-use or invalid item(s) blocked';
    if (errors.isNotEmpty) msg += ' · ${errors.first}';
    return msg;
  }

  Map<String, dynamic> toJson() => {
        'rows': rows, 'files': files, 'kept': kept, 'failed': failed, 'retained': retained,
        'verifyFailed': verifyFailed, 'corsBlocked': corsBlocked, 'errors': errors, 'deletedIds': deletedIds,
      };
}

/// Progress callback for the purge overlay.
class PurgePhase {
  const PurgePhase(this.text, this.current, this.total, {this.live, this.indeterminate = false});
  final String text;
  final int current;
  final int total;
  final String? live;
  final bool indeterminate;
}
