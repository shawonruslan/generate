import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Real-time sync + Dhaka calendar helpers.
///
/// PRIMARY: Firebase server clock (`.info/serverTimeOffset`, injected by the
/// RTDB client). FALLBACK: free HTTP time APIs. Never depends on the device
/// clock being correct (mirrors `realNow()`, `syncRealTime()` in the panel).
class RealTime {
  RealTime._();
  static final RealTime instance = RealTime._();

  int offsetMs = 0;
  bool synced = false;
  bool _fbAttached = false;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Timer? _timer;

  Stream<void> get changes => _changes.stream;

  /// Epoch ms of "real now".
  int nowMs() => DateTime.now().millisecondsSinceEpoch + offsetMs;
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(nowMs(), isUtc: true);

  /// Called by the Firebase client whenever `.info/serverTimeOffset` arrives.
  void setFirebaseOffset(num off) {
    offsetMs = off.round();
    synced = true;
    _fbAttached = true;
    _changes.add(null);
  }

  void start() {
    syncRealTime();
    Timer(const Duration(seconds: 3), syncRealTime);
    _timer ??= Timer.periodic(const Duration(minutes: 15), (_) => syncRealTime());
  }

  Future<void> syncRealTime() async {
    if (_fbAttached && synced) return;
    final sources = <_TimeSource>[
      _TimeSource('https://timeapi.io/api/time/current/zone?timeZone=UTC', (d) {
        final dt = d is Map ? d['dateTime'] : null;
        if (dt is! String || dt.isEmpty) return null;
        final parsed = DateTime.tryParse(dt.endsWith('Z') ? dt : '${dt}Z');
        return parsed?.millisecondsSinceEpoch;
      }),
      _TimeSource('https://worldtimeapi.org/api/timezone/Etc/UTC', (d) {
        final u = d is Map ? d['unixtime'] : null;
        return u is num ? (u * 1000).round() : null;
      }),
    ];
    for (final s in sources) {
      try {
        final t0 = DateTime.now().millisecondsSinceEpoch;
        final res = await http.get(Uri.parse(s.url)).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final serverMs = s.pick(jsonDecode(res.body));
        final t1 = DateTime.now().millisecondsSinceEpoch;
        if (serverMs == null) continue;
        offsetMs = serverMs - ((t0 + t1) ~/ 2);
        synced = true;
        _changes.add(null);
        return;
      } catch (_) {
        // try next source
      }
    }
  }
}

class _TimeSource {
  _TimeSource(this.url, this.pick);
  final String url;
  final int? Function(dynamic) pick;
}

/// Dhaka = UTC+6, no DST.
const Duration kDhakaOffset = Duration(hours: 6);

/// A "Dhaka wall-clock" DateTime (stored as UTC so arithmetic is stable).
DateTime dhakaNow() => RealTime.instance.now().add(kDhakaOffset);

/// `getDhakaDate(offsetDays)` - Dhaka wall-clock date shifted by N days.
DateTime getDhakaDate([int offsetDays = 0]) {
  final d = dhakaNow();
  return DateTime.utc(d.year, d.month, d.day + offsetDays, d.hour, d.minute, d.second);
}

String two(int n) => n.toString().padLeft(2, '0');

/// `fmtDateKey` -> YYYY-MM-DD
String fmtDateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

/// `dhakaTodayKey` -> YYYY-MM-DD (bot gate format).
String dhakaTodayKey() => fmtDateKey(getDhakaDate(0));

/// `dhakaTodayString` -> M/D/YYYY (uploadState.lastUploadDate format).
String dhakaTodayString() {
  final d = getDhakaDate(0);
  return '${d.month}/${d.day}/${d.year}';
}

String dhakaDateString(DateTime d) => '${d.month}/${d.day}/${d.year}';

/// Parse YYYY-MM-DD into a UTC-midnight DateTime (calendar day only).
DateTime? parseDateKey(String? key) {
  if (key == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(key.trim());
  if (m == null) return null;
  return DateTime.utc(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

/// `dhakaEpochMs(dateKey, minutesOfDay)` - epoch ms of that Dhaka minute.
int dhakaEpochMs(String dateKey, int minutesOfDay) {
  final d = parseDateKey(dateKey) ?? DateTime.utc(1970);
  return DateTime.utc(d.year, d.month, d.day, 0, minutesOfDay).millisecondsSinceEpoch - kDhakaOffset.inMilliseconds;
}

/// `dhakaNowMinutes` - minutes since Dhaka midnight (real time).
int dhakaNowMinutes() {
  final d = dhakaNow();
  return d.hour * 60 + d.minute;
}

/// `clock12(totalMin)` -> "3:05 PM"
String clock12(int totalMin) {
  final m = ((totalMin % 1440) + 1440) % 1440;
  final h = m ~/ 60;
  final mm = m % 60;
  final ampm = h >= 12 ? 'PM' : 'AM';
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$hh:${two(mm)} $ampm';
}

/// `hourLabel(h)` -> "3:00 PM"
String hourLabel(int h) {
  final ampm = h >= 12 ? 'PM' : 'AM';
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$hh:00 $ampm';
}

String windowLabel(int h, {int windowHours = 3}) => '${hourLabel(h)} - ${hourLabel((h + windowHours) % 24)}';

/// `fmtDhaka(ts)` -> "07/03 3:05 PM"
String fmtDhaka(num? ts) {
  if (ts == null || ts == 0) return '-';
  final d = DateTime.fromMillisecondsSinceEpoch(ts.round(), isUtc: true).add(kDhakaOffset);
  return '${two(d.day)}/${two(d.month)} ${clock12(d.hour * 60 + d.minute)}';
}

/// `fmtDhakaStamp(ms)` -> "12 Mar, 3:05 PM"
String fmtDhakaStamp(num? ms) {
  if (ms == null || ms == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true).add(kDhakaOffset);
  return '${d.day} ${kMonthShort[d.month - 1]}, ${clock12(d.hour * 60 + d.minute)}';
}

int? minutesAgo(num? ts) => (ts == null || ts == 0) ? null : ((DateTime.now().millisecondsSinceEpoch - ts) / 60000).round();

const List<String> kMonthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const List<String> kMonthLong = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'
];
const List<String> kWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> kWeekdayLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String weekdayShort(DateTime d) => kWeekdayShort[d.weekday - 1];
String weekdayLong(DateTime d) => kWeekdayLong[d.weekday - 1];

/// "Monday, Mar 3"
String fmtLongDay(DateTime d) => '${weekdayLong(d)}, ${kMonthShort[d.month - 1]} ${d.day}';

/// "Monday, March 3"
String fmtLongDayFull(DateTime d) => '${weekdayLong(d)}, ${kMonthLong[d.month - 1]} ${d.day}';

/// `fmtPinDate(key)` -> "Mon 3 Mar"
String fmtPinDate(String? key) {
  final d = parseDateKey(key);
  if (d == null) return key ?? '-';
  return '${weekdayShort(d)} ${d.day} ${kMonthShort[d.month - 1]}';
}

/// `relDayLabel(key, today)` -> "overdue - runs today" / "today" / "tomorrow" / "in N days"
String relDayLabel(String key, String todayKey) {
  if (key.compareTo(todayKey) < 0) return 'overdue - runs today';
  if (key == todayKey) return 'today';
  final a = parseDateKey(key);
  final b = parseDateKey(todayKey);
  if (a == null || b == null) return '';
  final diff = a.difference(b).inDays;
  if (diff == 1) return 'tomorrow';
  return 'in $diff days';
}

/// `formatBytes`
String formatBytes(num? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  const sizes = ['B', 'KB', 'MB'];
  var i = 0;
  var v = bytes.toDouble();
  while (v >= 1024 && i < 2) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(2)} ${sizes[i]}';
}

/// `fmtCountdown(ms)` -> {d,h,m,s}
class Countdown {
  const Countdown(this.days, this.hours, this.minutes, this.seconds, this.negative);
  final int days, hours, minutes, seconds;
  final bool negative;
  static Countdown fromMs(int ms) {
    final neg = ms < 0;
    var s = (ms.abs() / 1000).floor();
    final d = s ~/ 86400;
    s -= d * 86400;
    final h = s ~/ 3600;
    s -= h * 3600;
    final m = s ~/ 60;
    s -= m * 60;
    return Countdown(d, h, m, s, neg);
  }
}
