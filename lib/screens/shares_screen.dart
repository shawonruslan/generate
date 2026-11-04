import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Shared links screen (admin only).
///
/// - List of share links: file name, downloads n/max, expiry, lock icon,
///   enable/disable toggle, delete.
/// - Tap a share for a detail sheet with the full public URL + copy button.
/// - Create flow ([requestNew] / + button): pick a drive file, set options
///   (password, expiry, max downloads), then show the new URL with copy.
class SharesScreen extends StatefulWidget {
  const SharesScreen({super.key});

  /// Wired by the home shell's "+ New" button / FAB.
  static VoidCallback? requestNew;

  @override
  State<SharesScreen> createState() => _SharesScreenState();
}

class _SharesScreenState extends State<SharesScreen> {
  List<ShareLink> _shares = [];
  bool _loading = true;
  String? _error;
  final Map<String, bool> _active = {}; // id -> active (not disabled)

  @override
  void initState() {
    super.initState();
    SharesScreen.requestNew = _onNew;
    _load();
  }

  @override
  void dispose() {
    SharesScreen.requestNew = null;
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
    final shares = await guard(context, () => _session.api.getShares());
    if (!mounted) return;
    if (shares == null) {
      setState(() {
        _loading = false;
        _error = 'Could not load shared links.';
      });
      return;
    }
    setState(() {
      _shares = shares;
      _loading = false;
      for (final s in shares) {
        _active.putIfAbsent(s.id, () => true);
      }
    });
  }

  // ---------------- create flow ----------------

  void _onNew() {
    if (!_isAdmin) return;
    _pickFile();
  }

  Future<void> _pickFile() async {
    var files = _session.drive?.files;
    if (files == null) {
      final data = await guard(context, () => _session.api.getData());
      if (!mounted) return;
      files = data?.files;
    }
    if (files == null || files.isEmpty) {
      showMsg(context, 'No files to share yet.', error: true);
      return;
    }
    final list = files.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final picked = await showDialog<DriveFile>(
      context: context,
      builder: (c) => _FilePickerDialog(files: list),
    );
    if (picked == null || !mounted) return;
    _createShareOptions(picked);
  }

  Future<void> _createShareOptions(DriveFile file) async {
    final pwCtrl = TextEditingController();
    final maxDlCtrl = TextEditingController();
    int expiresHours = 168; // default 7 days like the web app
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('Create share link'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FileTypeIcon(name: file.name, mime: file.type, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(file.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pwCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password (optional, min 4 chars)',
                    hintText: 'leave empty for a public link',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: expiresHours,
                  decoration:
                      const InputDecoration(labelText: 'Expiry'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Never')),
                    DropdownMenuItem(value: 1, child: Text('1 hour')),
                    DropdownMenuItem(value: 24, child: Text('1 day')),
                    DropdownMenuItem(value: 168, child: Text('7 days')),
                    DropdownMenuItem(value: 720, child: Text('30 days')),
                  ],
                  onChanged: (v) => setS(() => expiresHours = v ?? 0),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maxDlCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max downloads (optional)',
                    hintText: 'empty = unlimited',
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
                child: const Text('Create')),
          ],
        ),
      ),
    );
    final pw = pwCtrl.text.trim();
    final maxDl = int.tryParse(maxDlCtrl.text.trim());
    pwCtrl.dispose();
    maxDlCtrl.dispose();
    if (res != true) return;
    if (pw.isNotEmpty && pw.length < 4) {
      showMsg(context, 'Password must be at least 4 characters.', error: true);
      return;
    }
    final created = await guard(context, () => _session.api.createShare(
          fileId: file.id,
          password: pw.isEmpty ? null : pw,
          expiresHours: expiresHours == 0 ? null : expiresHours,
          maxDownloads: maxDl,
        ));
    if (!mounted || created == null) return;
    final url = _session.api.shareUrl(created.id);
    await _showCreatedDialog(url, pw.isNotEmpty);
    await Clipboard.setData(ClipboardData(text: url));
    _load();
  }

  Future<void> _showCreatedDialog(String url, bool protected) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Share link created'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(url,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(protected
                  ? 'This link is password-protected.'
                  : 'This link is public — anyone with the link can download.'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Done')),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              showMsg(context, 'Link copied to clipboard.');
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  // ---------------- row actions ----------------

  Future<void> _toggleActive(ShareLink s) async {
    final now = _active[s.id] ?? true;
    final next = !now;
    // Per worker-api.md the exact patch field is `disabled`.
    final res = await guard(
        context, () => _session.api.patchShare(s.id, {'disabled': !next}));
    if (res != null) {
      setState(() => _active[s.id] = next);
      showMsg(context, next ? 'Link enabled.' : 'Link disabled.');
    }
  }

  Future<void> _delete(ShareLink s) async {
    final ok = await confirmDialog(context,
        title: 'Delete share link',
        message: 'Delete the link for "${s.fileName}"? The file is untouched.');
    if (!ok) return;
    final res = await guard(context, () => _session.api.deleteShare(s.id));
    if (res != null) {
      showMsg(context, 'Link deleted.');
      _load();
    }
  }

  void _showDetail(ShareLink s) {
    final url = _session.api.shareUrl(s.id);
    final active = _active[s.id] ?? true;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) {
        final night = Theme.of(c).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.fileName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    if (!active)
                      const Chip(label: Text('disabled'),
                          visualDensity: VisualDensity.compact),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(url,
                    style: TextStyle(
                        color: night
                            ? AppColors.nightMuted
                            : AppColors.dayMuted)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _detailStat('Downloads',
                        '${s.dl}${s.max != null ? ' / ${s.max}' : ''}'),
                    _detailStat('Expires',
                        s.exp == null || s.exp == 0
                            ? 'Never'
                            : formatDateTime(s.exp!)),
                    _detailStat('Created', timeAgo(s.createdAt)),
                    _detailStat(
                        'Protection', s.hasPw ? 'Password' : 'Public'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: url));
                          showMsg(context, 'Link copied to clipboard.');
                          Navigator.pop(c);
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy link'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(c);
                          _delete(s);
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const EmptyView(
          icon: Icons.link_outlined,
          message: 'Shared links are admin only.');
    }
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    if (_loading) return const LoadingView(label: 'Loading shared links…');
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (_shares.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const EmptyView(
              icon: Icons.link_outlined, message: 'No share links yet.'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.add),
            label: const Text('Create share link'),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _shares.length,
        itemBuilder: (c, i) => _shareCard(theme, night, _shares[i]),
      ),
    );
  }

  Widget _shareCard(ThemeData theme, bool night, ShareLink s) {
    final active = _active[s.id] ?? true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(s),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              FileTypeIcon(
                  name: s.fileName,
                  mime: guessMime(s.fileName),
                  size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: active
                                      ? null
                                      : (night
                                          ? AppColors.nightMuted
                                          : AppColors.dayMuted))),
                        ),
                        if (s.hasPw)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.lock_outline, size: 16),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${s.dl}${s.max != null ? ' / ${s.max}' : ''} downloads · ${s.exp == null || s.exp == 0 ? 'Never expires' : 'Expires ${formatDateTime(s.exp!)}'}',
                      style: TextStyle(
                          fontSize: 12,
                          color: night
                              ? AppColors.nightMuted
                              : AppColors.dayMuted),
                    ),
                    Text('Created ${timeAgo(s.createdAt)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: night
                                ? AppColors.nightMuted
                                : AppColors.dayMuted)),
                  ],
                ),
              ),
              if (!active)
                const Chip(
                    label: Text('disabled'),
                    visualDensity: VisualDensity.compact),
              Switch(
                value: active,
                onChanged: (_) => _toggleActive(s),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Delete link',
                onPressed: () => _delete(s),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog for picking a drive file to share, with a search field.
class _FilePickerDialog extends StatefulWidget {
  final List<DriveFile> files;
  const _FilePickerDialog({required this.files});

  @override
  State<_FilePickerDialog> createState() => _FilePickerDialogState();
}

class _FilePickerDialogState extends State<_FilePickerDialog> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final shown = _q.isEmpty
        ? widget.files
        : widget.files
            .where((f) => f.name.toLowerCase().contains(_q))
            .toList();
    return AlertDialog(
      title: const Text('Pick a file to share'),
      content: SizedBox(
        width: 460,
        height: 440,
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Search files…',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? const EmptyView(
                      icon: Icons.search_off_outlined,
                      message: 'No files match.')
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (c, i) {
                        final f = shown[i];
                        return ListTile(
                          dense: true,
                          leading: FileTypeIcon(
                              name: f.name, mime: f.type, size: 32),
                          title: Text(f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(formatBytes(f.size),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: night
                                      ? AppColors.nightMuted
                                      : AppColors.dayMuted)),
                          onTap: () => Navigator.pop(c, f),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
      ],
    );
  }
}
