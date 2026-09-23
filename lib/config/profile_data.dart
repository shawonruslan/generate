// Build profiles available in this copy of the app.
//
// This bundle ships with its own profile only (values mirror the top of index.html).
// Add more profiles here and pick one with `--dart-define=BUILD=<id>`.

import 'build_config.dart';

/// Profile used when the app is built without `--dart-define=BUILD=...`.
const String kDefaultProfileId = 'shimul';

/// Every profile compiled into this executable.
const List<BuildProfile> kProfiles = [
  kProfileShimul,
];

// ---------------------------------------------------------------------------
// shimul (shimul-vpn.zip) - 4 accounts
// ---------------------------------------------------------------------------
const BuildProfile kProfileShimul = BuildProfile(
  id: 'shimul',
  title: 'Shimul (4 accounts)',
  r2WorkerUrl: 'https://shimul.shawonhawladar.workers.dev',
  googleCalendarApiKey: '',
  defaultUploadWindows: {
    'zedge1': [6, 12, 18],
    'zedge2': [7, 13, 19],
    'zedge3': [8, 14, 22],
    'zedge4': [9, 15, 23],
  },
  accounts: [
    FirebaseAccountConfig(
      key: 'zedge1',
      apiKey: 'AIzaSyBnNAwFptU9GG6M8iTzIV1ulGVxnCZTzxw',
      authDomain: 'shimul-zedge1.firebaseapp.com',
      databaseURL: 'https://shimul-zedge1-default-rtdb.asia-southeast1.firebasedatabase.app',
      projectId: 'shimul-zedge1',
      storageBucket: 'shimul-zedge1.firebasestorage.app',
      messagingSenderId: '451307537743',
      appId: '1:451307537743:web:37e3ad4f85c93dc4adf13a',
    ),
    FirebaseAccountConfig(
      key: 'zedge2',
      apiKey: 'AIzaSyDNiYWqMdsoFJoHJZ-hAhfXigOl9nh778s',
      authDomain: 'shimul-zedge-2.firebaseapp.com',
      databaseURL: 'https://shimul-zedge-2-default-rtdb.asia-southeast1.firebasedatabase.app',
      projectId: 'shimul-zedge-2',
      storageBucket: 'shimul-zedge-2.firebasestorage.app',
      messagingSenderId: '884644788118',
      appId: '1:884644788118:web:377568ac042d5b7ba40fb7',
    ),
    FirebaseAccountConfig(
      key: 'zedge3',
      apiKey: 'AIzaSyDqo0RkYd5-xdQ704I1By2FbBoNwICJecI',
      authDomain: 'shimul-zedge3.firebaseapp.com',
      databaseURL: 'https://shimul-zedge3-default-rtdb.firebaseio.com',
      projectId: 'shimul-zedge3',
      storageBucket: 'shimul-zedge3.firebasestorage.app',
      messagingSenderId: '370280739654',
      appId: '1:370280739654:web:177836e8d4060f62f1eb47',
    ),
    FirebaseAccountConfig(
      key: 'zedge4',
      apiKey: 'AIzaSyAhs54UhZtrYDz50oav1NefACpaItBPvJc',
      authDomain: 'shimul-zedge-4.firebaseapp.com',
      databaseURL: 'https://shimul-zedge-4-default-rtdb.firebaseio.com',
      projectId: 'shimul-zedge-4',
      storageBucket: 'shimul-zedge-4.firebasestorage.app',
      messagingSenderId: '352284549595',
      appId: '1:352284549595:web:ecce9eaf1d061b96e747fe',
    ),
  ],
);
