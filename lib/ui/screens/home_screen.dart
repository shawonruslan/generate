import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dhaka_time.dart';
import '../../state/nav.dart';
import '../dialogs/asset_details.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';
import '../widgets/queue_card.dart';
import '../widgets/responsive.dart';
import '../widgets/run_timeline.dart';
import '../widgets/sections.dart';
import '../widgets/stat_card.dart';

/// Dashboard: v27 hero, today's uploads, stats, metadata alerts, failed uploads,
/// recently added, system toolkits (`updateDashboardStats` + v27 hero).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final queued = app.queuedItems;
    int count(String t) => queued.where((i) => i.contentType == t).length;
    final audio = count('RINGTONE');
    final c24 = count('WALLPAPER_24H'), cDual = count('WALLPAPER_DUAL'), cBat = count('WALLPAPER_BATTERY');
    final cLive = count('LIVE_WALLPAPER'), cChg = count('CHARGING_ANIMATION');
    final sets = c24 + cDual + cBat + cLive + cChg;
    final wallpaper = queued.length - audio - sets;
    final failed = app.failedItems.length;
    final recent = [...app.queueItems]..sort((a, b) => b.id.compareTo(a.id));
    final nav = context.read<NavState>();

    return PageBody(children: [
      const _Hero(),
      const SizedBox(height: 16),
      const RunTimeline(showCalendarLink: true),
      const SizedBox(height: 16),
      AutoGrid(minTile: 190, gap: 12, children: [
        StatCard(label: 'Active Database', value: app.accountUpper(app.activeProject), icon: 'fa-database', tone: 'primary'),
        StatCard(label: 'Queued Uploads', value: '${queued.length}', icon: 'fa-layer-group', tone: 'secondary', onTap: () => nav.go(AppTab.upload)),
        StatCard(label: 'Failed Uploads', value: '$failed', icon: 'fa-triangle-exclamation', tone: failed > 0 ? 'danger' : 'success', onTap: () {
          app.queueFilter.status = 'failed';
          app.uploadPage = 1;
          app.touch();
          nav.go(AppTab.upload);
        }),
        StatCard(label: 'Audios Loaded', value: '$audio', icon: 'fa-music', tone: 'accent'),
        StatCard(label: 'Wallpapers Loaded', value: '$wallpaper', icon: 'fa-images', tone: 'success'),
        StatCard(label: '24H Sets', value: '$c24', icon: 'fa-clock', tone: 'primary'),
        StatCard(label: 'Dual Sets', value: '$cDual', icon: 'fa-clone', tone: 'secondary'),
        StatCard(label: 'Battery Sets', value: '$cBat', icon: 'fa-battery-half', tone: 'accent'),
        StatCard(label: 'Live Wallpapers', value: '$cLive', icon: 'fa-film', tone: 'success'),
        StatCard(label: 'Charging Animations', value: '$cChg', icon: 'fa-bolt', tone: 'primary'),
      ]),
      const SizedBox(height: 16),
      const MetaAlertSection(),
      if (app.missingMetadataItems.isNotEmpty || app.metaAlerts.values.any((a) => a != null && a.count > 0)) const SizedBox(height: 16),
      const FailedSection(),
      if (failed > 0) const SizedBox(height: 16),
      GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle('Recently Added in Queue', icon: 'fa-history', trailing: TextButton(onPressed: () => nav.go(AppTab.upload), child: const Text('Open queue ↗'))),
          const SizedBox(height: 14),
          if (recent.isEmpty)
            const EmptyNote('No files uploaded in this database yet. Drag some into the Upload Queue!', icon: 'fa-box-open', big: true)
          else
            AutoGrid(minTile: 230, gap: 12, maxCols: 4, children: [
              for (final it in recent.take(4)) QueueCard(it, compact: true, onOpen: () => openAssetDetails(context, it.id), onDelete: () => deleteQueueItemFlow(context, it)),
            ]),
        ]),
      ),
      const SizedBox(height: 16),
      const SectionTitle('System Toolkits', icon: 'fa-toolbox'),
      const SizedBox(height: 12),
      AutoGrid(minTile: 280, gap: 12, maxCols: 3, children: [
        _ModuleCard(icon: 'fa-cloud-upload-alt', title: 'Upload Queue', desc: 'Upload image & audio content, manage tags, categories, descriptions, and watch live upload worker progress.', onTap: () => nav.go(AppTab.upload)),
        _ModuleCard(icon: 'fa-calendar-alt', title: 'Schedule Calendar', desc: 'Examine publishing timeline mapped for Dhaka timezone. Shift priority queues, requeue, and reorder uploads.', onTap: () => nav.go(AppTab.schedule)),
        _ModuleCard(icon: 'fa-share-nodes', title: 'Distribute Content', desc: 'Distribute ringtones, wallpapers & videos round-robin across Zedge 1, 2, 3, and 4 automatically.', onTap: () => nav.go(AppTab.distribute)),
      ]),
    ]);
  }
}

class _Hero extends StatelessWidget {
  const _Hero();
  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final nav = context.read<NavState>();
    return ValueListenableBuilder<int>(
      valueListenable: app.clockTick,
      builder: (context, _, __) {
        final d = dhakaNow();
        final h = d.hour;
        final greet = h < 5 ? 'Working late' : (h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : (h < 21 ? 'Good evening' : 'Good night')));
        final unread = app.notifications.unread;
        final narrow = Bp.isCompact(context);
        final clock = Column(crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
          Text('${two(h % 12 == 0 ? 12 : h % 12)}:${two(d.minute)}:${two(d.second)} ${h < 12 ? 'AM' : 'PM'}', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: p.onInk, letterSpacing: -1, fontFeatures: const [FontFeature.tabularFigures()])),
          Text('${fmtLongDayFull(d)} · Dhaka (GMT+6)', style: TextStyle(fontSize: 12, color: p.onInk.withValues(alpha: 0.75))),
        ]);
        final copy = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$greet, ${app.profile.title}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: p.onInk, letterSpacing: -0.6)),
          const SizedBox(height: 6),
          Text('Account ${app.accountUpper(app.activeProject)} · ${app.queuedItems.length} in queue · ${app.failedItems.length} failed · $unread unread', style: TextStyle(fontSize: 13.5, color: p.onInk.withValues(alpha: 0.8))),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ZButton('Upload files', icon: 'fa-cloud-upload-alt', small: true, onPressed: () => nav.go(AppTab.upload)),
            ZButton('Calendar', icon: 'fa-calendar-alt', small: true, kind: ZBtnKind.ghost, onPressed: () => nav.go(AppTab.schedule)),
            ZButton('Pins', icon: 'fa-thumbtack', small: true, kind: ZBtnKind.ghost, onPressed: () => nav.go(AppTab.pins)),
            ZButton('Distribute', icon: 'fa-share-nodes', small: true, kind: ZBtnKind.ghost, onPressed: () => nav.go(AppTab.distribute)),
          ]),
        ]);
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [p.ink, p.ink2, p.primary.withValues(alpha: 0.85)], stops: const [0, 0.6, 1], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(p.radiusLg),
            boxShadow: [BoxShadow(color: p.primary.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 12))],
          ),
          child: Stack(children: [
            Positioned(right: -30, top: -40, child: Fa('fa-bolt', size: 180, color: p.onInk.withValues(alpha: 0.06))),
            narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [copy, const SizedBox(height: 18), clock])
                : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: copy), const SizedBox(width: 20), clock]),
          ]),
        );
      },
    );
  }
}

class _ModuleCard extends StatefulWidget {
  const _ModuleCard({required this.icon, required this.title, required this.desc, required this.onTap});
  final String icon, title, desc;
  final VoidCallback onTap;
  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _h ? -4 : 0, 0),
        child: GlassCard(
          onTap: widget.onTap,
          glow: _h,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 46, height: 46, alignment: Alignment.center, decoration: BoxDecoration(gradient: p.primaryGradient, borderRadius: BorderRadius.circular(14)), child: Fa(widget.icon, size: 20, color: p.onPrimary)),
            const SizedBox(height: 14),
            Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.text)),
            const SizedBox(height: 6),
            Text(widget.desc, style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.45)),
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Launch Module', style: TextStyle(fontWeight: FontWeight.w800, color: p.primary, fontSize: 13)),
              const SizedBox(width: 6),
              Fa('fa-angle-right', size: 12, color: p.primary),
            ]),
          ]),
        ),
      ),
    );
  }
}
