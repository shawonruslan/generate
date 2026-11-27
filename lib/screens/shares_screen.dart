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
        _active.putIfAbsent(s.id, () => !s.disabled);
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
                  value: expiresHours,
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
    final res = await guard(context, () async {
      await _session.api.patchShare(s.id, {'disabled': !next});
      return true;
    });
    if (res == true) {
      setState(() => _active[s.id] = next);
      showMsg(context, next ? 'Link enabled.' : 'Link disabled.');
    }
  }

  Future<void> _delete(ShareLink s) async {
    final ok = await confirmDialog(context,
        title: 'Delete share link',
        message: 'Delete the link for "${s.fileName}"? The file is untouched.');
    if (!ok) return;
    final res = await guard(context, () async {
      await _session.api.deleteShare(s.id);
      return true;
    });
    if (res == true) {
      showMsg(context, 'Link deleted.');
      _load();
    }
  }

  void _showDetail(ShareLink s) {
    final url = _session.api.shareUrl(s.id);
    final active = _active[s.id] ?? !s.disabled;
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
                    _detailStat('Created', formatDate(s.createdAt)),
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
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final line = night ? AppColors.nightLine : AppColors.dayLine;
    final line2 = night ? AppColors.nightLine2 : const Color(0xFFEDEAE2);
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Shared links',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                    '${_shares.length} link${_shares.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 13, color: muted)),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: _shares.isEmpty
                  ? _emptyState(night)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Text('FILE',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.04 * 12,
                                  color: muted)),
                        ),
                        Divider(height: 1, color: line),
                        for (var i = 0; i < _shares.length; i++) ...[
                          _shareRow(theme, night, _shares[i]),
                          if (i < _shares.length - 1)
                            Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                                color: line2),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(bool night) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.share, size: 44, color: muted),
          const SizedBox(height: 12),
          const Text('No shared links',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Right-click a file → "Share link" to create a public link (optional password).',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.add),
            label: const Text('Create share link'),
          ),
        ],
      ),
    );
  }

  Widget _protPill(bool night, bool hasPw) {
    if (hasPw) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: night ? AppColors.nightSide2 : const Color(0xFFF4F2ED),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 11),
            SizedBox(width: 3),
            Text('Password',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public, size: 11, color: Color(0xFFB45309)),
          SizedBox(width: 3),
          Text('Public',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB45309))),
        ],
      ),
    );
  }

  Widget _shareRow(ThemeData theme, bool night, ShareLink s) {
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final active = _active[s.id] ?? !s.disabled;
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = s.exp != null && s.exp! > 0 && s.exp! < now;
    final full = s.max != null && s.dl >= s.max!;
    final String? status = s.fileName.isEmpty
        ? 'File deleted'
        : !active
            ? 'Disabled'
            : expired
                ? 'Expired'
                : full
                    ? 'Limit reached'
                    : null;
    final url = (s.url != null && s.url!.isNotEmpty)
        ? s.url!
        : _session.api.shareUrl(s.id);
    return InkWell(
      onTap: () => _showDetail(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            FileTypeIcon(
                name: s.fileName, mime: guessMime(s.fileName), size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            s.fileName.isEmpty
                                ? '(deleted file)'
                                : s.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                      ),
                      if (s.hasPw)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child:
                              Icon(Icons.lock_outline, size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    status ?? 'Created ${formatDate(s.createdAt)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: status != null
                            ? theme.colorScheme.error
                            : muted),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _protPill(night, s.hasPw),
                      Text(
                          '${s.dl}${s.max != null ? ' / ${s.max}' : ''} downloads',
                          style: TextStyle(fontSize: 12, color: muted)),
                      Text(
                          s.exp == null || s.exp == 0
                              ? 'Never expires'
                              : 'Expires ${formatDateTime(s.exp!)}',
                          style: TextStyle(fontSize: 12, color: muted)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                showMsg(context, 'Link copied.');
              },
            ),
            IconButton(
              tooltip: active ? 'Disable' : 'Enable',
              icon: Icon(
                  active ? Icons.toggle_on : Icons.toggle_off,
                  size: 26,
                  color: active
                      ? (night
                          ? AppColors.brandDark
                          : AppColors.brandLight)
                      : muted),
              onPressed: () => _toggleActive(s),
            ),
            IconButton(
              tooltip: 'Delete link',
              icon: Icon(Icons.delete_outline,
                  size: 20, color: theme.colorScheme.error),
              onPressed: () => _delete(s),
            ),
          ],
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
