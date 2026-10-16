import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dhaka_time.dart';

/// SPECIAL DAYS ENGINE (100% live feeds, no manual holiday list)
/// 1) India + Bangladesh public holidays -> Google Calendar holiday feeds
/// 2) All other countries' public holidays -> date.nager.at (no API key)
/// 3) Built-in: only fixed-date world/fun days that no API provides.
/// Every feed is cached for 7 days (SharedPreferences == localStorage).
class SpecialDay {
  SpecialDay({required this.name, required this.icon, required this.kind, required this.slug, this.countries});
  final String name;
  final String icon; // font-awesome name, e.g. "fa-gifts"
  final String kind; // holiday | festival | bd | global
  final String slug;
  List<String>? countries;

  /// Chip label: show the country code only when a holiday belongs to exactly one country.
  String get label => (countries != null && countries!.length == 1) ? '$name (${countries!.first})' : name;

  int get rank => const {'festival': 0, 'bd': 1, 'global': 2, 'holiday': 3}[kind] ?? 9;
}

const List<String> kSpecialDaysEurope = ['GB', 'IE', 'DE', 'FR', 'ES', 'PT', 'IT', 'NL', 'BE', 'CH', 'AT', 'SE', 'NO', 'DK', 'FI', 'PL', 'CZ', 'GR', 'RU', 'UA'];
const List<String> kSpecialDaysAmericas = ['US', 'CA', 'MX', 'BR', 'AR', 'CL', 'CO', 'PE'];
const List<String> kSpecialDaysAsia = ['JP', 'KR', 'CN', 'HK', 'SG', 'VN', 'ID', 'KZ'];
final List<String> kSpecialDaysCountries = [...kSpecialDaysEurope, ...kSpecialDaysAmericas, ...kSpecialDaysAsia];
const int kSpecialDaysCacheMs = 7 * 24 * 60 * 60 * 1000;

const Map<String, String> kGoogleHolidayCalendars = {
  'IN': 'en.indian.official#holiday@group.v.calendar.google.com',
  'BD': 'en.bd.official#holiday@group.v.calendar.google.com',
};

const bool kSpecialDaysIncludeWorldDays = true;

/// [month, day, name, icon] - all stored with kind "global"
const List<List<Object>> kSpecialDaysWorld = [
  [1, 1, "New Year's Day", 'fa-champagne-glasses'],
  [2, 9, 'Pizza Day', 'fa-pizza-slice'],
  [2, 14, "Valentine's Day", 'fa-heart'],
  [3, 8, "Women's Day", 'fa-venus'],
  [3, 20, 'Day of Happiness / Spring Begins', 'fa-face-smile'],
  [4, 1, "April Fools' Day", 'fa-face-grin-tears'],
  [4, 15, 'World Art Day', 'fa-palette'],
  [4, 22, 'Earth Day', 'fa-earth-americas'],
  [5, 4, 'Star Wars Day', 'fa-jedi'],
  [5, 21, 'International Tea Day', 'fa-mug-hot'],
  [6, 5, 'World Environment Day', 'fa-leaf'],
  [6, 8, 'World Oceans Day', 'fa-water'],
  [6, 21, 'World Music Day / Summer Begins', 'fa-music'],
  [7, 7, 'World Chocolate Day', 'fa-cookie-bite'],
  [7, 17, 'World Emoji Day', 'fa-face-laugh-squint'],
  [7, 30, 'Intl Friendship Day', 'fa-user-group'],
  [8, 8, 'International Cat Day', 'fa-cat'],
  [8, 19, 'World Photography Day', 'fa-camera-retro'],
  [8, 26, 'International Dog Day', 'fa-dog'],
  [9, 21, 'Day of Peace', 'fa-dove'],
  [9, 22, 'Autumn Begins', 'fa-wind'],
  [10, 1, 'International Coffee Day', 'fa-mug-saucer'],
  [10, 4, 'World Animal Day', 'fa-paw'],
  [10, 5, "World Teachers' Day", 'fa-chalkboard-user'],
  [10, 10, 'World Mental Health Day', 'fa-brain'],
  [10, 31, 'Halloween', 'fa-ghost'],
  [11, 13, 'World Kindness Day', 'fa-hand-holding-heart'],
  [11, 14, "Children's Day", 'fa-child'],
  [11, 19, "Intl Men's Day", 'fa-mars'],
  [12, 21, 'Winter Begins', 'fa-snowflake'],
  [12, 24, 'Christmas Eve', 'fa-sleigh'],
  [12, 25, 'Christmas', 'fa-gifts'],
  [12, 31, "New Year's Eve", 'fa-champagne-glasses'],
];

const Map<String, String> kSpecialKindText = {'festival': 'Festival', 'bd': 'Bangladesh', 'global': 'Global day', 'holiday': 'Public holiday'};
const Map<String, String> kHolidayNoteKind = {'holiday': 'Public holiday', 'festival': 'Festival', 'bd': 'Special day', 'global': 'Observance'};

const Map<String, String> kHolidayCountryNames = {
  'GB': 'United Kingdom', 'IE': 'Ireland', 'DE': 'Germany', 'FR': 'France', 'ES': 'Spain', 'PT': 'Portugal',
  'IT': 'Italy', 'NL': 'Netherlands', 'BE': 'Belgium', 'CH': 'Switzerland', 'AT': 'Austria', 'SE': 'Sweden',
  'NO': 'Norway', 'DK': 'Denmark', 'FI': 'Finland', 'PL': 'Poland', 'CZ': 'Czechia', 'GR': 'Greece',
  'RU': 'Russia', 'UA': 'Ukraine', 'US': 'United States', 'CA': 'Canada', 'MX': 'Mexico', 'BR': 'Brazil',
  'AR': 'Argentina', 'CL': 'Chile', 'CO': 'Colombia', 'PE': 'Peru', 'JP': 'Japan', 'KR': 'South Korea',
  'CN': 'China', 'HK': 'Hong Kong', 'SG': 'Singapore', 'VN': 'Vietnam', 'ID': 'Indonesia', 'KZ': 'Kazakhstan',
  'IN': 'India', 'BD': 'Bangladesh', 'AU': 'Australia', 'NZ': 'New Zealand', 'AE': 'UAE', 'SA': 'Saudi Arabia',
  'TR': 'Turkey', 'PK': 'Pakistan', 'LK': 'Sri Lanka', 'NP': 'Nepal', 'MY': 'Malaysia', 'PH': 'Philippines',
  'TH': 'Thailand', 'ZA': 'South Africa', 'EG': 'Egypt', 'NG': 'Nigeria',
};

class _Hint {
  const _Hint(this.re, this.codes);
  final String re;
  final List<String> codes;
}

/// Built-in day names carry their country in the label, e.g. "Republic Day (India)".
const List<_Hint> _kHolidayNameHints = [
  _Hint(r'\((?:bd|bangladesh)\)', ['BD']), _Hint(r'\(india\)', ['IN']), _Hint(r'\(u\.?s\.?a?\.?\)|\(united states\)', ['US']),
  _Hint(r'\((?:uk|gb|great britain|united kingdom)\)', ['GB']), _Hint(r'\(canada\)', ['CA']), _Hint(r'\(japan\)', ['JP']),
  _Hint(r'\(china\)', ['CN']), _Hint(r'\(korea\)', ['KR']), _Hint(r'\(mexico\)', ['MX']), _Hint(r'\(brazil\)', ['BR']),
  _Hint(r'\(germany\)', ['DE']), _Hint(r'\(france\)', ['FR']), _Hint(r'\(pakistan\)', ['PK']), _Hint(r'\(nepal\)', ['NP']),
  _Hint(r'\(australia\)', ['AU']), _Hint(r'juneteenth|thanksgiving \(us\)|veterans day', ['US']),
  _Hint(r'cinco de mayo', ['MX']), _Hint(r"st\.? patrick", ['IE']),
  _Hint(r'pohela boishakh|bangla noboborsho|noboborsho|shohid dibosh|ekushey|mother language day|nobanno|victory day \(bd\)|sheikh mujib|shaheed', ['BD']),
  _Hint(r'durga puja|kali puja|laxmi puja|lakshmi puja|saraswati puja|bijoya|dashami|dol purnima|buddha purnima|vesak', ['BD', 'IN']),
  _Hint(r'eid ?ul-? ?fitr|eid ?al-? ?fitr|eid ?ul-? ?adha|eid ?al-? ?adha|ramadan|ramzan|shab-? ?e-? ?barat|shab-? ?e-? ?qadr|ashura|muharram|miladunnabi|eid-? ?e-? ?milad', ['BD', 'IN']),
  _Hint(r'diwali|deepavali|holi\b|janmashtami|krishna janma|ganesh chaturthi|raksha bandhan|rakhi|dussehra|dasara|navratri|makar sankranti|pongal|onam|baisakhi|vaisakhi|gandhi jayanti|republic day \(india\)|ram navami|rama navami|maha ?shivratri|shivaratri|guru nanak|bhai dooj|chhath|ugadi|gudi padwa|karva chauth', ['IN']),
  _Hint(r'chinese new year|lunar new year', ['CN']), _Hint(r'thai pongal|sinhala', ['LK']), _Hint(r'nowruz|persian new year', ['TR']),
];

String holidayIconFor(String? name) {
  final n = (name ?? '').toLowerCase();
  if (n.contains('christmas')) return 'fa-gifts';
  if (n.contains('thanksgiving')) return 'fa-drumstick-bite';
  if (n.contains('independence')) return 'fa-flag';
  if (n.contains('new year')) return 'fa-champagne-glasses';
  if (n.contains('labor') || n.contains('labour') || n.contains('worker')) return 'fa-hammer';
  if (n.contains('memorial') || n.contains('veteran') || n.contains('armistice')) return 'fa-medal';
  if (n.contains('luther')) return 'fa-dove';
  if (n.contains('easter') || n.contains('good friday')) return 'fa-egg';
  if (n.contains('halloween')) return 'fa-ghost';
  if (n.contains('boxing')) return 'fa-box-open';
  return 'fa-landmark';
}

/// Country codes for a special day: feed countries win, then name hints, then kind.
List<String> holidayCountryCodes(SpecialDay? e) {
  if (e == null) return const [];
  final out = <String>[];
  void push(String c) {
    final cc = c.trim().toUpperCase();
    if (RegExp(r'^[A-Z]{2}$').hasMatch(cc) && !out.contains(cc)) out.add(cc);
  }
  if (e.countries != null && e.countries!.isNotEmpty) {
    e.countries!.forEach(push);
    if (out.isNotEmpty) return out;
  }
  for (final h in _kHolidayNameHints) {
    if (RegExp(h.re, caseSensitive: false).hasMatch(e.name)) {
      h.codes.forEach(push);
      if (out.isNotEmpty) return out;
      break;
    }
  }
  if (e.kind == 'bd') return ['BD'];
  if (e.kind == 'festival') return ['IN'];
  return const [];
}

String countryFlagEmoji(String cc) {
  final c = cc.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '';
  return String.fromCharCodes(c.codeUnits.map((u) => 127397 + u));
}

String holidayCountryText(List<String> codes) {
  if (codes.isEmpty) return '';
  final names = codes.take(2).map((c) => kHolidayCountryNames[c] ?? c).toList();
  final extra = codes.length - names.length;
  return names.join(' \u00b7 ') + (extra > 0 ? ' +$extra more' : '');
}

DateTime nthWeekdayOfMonth(int year, int month, int weekdaySun0, int n) {
  // weekdaySun0: JS getDay() convention, 0 = Sunday.
  final first = DateTime.utc(year, month, 1);
  final firstDow = first.weekday % 7; // Dart: Mon=1..Sun=7 -> Sun=0
  return DateTime.utc(year, month, 1 + ((7 + weekdaySun0 - firstDow) % 7) + (n - 1) * 7);
}

class SpecialDaysEngine {
  SpecialDaysEngine({required this.googleCalendarApiKey});

  final String googleCalendarApiKey;
  final Map<String, List<SpecialDay>> _byDate = {};
  final Set<int> _builtYears = {};
  final Set<String> _triedFeeds = {};
  final Set<String> onlineCountries = {};
  int onlineFeeds = 0;
  bool _syncing = false;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  List<SpecialDay> forDate(String dateKey) => _byDate[dateKey] ?? const [];

  List<SpecialDay> sortedForDate(String dateKey) {
    final l = List<SpecialDay>.from(forDate(dateKey));
    l.sort((a, b) => a.rank.compareTo(b.rank));
    return l;
  }

  /// Back-compat helper (Day Picker): all special days on that date, or null.
  String? holidayFor(DateTime d) {
    final all = forDate(fmtDateKey(d));
    return all.isEmpty ? null : all.map((e) => e.label).join(' \u2022 ');
  }

  void addSpecialDay(String? dateKey, String? name, String? icon, String? kind, String? country) {
    if (dateKey == null || dateKey.isEmpty || name == null || name.isEmpty) return;
    final list = _byDate.putIfAbsent(dateKey, () => []);
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    SpecialDay? existing;
    for (final e in list) {
      if (e.slug == slug) {
        existing = e;
        break;
      }
      if (slug.length >= 6 && e.slug.length >= 6 && (e.slug.contains(slug) || slug.contains(e.slug))) {
        existing = e;
        break;
      }
    }
    if (existing != null) {
      if (country != null && existing.countries != null && !existing.countries!.contains(country)) {
        existing.countries!.add(country);
      }
      return;
    }
    list.add(SpecialDay(
      name: name,
      icon: (icon == null || icon.isEmpty) ? 'fa-star' : icon,
      kind: (kind == null || kind.isEmpty) ? 'global' : kind,
      slug: slug,
      countries: country != null ? [country] : null,
    ));
  }

  void buildBuiltin(int year) {
    if (_builtYears.contains(year)) return;
    _builtYears.add(year);
    if (!kSpecialDaysIncludeWorldDays) return;
    for (final row in kSpecialDaysWorld) {
      addSpecialDay('$year-${two(row[0] as int)}-${two(row[1] as int)}', row[2] as String, row[3] as String, 'global', null);
    }
    void add(DateTime d, String name, String icon) => addSpecialDay(fmtDateKey(d), name, icon, 'global', null);
    add(nthWeekdayOfMonth(year, 5, 0, 2), "Mother's Day", 'fa-heart');
    add(nthWeekdayOfMonth(year, 6, 0, 3), "Father's Day", 'fa-user-tie');
    add(nthWeekdayOfMonth(year, 8, 0, 1), 'Friendship Day', 'fa-user-group');
    add(nthWeekdayOfMonth(year, 10, 5, 1), 'World Smile Day', 'fa-face-smile');
    final thanksgiving = nthWeekdayOfMonth(year, 11, 4, 4);
    add(thanksgiving.add(const Duration(days: 1)), 'Black Friday', 'fa-tags');
    add(thanksgiving.add(const Duration(days: 4)), 'Cyber Monday', 'fa-laptop');
  }

  Future<List<Map<String, String>>?> _cached(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is Map && j['rows'] is List && DateTime.now().millisecondsSinceEpoch - ((j['at'] as num?) ?? 0) < kSpecialDaysCacheMs) {
        return (j['rows'] as List).whereType<Map>().map((r) => {'date': '${r['date']}', 'name': '${r['name']}'}).toList();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _store(String cacheKey, List<Map<String, String>> rows) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'rows': rows}));
    } catch (_) {}
  }

  Future<bool> fetchHolidayFeed(int year, String country) async {
    final feedKey = '${year}_$country';
    if (_triedFeeds.contains(feedKey)) return false;
    _triedFeeds.add(feedKey);
    final cacheKey = 'specialDaysFeed_v1_$feedKey';
    var rows = await _cached(cacheKey);
    if (rows == null) {
      final res = await http.get(Uri.parse('https://date.nager.at/api/v3/PublicHolidays/$year/$country')).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw Exception('Holiday feed $feedKey HTTP ${res.statusCode}');
      final data = jsonDecode(res.body);
      rows = (data is List ? data : const [])
          .whereType<Map>()
          .where((h) => h['date'] != null && h['global'] != false)
          .map((h) => {'date': '${h['date']}', 'name': '${h['name'] ?? h['localName'] ?? ''}'})
          .toList();
      await _store(cacheKey, rows);
    }
    for (final h in rows) {
      addSpecialDay(h['date'], h['name'], holidayIconFor(h['name']), 'holiday', country);
    }
    return true;
  }

  Future<bool> fetchGoogleHolidayFeed(int year, String country) async {
    final calendarId = kGoogleHolidayCalendars[country];
    if (calendarId == null || googleCalendarApiKey.isEmpty) return false;
    final feedKey = 'google_${year}_$country';
    if (_triedFeeds.contains(feedKey)) return false;
    _triedFeeds.add(feedKey);
    final cacheKey = 'specialDaysFeed_v1_$feedKey';
    var rows = await _cached(cacheKey);
    if (rows == null) {
      final uri = Uri.https('www.googleapis.com', '/calendar/v3/calendars/$calendarId/events', {
        'key': googleCalendarApiKey,
        'timeMin': '$year-01-01T00:00:00Z',
        'timeMax': '${year + 1}-01-01T00:00:00Z',
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'maxResults': '2500',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw Exception('Google holiday feed $feedKey HTTP ${res.statusCode}');
      final data = jsonDecode(res.body);
      final items = data is Map && data['items'] is List ? data['items'] as List : const [];
      rows = <Map<String, String>>[];
      for (final ev in items.whereType<Map>()) {
        final start = ev['start'];
        String raw = '';
        if (start is Map) {
          raw = (start['date'] ?? '${start['dateTime'] ?? ''}').toString();
          if (raw.length > 10) raw = raw.substring(0, 10);
        }
        if (raw.isNotEmpty) rows.add({'date': raw, 'name': '${ev['summary'] ?? 'Public holiday'}'});
      }
      await _store(cacheKey, rows);
    }
    for (final h in rows) {
      addSpecialDay(h['date'], h['name'], holidayIconFor(h['name']), 'holiday', country);
    }
    return true;
  }

  Future<void> syncOnline(List<int> years) async {
    if (_syncing) return;
    _syncing = true;
    final jobs = <Future<String?>>[];
    for (final year in years) {
      for (final country in kSpecialDaysCountries) {
        jobs.add(fetchHolidayFeed(year, country).then((ok) => ok ? country : null).catchError((_) => null));
      }
      for (final country in kGoogleHolidayCalendars.keys) {
        jobs.add(fetchGoogleHolidayFeed(year, country).then((ok) => ok ? country : null).catchError((_) => null));
      }
    }
    final results = await Future.wait(jobs);
    _syncing = false;
    var merged = 0;
    for (final r in results) {
      if (r != null) {
        merged++;
        onlineCountries.add(r);
      }
    }
    if (merged > 0) {
      onlineFeeds += merged;
      _changes.add(null);
    }
  }

  /// `ensureSpecialDays()` - builtin days for this + 2 years, then online sync.
  void ensure() {
    final y = getDhakaDate(0).year;
    final years = [y, y + 1, y + 2];
    years.forEach(buildBuiltin);
    unawaited(syncOnline(years));
  }
}
