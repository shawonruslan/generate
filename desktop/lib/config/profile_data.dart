// Build profiles available in this copy of the app.
//
// This bundle ships with its own profile only (values mirror the top of index.html).
// Add more profiles here and pick one with `--dart-define=BUILD=<id>`.

import 'build_config.dart';

/// Profile used when the app is built without `--dart-define=BUILD=...`.
const String kDefaultProfileId = 'shawon';

/// Every profile compiled into this executable.
const List<BuildProfile> kProfiles = [
  kProfileShawon,
];

// ---------------------------------------------------------------------------
// shawon (shawon-vpn.zip) - 4 accounts
// ---------------------------------------------------------------------------
const BuildProfile kProfileShawon = BuildProfile(
  id: 'shawon',
  title: 'Shawon (4 accounts)',
  r2WorkerUrl: 'https://frosty-pine-2f7dzedge-r2-gateway.holaexplainer.workers.dev',
  googleCalendarApiKey: 'AIzaSyAnNeYfEYF6Z41r-QBo2q8eWKaP-CBPlnc',
  defaultUploadWindows: {
    'zedge1': [4, 10, 16],
    'zedge2': [5, 11, 17],
    'zedge3': [10, 16, 20],
    'zedge4': [11, 17, 21],
  },
  accounts: [
    FirebaseAccountConfig(
      key: 'zedge1',
      apiKey: 'AIzaSyDwM-L754rnznedU6UIxsLmB4eyYFp7NnA',
      authDomain: 'zedgeautomation.firebaseapp.com',
      databaseURL: 'https://zedgeautomation-default-rtdb.firebaseio.com',
      projectId: 'zedgeautomation',
      storageBucket: 'zedgeautomation.firebasestorage.app',
      messagingSenderId: '1061461206697',
      appId: '1:1061461206697:web:2e0b1e1ebb9b58ea952bb8',
    ),
    FirebaseAccountConfig(
      key: 'zedge2',
      apiKey: 'AIzaSyB0rSfo4u9mmlnl2--svGLCGh-Ta3sq1LE',
      authDomain: 'zedge-automation-2.firebaseapp.com',
      databaseURL: 'https://zedge-automation-2-default-rtdb.asia-southeast1.firebasedatabase.app',
      projectId: 'zedge-automation-2',
      storageBucket: 'zedge-automation-2.firebasestorage.app',
      messagingSenderId: '767724772077',
      appId: '1:767724772077:web:27131e41eb0d27209b8ae4',
    ),
    FirebaseAccountConfig(
      key: 'zedge3',
      apiKey: 'AIzaSyC5cD9PrW7lOIrXvhlYJvNRu-eUBreGV0U',
      authDomain: 'zedge-automation-3.firebaseapp.com',
      databaseURL: 'https://zedge-automation-3-default-rtdb.asia-southeast1.firebasedatabase.app',
      projectId: 'zedge-automation-3',
      storageBucket: 'zedge-automation-3.firebasestorage.app',
      messagingSenderId: '111041866150',
      appId: '1:111041866150:web:c20550188e06579435c767',
    ),
    FirebaseAccountConfig(
      key: 'zedge4',
      apiKey: 'AIzaSyDCYMrTkFei1ZfSKbFN2tKZijaEN1nn-kk',
      authDomain: 'zedge-4.firebaseapp.com',
      databaseURL: 'https://zedge-4-default-rtdb.asia-southeast1.firebasedatabase.app',
      projectId: 'zedge-4',
      storageBucket: 'zedge-4.firebasestorage.app',
      messagingSenderId: '269891256214',
      appId: '1:269891256214:web:3c58fdbdd2a1d8d1e167b7',
    ),
  ],
);
