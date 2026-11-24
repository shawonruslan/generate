/// Content-type constants shared with the web panel (`index.html`),
/// the upload bots (`zedgeN.yml`) and the Android app (`core/Core.kt`).
library;

/// Rotation order the bot uses for "one content type per day".
const List<String> kTypeCycle = [
  'AUDIO',
  'WALLPAPER',
  'WALLPAPER_24H',
  'WALLPAPER_DUAL',
  'WALLPAPER_BATTERY',
  'LIVE_WALLPAPER',
  'CHARGING_ANIMATION',
];

const List<String> kSlots24h = ['morning', 'afternoon', 'evening', 'night'];

class SetTypeMeta {
  const SetTypeMeta({
    required this.type,
    required this.slots,
    required this.label,
    required this.short,
    required this.icon,
    required this.prefix,
  });
  final String type;
  final List<String> slots;
  final String label;
  final String short;
  final String icon;
  final String prefix;
}

const Map<String, SetTypeMeta> kSetTypeMeta = {
  'WALLPAPER_24H': SetTypeMeta(
    type: 'WALLPAPER_24H',
    slots: kSlots24h,
    label: '24H Wallpaper Set',
    short: '24H',
    icon: 'fa-clock',
    prefix: '24h',
  ),
  'WALLPAPER_DUAL': SetTypeMeta(
    type: 'WALLPAPER_DUAL',
    slots: ['lock', 'home'],
    label: 'Dual Wallpaper Set',
    short: 'DUAL',
    icon: 'fa-mobile-alt',
    prefix: 'dual',
  ),
  'WALLPAPER_BATTERY': SetTypeMeta(
    type: 'WALLPAPER_BATTERY',
    slots: ['critical', 'low', 'mid', 'high', 'full', 'charging'],
    label: 'Battery Wallpaper Set',
    short: 'BATTERY',
    icon: 'fa-battery-three-quarters',
    prefix: 'battery',
  ),
};

class VideoTypeMeta {
  const VideoTypeMeta({required this.type, required this.label, required this.short, required this.icon, required this.prefix});
  final String type;
  final String label;
  final String short;
  final String icon;
  final String prefix;
}

const Map<String, VideoTypeMeta> kVideoTypeMeta = {
  'LIVE_WALLPAPER': VideoTypeMeta(type: 'LIVE_WALLPAPER', label: 'Live Wallpaper', short: 'LIVE', icon: 'fa-film', prefix: 'live'),
  'CHARGING_ANIMATION': VideoTypeMeta(type: 'CHARGING_ANIMATION', label: 'Charging Animation', short: 'CHARGE', icon: 'fa-bolt', prefix: 'charging'),
};

class DayTypeUi {
  const DayTypeUi({required this.cls, required this.title, required this.icon, required this.label, required this.short});
  final String cls;
  final String title;
  final String icon;
  final String label;
  final String short;
}

const Map<String, DayTypeUi> kDayTypeUi = {
  'AUDIO': DayTypeUi(cls: 'audio', title: 'Audio Day', icon: 'fa-music', label: 'Ringtone', short: 'Ringtone day'),
  'WALLPAPER': DayTypeUi(cls: 'wall', title: 'Wallpaper Day', icon: 'fa-images', label: 'Wallpaper', short: 'Wallpaper day'),
  'WALLPAPER_24H': DayTypeUi(cls: 'day24h', title: '24H Wallpaper Day', icon: 'fa-clock', label: '24H Set', short: '24H set day'),
  'WALLPAPER_DUAL': DayTypeUi(cls: 'day24h', title: 'Dual Wallpaper Day', icon: 'fa-mobile-alt', label: 'Dual Set', short: 'Dual set day'),
  'WALLPAPER_BATTERY': DayTypeUi(cls: 'day24h', title: 'Battery Wallpaper Day', icon: 'fa-battery-three-quarters', label: 'Battery', short: 'Battery set day'),
  'LIVE_WALLPAPER': DayTypeUi(cls: 'day24h', title: 'Live Wallpaper Day', icon: 'fa-film', label: 'Live Video', short: 'Live wallpaper day'),
  'CHARGING_ANIMATION': DayTypeUi(cls: 'day24h', title: 'Charging Animation Day', icon: 'fa-bolt', label: 'Charging', short: 'Charging animation day'),
};

/// Queue-type filter labels (`QUEUE_TYPE_LABELS`).
const Map<String, String> kQueueTypeLabels = {
  'RINGTONE': 'Ringtones',
  'WALLPAPER': 'Wallpapers',
  'WALLPAPER_24H': '24H sets',
  'WALLPAPER_DUAL': 'Dual sets',
  'WALLPAPER_BATTERY': 'Battery sets',
  'LIVE_WALLPAPER': 'Live wallpapers',
  'CHARGING_ANIMATION': 'Charging animations',
};

/// v25 Mix Mode content types (`VARIETY_TYPES`).
const List<MapEntry<String, String>> kVarietyTypes = [
  MapEntry('RINGTONE', 'Ringtone'),
  MapEntry('WALLPAPER', 'Wallpaper'),
  MapEntry('WALLPAPER_24H', '24H set'),
  MapEntry('WALLPAPER_DUAL', 'Dual set'),
  MapEntry('WALLPAPER_BATTERY', 'Battery set'),
  MapEntry('LIVE_WALLPAPER', 'Live wallpaper'),
  MapEntry('CHARGING_ANIMATION', 'Charging animation'),
];
final List<String> kVarietyAll = kVarietyTypes.map((e) => e.key).toList(growable: false);

String varietyLabel(String t) {
  for (final e in kVarietyTypes) {
    if (e.key == t) return e.value;
  }
  return t;
}

/// Run schedule constants (`RUN_WINDOW_HOURS`, `RUN_SLOT_MIN`, ...).
const int kRunWindowHours = 3;
const int kRunSlotMin = 30;
const int kRunMaxDelayMin = 14;
const int kRunsPerDay = 3;

/// Planner: a content type needs at least this many queued files before the
/// rotation gives it a day (`MIN_STOCK_FOR_DAY`).
const int kMinStockForDay = 3;

/// Upload / calendar paging
const int kUploadPerPage = 12;
const int kScheduleDaysPerPage = 7;

/// Image output size for every wallpaper/set slot / video cover.
const int kWallpaperWidth = 1620;
const int kWallpaperHeight = 2880;

/// Video limits
const int kVideoMaxBytes = 50 * 1024 * 1024;
const int kVideoMinWidth = 1080;
const int kVideoMinHeight = 1920;
const double kVideoMaxSeconds = 30;

/// Zedge categories (`Z_RT_CATS`, `Z_IMG_CATS`) used to validate AI metadata JSON.
const List<String> kZedgeRingtoneCategories = [
  'LATIN', 'MESSAGE_TONES', 'OTHER', 'POP', 'RNB_SOUL', 'REGGAE', 'RELIGIOUS', 'ROCK', 'SAYINGS', 'ALTERNATIVE',
  'ANIMALS', 'BLUES', 'BOLLYWOOD', 'CHILDREN', 'CLASSICAL', 'SOUND_EFFECTS', 'WORLD', 'COMEDY', 'CONTACT_RINGTONES',
  'COUNTRY', 'DANCE', 'ELECTRONICA', 'GAMES', 'HIP_HOP', 'HOLIDAYS', 'JAZZ'
];
const List<String> kZedgeImageCategories = [
  'ANIMALS', 'ANIME', 'CARS_N_VEHICLES', 'COMICS', 'DESIGNS', 'DRAWINGS', 'ENTERTAINMENT', 'FUNNY', 'GAMES',
  'HOLIDAYS', 'LOVE', 'MUSIC', 'NATURE', 'OTHER', 'PATTERNS', 'PEOPLE', 'SAYINGS', 'SPACE', 'SPIRITUAL', 'SPORTS',
  'TECHNOLOGY'
];

/// `Z_META_POLICY_RE` - titles/descriptions containing these are rejected.
final RegExp kMetaPolicyRe = RegExp(
  r'(https?://|www\.|\.com\b|\.net\b|follow (me|us)|subscribe|download (now|free|link)|telegram|whatsapp|instagram|tiktok|youtube|discount|promo code|porn|xxx|nude|naked|\bsex\b|nsfw|erotic|hentai|kill yourself|terrorist|nazi)',
  caseSensitive: false,
);

const String kMetaSchemaVersion = 'zedge-meta-v1';
