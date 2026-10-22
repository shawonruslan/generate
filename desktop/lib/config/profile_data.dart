// Build profiles available in this copy of the app.
//
// This bundle ships with its own profile only (values mirror the top of index.html).
// Add more profiles here and pick one with `--dart-define=BUILD=<id>`.

import 'build_config.dart';

/// Profile used when the app is built without `--dart-define=BUILD=...`.
const String kDefaultProfileId = 'mahbub';

/// Every profile compiled into this executable.
const List<BuildProfile> kProfiles = [
  kProfileMahbub,
];

// ---------------------------------------------------------------------------
// mahbub (mahbub-earn.zip) - 1 account
// ---------------------------------------------------------------------------
const BuildProfile kProfileMahbub = BuildProfile(
  id: 'mahbub',
  title: 'Mahbub (1 account)',
  r2WorkerUrl: 'https://raspy-term-bb6e.salakhan101xxx.workers.dev',
  googleCalendarApiKey: '',
  defaultUploadWindows: {
    'zedge1': [10, 15, 20],
  },
  telegramNote: 'Telegram: set repository secrets TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID (greeting "হ্যালো মাহবুব ভাই").',
  accounts: [
    FirebaseAccountConfig(
      key: 'zedge1',
      apiKey: 'AIzaSyDfKl4jfBKbI-acSuZElXQ8eRHpHJQvm04',
      authDomain: 'zedge1-2624f.firebaseapp.com',
      databaseURL: 'https://zedge1-2624f-default-rtdb.firebaseio.com',
      projectId: 'zedge1-2624f',
      storageBucket: 'zedge1-2624f.firebasestorage.app',
      messagingSenderId: '676567658794',
      appId: '1:676567658794:web:eccbef1e42c9f27cd3ee53',
    ),
  ],
);
