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
import '../widgets/brand_logo.dart';
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
    // brand icon follows the live theme (Windows taskbar / title bar); no-op when unchanged
    // ignore: unawaited_futures
    syncWindowIcon(app.palette);
    final sidebarW = narrow ? 0.0 : (mini ? 78.0 : 264.0);

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
            Positioned(left: 0, top: 0, bottom: 0, width: 272, child: const _Sidebar(mini: false)),
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
              const BrandLogo(size: 64, radiusFactor: 0.28),
              const SizedBox(height: 16),
              Text('Meta Hawladar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
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

/// Navigation groups shown in the sidebar (section labels are UI-only; tabs are unchanged).
const List<(String, List<AppTab>)> _kNavGroups = [
  ('Workspace', [AppTab.home, AppTab.upload, AppTab.schedule, AppTab.pins]),
  ('Automation', [AppTab.distribute, AppTab.github, AppTab.vpn]),
  ('System', [AppTab.notifications]),
];

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.mini});
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nav = context.watch<NavState>();
    final p = app.palette;
    final failed = app.failedItems.length;
    final unread = app.notifications.unread;
    final hPad = mini ? 10.0 : 14.0;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p.sidebarColor.withValues(alpha: p.isDark ? 0.80 : 0.94), p.sidebarColor.withValues(alpha: p.isDark ? 0.62 : 0.86)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(right: BorderSide(color: p.border)),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Column(children: [
            // ---- brand
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 18, hPad, 12),
              child: Row(mainAxisAlignment: mini ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
                const BrandLogo(size: 42, radiusFactor: 0.32),
                if (!mini) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Meta Hawladar', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: p.text, letterSpacing: -0.2)),
                      const SizedBox(height: 1),
                      Text('Zedge Content Studio', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
              ]),
            ),
            // ---- active account card
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 6),
              child: _AccountCard(mini: mini),
            ),
            // ---- navigation
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 8),
                children: [
                  for (final g in _kNavGroups) ...[
                    if (!mini)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Text(g.$1.toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w800, color: p.muted.withValues(alpha: 0.85))),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                        child: Divider(height: 1, color: p.border),
                      ),
                    for (final t in g.$2)
                      _NavItem(
                        tab: t,
                        on: nav.tab == t,
                        mini: mini,
                        badge: t == AppTab.upload ? failed : (t == AppTab.notifications ? unread : 0),
                        danger: t == AppTab.upload,
                        onTap: () => nav.go(t),
                      ),
                  ],
                ],
              ),
            ),
            // ---- today progress
            if (!mini) Padding(padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8), child: const _TodayCard()),
            // ---- clock + tools
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
              child: _SidebarClock(mini: mini),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Active account (database) card - click to switch, mirrors the header dropdown.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.mini});
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.palette;
    final live = app.liveSync;
    final idx = app.profile.account(app.activeProject)?.index ?? 0;
    final avatar = Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [p.accent, p.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(idx > 0 ? idx.toString().padLeft(2, '0') : 'DB', style: TextStyle(color: p.onPrimary, fontWeight: FontWeight.w900, fontSize: 12.5)),
      ),
      Positioned(
        right: -3,
        bottom: -3,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: live ? p.ok : p.warn, border: Border.all(color: p.sidebarColor, width: 2)),
        ),
      ),
    ]);
    final menu = PopupMenuButton<String>(
      tooltip: 'Switch Zedge account (database)',
      offset: Offset(mini ? 48 : 0, 46),
      onSelected: app.connectToDatabase,
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
        padding: EdgeInsets.symmetric(horizontal: mini ? 0 : 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.tintCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border),
        ),
        child: Row(mainAxisAlignment: mini ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
          avatar,
          if (!mini) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.accountLabel(app.activeProject), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.text)),
                Text(
                  live ? '${app.queuedItems.length} in queue · live' : (app.connecting ? 'connecting…' : '${app.queuedItems.length} in queue'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: live ? p.ok : p.muted, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            Fa('fa-chevron-down', size: 10, color: p.muted),
          ],
        ]),
      ),
    );
    return mini ? Tooltip(message: '${app.accountLabel(app.activeProject)} · switch account', child: menu) : menu;
  }
}

/// "Today" progress card: done / total upload slots across all accounts (same data as the run timeline).
class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.palette;
    return ValueListenableBuilder<int>(
      valueListenable: app.clockTick,
      builder: (_, __, ___) {
        final cards = app.overview(RealTime.instance.nowMs());
        final total = cards.fold<int>(0, (a, c) => a + c.slots.length);
        final done = cards.fold<int>(0, (a, c) => a + c.doneCount);
        final ratio = total == 0 ? 0.0 : done / total;
        final failed = app.failedItems.length;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [p.primary.withValues(alpha: 0.16), p.accent.withValues(alpha: 0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.primary.withValues(alpha: 0.28)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Fa('fa-cloud-upload-alt', size: 11, color: p.primary),
              const SizedBox(width: 7),
              Expanded(child: Text("TODAY'S UPLOADS", style: TextStyle(fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: p.muted))),
              Text('$done / $total', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: p.text, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: ratio.clamp(0.0, 1.0).toDouble(), minHeight: 6, color: p.primary, backgroundColor: p.primary.withValues(alpha: 0.15)),
            ),
            const SizedBox(height: 7),
            Row(children: [
              Expanded(child: Text('${cards.length} accounts · Dhaka', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: p.muted))),
              if (failed > 0)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Fa('fa-triangle-exclamation', size: 9, color: p.danger),
                  const SizedBox(width: 4),
                  Text('$failed failed', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.danger)),
                ]),
            ]),
          ]),
        );
      },
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
    final on = widget.on;
    final fg = on ? p.navActiveFg : (_hover ? p.text : p.muted);
    final iconBox = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: on ? p.navActiveFg.withValues(alpha: 0.18) : (_hover ? p.primary.withValues(alpha: 0.14) : p.tintChip),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(child: Fa(kTabIcon[widget.tab]!, size: 13.5, color: on ? p.navActiveFg : (_hover ? p.primary : p.muted))),
    );
    final item = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 4),
          padding: EdgeInsets.symmetric(horizontal: widget.mini ? 0 : 8, vertical: widget.mini ? 7 : 6),
          transform: Matrix4.translationValues(_hover && !on && !widget.mini ? 2 : 0, 0, 0),
          decoration: BoxDecoration(
            gradient: on ? (p.cfg.elements['navActive'] != null ? LinearGradient(colors: [p.navActiveColor, p.navActiveColor]) : p.buttonGradient) : null,
            color: on ? null : (_hover ? p.surfaceHover : Colors.transparent),
            borderRadius: BorderRadius.circular(13),
            boxShadow: on ? [BoxShadow(color: p.primary.withValues(alpha: 0.32), blurRadius: 18, offset: const Offset(0, 7))] : null,
          ),
          child: Row(mainAxisAlignment: widget.mini ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              iconBox,
              if (widget.mini && widget.badge > 0) Positioned(right: -7, top: -7, child: _Badge(widget.badge, color: widget.danger ? p.danger : p.accent)),
            ]),
            if (!widget.mini) ...[
              const SizedBox(width: 11),
              Expanded(child: Text(kTabNav[widget.tab]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 13.5, fontWeight: on ? FontWeight.w800 : FontWeight.w600))),
              if (widget.badge > 0)
                _Badge(widget.badge, color: on ? p.navActiveFg.withValues(alpha: 0.25) : (widget.danger ? p.danger : p.accent), fg: on ? p.navActiveFg : null)
              else if (on)
                Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: p.navActiveFg.withValues(alpha: 0.9))),
            ],
          ]),
        ),
      ),
    );
    return widget.mini ? Tooltip(message: kTabNav[widget.tab]!, waitDuration: const Duration(milliseconds: 300), child: item) : item;
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

/// Bottom block: Dhaka clock (bot time) + Theme Studio / collapse buttons + version line.
class _SidebarClock extends StatelessWidget {
  const _SidebarClock({required this.mini});
  final bool mini;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.palette;
    return ValueListenableBuilder<int>(
      valueListenable: app.clockTick,
      builder: (_, __, ___) {
        final d = RealTime.instance.now().add(kDhakaOffset);
        final time = '${two(d.hour)}:${two(d.minute)}';
        final sec = two(d.second);
        final date = '${kWeekdayLong[(d.weekday + 6) % 7]}, ${d.day} ${kMonthShort[d.month - 1]} ${d.year}';
        if (mini) {
          return Column(children: [
            Tooltip(
              message: '$time:$sec · Asia/Dhaka (bot time)',
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                width: double.infinity,
                decoration: BoxDecoration(color: p.tintCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
                child: Column(children: [
                  Text(time, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.text, fontFeatures: const [FontFeature.tabularFigures()])),
                  Text('DHK', style: TextStyle(fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w800, color: p.muted)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            ZIconButton('fa-palette', tooltip: 'Theme Studio', onPressed: () => openThemeStudio(context)),
            const SizedBox(height: 6),
            ZIconButton('fa-angles-right', tooltip: 'Expand sidebar', onPressed: () => app.setSidebar('full')),
          ]);
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: p.tintCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(time, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.text, height: 1, fontFeatures: const [FontFeature.tabularFigures()], letterSpacing: 0.3)),
              const SizedBox(width: 4),
              Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(sec, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.primary, fontFeatures: const [FontFeature.tabularFigures()]))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                child: Text('DHAKA', style: TextStyle(fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w800, color: p.primary)),
              ),
            ]),
            const SizedBox(height: 3),
            Text(date, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ZButton('Theme Studio', icon: 'fa-palette', small: true, kind: ZBtnKind.soft, expand: true, onPressed: () => openThemeStudio(context))),
              const SizedBox(width: 6),
              ZIconButton(app.sidebarState == 'mini' ? 'fa-angles-right' : 'fa-angles-left', tooltip: app.sidebarState == 'mini' ? 'Expand sidebar' : 'Collapse sidebar', onPressed: () => app.setSidebar(app.sidebarState == 'mini' ? 'full' : 'mini')),
            ]),
            const SizedBox(height: 8),
            Text('v27 · Glass UI · ${app.profile.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: p.muted)),
          ]),
        );
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
              if (narrow) const BrandLogo(size: 36, radiusFactor: 0.3),
              if (narrow) const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Meta Hawladar', style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: p.muted)),
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
