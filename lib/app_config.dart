/// Static backend configuration shared by every screen.
///
/// Mirrors the constants of the web dashboard (index.html) one-to-one so the
/// native apps and the browser version stay interchangeable.
library;

class ZedgeAccount {
  const ZedgeAccount({
    required this.id,
    required this.label,
    required this.projectId,
    required this.databaseUrl,
  });

  final String id;
  final String label;
  final String projectId;
  final String databaseUrl;
}

const List<ZedgeAccount> kAccounts = <ZedgeAccount>[
  ZedgeAccount(
    id: 'zedge1',
    label: 'Zedge 1',
    projectId: 'zedgeautomation',
    databaseUrl: 'https://zedgeautomation-default-rtdb.firebaseio.com',
  ),
  ZedgeAccount(
    id: 'zedge2',
    label: 'Zedge 2',
    projectId: 'zedge-automation-2',
    databaseUrl:
        'https://zedge-automation-2-default-rtdb.asia-southeast1.firebasedatabase.app',
  ),
  ZedgeAccount(
    id: 'zedge3',
    label: 'Zedge 3',
    projectId: 'zedge-automation-3',
    databaseUrl:
        'https://zedge-automation-3-default-rtdb.asia-southeast1.firebasedatabase.app',
  ),
];

ZedgeAccount accountById(String id) => kAccounts.firstWhere(
      (ZedgeAccount a) => a.id == id,
      orElse: () => kAccounts.first,
    );

/// Cloudflare Worker that proxies uploads into the R2 bucket.
const String kR2WorkerUrl =
    'https://frosty-pine-2f7dzedge-r2-gateway.holaexplainer.workers.dev';

const String kQueuePath = 'wallpaperQueue';
const String kUploadStatePath = 'uploadState';
const String kSettingsPath = 'dashboardSettings';
const String kGhSettingsPath = 'dashboardSettings/ghPanel';

/// Uploads the bot performs per day.
const int kUploadsPerDay = 3;
const int kQueuePerPage = 12;
const int kScheduleDaysPerPage = 28;
const int kImageTargetWidth = 1620;
const int kImageTargetHeight = 2880;
const int kVideoMaxBytes = 50 * 1024 * 1024;

/// Dhaka is UTC+6 all year.
const Duration kDhakaOffset = Duration(hours: 6);

/// Daily rotation used by the uploader bot.
const List<String> kTypeCycle = <String>[
  'AUDIO',
  'WALLPAPER',
  'WALLPAPER_24H',
  'WALLPAPER_DUAL',
  'WALLPAPER_BATTERY',
  'LIVE_WALLPAPER',
  'CHARGING_ANIMATION',
];

/// Slot layout for every multi-image set type.
const Map<String, List<String>> kSetSlots = <String, List<String>>{
  'WALLPAPER_24H': <String>['morning', 'afternoon', 'evening', 'night'],
  'WALLPAPER_DUAL': <String>['lock', 'home'],
  'WALLPAPER_BATTERY': <String>[
    'critical',
    'low',
    'mid',
    'high',
    'full',
    'charging',
  ],
};

/// Short badge text and R2 folder prefix, identical to SET_TYPE_META /
/// VIDEO_TYPE_META in the web dashboard.
class TypeMeta {
  const TypeMeta({
    required this.label,
    required this.short,
    required this.prefix,
    required this.dayLabel,
  });

  final String label;
  final String short;
  final String prefix;
  final String dayLabel;
}

const Map<String, TypeMeta> kTypeMeta = <String, TypeMeta>{
  'AUDIO': TypeMeta(
      label: 'Ringtone', short: 'AUDIO', prefix: '', dayLabel: 'Ringtone'),
  'RINGTONE': TypeMeta(
      label: 'Ringtone', short: 'AUDIO', prefix: '', dayLabel: 'Ringtone'),
  'WALLPAPER': TypeMeta(
      label: 'Wallpaper', short: 'WALL', prefix: '', dayLabel: 'Wallpaper'),
  'WALLPAPER_24H': TypeMeta(
      label: '24H Wallpaper Set',
      short: '24H',
      prefix: '24h',
      dayLabel: '24H Set'),
  'WALLPAPER_DUAL': TypeMeta(
      label: 'Dual Wallpaper Set',
      short: 'DUAL',
      prefix: 'dual',
      dayLabel: 'Dual Set'),
  'WALLPAPER_BATTERY': TypeMeta(
      label: 'Battery Wallpaper Set',
      short: 'BATTERY',
      prefix: 'battery',
      dayLabel: 'Battery'),
  'LIVE_WALLPAPER': TypeMeta(
      label: 'Live Wallpaper',
      short: 'LIVE',
      prefix: 'live',
      dayLabel: 'Live Video'),
  'CHARGING_ANIMATION': TypeMeta(
      label: 'Charging Animation',
      short: 'CHARGE',
      prefix: 'charging',
      dayLabel: 'Charging'),
};

TypeMeta metaFor(String type) =>
    kTypeMeta[type] ??
    TypeMeta(label: type, short: type, prefix: '', dayLabel: type);

const Map<String, String> kTypeLabels = <String, String>{
  'AUDIO': 'Ringtone',
  'RINGTONE': 'Ringtone',
  'WALLPAPER': 'Wallpaper',
  'WALLPAPER_24H': '24H Wallpaper Set',
  'WALLPAPER_DUAL': 'Dual Wallpaper Set',
  'WALLPAPER_BATTERY': 'Battery Wallpaper Set',
  'LIVE_WALLPAPER': 'Live Wallpaper',
  'CHARGING_ANIMATION': 'Charging Animation',
};

bool isSetType(String type) => kSetSlots.containsKey(type);
bool isVideoType(String type) =>
    type == 'LIVE_WALLPAPER' || type == 'CHARGING_ANIMATION';
bool isAudioType(String type) => type == 'AUDIO' || type == 'RINGTONE';

/// Normalises the type stored on a queue row to the bucket used by the
/// schedule (RINGTONE rows live in the AUDIO bucket).
String scheduleBucket(String contentType) =>
    contentType == 'RINGTONE' ? 'AUDIO' : contentType;

/// Regions used by the holiday engine (Nager.Date feed, no key needed).
const Map<String, List<String>> kNagerRegions = <String, List<String>>{
  'EUROPE': <String>[
    'GB', 'IE', 'DE', 'FR', 'ES', 'PT', 'IT', 'NL', 'BE', 'CH',
    'AT', 'SE', 'NO', 'DK', 'FI', 'PL', 'CZ', 'GR', 'RU', 'UA',
  ],
  'AMERICAS': <String>['US', 'CA', 'MX', 'BR', 'AR', 'CL', 'CO', 'PE'],
  'ASIA': <String>['JP', 'KR', 'CN', 'HK', 'SG', 'VN', 'ID', 'KZ'],
};

List<String> get kNagerCountries => <String>[
      for (final List<String> list in kNagerRegions.values) ...list,
    ];

/// India + Bangladesh come from the Google Calendar holiday feeds.
const Map<String, String> kGoogleHolidayCalendars = <String, String>{
  'IN': 'en.indian.official#holiday@group.v.calendar.google.com',
  'BD': 'en.bd.official#holiday@group.v.calendar.google.com',
};

const Map<String, String> kCountryNames = <String, String>{
  'IN': 'India', 'BD': 'Bangladesh', 'US': 'United States',
  'GB': 'United Kingdom', 'CA': 'Canada', 'AU': 'Australia',
  'DE': 'Germany', 'FR': 'France', 'IT': 'Italy', 'ES': 'Spain',
  'NL': 'Netherlands', 'BE': 'Belgium', 'AT': 'Austria',
  'CH': 'Switzerland', 'SE': 'Sweden', 'NO': 'Norway',
  'DK': 'Denmark', 'FI': 'Finland', 'PL': 'Poland',
  'PT': 'Portugal', 'IE': 'Ireland', 'GR': 'Greece',
  'CZ': 'Czechia', 'RU': 'Russia', 'UA': 'Ukraine',
  'MX': 'Mexico', 'BR': 'Brazil', 'AR': 'Argentina',
  'CL': 'Chile', 'CO': 'Colombia', 'PE': 'Peru', 'JP': 'Japan',
  'KR': 'South Korea', 'CN': 'China', 'HK': 'Hong Kong',
  'SG': 'Singapore', 'VN': 'Vietnam', 'ID': 'Indonesia',
  'KZ': 'Kazakhstan', 'WW': 'Worldwide',
};

/// Fixed-date world observances (month, day, name) - built-in fallback that
/// always renders even when the online feeds are unreachable.
const List<List<Object>> kWorldDaysFixed = <List<Object>>[
  <Object>[1, 1, 'New Year\'s Day'],
  <Object>[2, 9, 'Pizza Day'],
  <Object>[2, 14, 'Valentine\'s Day'],
  <Object>[3, 8, 'Women\'s Day'],
  <Object>[3, 20, 'Day of Happiness'],
  <Object>[4, 1, 'April Fools\' Day'],
  <Object>[4, 15, 'World Art Day'],
  <Object>[4, 22, 'Earth Day'],
  <Object>[5, 4, 'Star Wars Day'],
  <Object>[5, 21, 'International Tea Day'],
  <Object>[6, 5, 'Environment Day'],
  <Object>[6, 8, 'World Oceans Day'],
  <Object>[6, 21, 'World Music Day'],
  <Object>[7, 7, 'World Chocolate Day'],
  <Object>[7, 17, 'World Emoji Day'],
  <Object>[7, 30, 'Friendship Day'],
  <Object>[8, 8, 'International Cat Day'],
  <Object>[8, 19, 'World Photography Day'],
  <Object>[8, 26, 'National Dog Day'],
  <Object>[9, 21, 'Peace Day'],
  <Object>[9, 22, 'First Day of Autumn'],
  <Object>[10, 1, 'International Coffee Day'],
  <Object>[10, 4, 'World Animal Day'],
  <Object>[10, 5, 'World Teachers\' Day'],
  <Object>[10, 10, 'Mental Health Day'],
  <Object>[10, 31, 'Halloween'],
  <Object>[11, 13, 'World Kindness Day'],
  <Object>[11, 14, 'Children\'s Day'],
  <Object>[11, 19, 'International Men\'s Day'],
  <Object>[12, 21, 'First Day of Winter'],
  <Object>[12, 24, 'Christmas Eve'],
  <Object>[12, 25, 'Christmas Day'],
  <Object>[12, 31, 'New Year\'s Eve'],
];

/// Injected at build time by the workflow:
/// `--dart-define=GOOGLE_CALENDAR_API_KEY=...`
/// If it is empty the user can paste a key in Settings instead.
const String kBuildCalendarApiKey =
    String.fromEnvironment('GOOGLE_CALENDAR_API_KEY');

/// Key shipped in the web dashboard - used as last fallback.
const String kDefaultCalendarApiKey = 'AIzaSyAnNeYfEYF6Z41r-QBo2q8eWKaP-CBPlnc';

/// GitHub REST API (Control panel).
const String kGithubApi = 'https://api.github.com';
const String kGeneratorWorkflow = 'generator.yml';
