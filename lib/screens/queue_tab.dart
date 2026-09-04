import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/queue_item.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/item_editor.dart';
import '../widgets/queue_card.dart';

class QueueTab extends StatelessWidget {
  const QueueTab({super.key});

  static const List<String> _statuses = <String>[
    'ALL',
    'queued',
    'processing',
    'done',
    'failed',
  ];

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<QueueItem> items = state.filteredItems;

    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: const BoxDecoration(
            color: Zc.panel,
            border: Border(bottom: BorderSide(color: Zc.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                onChanged: state.setSearch,
                decoration: const InputDecoration(
                  hintText: 'Search title, tags or category',
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    ..._statuses.map(
                      (String status) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          selected: state.statusFilter == status,
                          onSelected: (bool _) => state.setStatusFilter(status),
                          selectedColor: Zc.gold,
                          showCheckmark: false,
                          label: Text(
                            status == 'ALL' ? 'All status' : status.toUpperCase(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const VerticalDivider(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        selected: state.typeFilter == 'ALL',
                        onSelected: (bool _) => state.setTypeFilter('ALL'),
                        selectedColor: Zc.gold,
                        showCheckmark: false,
                        label: const Text('All types'),
                      ),
                    ),
                    ...kTypeCycle.map(
                      (String type) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          selected: state.typeFilter == type,
                          onSelected: (bool _) => state.setTypeFilter(type),
                          selectedColor: Zc.gold,
                          showCheckmark: false,
                          avatar: Icon(Zc.typeIcon(type), size: 14),
                          label: Text(kTypeLabels[type] ?? type),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'Nothing matches these filters',
                    style: TextStyle(color: Zc.muted, fontWeight: FontWeight.w700),
                  ),
                )
              : LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final int columns =
                        (constraints.maxWidth / 250).floor().clamp(1, 5);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.86,
                      ),
                      itemCount: items.length,
                      itemBuilder: (BuildContext context, int index) {
                        final QueueItem item = items[index];
                        return QueueCard(
                          item: item,
                          onTap: () => showItemEditor(context, item),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
