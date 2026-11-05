import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/config.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Shared group feed (v7.2+): composer + seen-by feed.
/// Full parity with the web app's Group view: caption (≤500), optional file
/// attach (≤512MB), pin/unpin (admin), delete (own or admin), avatar-stack
/// "Seen by" row, Pinned/Recent sections.
class GroupScreen extends StatefulWidget {
  /// Set by the shell: focuses the composer caption field.
  static VoidCallback? requestNew;

  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final _captionCtrl = TextEditingController();
  final _captionFocus = FocusNode();
  final _scrollCtrl = ScrollController();

  GroupFeed? _feed;
  bool _loading = true;
  String? _error;

  // Composer attachment.
  String? _attachPath;
  String? _attachName;
  int _attachSize = 0;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    GroupScreen.requestNew = _focusComposer;
    _load();
  }

  @override
  void dispose() {
    GroupScreen.requestNew = null;
    _captionCtrl.dispose();
    _captionFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  ApiClient get _api => context.read<SessionProvider>().api;
  SessionUser? get _me => context.read<SessionProvider>().user;
  bool get _isAdmin => context.read<SessionProvider>().isAdmin;

  void _focusComposer() {
    if (!mounted) return;
    _scrollCtrl.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    _captionFocus.requestFocus();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Every GET marks the caller as seen server-side (worker behavior).
    final feed = await guard(context, () => _api.getGroup());
    if (!mounted) return;
    setState(() {
      _loading = false;
      _feed = feed;
      if (feed == null) _error = 'Could not load the group feed.';
    });
  }

  // ---------------- composer ----------------

  Future<void> _pickAttachment() async {
    final res = await FilePicker.platform
        .pickFiles(allowMultiple: false, withData: false);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    if (f.path == null) {
      if (mounted) showMsg(context, 'Could not read that file.', error: true);
      return;
    }
    setState(() {
      _attachPath = f.path;
      _attachName = f.name;
      _attachSize = f.size;
    });
  }

  void _removeAttachment() => setState(() {
        _attachPath = null;
        _attachName = null;
        _attachSize = 0;
      });

  Future<void> _post() async {
    if (_posting) return;
    final caption = _captionCtrl.text.trim();
    if (caption.isEmpty && _attachPath == null) {
      showMsg(context, 'Write a caption or attach a file first.', error: true);
      return;
    }
    if (_attachSize > AppConfig.groupPostMaxBytes) {
      showMsg(context, 'File exceeds the 512 MB group post limit.',
          error: true);
      return;
    }
    setState(() => _posting = true);
    try {
      GroupFile? file;
      if (_attachPath != null && _attachName != null) {
        final path = _attachPath!;
        final name = _attachName!;
        GroupUploadDescriptor? desc;
        final ok = await ProgressDialog.show(context,
            title: 'Uploading attachment…', task: (report) async {
          desc = await _api.uploadGroupFile(
            localPath: path,
            fileName: name,
            mime: guessMime(name),
            onProgress: report,
          );
        });
        if (!ok || desc == null) {
          if (mounted) {
            showMsg(context, 'Attachment upload failed.', error: true);
            setState(() => _posting = false);
          }
          return;
        }
        file = desc;
      }
      final post = await guard(
          context, () => _api.createPost(caption: caption, file: file));
      if (!mounted) return;
      if (post != null) {
        _captionCtrl.clear();
        _removeAttachment();
        showMsg(context, 'Posted to group.');
        await _load();
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Widget _composer() {
    final me = _me;
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 3px brand accent bar on top (web: .gp-composer::before).
          Container(height: 3, color: brand),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AvatarWidget(
                        url: _feed?.avatars[me?.username],
                        name: me?.username ?? '?',
                        radius: 21),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: night
                              ? AppColors.nightSide2
                              : const Color(0xFFF4F2ED),
                          border: Border.all(
                              color: night
                                  ? AppColors.nightLine
                                  : AppColors.dayLine),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _captionCtrl,
                          focusNode: _captionFocus,
                          maxLength: 500,
                          maxLines: null,
                          minLines: 2,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            hintText:
                                'Sobai ke kichu janate chan? Caption likhun… (file charao post kora jay)',
                            border: InputBorder.none,
                            filled: false,
                            counterText: '',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_attachName != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: night
                          ? AppColors.nightSide2
                          : const Color(0xFFEFEDE6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.attach_file, size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '$_attachName · ${formatBytes(_attachSize)}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: _removeAttachment,
                          child: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _posting ? null : _pickAttachment,
                      icon: const Icon(Icons.attach_file, size: 16),
                      label: const Text('Attach'),
                      style: TextButton.styleFrom(
                        backgroundColor: night
                            ? AppColors.nightSide2
                            : const Color(0xFFEFEDE6),
                        foregroundColor: muted,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _posting ? null : _post,
                      icon: _posting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send, size: 16),
                      label: const Text('Post'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- post actions ----------------

  Future<void> _togglePin(GroupPost p) async {
    final ok = await guard(context, () async {
      await _api.pinPost(id: p.id, pinned: !p.pinned);
      return true;
    });
    if (ok == true && mounted) {
      showMsg(context, p.pinned ? 'Post unpinned.' : 'Post pinned.');
      await _load();
    }
  }

  Future<void> _deletePost(GroupPost p) async {
    final preview = (p.caption.isNotEmpty
            ? p.caption
            : (p.file?.name ?? 'attachment'))
        .trim();
    final short = preview.length > 80 ? '${preview.substring(0, 80)}…' : preview;
    final yes = await confirmDialog(context,
        title: 'Delete post?',
        message: '“$short” (${p.by}) will be permanently deleted.');
    if (!yes) return;
    final ok = await guard(context, () async {
      await _api.deletePost(p.id);
      return true;
    });
    if (ok == true && mounted) {
      showMsg(context, 'Post deleted.');
      await _load();
    }
  }

  Future<Directory> _downloadDir() async {
    final base =
        await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory(
        '${base.path}${Platform.pathSeparator}teamdrive-group');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _downloadFile(GroupFile f) async {
    final url = f.url;
    if (url == null || url.isEmpty) {
      showMsg(context, 'No download link available.', error: true);
      return;
    }
    final dir = await _downloadDir();
    var name = cleanName(f.name).isEmpty ? 'file' : cleanName(f.name);
    var target = File('${dir.path}${Platform.pathSeparator}$name');
    var i = 1;
    while (await target.exists()) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      target = File('${dir.path}${Platform.pathSeparator}$stem ($i)$ext');
      i++;
    }
    final ok = await ProgressDialog.show(context,
        title: 'Downloading…', task: (report) async {
      await _api.downloadFile(url: url, savePath: target.path,
          onProgress: (s, t) => report(s, t));
    });
    if (!mounted) return;
    if (ok) {
      showMsg(context, 'Saved to ${target.path}');
    } else {
      showMsg(context, 'Download failed.', error: true);
    }
  }

  void _previewFile(GroupFile f) {
    if (!isImageMime(f.type)) {
      showMsg(context, 'No preview for this file type — use download.');
      return;
    }
    final url = f.url;
    if (url == null || url.isEmpty) return;
    showDialog(
      context: context,
      builder: (c) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(f.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () {
                      Navigator.pop(c);
                      _downloadFile(f);
                    }),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(c)),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(_api.previewUrl(url),
                    errorBuilder: (_, __, ___) =>
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Could not load preview.'),
                        )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- feed widgets ----------------

  /// Mirrors the web app's seenRow(): author excluded, "you" for self,
  /// up to 5 avatars, text lists up to 3 names then "+N more".
  Widget _seenRow(GroupPost p) {
    final me = _me?.username ?? '';
    final viewers = p.seen.keys.where((u) => u != p.by).toList();
    String nameOf(String u) =>
        u == me ? 'you' : (u == 'admin' ? 'Admin' : u);

    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final avatars = _feed?.avatars ?? {};

    final String text;
    if (viewers.isEmpty) {
      text = 'No views yet';
    } else if (viewers.length <= 3) {
      text = 'Seen by ${viewers.map(nameOf).join(', ')}';
    } else {
      text =
          'Seen by ${viewers.take(3).map(nameOf).join(', ')} +${viewers.length - 3} more';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          if (viewers.isNotEmpty)
            SizedBox(
              width: (viewers.length.clamp(1, 5) * 16 + 8).toDouble(),
              height: 24,
              child: Stack(
                children: [
                  for (var i = 0; i < viewers.length.clamp(0, 5); i++)
                    Positioned(
                      left: i * 16.0,
                      child: AvatarWidget(
                        url: avatars[viewers[i]],
                        name: viewers[i],
                        radius: 12,
                      ),
                    ),
                ],
              ),
            ),
          if (viewers.isNotEmpty) const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: viewers.map(nameOf).join(', '),
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: night ? AppColors.nightMuted : AppColors.dayMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileCard(GroupFile f) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final ext =
        f.name.contains('.') ? f.name.split('.').last.toUpperCase() : '';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _previewFile(f),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: night ? AppColors.nightSide2 : const Color(0xFFEFEDE6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            FileTypeIcon(name: f.name, mime: f.type, size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                      '${ext.isEmpty ? 'File' : ext} · ${formatBytes(f.size)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: night
                              ? AppColors.nightMuted
                              : AppColors.dayMuted)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Preview',
              icon: const Icon(Icons.visibility_outlined, size: 20),
              onPressed: () => _previewFile(f),
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              onPressed: () => _downloadFile(f),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _postCard(GroupPost p) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final me = _me?.username ?? '';
    final mine = p.by == me;
    final displayName = p.by == 'admin' ? 'Admin' : p.by;
    final avatars = _feed?.avatars ?? {};

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shape: p.pinned
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE8A13C), width: 1.2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.pinned)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.push_pin, size: 14, color: Color(0xFFE8A13C)),
                    SizedBox(width: 4),
                    Text('Pinned',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Color(0xFFE8A13C))),
                  ],
                ),
              ),
            Row(
              children: [
                AvatarWidget(
                    url: avatars[p.by], name: p.by, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                          if (p.by == 'admin') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: night
                                    ? AppColors.brandDark
                                    : AppColors.brandLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('ADMIN',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.07 * 10,
                                      color: Colors.white)),
                            ),
                          ],
                        ],
                      ),
                      Tooltip(
                        message: formatDateTime(p.ts),
                        child: Text(formatRelative(p.ts),
                            style: TextStyle(
                                fontSize: 12,
                                color: night
                                    ? AppColors.nightMuted
                                    : AppColors.dayMuted)),
                      ),
                    ],
                  ),
                ),
                if (_isAdmin)
                  IconButton(
                    tooltip: p.pinned ? 'Unpin' : 'Pin',
                    icon: Icon(
                        p.pinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 20),
                    onPressed: () => _togglePin(p),
                  ),
                if (_isAdmin || mine)
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: theme.colorScheme.error,
                    onPressed: () => _deletePost(p),
                  ),
              ],
            ),
            if (p.caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(p.caption),
              ),
            if (p.file != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _fileCard(p.file!),
              ),
            _seenRow(p),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      );

  Widget _pageHeader() {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Group',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _load,
              ),
            ],
          ),
          Row(
            children: [
              Text('Admin + sob member er shared space',
                  style: TextStyle(fontSize: 13, color: muted)),
              const SizedBox(width: 8),
              Text('${_feed?.posts.length ?? 0} posts',
                  style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const LoadingView(label: 'Loading group feed…')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    controller: _scrollCtrl,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _pageHeader()),
                      SliverToBoxAdapter(child: _composer()),
                      if ((_feed?.posts ?? []).isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyView(
                              icon: Icons.forum_outlined,
                              message:
                                  'No posts yet — be the first to share!'),
                        )
                      else ...[
                        if (_feed!.posts.any((p) => p.pinned)) ...[
                          SliverToBoxAdapter(
                              child: _sectionHeader(
                                  Icons.push_pin, 'Pinned')),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (c, i) => _postCard(_feed!.posts
                                  .where((p) => p.pinned)
                                  .toList()[i]),
                              childCount: _feed!.posts
                                  .where((p) => p.pinned)
                                  .length,
                            ),
                          ),
                        ],
                        SliverToBoxAdapter(
                            child: _sectionHeader(
                                Icons.history_outlined, 'Recent')),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (c, i) => _postCard(_feed!.posts
                                .where((p) => !p.pinned)
                                .toList()[i]),
                            childCount: _feed!.posts
                                .where((p) => !p.pinned)
                                .length,
                          ),
                        ),
                        const SliverToBoxAdapter(
                            child: SizedBox(height: 24)),
                      ],
                    ],
                  ),
                ),
    );
  }
}
