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

class _RecentScreenState extends State<RecentScreen> {
  bool _loading = true;
  String? _error;

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
    return RefreshIndicator(
      onRefresh: () async {
        await guard(context, () => session.refreshDrive());
      },
      child: ListView.builder(
        itemCount: top.length,
        itemBuilder: (_, i) => _row(drive, top[i]),
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

  Widget _row(DriveData drive, DriveFile f) {
    return ListTile(
      leading: FileTypeIcon(name: f.name, mime: f.type),
      title: Text(f.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${_folderPathText(drive, f.folder)}\n${formatBytes(f.size)} · ${timeAgo(f.uploadedAt)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      trailing: f.isLocked
          ? Icon(Icons.lock_outline,
              size: 18, color: Theme.of(context).colorScheme.error)
          : const Icon(Icons.chevron_right, size: 18),
      onTap: () => _menu(f),
    );
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
                  Text('${formatBytes(f.size)} · ${timeAgo(f.uploadedAt)}'),
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
                  '${formatDateTime(f.uploadedAt)} (${timeAgo(f.uploadedAt)})'),
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
