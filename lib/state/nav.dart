import 'package:flutter/foundation.dart';

/// Tabs of the panel (hash routes of the web app).
enum AppTab { home, upload, schedule, pins, distribute, github, vpn, notifications }

const Map<AppTab, String> kTabLabel = {
  AppTab.home: 'Dashboard',
  AppTab.upload: 'Upload Queue',
  AppTab.schedule: 'Schedule Calendar',
  AppTab.pins: 'Pin Manager',
  AppTab.distribute: 'Distribute Content',
  AppTab.github: 'GitHub Control',
  AppTab.vpn: 'VPN',
  AppTab.notifications: 'Notifications',
};

const Map<AppTab, String> kTabNav = {
  AppTab.home: 'Home',
  AppTab.upload: 'Upload Queue',
  AppTab.schedule: 'Schedule Calendar',
  AppTab.pins: 'Pin Manager',
  AppTab.distribute: 'Distribute Content',
  AppTab.github: 'GitHub Control',
  AppTab.vpn: 'VPN',
  AppTab.notifications: 'Notifications',
};

const Map<AppTab, String> kTabIcon = {
  AppTab.home: 'fa-house',
  AppTab.upload: 'fa-cloud-upload-alt',
  AppTab.schedule: 'fa-calendar-alt',
  AppTab.pins: 'fa-thumbtack',
  AppTab.distribute: 'fa-share-nodes',
  AppTab.github: 'fa-code-branch',
  AppTab.vpn: 'fa-shield-halved',
  AppTab.notifications: 'fa-bell',
};

/// Navigation state (current tab + "open item" requests coming from other screens).
class NavState extends ChangeNotifier {
  AppTab tab = AppTab.home;
  bool drawerOpen = false;

  /// Set by other screens to open an asset in the details page.
  String? pendingItemId;

  void go(AppTab t) {
    tab = t;
    drawerOpen = false;
    notifyListeners();
  }

  void openItem(String id) {
    pendingItemId = id;
    notifyListeners();
  }

  void toggleDrawer([bool? v]) {
    drawerOpen = v ?? !drawerOpen;
    notifyListeners();
  }
}
