import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/nav.dart';
import '../dialogs/asset_details.dart';
import '../dialogs/purge_overlay.dart';
import 'common.dart';
import 'queue_card.dart';

/// Single-item delete flow (`deleteQueueItem`).
Future<void> deleteQueueItemFlow(BuildContext context, QueueItem item) async {
  final app = context.app;
  final ok = await confirmDialog(
    context,
    'Permanently delete "${item.name.isNotEmpty ? item.name : item.id}"?\n\nThis removes it from the queue AND deletes its file(s) from R2 storage.',
    title: 'Delete item',
    okLabel: 'Delete',
    danger: true,
  );
  if (!ok || !context.mounted) return;
  await runPurge(context, account: app.activeProject, ids: [item.id]);
}

/// "Failed Uploads" section (`renderFailedUploads`). Home hides it when empty; Upload always shows it.
class FailedSection extends StatefulWidget {
  const FailedSection({super.key, this.alwaysShow = false});
  final bool alwaysShow;
  @override
  State<FailedSection> createState() => _FailedSectionState();
}

class _FailedSectionState extends State<FailedSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final failed = app.failedItems
      ..sort((a, b) {
        final c = ((b.failedAt ?? 0).compareTo(a.failedAt ?? 0));
        return c != 0 ? c : b.id.compareTo(a.id);
      });
    if (failed.isEmpty && !widget.alwaysShow) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
          SectionTitle('Failed Uploads', icon: 'fa-triangle-exclamation', trailing: Pill('${failed.length}', icon: 'fa-xmark', small: true, color: p.danger.withValues(alpha: 0.15), fg: p.danger)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            ZButton('Requeue all', icon: 'fa-rotate-right', small: true, kind: ZBtnKind.success, busy: _busy, onPressed: failed.isEmpty ? null : () => _all(context, failed, false)),
            const SizedBox(width: 8),
            ZButton('Delete all failed', icon: 'fa-trash-alt', small: true, kind: ZBtnKind.danger, busy: _busy, onPressed: failed.isEmpty ? null : () => _all(context, failed, true)),
          ]),
        ]),
        const SizedBox(height: 14),
        if (failed.isEmpty)
          EmptyNote('No failed uploads in ${app.accountUpper(app.activeProject)}. Everything is healthy.', icon: 'fa-circle-check')
        else
          for (final it in failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FailedRow(
                it,
                account: app.activeProject,
                onRequeue: () async {
                  try {
                    await app.repo.requeueItemsById(app.activeProject, [it.id]);
                    app.showToast('Requeued "${it.title.trim().isNotEmpty ? it.title.trim() : (it.name.isNotEmpty ? it.name : 'item')}"', 'ok');
                  } catch (e) {
                    app.showToast('Requeue failed: ${e.toString().replaceFirst('Exception: ', '')}', 'err');
                  }
                },
                onDetails: () => openAssetDetails(context, it.id),
                onDelete: () => deleteQueueItemFlow(context, it),
              ),
            ),
      ]),
    );
  }

  Future<void> _all(BuildContext context, List<QueueItem> failed, bool delete) async {
    final app = context.app;
    if (delete) {
      final ok = await confirmDialog(context, 'Permanently delete all ${failed.length} failed item(s) from ${app.accountUpper(app.activeProject)} (queue + R2 files)? This cannot be undone.', title: 'Delete all failed', okLabel: 'Delete all', danger: true);
      if (!ok || !context.mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (!delete) {
        await app.repo.requeueItemsById(app.activeProject, failed.map((i) => i.id).toList());
        app.showToast('Requeued ${failed.length} item(s)', 'ok');
      } else {
        await runPurge(context, account: app.activeProject, ids: failed.map((i) => i.id).toList(), what: 'failed item(s)');
      }
    } catch (e) {
      app.showToast('Action failed: ${e.toString().replaceFirst('Exception: ', '')}', 'err');
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// "Metadata missing" section (`renderMetadataAlerts`).
class MetaAlertSection extends StatelessWidget {
  const MetaAlertSection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final missing = app.missingMetadataItems;
    final count = missing.length;
    final others = <(String, MetaAlertReport)>[
      for (final k in app.accountKeys)
        if (k != app.activeProject && app.metaAlerts[k] != null && app.metaAlerts[k]!.count > 0) (k, app.metaAlerts[k]!),
    ];
    if (count == 0 && others.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderColor: count > 0 ? p.warn.withValues(alpha: 0.45) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
          SectionTitle('Metadata missing', icon: 'fa-tags', trailing: Pill('$count', small: true, color: p.warn.withValues(alpha: 0.18), fg: p.warn)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            ZButton('Show in queue', icon: 'fa-filter', small: true, kind: ZBtnKind.soft, onPressed: () {
              app.queueFilter.status = 'nometa';
              app.uploadPage = 1;
              app.touch();
              context.read<NavState>().go(AppTab.upload);
            }),
            if (!app.metaNotify) ...[
              const SizedBox(width: 8),
              ZButton('Enable desktop alerts', icon: 'fa-bell', small: true, kind: ZBtnKind.ghost, onPressed: () => app.enableMetaNotify()),
            ],
          ]),
        ]),
        const SizedBox(height: 8),
        Text('These queued files have no title / tags / category. The upload bot skips them until metadata is added (edit here, in the app, or run generator.yml → metadata).', style: TextStyle(fontSize: 12.5, color: p.muted)),
        const SizedBox(height: 12),
        if (count == 0)
          EmptyNote('Every queued file in ${app.accountLabel(app.activeProject)} has metadata.', icon: 'fa-check-circle')
        else ...[
          for (final i in missing.take(12))
            InkWell(
              onTap: () => openAssetDetails(context, i.id),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  ItemThumb(i, width: 40, height: 40, radius: 8, showBadge: false),
                  const SizedBox(width: 10),
                  Expanded(child: Tooltip(message: i.name.isNotEmpty ? i.name : i.id, child: Text(i.displayTitleOrId, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: p.text)))),
                  const SizedBox(width: 10),
                  Text('missing: ${i.metadataMissingFields.join(', ')}', style: TextStyle(fontSize: 12, color: p.warn, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  ZButton('Fix', icon: 'fa-pen', small: true, kind: ZBtnKind.soft, onPressed: () => openAssetDetails(context, i.id)),
                ]),
              ),
            ),
          if (count > 12) Padding(padding: const EdgeInsets.only(top: 4), child: Text('+ ${count - 12} more → use "Show in queue"', style: TextStyle(fontSize: 12, color: p.muted))),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Other accounts (bot report):', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
            for (final (k, a) in others)
              Pill('${app.accountLabel(k)}: ${a.count}', icon: 'fa-database', small: true, color: p.tintChip, fg: p.text, tooltip: 'Reported by the bot ${a.updatedDhaka ?? ''}', onTap: () => app.connectToDatabase(k)),
          ]),
        ],
      ]),
    );
  }
}
