import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Announcements screen (admin management).
///
/// Active announcements are also embedded in every GET /api/data response, so
/// all users see them — no extra sync work is needed here.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  /// Wired by the home shell's "+ New" button / FAB.
  static VoidCallback? requestNew;

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Announcement> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    AnnouncementsScreen.requestNew = _onNew;
    _load();
  }

  @override
  void dispose() {
    AnnouncementsScreen.requestNew = null;
    super.dispose();
  }

  SessionProvider get _session =>
      Provider.of<SessionProvider>(context, listen: false);
  bool get _isAdmin => _session.isAdmin;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final items = await guard(context, () => _session.api.getAnnouncements());
    if (!mounted) return;
    if (items == null) {
      setState(() {
        _loading = false;
        _error = 'Could not load announcements.';
      });
      return;
    }
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  // ---------------- create ----------------

  void _onNew() {
    if (!_isAdmin) return;
    _showCreateDialog();
  }

  Future<void> _showCreateDialog() async {
    final textCtrl = TextEditingController();
    final expCtrl = TextEditingController();
    String type = 'info';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('New announcement'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: textCtrl,
                  maxLength: 300,
                  maxLines: 3,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'What should everyone know?',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration:
                      const InputDecoration(labelText: 'Type'),
                  items: _types.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Row(
                              children: [
                                _typeDot(e.value),
                                const SizedBox(width: 8),
                                Text(e.key[0].toUpperCase() +
                                    e.key.substring(1)),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setS(() => type = v ?? 'info'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: expCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Expires after (hours, optional)',
                    hintText: 'empty = no expiry (max 8760)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Post')),
          ],
        ),
      ),
    );
    final text = textCtrl.text.trim();
    final expText = expCtrl.text.trim();
    textCtrl.dispose();
    expCtrl.dispose();
    if (ok != true) return;
    if (text.isEmpty) {
      showMsg(context, 'Announcement text is required.', error: true);
      return;
    }
    if (text.length > 300) {
      showMsg(context, 'Announcement must be 300 characters or less.',
          error: true);
      return;
    }
    int? expiresHours;
    if (expText.isNotEmpty) {
      final h = int.tryParse(expText);
      if (h == null || h < 0 || h > 8760) {
        showMsg(context, 'Expiry must be a number between 0 and 8760.',
            error: true);
        return;
      }
      if (h > 0) expiresHours = h;
    }
    final created = await guard(context, () => _session.api.createAnnouncement(
          text: text,
          type: type,
          expiresHours: expiresHours,
        ));
    if (created != null) {
      showMsg(context, 'Announcement posted.');
      _load();
    }
  }

  // ---------------- row actions ----------------

  Future<void> _toggleActive(Announcement a) async {
    final next = !(a.active ?? true);
    final res = await guard(context,
        () => _session.api.setAnnouncementActive(id: a.id, active: next));
    if (res != null) {
      showMsg(context, next ? 'Announcement activated.' : 'Announcement deactivated.');
      _load();
    }
  }

  Future<void> _delete(Announcement a) async {
    final ok = await confirmDialog(context,
        title: 'Delete announcement',
        message: 'Delete this announcement for everyone?');
    if (!ok) return;
    final res =
        await guard(context, () => _session.api.deleteAnnouncement(a.id));
    if (res != null) {
      showMsg(context, 'Announcement deleted.');
      _load();
    }
  }

  // ---------------- type styling ----------------

  static const Map<String, Color> _types = {
    'info': AppColors.brandLight,
    'success': AppColors.okLight,
    'warning': AppColors.warn,
    'urgent': AppColors.dangerLight,
  };

  static Widget _typeDot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _typeChip(String type) {
    final color = _types[type] ?? _types['info']!;
    final label = type.isEmpty
        ? 'Info'
        : type[0].toUpperCase() + type.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _typeDot(color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
        ],
      ),
    );
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const EmptyView(
          icon: Icons.campaign_outlined,
          message: 'Announcements are admin only.');
    }
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    if (_loading) return const LoadingView(label: 'Loading announcements…');
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const EmptyView(
              icon: Icons.campaign_outlined,
              message: 'No announcements yet.'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add),
            label: const Text('New announcement'),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (c, i) => _card(theme, night, _items[i]),
      ),
    );
  }

  Widget _card(ThemeData theme, bool night, Announcement a) {
    final active = a.active ?? true;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = a.exp != null && a.exp! > 0 && a.exp! < now;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _typeChip(a.type),
                const SizedBox(width: 8),
                if (expired)
                  Chip(
                    label: const Text('expired'),
                    visualDensity: VisualDensity.compact,
                    labelStyle:
                        TextStyle(color: theme.colorScheme.error),
                  ),
                if (!active && !expired)
                  Chip(
                    label: const Text('inactive'),
                    visualDensity: VisualDensity.compact,
                    labelStyle: TextStyle(color: muted),
                  ),
                const Spacer(),
                Switch(
                  value: active,
                  onChanged: (_) => _toggleActive(a),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete announcement',
                  onPressed: () => _delete(a),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(a.text, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            Text(
              'Posted ${timeAgo(a.createdAt)}'
              '${a.exp != null && a.exp! > 0 ? ' · expires ${formatDateTime(a.exp!)}' : ' · no expiry'}',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
