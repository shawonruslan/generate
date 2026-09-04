import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/schedule.dart';

/// One chip on a calendar day. Same-named holidays from several countries are
/// merged into one chip that lists every country.
class SpecialDay {
  SpecialDay({
    required this.dateKey,
    required this.name,
    required this.kind,
    List<String>? countries,
  }) : countries = countries ?? <String>[];

  final String dateKey; // yyyy-MM-dd
  final String name;

  /// festival < bd < global < holiday (render priority, lower first)
  final String kind;
  final List<String> countries;

  int get rank {
    switch (kind) {
      case 'festival':
        return 0;
      case 'bd':
        return 1;
      case 'global':
        return 2;
      default:
        return 3;
    }
  }

  String get countryLabel {
    if (countries.isEmpty || countries.first == 'WW') return 'Worldwide';
    if (countries.length == 1) {
      return kCountryNames[countries.first] ?? countries.first;
    }
    if (countries.length <= 3) return countries.join(' · ');
    return '${countries.take(3).join(' · ')} +${countries.length - 3}';
  }

  String get flags => countries
      .where((String c) => c != 'WW')
      .take(4)
      .map(flagOf)
      .join(' ');

  static String flagOf(String country) {
    if (country.length != 2) return '';
    const int base = 0x1F1E6;
    final int a = country.toUpperCase().codeUnitAt(0) - 65;
    final int b = country.toUpperCase().codeUnitAt(1) - 65;
    if (a < 0 || a > 25 || b < 0 || b > 25) return '';
    return String.fromCharCodes(<int>[base + a, base + b]);
  }
}

/// Holiday engine - port of the SPECIAL_DAYS logic of the web dashboard.
///
/// * Built-in world observances + nth-weekday days always render (offline).
/// * Nager.Date public holidays for Europe / Americas / Asia (no key).
/// * India + Bangladesh from the Google Calendar holiday feeds (API key).
/// * Everything is cached on disk for 7 days.
class HolidayService {
  HolidayService();

  static const Duration cacheTtl = Duration(days: 7);

  final Map<String, Map<String, SpecialDay>> _byDate =
      <String, Map<String, SpecialDay>>{};
  final Set<String> _loadedFeeds = <String>{};
  final Set<int> _builtinYears = <int>{};
  final Set<String> _onlineCountries = <String>{};

  String _apiKey = kBuildCalendarApiKey.isNotEmpty
      ? kBuildCalendarApiKey
      : kDefaultCalendarApiKey;
  List<String> _enabledRegions = kNagerRegions.keys.toList();
  bool _googleEnabled = true;

  String get apiKey => _apiKey;
  bool get hasApiKey => _apiKey.trim().isNotEmpty;
  List<String> get enabledRegions => List<String>.unmodifiable(_enabledRegions);
  bool get googleEnabled => _googleEnabled;

  /// Number of countries with at least one online holiday loaded.
  int get onlineCountryCount => _onlineCountries.length;
  bool get onlineReady => _onlineCountries.isNotEmpty;

  Future<void> loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? storedKey = prefs.getString('googleCalendarApiKey');
    if (storedKey != null && storedKey.trim().isNotEmpty) {
      _apiKey = storedKey.trim();
    }
    final List<String>? regions = prefs.getStringList('holidayRegions');
    if (regions != null) _enabledRegions = regions;
    _googleEnabled = prefs.getBool('holidayGoogle') ?? true;
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key.trim().isEmpty ? kDefaultCalendarApiKey : key.trim();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('googleCalendarApiKey', key.trim());
    _loadedFeeds.removeWhere((String feed) => feed.startsWith('google_'));
  }

  Future<void> setRegions(List<String> regions, bool google) async {
    _enabledRegions = regions;
    _googleEnabled = google;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('holidayRegions', regions);
    await prefs.setBool('holidayGoogle', google);
  }

  /// Sorted chips for one day.
  List<SpecialDay> forDateKey(String dateKey) {
    final Map<String, SpecialDay>? map = _byDate[dateKey];
    if (map == null) return const <SpecialDay>[];
    final List<SpecialDay> list = map.values.toList()
      ..sort((SpecialDay a, SpecialDay b) {
        final int r = a.rank.compareTo(b.rank);
        if (r != 0) return r;
        return b.countries.length.compareTo(a.countries.length);
      });
    return list;
  }

  /// Built-in list is synchronous so the calendar is never blank.
  void ensureBuiltin(List<int> years) {
    for (final int year in years) {
      if (_builtinYears.contains(year)) continue;
      _builtinYears.add(year);
      for (final List<Object> entry in kWorldDaysFixed) {
        final DateTime d = DateTime(year, entry[0] as int, entry[1] as int);
        _add(dateKeyOf(d), entry[2] as String, 'WW', 'festival');
      }
      _add(dateKeyOf(_nthWeekday(year, 5, DateTime.sunday, 2)),
          "Mother's Day", 'WW', 'festival');
      _add(dateKeyOf(_nthWeekday(year, 6, DateTime.sunday, 3)),
          "Father's Day", 'WW', 'festival');
      _add(dateKeyOf(_nthWeekday(year, 8, DateTime.sunday, 1)),
          'Friendship Day', 'WW', 'festival');
      _add(dateKeyOf(_nthWeekday(year, 10, DateTime.friday, 1)),
          'World Smile Day', 'WW', 'festival');
      final DateTime thanksgiving = _nthWeekday(year, 11, DateTime.thursday, 4);
      _add(dateKeyOf(thanksgiving), 'Thanksgiving', 'US', 'holiday');
      _add(dateKeyOf(thanksgiving.add(const Duration(days: 1))),
          'Black Friday', 'WW', 'festival');
      _add(dateKeyOf(thanksgiving.add(const Duration(days: 4))),
          'Cyber Monday', 'WW', 'festival');
    }
  }

  static DateTime _nthWeekday(int year, int month, int weekday, int n) {
    final DateTime first = DateTime(year, month, 1);
    int delta = (weekday - first.weekday) % 7;
    if (delta < 0) delta += 7;
    return DateTime(year, month, 1 + delta + (n - 1) * 7);
  }

  /// Loads (or refreshes from cache) every online feed needed for [years].
  Future<void> ensureYears(List<int> years) async {
    ensureBuiltin(years);
    final List<Future<void>> jobs = <Future<void>>[];
    for (final int year in years) {
      if (_googleEnabled) {
        for (final String country in kGoogleHolidayCalendars.keys) {
          jobs.add(_loadGoogle(year, country));
        }
      }
      for (final String region in _enabledRegions) {
        for (final String country in kNagerRegions[region] ?? const <String>[]) {
          jobs.add(_loadNager(year, country));
        }
      }
    }
    await Future.wait(jobs);
  }

  static String _slug(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9]+"), ' ')
      .trim()
      .replaceAll(RegExp(r'\b(day|holiday|observance|public)\b'), '')
      .trim();

  void _add(String dateKey, String name, String country, String kind) {
    final Map<String, SpecialDay> bucket =
        _byDate.putIfAbsent(dateKey, () => <String, SpecialDay>{});
    final String slug = _slug(name).isEmpty ? name.toLowerCase() : _slug(name);
    final SpecialDay? existing = bucket[slug];
    if (existing != null) {
      if (!existing.countries.contains(country)) existing.countries.add(country);
      return;
    }
    bucket[slug] = SpecialDay(
      dateKey: dateKey,
      name: name,
      kind: kind,
      countries: <String>[country],
    );
  }

  Future<List<dynamic>?> _cachedFeed(String feedKey) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('feed_$feedKey');
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Object? savedAt = decoded['savedAt'];
      final int stamp = savedAt is num ? savedAt.toInt() : 0;
      final DateTime saved = DateTime.fromMillisecondsSinceEpoch(stamp);
      if (DateTime.now().difference(saved) > cacheTtl) return null;
      final Object? items = decoded['items'];
      if (items is List) return items;
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _storeFeed(String feedKey, List<dynamic> items) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'feed_$feedKey',
      jsonEncode(<String, Object?>{
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'items': items,
      }),
    );
  }

  void _apply(List<dynamic> items, String country, String kind) {
    for (final Object? entry in items) {
      if (entry is Map) {
        final Object? date = entry['date'];
        final Object? name = entry['name'];
        if (date != null && name != null) {
          _add(date.toString(), name.toString(), country, kind);
          _onlineCountries.add(country);
        }
      }
    }
  }

  Future<void> _loadGoogle(int year, String country) async {
    final String feedKey = 'google_${year}_$country';
    if (_loadedFeeds.contains(feedKey)) return;

    List<dynamic>? items = await _cachedFeed(feedKey);

    if (items == null && hasApiKey) {
      final String? calendarId = kGoogleHolidayCalendars[country];
      if (calendarId == null) return;
      final Uri uri = Uri.https(
        'www.googleapis.com',
        '/calendar/v3/calendars/${Uri.encodeComponent(calendarId)}/events',
        <String, String>{
          'key': _apiKey,
          'timeMin': '$year-01-01T00:00:00Z',
          'timeMax': '${year + 1}-01-01T00:00:00Z',
          'singleEvents': 'true',
          'orderBy': 'startTime',
          'maxResults': '2500',
        },
      );
      try {
        final http.Response res =
            await http.get(uri).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) return;
        final Object? decoded = jsonDecode(res.body);
        if (decoded is! Map) return;
        final Object? events = decoded['items'];
        if (events is! List) return;
        items = events
            .map((Object? event) {
              if (event is! Map) return null;
              final Object? start = event['start'];
              String? date;
              if (start is Map) {
                final Object? dateOnly = start['date'];
                final Object? dateTime = start['dateTime'];
                if (dateOnly != null) {
                  date = dateOnly.toString();
                } else if (dateTime != null) {
                  final String value = dateTime.toString();
                  date = value.length >= 10 ? value.substring(0, 10) : null;
                }
              }
              if (date == null) return null;
              return <String, String>{
                'date': date,
                'name': (event['summary'] ?? 'Holiday').toString(),
              };
            })
            .whereType<Map<String, String>>()
            .toList();
        await _storeFeed(feedKey, items);
      } catch (_) {
        return;
      }
    }

    if (items == null) return;
    _apply(items, country, country == 'BD' ? 'bd' : 'holiday');
    _loadedFeeds.add(feedKey);
  }

  Future<void> _loadNager(int year, String country) async {
    final String feedKey = 'nager_${year}_$country';
    if (_loadedFeeds.contains(feedKey)) return;

    List<dynamic>? items = await _cachedFeed(feedKey);

    if (items == null) {
      final Uri uri = Uri.https(
        'date.nager.at',
        '/api/v3/PublicHolidays/$year/$country',
      );
      try {
        final http.Response res =
            await http.get(uri).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) return;
        final Object? decoded = jsonDecode(res.body);
        if (decoded is! List) return;
        items = decoded
            .map((Object? entry) {
              if (entry is! Map) return null;
              if (entry['global'] == false) return null;
              final Object? date = entry['date'];
              if (date == null) return null;
              final Object? local = entry['localName'];
              final Object? english = entry['name'];
              return <String, String>{
                'date': date.toString(),
                'name': (english ?? local ?? 'Holiday').toString(),
              };
            })
            .whereType<Map<String, String>>()
            .toList();
        await _storeFeed(feedKey, items);
      } catch (_) {
        return;
      }
    }

    _apply(items, country, 'holiday');
    _loadedFeeds.add(feedKey);
  }
}
