import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/queue_item.dart';
import '../models/schedule.dart';
import '../services/time_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/item_editor.dart';
import '../widgets/queue_card.dart';
import '../widgets/stat_card.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';

/// Home: live stats, recently added media and the System Toolkit shortcuts.
class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key, required this.onNavigate});

  final ValueChanged<AppTab> onNavigate;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final ScheduleStats stats = state.scheduleStats;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool wide = c.maxWidth >= 900;
        final int cols = c.maxWidth >= 1250
            ? 5
            : c.maxWidth >= 900
                ? 4
                : c.maxWidth >= 560
                    ? 3
                    : 2;

        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 8, wide ? 24 : 14, 32),
          children: <Widget>[
            _Hero(state: state, stats: stats, onNavigate: onNavigate),
            const SizedBox(height: 18),
            const SectionTitle(
              icon: Icons.insights_rounded,
              title: 'Live Statistics',
              subtitle: 'Queued content of the active database',
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: wide ? 1.55 : 1.3,
              children: <Widget>[
                StatCard(
                  icon: Icons.storage_rounded,
                  label: 'Active DB',
                  value: state.account.label,
                  hint: state.account.projectId,
                  accent: Zc.ink,
                ),
                StatCard(
                  icon: Icons.layers_rounded,
                  label: 'Queued Total',
                  value: '${state.queuedCount}',
                  hint: '${state.items.length} rows in DB',
                  onTap: () => onNavigate(AppTab.queue),
                ),
                StatCard(
                  icon: Icons.music_note_rounded,
                  label: 'Audios',
                  value: '${state.audioCount}',
                  hint: 'MP3 ringtones',
                  accent: Zc.purple,
                ),
                StatCard(
                  icon: Icons.wallpaper_rounded,
                  label: 'Wallpapers',
                  value: '${state.wallpaperCount}',
                  hint: 'Static JPEG',
                  accent: Zc.goldDeep,
                ),
                StatCard(
                  icon: Icons.schedule_rounded,
                  label: '24H Sets',
                  value: '${state.countBucket('WALLPAPER_24H')}',
                  hint: 'Day / Night sets',
                  accent: Zc.info,
                ),
                StatCard(
                  icon: Icons.smartphone_rounded,
                  label: 'Dual Sets',
                  value: '${state.countBucket('WALLPAPER_DUAL')}',
                  hint: 'Lock / Home',
                  accent: const Color(0xFF00A8A8),
                ),
                StatCard(
                  icon: Icons.battery_charging_full_rounded,
                  label: 'Battery Sets',
                  value: '${state.countBucket('WALLPAPER_BATTERY')}',
                  hint: '4 charge levels',
                  accent: Zc.okDeep,
                ),
                StatCard(
                  icon: Icons.movie_creation_rounded,
                  label: 'Live',
                  value: '${state.countBucket('LIVE_WALLPAPER')}',
                  hint: 'MP4 live wallpapers',
                  accent: const Color(0xFFE0457B),
                ),
                StatCard(
                  icon: Icons.bolt_rounded,
                  label: 'Charging',
                  value: '${state.countBucket('CHARGING_ANIMATION')}',
                  hint: 'Charging animations',
                  accent: Zc.orange,
                ),
                StatCard(
                  icon: Icons.today_rounded,
                  label: 'Today',
                  value: '${stats.uploadedToday}/$kUploadsPerDay',
                  hint: '${metaFor(stats.todayType).label} day',
                  accent: Zc.warn,
                  onTap: () => onNavigate(AppTab.schedule),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SectionTitle(
              icon: Icons.new_releases_rounded,
              title: 'Recently Added',
              subtitle: 'Newest 4 rows in ${state.account.label}',
              trailing: TextButton.icon(
                onPressed: () => onNavigate(AppTab.queue),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Open queue'),
              ),
            ),
            const SizedBox(height: 12),
            if (state.connecting && state.items.isEmpty)
              const Panel(
                child: SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (state.recentItems.isEmpty)
              Panel(
                child: EmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'The queue is empty',
                  message: 'Upload wallpapers, sets, videos or ringtones from '
                      'the Upload Queue tab.',
                  action: GradientButton(
                    label: 'Go to Upload Queue',
                    icon: Icons.cloud_upload_rounded,
                    onPressed: () => onNavigate(AppTab.queue),
                  ),
                ),
              )
            else
              GridView.count(
                crossAxisCount: c.maxWidth >= 1100
                    ? 4
                    : c.maxWidth >= 640
                        ? 2
                        : 1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: c.maxWidth >= 640 ? 0.74 : 0.9,
                children: state.recentItems
                    .map(
                      (QueueItem item) => QueueCard(
                        item: item,
                        onTap: () => showItemEditor(context, item),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 22),
            const SectionTitle(
              icon: Icons.construction_rounded,
              title: 'System Toolkit',
              subtitle: 'Every workflow of the Automation Hub',
              gradient: Zc.accentGradient,
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: c.maxWidth >= 1100
                  ? 3
                  : c.maxWidth >= 640
                      ? 2
                      : 1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: c.maxWidth >= 640 ? 2.2 : 2.6,
              children: <Widget>[
                _ToolCard(
                  icon: Icons.cloud_upload_rounded,
                  title: 'Upload Queue',
                  text: 'Wallpapers, 24H / Dual / Battery sets, live wallpapers, '
                      'charging animations and MP3 ringtones - auto resized to '
                      '${kImageTargetWidth}x$kImageTargetHeight.',
                  onTap: () => onNavigate(AppTab.queue),
                ),
                _ToolCard(
                  icon: Icons.calendar_month_rounded,
                  title: 'Schedule Calendar',
                  text: 'Rolling AUDIO / WALLPAPER / 24H / DUAL / BATTERY / '
                      'LIVE / CHARGING cycle, pinned dates and special days.',
                  onTap: () => onNavigate(AppTab.schedule),
                ),
                _ToolCard(
                  icon: Icons.hub_rounded,
                  title: 'Distribute',
                  text: 'Round-robin bulk upload to Zedge 1, 2 and 3 with '
                      'chunked set grouping and duplicate protection.',
                  onTap: () => onNavigate(AppTab.distribute),
                ),
                _ToolCard(
                  icon: Icons.terminal_rounded,
                  title: 'GitHub Control',
                  text: 'Run the ringtone & metadata generators, watch runs, '
                      'push files and manage the Gemini session.',
                  onTap: () => onNavigate(AppTab.github),
                ),
                _ToolCard(
                  icon: Icons.access_time_filled_rounded,
                  title: 'Dhaka Clock',
                  text: '${dhakaStamp(state.dhakaNow)} - '
                      '${state.timeSynced ? 'REAL SYNC (${state.time.source})' : 'DEVICE CLOCK'}',
                  onTap: () => state.time
                      .sync(state.account.databaseUrl)
                      .then((_) => state.refreshHolidays()),
                ),
                _ToolCard(
                  icon: Icons.settings_rounded,
                  title: 'Settings',
                  text: 'Holiday regions, Google Calendar key, preview device '
                      'and cache.',
                  onTap: () => onNavigate(AppTab.settings),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.state,
    required this.stats,
    required this.onNavigate,
  });

  final AppState state;
  final ScheduleStats stats;
  final ValueChanged<AppTab> onNavigate;

  @override
  Widget build(BuildContext context) {
    final TypeMeta meta = metaFor(stats.todayType);
    final List<ScheduleDay> days = state.buildScheduleDays();
    final ScheduleDay? today = days.isEmpty ? null : days.first;
    final int pinned = today == null ? 0 : today.slots.length;

    return Panel(
      gradient: Zc.headerGradient,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(20),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20,
        runSpacing: 14,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Today is a ${meta.dayLabel}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Zc.ink,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${dhakaStamp(state.dhakaNow)} Dhaka - '
                  '${stats.remainingToday} of $kUploadsPerDay uploads left - '
                  '$pinned/${today?.slotLimit ?? kUploadsPerDay} slots filled',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Zc.ink.withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    GradientButton(
                      label: 'Upload media',
                      icon: Icons.cloud_upload_rounded,
                      gradient: const LinearGradient(
                        colors: <Color>[Zc.ink, Color(0xFF3A321C)],
                      ),
                      foreground: Colors.white,
                      dense: true,
                      onPressed: () => onNavigate(AppTab.queue),
                    ),
                    GradientButton(
                      label: 'Open calendar',
                      icon: Icons.calendar_month_rounded,
                      gradient: const LinearGradient(
                        colors: <Color>[Colors.white, Color(0xFFFFF6D8)],
                      ),
                      dense: true,
                      onPressed: () => onNavigate(AppTab.schedule),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _MiniStat('Queued', '${state.queuedCount}'),
              _MiniStat('Audios', '${state.audioCount}'),
              _MiniStat('Wallpapers', '${state.wallpaperCount}'),
              _MiniStat('Specials', '${state.specialCount}'),
              _MiniStat(
                'Failed',
                '${state.statusCounts['failed'] ?? 0}',
                bad: (state.statusCounts['failed'] ?? 0) > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, {this.bad = false});

  final String label;
  final String value;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.9)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: bad ? Zc.danger : Zc.ink,
            ),
          ),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
              color: Zc.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Panel(
          padding: const EdgeInsets.all(14),
          radius: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: Zc.secondaryGradient,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Zc.ink, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: Zc.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: Zc.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Zc.muted),
            ],
          ),
        ),
      ),
    );
  }
}
