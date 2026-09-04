import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/account_switcher.dart';
import 'calendar_tab.dart';
import 'dashboard_tab.dart';
import 'distribute_tab.dart';
import 'github_tab.dart';
import 'queue_tab.dart';
import 'settings_tab.dart';

/// Tab ids shared with the Home toolkit shortcuts.
enum AppTab { home, queue, schedule, distribute, github, settings }

/// App frame: Sunshine header + pill navigation (desktop) or bottom bar
/// (mobile), identical structure to the Automation Hub dashboard.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppTab _tab = AppTab.home;

  static const List<_NavEntry> _entries = <_NavEntry>[
    _NavEntry(AppTab.home, 'Home', Icons.home_rounded),
    _NavEntry(AppTab.queue, 'Upload Queue', Icons.cloud_upload_rounded),
    _NavEntry(AppTab.schedule, 'Schedule Calendar', Icons.calendar_month_rounded),
    _NavEntry(AppTab.distribute, 'Distribute', Icons.hub_rounded),
    _NavEntry(AppTab.github, 'GitHub Control', Icons.terminal_rounded),
    _NavEntry(AppTab.settings, 'Settings', Icons.settings_rounded),
  ];

  void _go(AppTab tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final double width = MediaQuery.sizeOf(context).width;
    final bool wide = width >= 900;

    final List<Widget> pages = <Widget>[
      DashboardTab(onNavigate: _go),
      const QueueTab(),
      const CalendarTab(),
      const DistributeTab(),
      const GithubTab(),
      const SettingsTab(),
    ];

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              _Header(wide: wide, onSettings: () => _go(AppTab.settings)),
              if (wide) _PillNav(active: _tab, entries: _entries, onSelect: _go),
              if (state.error != null) _ErrorBar(state: state),
              if (state.uploading) _UploadBar(state: state),
              Expanded(
                child: IndexedStack(index: _tab.index, children: pages),
              ),
            ],
          ),
          if (state.booting) const _Loader(),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab.index > 4 ? 0 : _tab.index,
              backgroundColor: Zc.panel,
              indicatorColor: Zc.gold.withOpacity(0.45),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (int value) => _go(AppTab.values[value]),
              destinations: _entries
                  .take(5)
                  .map(
                    (_NavEntry entry) => NavigationDestination(
                      icon: Icon(entry.icon),
                      label: entry.shortLabel,
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _NavEntry {
  const _NavEntry(this.tab, this.label, this.icon);

  final AppTab tab;
  final String label;
  final IconData icon;

  String get shortLabel {
    switch (tab) {
      case AppTab.queue:
        return 'Queue';
      case AppTab.schedule:
        return 'Schedule';
      case AppTab.github:
        return 'GitHub';
      default:
        return label;
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.wide, required this.onSettings});

  final bool wide;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final double top = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 14, top + 14, wide ? 24 : 12, 14),
      decoration: const BoxDecoration(
        gradient: Zc.headerGradient,
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x33FFB400), blurRadius: 24, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Zc.ink,
              borderRadius: BorderRadius.circular(13),
              boxShadow: kSoftShadow,
            ),
            child: const Icon(Icons.bolt_rounded, color: Zc.gold, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Automation Hub',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Zc.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: wide ? 19 : 16,
                    letterSpacing: -0.3,
                    height: 1.05,
                  ),
                ),
                Text(
                  'Unified Zedge Content Studio',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Zc.ink.withOpacity(0.7),
                    fontWeight: FontWeight.w700,
                    fontSize: wide ? 11.5 : 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (wide) ...<Widget>[
            _LiveChip(state: state),
            const SizedBox(width: 10),
          ],
          AccountSwitcher(compact: !wide),
          if (!wide)
            IconButton(
              tooltip: 'Settings',
              onPressed: onSettings,
              icon: const Icon(Icons.settings_rounded, color: Zc.ink),
            ),
        ],
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final bool live = !state.connecting && state.error == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Zc.ink,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Pulse(color: live ? Zc.ok : Zc.warn),
          const SizedBox(width: 7),
          Text(
            live ? 'LIVE SYNC' : (state.connecting ? 'CONNECTING' : 'OFFLINE'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color});

  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
      ),
    );
  }
}

class _PillNav extends StatelessWidget {
  const _PillNav({
    required this.active,
    required this.entries,
    required this.onSelect,
  });

  final AppTab active;
  final List<_NavEntry> entries;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Zc.panel,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Zc.line, width: 1.5),
            boxShadow: kSoftShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: entries.map((_NavEntry e) {
              final bool on = e.tab == active;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => onSelect(e.tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: on ? Zc.goldGradient : null,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: on ? kSoftShadow : null,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(e.icon, size: 16,
                            color: on ? Zc.ink : Zc.muted),
                        const SizedBox(width: 7),
                        Text(
                          e.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: on ? Zc.ink : Zc.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Zc.danger.withOpacity(0.10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.wifi_off_rounded, size: 15, color: Zc.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Realtime Database unreachable - showing the last known data. '
              '(${state.error})',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Zc.danger,
              ),
            ),
          ),
          TextButton(
            onPressed: () => state.connect(state.account, persist: false),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _UploadBar extends StatelessWidget {
  const _UploadBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      color: Zc.creamDeep,
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.uploadStatus,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Zc.inkSoft,
              ),
            ),
          ),
          if (state.uploadProgress > 0)
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: state.uploadProgress,
                  minHeight: 6,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Zc.canvas,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                gradient: Zc.goldGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: kLiftShadow,
              ),
              child: const Icon(Icons.bolt_rounded, color: Zc.ink, size: 40),
            ),
            const SizedBox(height: 18),
            const Text(
              'Automation Hub',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Zc.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Connecting to your Zedge databases...',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Zc.muted,
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 160,
              child: LinearProgressIndicator(minHeight: 5),
            ),
          ],
        ),
      ),
    );
  }
}
