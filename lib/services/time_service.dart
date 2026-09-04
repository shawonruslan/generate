import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

/// Real-time clock sync. The web dashboard uses `.info/serverTimeOffset`; the
/// REST API has no equivalent, so we read the HTTP `Date` header of the database
/// host (same NTP-backed clock) and fall back to public time APIs.
class TimeService {
  Duration _offset = Duration.zero;
  bool _synced = false;
  String _source = 'DEVICE CLOCK';

  bool get synced => _synced;
  String get source => _source;
  Duration get offset => _offset;

  /// Corrected UTC instant.
  DateTime nowUtc() => DateTime.now().toUtc().add(_offset);

  /// Wall-clock time in Dhaka (UTC+6) as a naive DateTime.
  DateTime nowDhaka() {
    final DateTime utc = nowUtc();
    final DateTime shifted = utc.add(kDhakaOffset);
    return DateTime(shifted.year, shifted.month, shifted.day, shifted.hour,
        shifted.minute, shifted.second);
  }

  Future<void> sync(String databaseUrl) async {
    if (await _fromDateHeader(databaseUrl)) return;
    if (await _fromTimeApi()) return;
    if (await _fromWorldTimeApi()) return;
    _synced = false;
    _source = 'DEVICE CLOCK';
  }

  void _apply(DateTime serverUtc, String source) {
    _offset = serverUtc.difference(DateTime.now().toUtc());
    // Ignore sub-2-second jitter: device clock is good enough then.
    if (_offset.abs() < const Duration(seconds: 2)) _offset = Duration.zero;
    _synced = true;
    _source = source;
  }

  Future<bool> _fromDateHeader(String databaseUrl) async {
    try {
      final http.Response res = await http
          .get(Uri.parse('$databaseUrl/.json?shallow=true'))
          .timeout(const Duration(seconds: 8));
      final String? date = res.headers['date'];
      if (date == null) return false;
      final DateTime parsed = _parseHttpDate(date);
      _apply(parsed, 'REAL SYNC');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fromTimeApi() async {
    try {
      final http.Response res = await http
          .get(Uri.parse(
              'https://timeapi.io/api/time/current/zone?timeZone=UTC'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return false;
      final Object? body = jsonDecode(res.body);
      if (body is! Map) return false;
      final String? iso = body['dateTime']?.toString();
      if (iso == null) return false;
      _apply(DateTime.parse('${iso}Z').toUtc(), 'REAL SYNC');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fromWorldTimeApi() async {
    try {
      final http.Response res = await http
          .get(Uri.parse('https://worldtimeapi.org/api/timezone/Etc/UTC'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return false;
      final Object? body = jsonDecode(res.body);
      if (body is! Map) return false;
      final String? iso = body['utc_datetime']?.toString();
      if (iso == null) return false;
      _apply(DateTime.parse(iso).toUtc(), 'REAL SYNC');
      return true;
    } catch (_) {
      return false;
    }
  }

  static const Map<String, int> _months = <String, int>{
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  /// `Sat, 05 Sep 2026 18:36:32 GMT`
  static DateTime _parseHttpDate(String value) {
    final RegExpMatch? m = RegExp(
            r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(value);
    if (m == null) throw FormatException('bad date header: $value');
    return DateTime.utc(
      int.parse(m.group(3)!),
      _months[m.group(2)!] ?? 1,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}

/// `DD/MM/YYYY HH:mm` in Dhaka time - used for auto generated set names.
String dhakaStamp(DateTime dhaka) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dhaka.day)}/${two(dhaka.month)}/${dhaka.year} ${two(dhaka.hour)}:${two(dhaka.minute)}';
}
