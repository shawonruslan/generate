import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/dhaka_time.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../dialogs/asset_details.dart';
import '../dialogs/theme_studio.dart';
import '../screens/distribute_screen.dart';
import '../screens/github_screen.dart';
import '../screens/home_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/pins_screen.dart';
import '../screens/schedule_screen.dart';
import '../screens/upload_queue_screen.dart';
import '../screens/vpn_screen.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';
import '../widgets/responsive.dart';
import '../widgets/toasts.dart';

/// Root layout: aurora background, sidebar (full / mini / drawer), header, page body, toasts.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nav = context.watch<NavState>();
    final p = app.palette;
    final w = MediaQuery.sizeOf(context).width;
    final narrow = w < Bp.sm;
    final mini = !narrow && (app.sidebarState == 'mini' || w < Bp.md);
    final sidebarW = narrow ? 0.0 : (mini ? 76.0 : 248.0);

    // open item requested from another screen
    if (nav.pendingItemId != null) {
      final id = nav.pendingItemId!;
      nav.pendingItemId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => openAssetDetails(context, id));
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: Focus(
        autofocus: true,
        onKeyEvent: (n, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape && nav.drawerOpen) {
            nav.toggleDrawer(false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(children: [
          const Positioned.fill(child: _AuroraBackground()),
          Row(children: [
            if (!narrow) SizedBox(width: sidebarW, child: _Sidebar(mini: mini)),
            Expanded(
              child: Column(children: [
                _Header(narrow: narrow),
                Expanded(
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(a), child: c)),
                      child: KeyedSubtree(key: ValueKey(nav.tab), child: _page(nav.tab)),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
          if (narrow && nav.drawerOpen) ...[
            Positioned.fill(child: GestureDetector(onTap: () => nav.toggleDrawer(false), child: Container(color: Colors.black.withValues(alpha: 0.5)))),
            Positioned(left: 0, top: 0, bottom: 0, width: 260, child: const _Sidebar(mini: false)),
          ],
          if (!app.queueLoaded && app.connecting) const _Loader(),
          const ToastHost(),
        ]),
      ),
    );
  }

  Widget _page(AppTab t) {
    switch (t) {
      case AppTab.home:
        return const HomeScreen();
      case AppTab.upload:
        return const UploadQueueScreen();
      case AppTab.schedule:
        return const ScheduleScreen();
      case AppTab.pins:
        return const PinsScreen();
      case AppTab.distribute:
        return const DistributeScreen();
      case AppTab.github:
        return const GithubScreen();
      case AppTab.vpn:
        return const VpnScreen();
      case AppTab.notifications:
        return const NotificationsScreen();
    }
  }
}

class _AuroraBackground extends StatelessWidget {
  const _AuroraBackground();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return IgnorePointer(
      child: Stack(children: [
        Positioned.fill(child: Container(color: p.bg)),
        Positioned(
          left: -160,
          top: -120,
          child: _Blob(color: p.primary.withValues(alpha: p.isDark ? 0.22 : 0.16), size: 560),
        ),
        Positioned(
          right: -200,
          top: 120,
          child: _Blob(color: p.accent.withValues(alpha: p.isDark ? 0.16 : 0.12), size: 620),
        ),
        Positioned(
          left: 200,
          bottom: -260,
          child: _Blob(color: p.primary2.withValues(alpha: p.isDark ? 0.14 : 0.1), size: 700),
        ),
      ]),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      );
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.palette;
    return Positioned.fill(
      child: Container(
        color: p.bg.withValues(alpha: 0.75),
        child: Center(
          child: GlassCard(
            padding: const EdgeInsets.all(28),
            glow: true,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(18)), child: Center(child: Fa('fa-bolt', size: 22, color: p.onPrimary))),
              const SizedBox(height: 16),
              Text('Automation Hub', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
              const SizedBox(height: 4),
              Text('Connecting to ${app.accountLabel(app.activeProject)} · realtime sync', style: TextStyle(fontSize: 12.5, color: p.muted)),
              const SizedBox(height: 16),
              SizedBox(width: 180, child: LinearProgressIndicator(minHeight: 4, borderRadius: BorderRadius.circular(4))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.mini});
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nav = context.watch<NavState>();
    final p = app.palette;
    final failed = app.failedItems.length;
    final unread = context.watch<AppState>().notifications.unread;
    return Container(
      decoration: BoxDecoration(
        color: p.sidebarColor.withValues(alpha: p.isDark ? 0.72 : 0.9),
        border: Border(right: BorderSide(color: p.border)),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(mini ? 12 : 18, 18, mini ? 12 : 18, 10),
              child: Row(mainAxisAlignment: mini ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(13), boxShadow: [BoxShadow(color: p.primary.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6))]),
                  child: Center(child: Fa('fa-bolt', size: 17, color: p.onPrimary)),
                ),
                if (!mini) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Automation Hub', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: p.text, letterSpacing: -0.2)),
                      Text('Zedge Content Studio', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted)),
                    ]),
                  ),
                ],
              ]),
            ),
            Divider(color: p.border),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: mini ? 10 : 12, vertical: 8),
                children: AppTab.values.map((t) {
                  final on = nav.tab == t;
                  final badge = t == AppTab.upload ? failed : (t == AppTab.notifications ? unread : 0);
                  return _NavItem(tab: t, on: on, mini: mini, badge: badge, danger: t == AppTab.upload, onTap: () => nav.go(t));
                }).toList(),
              ),
            ),
            Divider(color: p.border),
            Padding(
              padding: EdgeInsets.all(mini ? 10 : 14),
              child: Column(crossAxisAlignment: mini ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
                _SidebarClock(mini: mini),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: mini ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                  ZIconButton('fa-palette', tooltip: 'Theme Studio', onPressed: () => openThemeStudio(context)),
                  if (!mini) ...[
                    const SizedBox(width: 8),
                    ZIconButton(app.sidebarState == 'mini' ? 'fa-angles-right' : 'fa-angles-left', tooltip: app.sidebarState == 'mini' ? 'Expand sidebar' : 'Collapse sidebar', onPressed: () => app.setSidebar(app.sidebarState == 'mini' ? 'full' : 'mini')),
                  ],
                ]),
                if (mini) Padding(padding: const EdgeInsets.only(top: 8), child: ZIconButton('fa-angles-right', tooltip: 'Expand sidebar', onPressed: () => app.setSidebar('full'))),
                if (!mini) Padding(padding: const EdgeInsets.only(top: 10), child: Text('v27 · Glass UI · ${app.profile.title}', style: TextStyle(fontSize: 10.5, color: p.muted))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.tab, required this.on, required this.mini, required this.badge, required this.onTap, this.danger = false});
  final AppTab tab;
  final bool on, mini, danger;
  final int badge;
  final VoidCallback onTap;
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fg = widget.on ? p.navActiveFg : (_hover ? p.text : p.muted);
    final item = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 4),
          padding: EdgeInsets.symmetric(horizontal: widget.mini ? 0 : 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: widget.on ? (p.cfg.elements['navActive'] != null ? LinearGradient(colors: [p.navActiveColor, p.navActiveColor]) : p.buttonGradient) : null,
            color: widget.on ? null : (_hover ? p.surfaceHover : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            boxShadow: widget.on ? [BoxShadow(color: p.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))] : null,
          ),
          child: Row(mainAxisAlignment: widget.mini ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              SizedBox(width: 22, child: Center(child: Fa(kTabIcon[widget.tab]!, size: 14, color: fg))),
              if (widget.mini && widget.badge > 0)
                Positioned(right: -6, top: -6, child: _Badge(widget.badge, color: widget.danger ? p.danger : p.accent)),
            ]),
            if (!widget.mini) ...[
              const SizedBox(width: 10),
              Expanded(child: Text(kTabNav[widget.tab]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w700))),
              if (widget.badge > 0) _Badge(widget.badge, color: widget.on ? p.navActiveFg.withValues(alpha: 0.25) : (widget.danger ? p.danger : p.accent), fg: widget.on ? p.navActiveFg : null),
            ],
          ]),
        ),
      ),
    );
    return widget.mini ? Tooltip(message: kTabNav[widget.tab]!, child: item) : item;
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.n, {required this.color, this.fg});
  final int n;
  final Color color;
  final Color? fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        child: Text(n > 99 ? '99+' : '$n', style: TextStyle(color: fg ?? Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}

class _SidebarClock extends StatelessWidget {
  const _SidebarClock({required this.mini});
  final bool mini;
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final p = context.pal;
    return ValueListenableBuilder<int>(
      valueListenable: app.clockTick,
      builder: (_, __, ___) {
        final d = RealTime.instance.now().add(kDhakaOffset);
        String two(int n) => n.toString().padLeft(2, '0');
        final time = '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
        final date = '${kWeekdayLong[(d.weekday + 6) % 7]}, ${d.day} ${kMonthShort[d.month - 1]} ${d.year}';
        if (mini) return Text('${two(d.hour)}:${two(d.minute)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.text, fontFeatures: const [FontFeature.tabularFigures()]));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(time, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text, fontFeatures: const [FontFeature.tabularFigures()], letterSpacing: 0.5)),
          Text(date, style: TextStyle(fontSize: 11, color: p.muted)),
          Text('Asia/Dhaka', style: TextStyle(fontSize: 10.5, color: p.muted)),
        ]);
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.narrow});
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nav = context.watch<NavState>();
    final p = app.palette;
    final w = MediaQuery.sizeOf(context).width;
    final missing = app.missingMetadataItems.length;
    final compact = w < Bp.md;
    return Container(
      decoration: BoxDecoration(
        color: p.headerColor.withValues(alpha: p.isDark ? 0.62 : 0.86),
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: Bp.pagePad(context), vertical: 10),
            child: Row(children: [
              if (narrow) ...[ZIconButton('fa-bars', tooltip: 'Menu', onPressed: () => nav.toggleDrawer()), const SizedBox(width: 10)],
              if (narrow) Container(width: 36, height: 36, decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(11)), child: Center(child: Fa('fa-bolt', size: 15, color: p.onPrimary))),
              if (narrow) const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Automation Hub', style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: p.muted)),
                  Text(kTabLabel[nav.tab]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 17 : 20, fontWeight: FontWeight.w800, color: p.text, letterSpacing: -0.3)),
                ]),
              ),
              if (!compact) ...[
                _LiveChip(on: app.liveSync),
                const SizedBox(width: 10),
              ],
              ZIconButton('fa-palette', tooltip: 'Theme Studio - customize colors, font size, corners', onPressed: () => openThemeStudio(context)),
              const SizedBox(width: 8),
              ZIconButton('fa-bell',
                  tooltip: 'Files without metadata (will not be uploaded)',
                  badge: missing,
                  color: missing > 0 ? p.warn : null,
                  onPressed: () {
                    app.queueFilter.status = 'nometa';
                    app.uploadPage = 1;
                    app.touch();
                    nav.go(AppTab.upload);
                  }),
              const SizedBox(width: 8),
              _AccountDropdown(compact: compact),
              const SizedBox(width: 8),
              _HeaderMenu(),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = on ? p.ok : p.warn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: c.withValues(alpha: 0.45))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _PulseDot(color: c),
        const SizedBox(width: 7),
        Text(on ? 'LIVE SYNC' : 'CONNECTING', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c)),
      ]),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
        child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color, boxShadow: [BoxShadow(color: widget.color, blurRadius: 8)])),
      );
}

/// Account switcher (`#activeZedgeAccount` + Sunshine dropdown).
class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({required this.compact});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.palette;
    return PopupMenuButton<String>(
      tooltip: 'Active Zedge account (database)',
      offset: const Offset(0, 44),
      onSelected: (k) => app.connectToDatabase(k),
      itemBuilder: (_) => app.accountKeys
          .map((k) => PopupMenuItem<String>(
                value: k,
                child: Row(children: [
                  Container(width: 26, height: 26, decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(8)), child: Center(child: Fa('fa-database', size: 11, color: p.onPrimary))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(app.accountLabel(k), style: TextStyle(fontWeight: FontWeight.w700, color: p.text))),
                  if (k == app.activeProject) Fa('fa-check', size: 12, color: p.ok),
                ]),
              ))
          .toList(),
      child: Container(
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
        decoration: BoxDecoration(gradient: p.buttonGradient, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: p.primary.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Fa('fa-database', size: 12, color: p.buttonFg),
          if (!compact) ...[const SizedBox(width: 8), Text(app.accountLabel(app.activeProject), style: TextStyle(color: p.buttonFg, fontWeight: FontWeight.w800, fontSize: 13))],
          const SizedBox(width: 8),
          Fa('fa-chevron-right', size: 9, color: p.buttonFg),
        ]),
      ),
    );
  }
}

/// `⋯` header menu (v27).
class _HeaderMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final nav = context.read<NavState>();
    final p = context.pal;
    PopupMenuItem<String> item(String v, String icon, String label) => PopupMenuItem<String>(
          value: v,
          child: Row(children: [SizedBox(width: 22, child: Fa(icon, size: 12, color: p.muted)), const SizedBox(width: 8), Text(label)]),
        );
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      offset: const Offset(0, 44),
      onSelected: (v) async {
        switch (v) {
          case 'home':
            nav.go(AppTab.home);
            break;
          case 'notif':
            nav.go(AppTab.notifications);
            break;
          case 'theme':
            openThemeStudio(context);
            break;
          case 'sidebar':
            app.setSidebar(app.sidebarState == 'mini' ? 'full' : 'mini');
            break;
          case 'read':
            app.notifications.markAll();
            break;
          case 'full':
            try {
              final fs = await windowManager.isFullScreen();
              await windowManager.setFullScreen(!fs);
            } catch (_) {}
            break;
          case 'reload':
            await app.connectToDatabase(app.activeProject);
            app.showToast('Panel reloaded');
            break;
        }
      },
      itemBuilder: (_) => [
        item('home', 'fa-house', 'Dashboard'),
        item('notif', 'fa-bell', 'Notification center'),
        item('theme', 'fa-palette', 'Theme Studio'),
        item('sidebar', 'fa-table-columns', 'Toggle compact sidebar'),
        const PopupMenuDivider(),
        item('read', 'fa-check-double', 'Mark notifications read'),
        item('full', 'fa-expand', 'Fullscreen'),
        item('reload', 'fa-rotate', 'Reload panel'),
      ],
      child: const ZIconButton('fa-ellipsis', tooltip: 'Menu'),
    );
  }
}

/// Scrollable page container with consistent padding + max width for ultra-wide monitors.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1680});
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final pad = Bp.pagePad(context);
    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 40),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ),
    );
  }
}
