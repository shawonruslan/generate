import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/queue_item.dart';
import '../theme/app_theme.dart';
import 'stat_card.dart';

/// One row in the queue grid. Tapping it opens the unified editor.
class QueueCard extends StatefulWidget {
  const QueueCard({super.key, required this.item, required this.onTap});

  final QueueItem item;
  final VoidCallback onTap;

  @override
  State<QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends State<QueueCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final QueueItem item = widget.item;
    final Color status = Zc.statusColor(item.status);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: Zc.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hover ? Zc.goldDeep : const Color(0xFFEBE2CB),
            width: 1.5,
          ),
          boxShadow: kSoftShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _Thumb(item: item),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: TagPill(
                        text: item.typeLabel,
                        color: Zc.goldDeep,
                        icon: Zc.typeIcon(item.contentType),
                        filled: true,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: TagPill(
                        text: item.status,
                        color: status,
                        filled: true,
                      ),
                    ),
                    if (item.isSet)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: TagPill(
                          text:
                              '${item.filledSlots.length}/${item.slots.length} slots',
                          color: Zc.ink,
                          icon: Icons.grid_view_rounded,
                          filled: true,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Zc.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.tags.isEmpty ? 'No tags yet' : item.tags,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Zc.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.event_rounded,
                            size: 13, color: Zc.muted),
                        const SizedBox(width: 5),
                        Text(
                          item.scheduledDate.isEmpty
                              ? 'Unscheduled'
                              : item.scheduledDate,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Zc.inkSoft,
                          ),
                        ),
                        const Spacer(),
                        if (item.error.isNotEmpty)
                          const Tooltip(
                            message: 'This item failed - open it to requeue',
                            child: Icon(Icons.error_outline_rounded,
                                size: 15, color: Zc.danger),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context) {
    if (item.isAudio) {
      return DecoratedBox(
        decoration: const BoxDecoration(gradient: Zc.headerGradient),
        child: const Center(
          child: Icon(Icons.graphic_eq_rounded, color: Zc.gold, size: 30),
        ),
      );
    }
    final String url = item.previewUrl;
    if (url.isEmpty) {
      return const ColoredBox(
        color: Zc.creamDeep,
        child: Center(
          child: Icon(Icons.image_rounded, color: Zc.muted, size: 26),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (BuildContext context, String _) =>
          const ColoredBox(color: Zc.creamDeep),
      errorWidget: (BuildContext context, String _, Object __) =>
          const ColoredBox(
        color: Zc.creamDeep,
        child: Center(
          child: Icon(Icons.broken_image_rounded, color: Zc.muted, size: 24),
        ),
      ),
    );
  }
}
