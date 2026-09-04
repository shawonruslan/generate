import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/queue_item.dart';
import '../models/schedule.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'phone_preview.dart';
import 'stat_card.dart';
import 'ui.dart';

/// Opens the content modal (phone mock-up + metadata editor).
Future<void> showItemEditor(BuildContext context, QueueItem item) {
  return showDialog<void>(
    context: context,
    barrierColor: Zc.ink.withOpacity(0.55),
    builder: (BuildContext ctx) => ItemEditorDialog(itemId: item.id),
  );
}

class ItemEditorDialog extends StatefulWidget {
  const ItemEditorDialog({super.key, required this.itemId});

  final String itemId;

  @override
  State<ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<ItemEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _tags;
  late final TextEditingController _category;
  late final TextEditingController _description;
  String _scheduled = '';
  bool _busy = false;
  bool _seeded = false;
  AudioPlayer? _player;
  bool _playing = false;

  QueueItem? _find(AppState state) {
    for (final QueueItem i in state.items) {
      if (i.id == widget.itemId) return i;
    }
    return null;
  }

  void _seed(QueueItem item) {
    if (_seeded) return;
    _seeded = true;
    _title = TextEditingController(text: item.title);
    _tags = TextEditingController(text: item.tags);
    _category = TextEditingController(text: item.category);
    _description = TextEditingController(text: item.description);
    _scheduled = item.scheduledDate;
  }

  @override
  void dispose() {
    if (_seeded) {
      _title.dispose();
      _tags.dispose();
      _category.dispose();
      _description.dispose();
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio(QueueItem item) async {
    _player ??= AudioPlayer();
    if (_playing) {
      await _player!.stop();
      setState(() => _playing = false);
      return;
    }
    try {
      await _player!.play(UrlSource(item.fileUrl));
      setState(() => _playing = true);
      _player!.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (e) {
      if (mounted) showSnack(context, 'Cannot play audio: $e', error: true);
    }
  }

  Future<void> _run(Future<void> Function() job, String done) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(AppState state, QueueItem item) => _run(() async {
        await state.updateItem(item.id, <String, dynamic>{
          'title': _title.text.trim(),
          'tags': _tags.text.trim(),
          'category': _category.text.trim().toUpperCase(),
          'description': _description.text.trim(),
          'scheduledDate': _scheduled.isEmpty ? null : _scheduled,
        });
      }, 'Saved');

  Future<void> _pickDate(AppState state) async {
    final DateTime today = state.todayDhaka;
    final DateTime initial = parseDateKey(_scheduled) ?? today;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      helpText: 'Pin to a day (Dhaka time)',
    );
    if (picked != null) setState(() => _scheduled = dateKeyOf(picked));
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final QueueItem? item = _find(state);
    if (item == null) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Text('This item was removed from the queue.'),
        ),
      );
    }
    _seed(item);

    final double width = MediaQuery.sizeOf(context).width;
    final bool wide = width >= 860;

    final Widget preview = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PhonePreview(
          key: ValueKey<String>('prev-${item.id}'),
          frames: item.previewFrames,
          autoPlay: item.isSet,
          baseWidth: wide ? 250 : 200,
          audioLabel: item.isAudio ? item.displayTitle : null,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            if (item.isAudio)
              GradientButton(
                label: _playing ? 'Stop' : 'Play ringtone',
                icon: _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                dense: true,
                gradient: const LinearGradient(
                    colors: <Color>[Zc.purple, Color(0xFF5E35B1)]),
                foreground: Colors.white,
                onPressed: () => _toggleAudio(item),
              ),
            if (item.fileUrl.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(item.fileUrl),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: Text(item.isVideo ? 'Open video' : 'Open file'),
              ),
          ],
        ),
      ],
    );

    final Widget form = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          item.displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Zc.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Zc.muted,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            TagPill(
              text: item.status.toUpperCase(),
              color: Zc.statusColor(item.status),
              filled: true,
            ),
            TagPill(
              text: item.typeLabel,
              color: Zc.typeColor(item.contentType),
              icon: Zc.typeIcon(item.contentType),
            ),
            if (item.category.isNotEmpty)
              TagPill(text: item.category, color: Zc.inkSoft),
            if (item.size > 0)
              TagPill(text: item.sizeLabel, color: Zc.muted),
            if (item.width > 0)
              TagPill(text: '${item.width}x${item.height}', color: Zc.muted),
            if (item.isSet)
              TagPill(
                text: '${item.filledSlots.length}/${item.slots.length} slots',
                color: Zc.info,
              ),
            if (item.distributedTo.isNotEmpty)
              TagPill(
                  text: 'via ${item.distributedTo}',
                  color: Zc.okDeep,
                  icon: Icons.hub_rounded),
          ],
        ),
        if (item.error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Zc.danger.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Zc.danger.withOpacity(0.3)),
            ),
            child: Text(
              item.error,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Zc.danger,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tags,
          decoration: const InputDecoration(
            labelText: 'Tags (comma separated)',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _category,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Category'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _busy ? null : () => _pickDate(state),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Scheduled date (pinned)',
                    suffixIcon: Icon(Icons.event_rounded, size: 18),
                  ),
                  child: Text(
                    _scheduled.isEmpty ? 'Auto (rolling cycle)' : _scheduled,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _scheduled.isEmpty ? Zc.muted : Zc.ink,
                    ),
                  ),
                ),
              ),
            ),
            if (_scheduled.isNotEmpty)
              IconButton(
                tooltip: 'Unpin',
                onPressed: () => setState(() => _scheduled = ''),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            GradientButton(
              label: 'Save',
              icon: Icons.save_rounded,
              dense: true,
              busy: _busy,
              onPressed: () => _save(state, item),
            ),
            if (!item.isQueued)
              GradientButton(
                label: 'Requeue',
                icon: Icons.replay_rounded,
                dense: true,
                gradient: Zc.successGradient,
                onPressed: _busy
                    ? null
                    : () => _run(() => state.requeueItem(item.id), 'Requeued'),
              ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        final int n = await state.copyToOtherAccounts(item);
                        if (n == 0) throw Exception('No account reachable');
                      }, 'Copied to the other accounts'),
              icon: const Icon(Icons.copy_all_rounded, size: 15),
              label: const Text('Copy to other accounts'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Zc.danger,
                side: BorderSide(color: Zc.danger.withOpacity(0.5), width: 1.5),
              ),
              onPressed: _busy
                  ? null
                  : () async {
                      final bool ok = await confirmDialog(
                        context,
                        title: 'Delete this item?',
                        message:
                            '"${item.displayTitle}" will be removed from ${state.account.label}. '
                            'The media file stays in R2.',
                        confirmLabel: 'Delete',
                        danger: true,
                      );
                      if (!ok || !mounted) return;
                      await _run(() => state.deleteItem(item.id), 'Deleted');
                      if (mounted) Navigator.of(context).pop();
                    },
              icon: const Icon(Icons.delete_outline_rounded, size: 15),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
    );

    return Dialog(
      insetPadding: EdgeInsets.all(wide ? 32 : 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 980 : 560, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
              decoration: const BoxDecoration(
                gradient: Zc.headerGradient,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Zc.typeIcon(item.contentType), color: Zc.ink, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Content preview & metadata',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Zc.ink,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Zc.ink),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(width: 330, child: preview),
                          const SizedBox(width: 22),
                          Expanded(child: form),
                        ],
                      )
                    : Column(
                        children: <Widget>[
                          preview,
                          const SizedBox(height: 18),
                          form,
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
