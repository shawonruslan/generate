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
// mahbub (mahbub-earn.zip) - 3 accounts (zedge2/zedge3 added v40.9)
// ---------------------------------------------------------------------------
const BuildProfile kProfileMahbub = BuildProfile(
  id: 'mahbub',
  title: 'Mahbub (3 accounts)',
  r2WorkerUrl: 'https://raspy-term-bb6e.salakhan101xxx.workers.dev',
  googleCalendarApiKey: '',
  defaultUploadWindows: {
    'zedge1': [10, 15, 20],
    'zedge2': [11, 16, 21],
    'zedge3': [5, 11, 17],
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
    FirebaseAccountConfig(
      key: 'zedge2',
      apiKey: 'AIzaSyCMPl3fcVJOavKRCQzW1WX7lK2PYYu0oWE',
      authDomain: 'zedge-2.firebaseapp.com',
      databaseURL: 'https://zedge-2-default-rtdb.firebaseio.com',
      projectId: 'zedge-2',
      storageBucket: 'zedge-2.firebasestorage.app',
      messagingSenderId: '107945298054',
      appId: '1:107945298054:web:6ea11289bca4cb91f72907',
    ),
    FirebaseAccountConfig(
      key: 'zedge3',
      apiKey: 'AIzaSyC6_OC_BWwb3-5YRJyrYBIRfe5R7MWSEoM',
      authDomain: 'zedge-3.firebaseapp.com',
      databaseURL: 'https://zedge-3-default-rtdb.firebaseio.com',
      projectId: 'zedge-3',
      storageBucket: 'zedge-3.firebasestorage.app',
      messagingSenderId: '10878299364',
      appId: '1:10878299364:web:b2161a7aaa3d60e21550f1',
    ),
  ],
);
