import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/dhaka_time.dart';
import '../../data/models.dart';
import '../../domain/upload_errors.dart';
import 'common.dart';
import 'fa.dart';

/// Item thumbnail used by cards, pin rows, failed rows and the details page.
/// Mirrors `itemThumbHtml` / `failedThumbHtml`: sets -> grid of slots, video -> thumb,
/// audio -> vinyl placeholder, image -> file.
class ItemThumb extends StatelessWidget {
  const ItemThumb(this.item, {super.key, this.width, this.height, this.radius = 12, this.showBadge = true});
  final QueueItem item;
  final double? width;
  final double? height;
  final double radius;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget inner;
    if (item.isMp3) {
      inner = Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [p.ink, p.ink2], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Center(child: _Vinyl(size: (width ?? 120) * 0.5)),
      );
    } else if (item.isSetType) {
      final slots = item.setSlots;
      inner = _SlotGrid(urls: slots.map(item.slotUrl).toList(), cols: slots.length == 2 ? 2 : (slots.length == 4 ? 2 : 3));
    } else if (item.isVideoType) {
      inner = NetImage(item.thumbUrl, fit: BoxFit.cover, fallbackIcon: 'fa-video');
    } else {
      inner = NetImage(item.fileUrl, fit: BoxFit.cover);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(fit: StackFit.expand, children: [
          inner,
          if (showBadge && (item.isSetType || item.isVideoType))
            Positioned(
              left: 8,
              top: 8,
              child: Pill(item.typeShort, icon: item.typeShortIcon, small: true, color: Colors.black.withValues(alpha: 0.65), fg: Colors.white),
            ),
        ]),
      ),
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({required this.urls, required this.cols});
  final List<String> urls;
  final int cols;
  @override
  Widget build(BuildContext context) {
    final rows = (urls.length / cols).ceil();
    return Column(
      children: List.generate(rows, (r) {
        return Expanded(
          child: Row(
            children: List.generate(cols, (c) {
              final i = r * cols + c;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: i < urls.length ? NetImage(urls[i], fit: BoxFit.cover) : const SizedBox(),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _Vinyl extends StatefulWidget {
  const _Vinyl({required this.size});
  final double size;
  @override
  State<_Vinyl> createState() => _VinylState();
}

class _VinylState extends State<_Vinyl> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = widget.size.clamp(36.0, 160.0).toDouble();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: s * 0.9,
        height: s * 0.9,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(colors: [p.primary, p.accent]),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        alignment: Alignment.center,
        child: Fa('fa-music', size: s * 0.36, color: p.onPrimary),
      ),
      Transform.translate(
        offset: Offset(-s * 0.25, 0),
        child: RotationTransition(
          turns: _c,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Color(0xff3a3a3a), Color(0xff111111), Color(0xff2a2a2a), Color(0xff0a0a0a)], stops: [0.3, 0.5, 0.75, 1]),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)],
            ),
            alignment: Alignment.center,
            child: Container(
              width: s * 0.36,
              height: s * 0.36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.primary),
              alignment: Alignment.center,
              child: Container(width: s * 0.08, height: s * 0.08, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xff111111))),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Colour of a status ribbon (`.card-status.<status>`).
Color statusColor(String status, dynamic pal) {
  switch (status.toLowerCase()) {
    case 'uploaded':
      return const Color(0xff22c55e);
    case 'processing':
      return const Color(0xff38bdf8);
    case 'failed':
    case 'error':
      return const Color(0xffef4444);
    default:
      return const Color(0xfff59e0b);
  }
}

/// Queue grid card (`renderUploadQueue`): media, status ribbon, "No metadata" flag,
/// title, size / category / added stamp, tags, Edit / Delete.
class QueueCard extends StatefulWidget {
  const QueueCard(this.item, {super.key, required this.onOpen, required this.onDelete, this.compact = false});
  final QueueItem item;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final bool compact;

  @override
  State<QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends State<QueueCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final it = widget.item;
    final status = it.status;
    final t = it.timeMs;
    final noMeta = status == 'queued' && !it.hasRequiredMetadata;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hover ? 1.015 : 1,
        duration: const Duration(milliseconds: 160),
        child: GlassCard(
          padding: EdgeInsets.zero,
          onTap: widget.onOpen,
          glow: _hover,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: widget.compact ? 1.35 : 1.15,
              child: Stack(fit: StackFit.expand, children: [
                ItemThumb(it, radius: 0),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Pill(status, small: true, color: statusColor(status, p), fg: Colors.white),
                ),
                if (noMeta)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Tooltip(
                      message: 'Missing: ${it.metadataMissingFields.join(', ')} - bot will skip this file',
                      child: Pill('No metadata', icon: 'fa-tags', small: true, color: const Color(0xffef4444), fg: Colors.white),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: p.text)),
                const SizedBox(height: 6),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  _info('fa-hdd', formatBytes(it.size), p),
                  _info('fa-folder', it.category.isEmpty ? '-' : it.category, p),
                  if (t != null) Tooltip(message: 'Added (Dhaka time)', child: _info('fa-calendar-plus', fmtDhakaStamp(t), p)),
                ]),
                if (it.tagList.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 22,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [for (final tg in it.tagList) Padding(padding: const EdgeInsets.only(right: 6), child: Pill(tg, small: true, color: p.tintChip, fg: p.text))],
                    ),
                  ),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(children: [
                Expanded(child: ZButton('Edit', icon: 'fa-edit', small: true, kind: ZBtnKind.soft, onPressed: widget.onOpen)),
                const SizedBox(width: 8),
                Expanded(child: ZButton('Delete', icon: 'fa-trash-alt', small: true, kind: ZBtnKind.danger, onPressed: widget.onDelete)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _info(String icon, String text, dynamic p) => Row(mainAxisSize: MainAxisSize.min, children: [
        Fa(icon, size: 11, color: p.muted),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 11.5, color: p.muted, fontWeight: FontWeight.w600)),
      ]);
}

/// Failed uploads row (`renderFailedUploads`).
class FailedRow extends StatefulWidget {
  const FailedRow(this.item, {super.key, required this.account, required this.onRequeue, required this.onDetails, required this.onDelete});
  final QueueItem item;
  final String account;
  final VoidCallback onRequeue;
  final VoidCallback onDetails;
  final VoidCallback onDelete;

  @override
  State<FailedRow> createState() => _FailedRowState();
}

class _FailedRowState extends State<FailedRow> {
  bool _raw = false;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final it = widget.item;
    final label = kSetTypeMeta[it.contentType]?.label ?? kVideoTypeMeta[it.contentType]?.label ?? (it.contentType == 'RINGTONE' ? 'Audio' : 'Wallpaper');
    final icon = it.isMp3 ? 'fa-music' : (it.isSetType || it.isVideoType ? it.typeShortIcon : 'fa-image');
    final hint = explainUploadError(it.error);
    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderColor: p.danger.withValues(alpha: 0.35),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 620;
        final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(it.displayTitle, style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Pill(label, icon: icon, small: true, color: p.tintChip, fg: p.text),
            Pill(widget.account.toUpperCase(), small: true, outline: true),
            if (it.failedAt != null) Text('failed ${fmtDhakaStamp(it.failedAt)}', style: TextStyle(fontSize: 11.5, color: p.muted)),
            if (it.name.isNotEmpty) Text(it.name, style: TextStyle(fontSize: 11.5, color: p.muted), overflow: TextOverflow.ellipsis),
          ]),
          const SizedBox(height: 6),
          Text(hint, style: TextStyle(fontSize: 12.5, color: p.danger, fontWeight: FontWeight.w600)),
          if (it.error.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _raw = !_raw),
              child: Text(_raw ? 'Hide full error' : 'Show full error', style: TextStyle(fontSize: 11.5, color: p.info, decoration: TextDecoration.underline)),
            ),
            if (_raw)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(it.error, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: p.text)),
              ),
          ],
        ]);
        final actions = Wrap(spacing: 6, runSpacing: 6, children: [
          ZButton('Requeue', icon: 'fa-redo', small: true, kind: ZBtnKind.success, onPressed: widget.onRequeue),
          ZButton('Details', icon: 'fa-info-circle', small: true, kind: ZBtnKind.soft, onPressed: widget.onDetails),
          ZButton('Delete', icon: 'fa-trash-alt', small: true, kind: ZBtnKind.danger, onPressed: widget.onDelete),
        ]);
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [ItemThumb(it, width: 64, height: 64), const SizedBox(width: 12), Expanded(child: info)]),
            const SizedBox(height: 10),
            actions,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ItemThumb(it, width: 72, height: 72),
          const SizedBox(width: 14),
          Expanded(child: info),
          const SizedBox(width: 12),
          actions,
        ]);
      }),
    );
  }
}
