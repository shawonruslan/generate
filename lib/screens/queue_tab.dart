import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/queue_item.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/item_editor.dart';
import '../widgets/queue_card.dart';
import '../widgets/ui.dart';
import '../widgets/upload_panel.dart';

/// Upload Queue: upload panel + filterable, paginated grid of every row.
class QueueTab extends StatefulWidget {
  const QueueTab({super.key});

  @override
  State<QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<QueueTab> {
  String _filter = 'ALL'; // ALL | WALL | SPECIAL | AUDIO | FAILED | DONE
  String _query = '';
  int _page = 0;

  List<QueueItem> _apply(List<QueueItem> items) {
    final String q = _query.trim().toLowerCase();
    return items.where((QueueItem i) {
      switch (_filter) {
        case 'WALL':
          if (!(i.contentType == 'WALLPAPER' && i.isQueued)) return false;
          break;
        case 'SPECIAL':
          if (!(i.isSpecial && i.isQueued)) return false;
          break;
        case 'AUDIO':
          if (!(i.isAudio && i.isQueued)) return false;
          break;
        case 'FAILED':
          if (i.status != 'failed') return false;
          break;
        case 'DONE':
          if (i.isQueued || i.status == 'failed') return false;
          break;
      }
      if (q.isEmpty) return true;
      return i.displayTitle.toLowerCase().contains(q) ||
          i.name.toLowerCase().contains(q) ||
          i.tags.toLowerCase().contains(q) ||
          i.category.toLowerCase().contains(q) ||
          i.typeLabel.toLowerCase().contains(q) ||
          i.status.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<QueueItem> filtered = _apply(state.items);
    final int pages = (filtered.length / kQueuePerPage).ceil().clamp(1, 1 << 20);
    if (_page >= pages) _page = pages - 1;
    final List<QueueItem> visible =
        filtered.skip(_page * kQueuePerPage).take(kQueuePerPage).toList();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool wide = c.maxWidth >= 900;
        final int cols = c.maxWidth >= 1400
            ? 6
            : c.maxWidth >= 1100
                ? 4
                : c.maxWidth >= 720
                    ? 3
                    : 2;
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 8, wide ? 24 : 14, 32),
          children: <Widget>[
            const UploadPanel(),
            const SizedBox(height: 18),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionTitle(
                    icon: Icons.layers_rounded,
                    title: 'Active Queue',
                    subtitle:
                        '${state.account.label} - ${state.items.length} rows, ${state.queuedCount} queued',
                    gradient: Zc.secondaryGradient,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _pill('ALL', 'Total', state.items.length, Zc.ink),
                      _pill('WALL', 'Wallpapers', state.wallpaperCount,
                          Zc.goldDeep),
                      _pill('SPECIAL', 'Special', state.specialCount, Zc.info),
                      _pill('AUDIO', 'Audios', state.audioCount, Zc.purple),
                      _pill('FAILED', 'Failed',
                          state.statusCounts['failed'] ?? 0, Zc.danger),
                      _pill(
                        'DONE',
                        'Uploaded',
                        state.items
                            .where((QueueItem i) =>
                                !i.isQueued && i.status != 'failed')
                            .length,
                        Zc.okDeep,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (String v) => setState(() {
                      _query = v;
                      _page = 0;
                    }),
                    decoration: const InputDecoration(
                      hintText: 'Search title, tags, category, type, status...',
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (state.connecting && state.items.isEmpty)
                    const SizedBox(
                      height: 160,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (visible.isEmpty)
                    const EmptyState(
                      icon: Icons.inbox_rounded,
                      title: 'No items match',
                      message: 'Upload something above or change the filter.',
                    )
                  else
                    GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.72,
                      children: visible
                          .map(
                            (QueueItem item) => QueueCard(
                              key: ValueKey<String>(item.id),
                              item: item,
                              onTap: () => showItemEditor(context, item),
                            ),
                          )
                          .toList(),
                    ),
                  if (pages > 1) ...<Widget>[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        IconButton(
                          onPressed: _page == 0
                              ? null
                              : () => setState(() => _page--),
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Text(
                          'Page ${_page + 1} / $pages  -  ${filtered.length} items',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: Zc.inkSoft,
                          ),
                        ),
                        IconButton(
                          onPressed: _page >= pages - 1
                              ? null
                              : () => setState(() => _page++),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pill(String id, String label, int count, Color color) {
    final bool on = _filter == id;
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () => setState(() {
        _filter = id;
        _page = 0;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: on ? color : Zc.cream,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: on ? color : Zc.line, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : Zc.inkSoft,
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: on ? Colors.white.withOpacity(0.25) : color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: on ? Colors.white : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
