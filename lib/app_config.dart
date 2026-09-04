/// Static backend configuration shared by every screen.
///
/// Nothing here talks to a WebView or an embedded browser: the app speaks to
/// Firebase Realtime Database over its REST + Server-Sent-Events API, which
/// behaves identically on Windows and Android.
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

/// Cloudflare Worker that proxies uploads into the R2 bucket.
const String kR2WorkerUrl =
    'https://frosty-pine-2f7dzedge-r2-gateway.holaexplainer.workers.dev';

const String kQueuePath = 'wallpaperQueue';
const String kUploadStatePath = 'uploadState';
const String kSettingsPath = 'dashboardSettings';

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

/// India + Bangladesh come from the Google Calendar holiday feeds, because the
/// free Nager feed has no Indian data and an incomplete Bangladeshi one.
const Map<String, String> kGoogleHolidayCalendars = <String, String>{
  'IN': 'en.indian.official#holiday@group.v.calendar.google.com',
  'BD': 'en.bd.official#holiday@group.v.calendar.google.com',
};

/// Everything else uses the free, key-less Nager feed.
const List<String> kNagerCountries = <String>[
  'US', 'GB', 'CA', 'AU', 'DE', 'FR', 'IT', 'ES', 'NL', 'BE',
  'AT', 'CH', 'SE', 'NO', 'DK', 'FI', 'PL', 'PT', 'IE', 'GR',
  'CZ', 'RO', 'HU', 'BR', 'MX', 'AR', 'CL', 'CO', 'JP', 'KR',
  'CN', 'HK', 'SG', 'VN', 'ID', 'KZ',
];

const Map<String, String> kCountryNames = <String, String>{
  'IN': 'India', 'BD': 'Bangladesh', 'US': 'United States',
  'GB': 'United Kingdom', 'CA': 'Canada', 'AU': 'Australia',
  'DE': 'Germany', 'FR': 'France', 'IT': 'Italy', 'ES': 'Spain',
  'NL': 'Netherlands', 'BE': 'Belgium', 'AT': 'Austria',
  'CH': 'Switzerland', 'SE': 'Sweden', 'NO': 'Norway',
  'DK': 'Denmark', 'FI': 'Finland', 'PL': 'Poland',
  'PT': 'Portugal', 'IE': 'Ireland', 'GR': 'Greece',
  'CZ': 'Czechia', 'RO': 'Romania', 'HU': 'Hungary',
  'BR': 'Brazil', 'MX': 'Mexico', 'AR': 'Argentina',
  'CL': 'Chile', 'CO': 'Colombia', 'JP': 'Japan',
  'KR': 'South Korea', 'CN': 'China', 'HK': 'Hong Kong',
  'SG': 'Singapore', 'VN': 'Vietnam', 'ID': 'Indonesia',
  'KZ': 'Kazakhstan',
};

/// Injected at build time by the workflow:
/// `--dart-define=GOOGLE_CALENDAR_API_KEY=...`
/// If it is empty the user can paste a key in Settings instead.
const String kBuildCalendarApiKey =
    String.fromEnvironment('GOOGLE_CALENDAR_API_KEY');
