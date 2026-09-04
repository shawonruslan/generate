import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/queue_item.dart';
import '../services/holiday_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/item_editor.dart';
import '../widgets/queue_card.dart';
import '../widgets/stat_card.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final Map<String, int> counts = state.statusCounts;
    final List<QueueItem> recent = state.items.take(8).toList();
    final List<SpecialDay> today = state.holidays.forDateKey(state.todayKey);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int columns = constraints.maxWidth > 1150
                ? 4
                : constraints.maxWidth > 780
                    ? 3
                    : constraints.maxWidth > 520
                        ? 2
                        : 1;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.62,
              children: <Widget>[
                StatCard(
                  icon: Icons.inventory_2_rounded,
                  label: 'Total in queue',
                  value: '${state.items.length}',
                  hint: '${state.unscheduledItems.length} unscheduled',
                ),
                StatCard(
                  icon: Icons.hourglass_bottom_rounded,
                  label: 'Waiting',
                  value: '${counts['queued'] ?? 0}',
                  hint: 'Ready for the bot to pick up',
                  accent: Zc.warn,
                ),
                StatCard(
                  icon: Icons.verified_rounded,
                  label: 'Published',
                  value:
                      '${(counts['done'] ?? 0) + (counts['uploaded'] ?? 0) + (counts['completed'] ?? 0)}',
                  hint: '${state.uploadsToday} uploaded today',
                  accent: Zc.ok,
                ),
                StatCard(
                  icon: Icons.error_outline_rounded,
                  label: 'Failed',
                  value: '${(counts['failed'] ?? 0) + (counts['error'] ?? 0)}',
                  hint: 'Open an item to requeue it',
                  accent: Zc.danger,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: Zc.headerGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: kSoftShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                "TODAY'S ROTATION",
                style: TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: Zc.goldGradient,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(Zc.typeIcon(state.todayType),
                        color: Zc.ink, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          kTypeLabels[state.todayType] ?? state.todayType,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${state.itemsForDateKey(state.todayKey).length} items scheduled for ${state.todayKey}',
                          style: const TextStyle(
                            color: Color(0x99FFFFFF),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (today.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                const Divider(color: Color(0x1FFFFFFF), height: 1),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: today
                      .map(
                        (SpecialDay day) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: const Color(0x33FFD400)),
                          ),
                          child: Text(
                            '${day.flag} ${day.name}',
                            style: const TextStyle(
                              color: Zc.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'RECENTLY ADDED',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w900,
            color: Zc.muted,
          ),
        ),
        const SizedBox(height: 12),
        if (state.items.isEmpty)
          _EmptyHint(connecting: state.connecting)
        else
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int columns = (constraints.maxWidth / 250).floor().clamp(1, 4);
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.86,
                children: recent
                    .map(
                      (QueueItem item) => QueueCard(
                        item: item,
                        onTap: () => showItemEditor(context, item),
                      ),
                    )
                    .toList(),
              );
            },
          ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.connecting});

  final bool connecting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44),
      decoration: BoxDecoration(
        color: Zc.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Zc.line, width: 1.5),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            connecting ? Icons.cloud_sync_rounded : Icons.inbox_rounded,
            size: 34,
            color: Zc.muted,
          ),
          const SizedBox(height: 10),
          Text(
            connecting ? 'Connecting to the database...' : 'The queue is empty',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Zc.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Use "New upload" to push wallpapers or ringtones into the queue.',
            style: TextStyle(fontSize: 11.5, color: Zc.muted),
          ),
        ],
      ),
    );
  }
}
