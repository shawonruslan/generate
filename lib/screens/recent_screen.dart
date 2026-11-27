import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Flat list of the most recently uploaded files across all folders
/// (newest first, capped at 100), with the same download/preview
/// actions as the drive screen.
class RecentScreen extends StatefulWidget {
  const RecentScreen({super.key});

  @override
  State<RecentScreen> createState() => _RecentScreenState();
}

enum _ViewMode { list, grid }

class _RecentScreenState extends State<RecentScreen> {
  bool _loading = true;
  String? _error;
  _ViewMode _view = _ViewMode.list;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionProvider>();
    if (session.drive != null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _error = null);
    await guard(context, () => session.refreshDrive());
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (session.drive == null) _error = 'Could not load files.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final drive = session.drive;
    if (_loading && drive == null) {
      return const LoadingView(label: 'Loading recent files…');
    }
    if (drive == null) {
      return ErrorView(
        message: _error ?? 'Could not load files.',
        onRetry: () {
          setState(() {
            _loading = true;
            _error = null;
          });
          _load();
        },
      );
    }
    final files = drive.files.values.toList()
      ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    final top = files.take(100).toList();
    if (top.isEmpty) {
      return const EmptyView(
          icon: Icons.history_outlined, message: 'No files yet');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerRow(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await guard(context, () => session.refreshDrive());
            },
            child: _view == _ViewMode.list
                ? _listView(top)
                : _gridView(top),
          ),
        ),
      ],
    );
  }

  /// "Recent" heading with a small clock icon + list/grid toggle at right.
  Widget _headerRow() {
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        children: [
          Icon(Icons.history, size: 22, color: brand),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Recent',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: _view == _ViewMode.list ? 'Grid view' : 'List view',
            icon: Icon(_view == _ViewMode.list
                ? Icons.grid_view_outlined
                : Icons.view_list_outlined),
            onPressed: () =>
                setState(() => _view = _view == _ViewMode.list
                    ? _ViewMode.grid
                    : _ViewMode.list),
          ),
        ],
      ),
    );
  }

  /// Section divider header ("FILES"), like the drive screen.
  Widget _sectionLabel(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(title.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: theme.hintColor)),
    );
  }

  /// White rounded-16 card containing a table of rows, with a "NAME"
  /// header row in small gray caps and hairline dividers (mirrors Drive).
  Widget _listCard(List<Widget> rows) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: theme.dividerColor.withOpacity(0.25),
              border:
                  Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Text('NAME',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: theme.hintColor)),
          ),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  color: theme.dividerColor.withOpacity(0.6)),
            rows[i],
          ],
        ],
      ),
    );
  }

  /// Blue "v2" version badge with a small circular-arrow icon.
  Widget _verBadge(int ver) {
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: brand.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.autorenew, size: 11, color: brand),
          const SizedBox(width: 3),
          Text('v$ver',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: brand)),
        ],
      ),
    );
  }

  /// Solid blue square download button (white down-arrow) for list rows.
  Widget _dlButton(DriveFile f) {
    final brand = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _downloadFile(f),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: brand,
          borderRadius: BorderRadius.circular(8),
        ),
        child:
            const Icon(Icons.download, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _listView(List<DriveFile> files) {
    return ListView(
      children: [
        _sectionLabel('Files'),
        _listCard([for (final f in files) _fileRow(f)]),
      ],
    );
  }

  Widget _gridView(List<DriveFile> files) {
    const delegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 170,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.92,
    );
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _sectionLabel('Files')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          sliver: SliverGrid.builder(
            gridDelegate: delegate,
            itemCount: files.length,
            itemBuilder: (_, i) => _fileGridTile(files[i]),
          ),
        ),
      ],
    );
  }

  /// File row identical to the drive list row: color tile icon, bold name,
  /// gray "size · relative" caption, blue v2 pill, blue download button,
  /// 3-dot menu at the right edge.
  Widget _fileRow(DriveFile f) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _menu(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            FileTypeIcon(name: f.name, mime: f.type, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (f.isLocked) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.lock,
                            size: 14,
                            color: theme.colorScheme.error),
                      ],
                      if (f.ver > 1 || f.vc > 0) ...[
                        const SizedBox(width: 6),
                        _verBadge(f.ver),
                      ],
                      if (f.shares > 0) ...[
                        const SizedBox(width: 6),
                        Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link,
                                  size: 13,
                                  color: Colors.grey.shade600),
                              const SizedBox(width: 2),
                              Text('${f.shares}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600)),
                            ]),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                      '${formatBytes(f.size)} · ${formatRelativeMs(f.uploadedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: theme.hintColor)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            f.url != null
                ? _dlButton(f)
                : Icon(Icons.lock_outline,
                    size: 18, color: theme.colorScheme.error),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _menu(f),
            ),
          ],
        ),
      ),
    );
  }

  /// File grid tile identical to the drive tile: white rounded-16 card,
  /// large light-gray preview area with the color tile icon centered,
  /// then file name (+ small type icon), gray "size · relative" caption,
  /// 3-dot at the bottom-right.
  Widget _fileGridTile(DriveFile f) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final thumbBg =
        night ? const Color(0xFF1B1B1B) : const Color(0xFFF2F1ED);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _menu(f),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 104,
                  color: thumbBg,
                  child: Center(
                    child: FileTypeIcon(
                        name: f.name, mime: f.type, size: 56),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 34, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            FileTypeIcon(
                                name: f.name, mime: f.type, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(f.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                            '${formatBytes(f.size)} · ${formatRelativeMs(f.uploadedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: theme.hintColor)),
                        if (f.ver > 1 || f.vc > 0 || f.isLocked) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (f.isLocked)
                                Icon(Icons.lock,
                                    size: 13,
                                    color: theme.colorScheme.error),
                              if (f.isLocked && (f.ver > 1 || f.vc > 0))
                                const SizedBox(width: 6),
                              if (f.ver > 1 || f.vc > 0)
                                _verBadge(f.ver),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 6,
              right: 6,
              child: IconButton(
                iconSize: 18,
                icon: const Icon(Icons.more_vert),
                onPressed: () => _menu(f),
              ),
            ),
          ],
        ),
      ),
    );
  }
  String _folderPathText(DriveData drive, String folderId) {
    final names = <String>[];
    var id = folderId;
    var guardN = 0;
    while (id != 'root' && drive.folders.containsKey(id) && guardN++ < 100) {
      final f = drive.folders[id]!;
      names.insert(0, f.name);
      id = f.parent;
    }
    return ['My Drive', ...names].join(' / ');
  }

  // ---------------- context menu ----------------

  void _menu(DriveFile f) {
    final locked = f.url == null;
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: FileTypeIcon(name: f.name, mime: f.type),
              title: Text(f.name,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle:
                  Text('${formatBytes(f.size)} · ${formatRelativeMs(f.uploadedAt)}'),
            ),
            const Divider(height: 1),
            if (locked)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Locked'),
                subtitle: Text((f.locked?['reason'] ??
                        f.locked?['by'] ??
                        'Locked by admin')
                    .toString()),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(c);
                  _downloadFile(f);
                },
              ),
              if (_previewable(f))
                ListTile(
                  leading: const Icon(Icons.visibility_outlined),
                  title: const Text('Preview'),
                  onTap: () {
                    Navigator.pop(c);
                    _previewFile(f);
                  },
                ),
            ],
            ListTile(
              leading: const Icon(Icons.info_outlined),
              title: const Text('Details'),
              onTap: () {
                Navigator.pop(c);
                _fileDetails(f);
              },
            ),
            ListTile(
              leading: Icon(Icons.close, color: theme.colorScheme.outline),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(c),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  bool _previewable(DriveFile f) =>
      isImageMime(f.type) ||
      isPdfMime(f.type) ||
      isVideoMime(f.type) ||
      isAudioMime(f.type);

  // ---------------- actions ----------------

  Future<void> _downloadFile(DriveFile f) async {
    if (f.url == null) {
      showMsg(context, 'This file is locked — download unavailable.',
          error: true);
      return;
    }
    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final savePath =
        '${dir.path}${Platform.pathSeparator}${cleanName(f.name)}';
    final session = context.read<SessionProvider>();
    final ok = await ProgressDialog.show(
      context,
      title: 'Downloading ${f.name}',
      task: (prog) => session.api.downloadFile(
        url: f.url!,
        savePath: savePath,
        onProgress: (rec, total) => prog(rec, total),
      ),
    );
    if (ok && mounted) showMsg(context, 'Saved to $savePath');
  }

  Future<void> _previewFile(DriveFile f) async {
    if (f.url == null) {
      showMsg(context, 'This file is locked — preview unavailable.',
          error: true);
      return;
    }
    if (isImageMime(f.type)) {
      await _previewImage(f);
    } else if (isVideoMime(f.type) || isAudioMime(f.type)) {
      final ok = await confirmDialog(context,
          title: 'Play media',
          message:
              'The app has no built-in player. Download "${f.name}" to play it?',
          okLabel: 'Download');
      if (ok && mounted) await _downloadFile(f);
    } else if (isPdfMime(f.type)) {
      if (!mounted) return;
      final dl = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('PDF preview'),
          content: const Text(
              'In-app PDF preview is not available. Download the file to view it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Close')),
            ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Download')),
          ],
        ),
      );
      if (dl == true && mounted) await _downloadFile(f);
    }
  }

  Future<void> _previewImage(DriveFile f) async {
    final session = context.read<SessionProvider>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: SizedBox(
          width: 200,
          height: 90,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
    Uint8List? bytes;
    try {
      final r = await Dio().get<List<int>>(
        session.api.previewUrl(f.url!),
        options: Options(responseType: ResponseType.bytes),
      );
      final data = r.data;
      if (data != null && data.isNotEmpty) bytes = Uint8List.fromList(data);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showMsg(context, 'Preview failed: $e', error: true);
      }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (bytes == null) {
      showMsg(context, 'Preview failed: empty response', error: true);
      return;
    }
    final img = bytes;
    await showDialog(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(c),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(img, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download'),
                onPressed: () {
                  Navigator.pop(c);
                  _downloadFile(f);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fileDetails(DriveFile f) {
    final drive = context.read<SessionProvider>().drive;
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(f.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(theme, 'Type', f.type),
              _kv(theme, 'Size', formatBytes(f.size)),
              _kv(theme, 'Location',
                  drive == null ? f.folder : _folderPathText(drive, f.folder)),
              _kv(theme, 'Uploaded',
                  '${formatDateTime(f.uploadedAt)} (${formatRelativeMs(f.uploadedAt)})'),
              _kv(theme, 'Uploaded by', f.uploadedBy),
              _kv(theme, 'Version',
                  'v${f.ver}${f.vc > 0 ? ' · ${f.vc} older' : ''}'),
              if (f.note != null && f.note!.isNotEmpty)
                _kv(theme, 'Note', f.note!),
              _kv(theme, 'Status',
                  f.isLocked
                      ? 'Locked${f.locked?['reason'] != null ? ' — ${f.locked!['reason']}' : ''}'
                      : 'Unlocked'),
            ],
          ),
        ),
        actions: [
          if (f.url != null && _previewable(f))
            TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  _previewFile(f);
                },
                child: const Text('Preview')),
          if (f.url != null)
            TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  _downloadFile(f);
                },
                child: const Text('Download')),
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(k,
                  style: TextStyle(color: theme.colorScheme.outline)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
