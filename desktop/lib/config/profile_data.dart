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
// mahbub - 1 account
// ---------------------------------------------------------------------------
const BuildProfile kProfileMahbub = BuildProfile(
  id: 'mahbub',
  title: 'Mahbub (1 account)',
  r2WorkerUrl: 'https://raspy-term-bb6e.salakhan101xxx.workers.dev',
  googleCalendarApiKey: 'AIzaSyAnNeYfEYF6Z41r-QBo2q8eWKaP-CBPlnc',
  defaultUploadWindows: {
    'zedge1': [4, 10, 16],
  },
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
