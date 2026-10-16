/// Build profiles - one per Zedge automation customer bundle.
///
/// Every value here mirrors the constants at the top of the web panel
/// (`index.html` -> `configs`, `R2_WORKER_URL`, `GOOGLE_CALENDAR_API_KEY`,
/// `DEFAULT_UPLOAD_WINDOWS`, `VPN_ACCOUNTS`). Select the profile at build time:
///
/// ```
/// flutter build windows --dart-define=BUILD=tarek
/// ```
///
/// The profiles that exist in this copy live in `profile_data.dart`
/// (`kProfiles`); `kDefaultProfileId` is used when no `BUILD` define is given.
/// Each customer bundle ships with only its own profile in that file.
library;

import 'profile_data.dart';
export 'profile_data.dart' show kProfiles, kDefaultProfileId;

class FirebaseAccountConfig {
  const FirebaseAccountConfig({
    required this.key,
    required this.apiKey,
    required this.authDomain,
    required this.databaseURL,
    required this.projectId,
    required this.storageBucket,
    required this.messagingSenderId,
    required this.appId,
  });

  /// `zedge1` .. `zedge4`
  final String key;
  final String apiKey;
  final String authDomain;
  final String databaseURL;
  final String projectId;
  final String storageBucket;
  final String messagingSenderId;
  final String appId;

  /// "Zedge 1" - same label the web header dropdown uses.
  String get label => key.replaceFirst('zedge', 'Zedge ');

  /// "ZEDGE 1" - used on schedule / VPN cards.
  String get upperLabel => key.replaceFirst('zedge', 'ZEDGE ');

  /// "ZEDGE1" - used by VPN scope chips.
  String get compactLabel => key.toUpperCase();

  /// Account index (1-based) parsed from the key.
  int get index => int.tryParse(key.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  bool get isPlaceholder => databaseURL.contains('YOUR-') || apiKey.startsWith('YOUR_');
}

class BuildProfile {
  const BuildProfile({
    required this.id,
    required this.title,
    required this.accounts,
    required this.r2WorkerUrl,
    required this.googleCalendarApiKey,
    required this.defaultUploadWindows,
    this.telegramNote,
  });

  final String id;
  final String title;
  final List<FirebaseAccountConfig> accounts;
  final String r2WorkerUrl;
  final String googleCalendarApiKey;

  /// `DEFAULT_UPLOAD_WINDOWS` - 3 start hours per account (Dhaka).
  final Map<String, List<int>> defaultUploadWindows;
  final String? telegramNote;

  List<String> get accountKeys => accounts.map((a) => a.key).toList(growable: false);

  /// `VPN_ACCOUNTS` == every configured account.
  List<String> get vpnAccounts => accountKeys;

  FirebaseAccountConfig? account(String key) {
    for (final a in accounts) {
      if (a.key == key) return a;
    }
    return null;
  }

  bool hasAccount(String key) => account(key) != null;

  List<int> windowsFor(String key) => List<int>.from(defaultUploadWindows[key] ?? const [10, 15, 20]);

  /// `--dart-define=BUILD=<id>`; defaults to the profile this bundle ships with.
  static const String compileTimeId = String.fromEnvironment('BUILD', defaultValue: kDefaultProfileId);

  static BuildProfile byId(String id) {
    final want = id.trim().toLowerCase();
    for (final p in kProfiles) {
      if (p.id == want) return p;
    }
    for (final p in kProfiles) {
      if (p.id == kDefaultProfileId) return p;
    }
    return kProfiles.first;
  }

  static List<BuildProfile> get all => kProfiles;
}
