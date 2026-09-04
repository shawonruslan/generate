import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/queue_item.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'phone_preview.dart';
import 'stat_card.dart';

/// The unified editor: live phone mock-up on the left, metadata on the right.
Future<void> showItemEditor(BuildContext context, QueueItem item) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x99120F07),
    builder: (BuildContext context) => ItemEditorDialog(item: item),
  );
}

class ItemEditorDialog extends StatefulWidget {
  const ItemEditorDialog({super.key, required this.item});

  final QueueItem item;

  @override
  State<ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<ItemEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _tags;
  late final TextEditingController _category;
  late final TextEditingController _description;
  DateTime? _scheduled;
  int _slotIndex = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final QueueItem item = widget.item;
    _title = TextEditingController(text: item.title);
    _tags = TextEditingController(text: item.tags);
    _category = TextEditingController(text: item.category);
    _description = TextEditingController(text: item.description);
    if (item.scheduledDate.isNotEmpty) {
      _scheduled = DateTime.tryParse(item.scheduledDate);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _category.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final AppState state = context.read<AppState>();
    await _run(
      () => state.updateItem(widget.item.id, <String, dynamic>{
        'title': _title.text.trim(),
        'tags': _tags.text.trim(),
        'category': _category.text.trim(),
        'description': _description.text.trim(),
        'scheduledDate': _scheduled == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_scheduled!),
      }),
      'Changes saved',
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _scheduled ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _scheduled = picked);
  }

  @override
  Widget build(BuildContext context) {
    final QueueItem item = widget.item;
    final List<PreviewFrame> frames = item.previewFrames;
    final Size screen = MediaQuery.sizeOf(context);
    final bool wide = screen.width > 900;

    final Widget preview = Container(
      padding: const EdgeInsets.all(22),
      decoration: const BoxDecoration(gradient: Zc.headerGradient),
      child: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            PhonePreview(
              frames: frames,
              autoPlay: frames.length > 1,
              baseWidth: wide ? 244 : 210,
              audioLabel: item.isAudio ? (item.name.isEmpty ? item.displayTitle : item.name) : null,
              onFrameChanged: (int index) => setState(() => _slotIndex = index),
            ),
            if (item.isSet && item.slots.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: List<Widget>.generate(item.slots.length, (int index) {
                  final String slot = item.slots[index];
                  final bool filled = item.slotUrl(slot).isNotEmpty;
                  final bool active = index == _slotIndex && filled;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: active
                          ? Zc.gold
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: filled
                            ? Zc.goldDeep
                            : Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      slot.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w900,
                        color: active
                            ? Zc.ink
                            : (filled ? Zc.gold : Colors.white54),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );

    final Widget form = Padding(
      padding: const EdgeInsets.all(22),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                TagPill(
                  text: item.typeLabel,
                  color: Zc.goldDeep,
                  icon: Zc.typeIcon(item.contentType),
                ),
                const SizedBox(width: 6),
                TagPill(text: item.status, color: Zc.statusColor(item.status)),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'ITEM TITLE'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'SEARCH TAGS',
                helperText: 'Comma separated',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'MAIN CATEGORY'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 5,
              decoration:
                  const InputDecoration(labelText: 'PUBLISHING DESCRIPTION'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'SCHEDULED UPLOAD DATE',
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.calendar_month_rounded,
                        size: 16, color: Zc.goldDeep),
                    const SizedBox(width: 8),
                    Text(
                      _scheduled == null
                          ? 'Not scheduled'
                          : DateFormat('dd MMM yyyy').format(_scheduled!),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    if (_scheduled != null)
                      TextButton(
                        onPressed: () => setState(() => _scheduled = null),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ),
            ),
            if (item.error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Zc.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Zc.danger.withValues(alpha: 0.3)),
                ),
                child: Text(
                  item.error,
                  style: const TextStyle(
                      fontSize: 11.5, color: Zc.danger, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ElevatedButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save Changes'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => context.read<AppState>().requeueItem(item.id),
                            'Item requeued',
                          ),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Requeue'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () async {
                              final int copied = await context
                                  .read<AppState>()
                                  .copyToOtherAccounts(item);
                              if (copied == 0) {
                                throw Exception('no account accepted the copy');
                              }
                            },
                            'Copied to the other accounts',
                          ),
                  icon: const Icon(Icons.copy_all_rounded, size: 16),
                  label: const Text('Copy to Other Accounts'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Zc.danger,
                    side: BorderSide(
                        color: Zc.danger.withValues(alpha: 0.4), width: 1.5),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: wide ? 940 : screen.width,
        height: (screen.height * 0.86).clamp(420.0, 780.0),
        child: wide
            ? Row(
                children: <Widget>[
                  SizedBox(width: 340, child: preview),
                  const VerticalDivider(width: 1),
                  Expanded(child: form),
                ],
              )
            : ListView(
                children: <Widget>[
                  SizedBox(height: 460, child: preview),
                  form,
                ],
              ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete this item?'),
        content: const Text(
          'The queue row is removed from the database. Files already uploaded '
          'to R2 stay where they are.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run(
      () => context.read<AppState>().deleteItem(widget.item.id),
      'Item deleted',
    );
    if (mounted) Navigator.of(context).pop();
  }
}
