import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';

class SpecialDay {
  const SpecialDay({
    required this.dateKey,
    required this.name,
    required this.country,
  });

  final String dateKey; // yyyy-MM-dd
  final String name;
  final String country;

  String get countryName => kCountryNames[country] ?? country;

  /// Regional indicator flag, e.g. BD -> two code points that render as a flag.
  String get flag {
    if (country.length != 2) return '';
    final int base = 0x1F1E6;
    final int a = country.toUpperCase().codeUnitAt(0) - 65;
    final int b = country.toUpperCase().codeUnitAt(1) - 65;
    if (a < 0 || a > 25 || b < 0 || b > 25) return '';
    return String.fromCharCodes(<int>[base + a, base + b]);
  }
}

/// Holiday engine.
///
/// India and Bangladesh are fetched from the official Google Calendar holiday
/// feeds (the free Nager feed has no Indian data at all and an incomplete
/// Bangladeshi one). Every other country uses the key-less Nager feed.
/// Results are cached on disk for 7 days, so the calendar works offline too.
class HolidayService {
  HolidayService();

  static const Duration cacheTtl = Duration(days: 7);

  final Map<String, List<SpecialDay>> _byDate = <String, List<SpecialDay>>{};
  final Set<String> _loadedFeeds = <String>{};

  String _apiKey = kBuildCalendarApiKey;
  List<String> _nagerCountries = const <String>[
    'US', 'GB', 'CA', 'DE', 'FR', 'JP', 'KR', 'BR', 'ID',
  ];

  String get apiKey => _apiKey;
  List<String> get nagerCountries => List<String>.unmodifiable(_nagerCountries);
  bool get hasApiKey => _apiKey.trim().isNotEmpty;

  Future<void> loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? storedKey = prefs.getString('googleCalendarApiKey');
    if (storedKey != null && storedKey.trim().isNotEmpty) {
      _apiKey = storedKey.trim();
    }
    final List<String>? stored = prefs.getStringList('holidayCountries');
    if (stored != null && stored.isNotEmpty) {
      _nagerCountries = stored;
    }
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('googleCalendarApiKey', _apiKey);
    _loadedFeeds.removeWhere((String feed) => feed.startsWith('google_'));
  }

  Future<void> setNagerCountries(List<String> countries) async {
    _nagerCountries = countries;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('holidayCountries', countries);
  }

  List<SpecialDay> forDateKey(String dateKey) =>
      _byDate[dateKey] ?? const <SpecialDay>[];

  /// Loads (or refreshes from cache) every feed needed for [years].
  Future<void> ensureYears(List<int> years) async {
    final List<Future<void>> jobs = <Future<void>>[];
    for (final int year in years) {
      for (final String country in kGoogleHolidayCalendars.keys) {
        jobs.add(_loadGoogle(year, country));
      }
      for (final String country in _nagerCountries) {
        jobs.add(_loadNager(year, country));
      }
    }
    await Future.wait(jobs);
  }

  void _add(String dateKey, String name, String country) {
    final List<SpecialDay> bucket =
        _byDate.putIfAbsent(dateKey, () => <SpecialDay>[]);
    final bool duplicate = bucket.any((SpecialDay day) =>
        day.name.toLowerCase() == name.toLowerCase() &&
        day.country == country);
    if (duplicate) return;
    bucket.add(SpecialDay(dateKey: dateKey, name: name, country: country));
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
        final http.Response res = await http.get(uri);
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
    for (final Object? entry in items) {
      if (entry is Map) {
        final Object? date = entry['date'];
        final Object? name = entry['name'];
        if (date != null && name != null) {
          _add(date.toString(), name.toString(), country);
        }
      }
    }
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
        final http.Response res = await http.get(uri);
        if (res.statusCode != 200) return;
        final Object? decoded = jsonDecode(res.body);
        if (decoded is! List) return;
        items = decoded
            .map((Object? entry) {
              if (entry is! Map) return null;
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

    for (final Object? entry in items) {
      if (entry is Map) {
        final Object? date = entry['date'];
        final Object? name = entry['name'];
        if (date != null && name != null) {
          _add(date.toString(), name.toString(), country);
        }
      }
    }
    _loadedFeeds.add(feedKey);
  }
}
