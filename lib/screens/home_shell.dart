import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/account_switcher.dart';
import '../widgets/upload_panel.dart';
import 'calendar_tab.dart';
import 'dashboard_tab.dart';
import 'queue_tab.dart';
import 'settings_tab.dart';

/// App frame: gold header + navigation rail (desktop) or bottom bar (mobile).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<_NavEntry> _entries = <_NavEntry>[
    _NavEntry('Dashboard', Icons.space_dashboard_rounded),
    _NavEntry('Queue', Icons.layers_rounded),
    _NavEntry('Schedule', Icons.calendar_month_rounded),
    _NavEntry('Settings', Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final bool wide = MediaQuery.sizeOf(context).width >= 900;

    final List<Widget> pages = const <Widget>[
      DashboardTab(),
      QueueTab(),
      CalendarTab(),
      SettingsTab(),
    ];

    return Scaffold(
      body: Column(
        children: <Widget>[
          _Header(wide: wide),
          if (state.error != null)
            Container(
              width: double.infinity,
              color: Zc.danger.withValues(alpha: 0.10),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.wifi_off_rounded, size: 15, color: Zc.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Realtime Database unreachable - showing the last known '
                      'data. (${state.error})',
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Zc.danger,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => state.connect(state.account),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: wide
                ? Row(
                    children: <Widget>[
                      NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: (int value) =>
                            setState(() => _index = value),
                        labelType: NavigationRailLabelType.all,
                        backgroundColor: Zc.panel,
                        indicatorColor: Zc.gold.withValues(alpha: 0.35),
                        destinations: _entries
                            .map(
                              (_NavEntry entry) => NavigationRailDestination(
                                icon: Icon(entry.icon),
                                label: Text(entry.label),
                              ),
                            )
                            .toList(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: IndexedStack(index: _index, children: pages),
                      ),
                    ],
                  )
                : IndexedStack(index: _index, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (int value) =>
                  setState(() => _index = value),
              destinations: _entries
                  .map(
                    (_NavEntry entry) => NavigationDestination(
                      icon: Icon(entry.icon),
                      label: entry.label,
                    ),
                  )
                  .toList(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showUploadSheet(context),
        backgroundColor: Zc.goldDeep,
        foregroundColor: Zc.ink,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'New upload',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _NavEntry {
  const _NavEntry(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _Header extends StatelessWidget {
  const _Header({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();

    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 22 : 14, 16, wide ? 22 : 14, 16),
      decoration: const BoxDecoration(gradient: Zc.headerGradient),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: Zc.goldGradient,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Center(
              child: Text(
                'Z',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  color: Zc.ink,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (wide)
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Zedge Studio',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Upload automation control room',
                  style: TextStyle(
                    color: Color(0x99FFFFFF),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          const Spacer(),
          if (state.connecting)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Zc.gold,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Reload data',
            onPressed: () {
              state.connect(state.account, persist: false);
              state.refreshHolidays();
            },
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
          const SizedBox(width: 4),
          const AccountSwitcher(),
        ],
      ),
    );
  }
}
