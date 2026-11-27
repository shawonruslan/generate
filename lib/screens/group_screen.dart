import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
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
import '../widgets/preview_dialog.dart';

const List<String> _groupEmojis = ['👍', '❤️', '😂', '😮', '😢', '😡', '🔥', '👏'];
const Map<String, (String, Color)> _rxMeta = {
  '👍': ('Like', Color(0xFF1877F2)),
  '❤️': ('Love', Color(0xFFE41E3F)),
  '😂': ('Haha', Color(0xFFF7B125)),
  '😮': ('Wow', Color(0xFFF7B125)),
  '😢': ('Sad', Color(0xFFF7B125)),
  '😡': ('Angry', Color(0xFFE9710F)),
  '🔥': ('Fire', Color(0xFFE9710F)),
  '👏': ('Clap', Color(0xFFF7B125)),
};
const List<String> _fbReactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];

class _QueuedFile {
  final String path;
  final String name;
  final int size;
  const _QueuedFile({required this.path, required this.name, required this.size});
}

/// Shared group feed (v7.8): multi-file & drag-and-drop composer, likes &
/// reactions on posts and comments, threaded comments, pin/unpin, seen-by.
class GroupScreen extends StatefulWidget {
  /// Set by the shell: focuses the composer caption field.
  static VoidCallback? requestNew;

  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  /// Phone-sized layout (Android): tighter spacing, smaller avatars & fonts.
  bool get _compact => MediaQuery.of(context).size.width < 600;

  final _captionCtrl = TextEditingController();
  final _captionFocus = FocusNode();
  final _scrollCtrl = ScrollController();

  GroupFeed? _feed;
  bool _loading = true;
  String? _error;

  // Multi-file composer attachments + drag-and-drop state.
  final List<_QueuedFile> _attachments = [];
  bool _dragging = false;
  bool _posting = false;

  // Expanded comment sections + per-post comment text controllers.
  final Set<String> _openComments = {};
  final Map<String, TextEditingController> _commentCtrls = {};
  final Set<String> _sendingComment = {};

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
    for (final c in _commentCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  ApiClient get _api => context.read<SessionProvider>().api;
  SessionUser? get _me => context.read<SessionProvider>().user;
  bool get _isAdmin => context.read<SessionProvider>().isAdmin;

  TextEditingController _commentCtrlFor(String postId) =>
      _commentCtrls.putIfAbsent(postId, () => TextEditingController());

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
    final feed = await guard(context, () => _api.getGroup());
    if (!mounted) return;
    setState(() {
      _loading = false;
      _feed = feed;
      if (feed == null) _error = 'Could not load the group feed.';
    });
  }

  // ---------------- composer (multi-file + drag & drop) ----------------

  Future<void> _addFilePaths(List<String> paths) async {
    var added = 0;
    for (final p in paths) {
      if (_attachments.length >= AppConfig.groupMaxFiles) {
        if (mounted) {
          showMsg(context,
              'Maximum ${AppConfig.groupMaxFiles} files per post.',
              error: true);
        }
        break;
      }
      final f = File(p);
      if (!await f.exists()) continue;
      final size = await f.length();
      if (size > AppConfig.groupPostMaxBytes) {
        if (mounted) {
          showMsg(context,
              '${p.split(Platform.pathSeparator).last} exceeds 512 MB.',
              error: true);
        }
        continue;
      }
      final name = p.split(Platform.pathSeparator).last;
      _attachments.add(_QueuedFile(path: p, name: name, size: size));
      added++;
    }
    if (added > 0 && mounted) setState(() {});
  }

  Future<void> _pickAttachments() async {
    final res = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: false);
    if (res == null || res.files.isEmpty) return;
    final paths = <String>[];
    for (final f in res.files) {
      if (f.path != null) paths.add(f.path!);
    }
    if (paths.isEmpty) {
      if (mounted) showMsg(context, 'Could not read selected files.', error: true);
      return;
    }
    await _addFilePaths(paths);
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  Future<void> _post() async {
    if (_posting) return;
    final caption = _captionCtrl.text.trim();
    if (caption.isEmpty && _attachments.isEmpty) {
      showMsg(context, 'Write a caption or attach files first.', error: true);
      return;
    }
    setState(() => _posting = true);
    try {
      final uploaded = <GroupFile>[];
      for (var i = 0; i < _attachments.length; i++) {
        final item = _attachments[i];
        GroupUploadDescriptor? desc;
        final label = _attachments.length > 1
            ? 'Uploading ${i + 1}/${_attachments.length}: ${item.name}'
            : 'Uploading ${item.name}…';
        final ok = await ProgressDialog.show(context,
            title: label, task: (report) async {
          desc = await _api.uploadGroupFile(
            localPath: item.path,
            fileName: item.name,
            mime: guessMime(item.name),
            onProgress: report,
          );
        });
        if (!ok || desc == null) {
          if (mounted) {
            showMsg(context, 'Upload failed for ${item.name}.', error: true);
            setState(() => _posting = false);
          }
          return;
        }
        uploaded.add(desc!);
      }
      final post = await guard(
          context,
          () => _api.createPost(
                caption: caption,
                files: uploaded,
                file: uploaded.isNotEmpty ? uploaded.first : null,
              ));
      if (!mounted) return;
      if (post != null) {
        _captionCtrl.clear();
        setState(() => _attachments.clear());
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

    return DropTarget(
      onDragEntered: (_) {
        if (!_dragging) setState(() => _dragging = true);
      },
      onDragExited: (_) {
        if (_dragging) setState(() => _dragging = false);
      },
      onDragDone: (details) async {
        setState(() => _dragging = false);
        final paths = details.files.map((x) => x.path).toList();
        await _addFilePaths(paths);
      },
      child: Card(
        margin: _compact
            ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
            : const EdgeInsets.fromLTRB(12, 10, 12, 8),
        clipBehavior: Clip.antiAlias,
        shape: _dragging
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: brand, width: 2),
              )
            : null,
        child: Container(
          color: _dragging ? brand.withOpacity(0.06) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 3, color: brand),
              Padding(
                padding: EdgeInsets.all(_compact ? 10 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AvatarWidget(
                            url: _feed?.avatars[me?.username],
                            name: me?.username ?? '?',
                            radius: _compact ? 17 : 21,
                            badge: me != null ? resolveBadge(me.username, _feed?.badges) : null),
                        SizedBox(width: _compact ? 10 : 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: night
                                  ? AppColors.nightSide2
                                  : const Color(0xFFF4F2ED),
                              border: Border.all(
                                  color: _dragging
                                      ? brand
                                      : (night
                                          ? AppColors.nightLine
                                          : AppColors.dayLine)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: _captionCtrl,
                              focusNode: _captionFocus,
                              maxLength: 500,
                              maxLines: null,
                              minLines: _compact ? 1 : 2,
                              textInputAction: TextInputAction.newline,
                              style: TextStyle(fontSize: _compact ? 14 : 15),
                              decoration: InputDecoration(
                                isDense: _compact,
                                hintStyle: TextStyle(
                                    fontSize: _compact ? 13.5 : 14,
                                    color: muted),
                                hintText: _dragging
                                    ? 'Drop files here to attach…'
                                    : (_compact
                                        ? 'Sobai ke kichu janate chan?'
                                        : 'Sobai ke kichu janate chan? Caption likhun… (drag & drop / multiple files supported)'),
                                border: InputBorder.none,
                                filled: false,
                                counterText: '',
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_attachments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < _attachments.length; i++)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: night
                                    ? AppColors.nightSide2
                                    : const Color(0xFFEFEDE6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.attach_file, size: 15),
                                  const SizedBox(width: 5),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 180),
                                    child: Text(
                                      '${_attachments[i].name} · ${formatBytes(_attachments[i].size)}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    onTap: _posting
                                        ? null
                                        : () => _removeAttachment(i),
                                    child: const Icon(Icons.close, size: 15),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                    SizedBox(height: _compact ? 8 : 10),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _posting ? null : _pickAttachments,
                          icon: const Icon(Icons.attach_file, size: 16),
                          label: Text(_attachments.isEmpty
                              ? 'Attach'
                              : 'Attach (${_attachments.length}/${AppConfig.groupMaxFiles})'),
                          style: TextButton.styleFrom(
                            backgroundColor: night
                                ? AppColors.nightSide2
                                : const Color(0xFFEFEDE6),
                            foregroundColor: muted,
                            shape: const StadiumBorder(),
                            padding: EdgeInsets.symmetric(
                                horizontal: _compact ? 12 : 14,
                                vertical: _compact ? 6 : 8),
                            minimumSize: Size(0, _compact ? 34 : 40),
                            textStyle: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_upload_outlined,
                                    size: 14, color: muted),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text('Drag & drop files',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11.5, color: muted)),
                                ),
                              ],
                            ),
                          ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Refresh',
                          icon: const Icon(Icons.refresh, size: 19),
                          visualDensity: _compact
                              ? VisualDensity.compact
                              : VisualDensity.standard,
                          onPressed: _load,
                        ),
                        const SizedBox(width: 4),
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
                            minimumSize: Size(0, _compact ? 34 : 40),
                            padding: EdgeInsets.symmetric(
                                horizontal: _compact ? 14 : 16, vertical: 8),
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
        ),
      ),
    );
  }

  // ---------------- reactions & comments actions ----------------

  Future<void> _toggleReaction(
      GroupPost p, GroupComment? cm, String emoji) async {
    final res = await guard(
      context,
      () => _api.reactGroup(
        postId: p.id,
        commentId: cm?.id,
        emoji: emoji,
      ),
    );
    if (res == null || !mounted) return;
    setState(() {
      if (cm != null) {
        cm.reactions
          ..clear()
          ..addAll(res);
      } else {
        p.reactions
          ..clear()
          ..addAll(res);
      }
    });
  }

  Future<void> _sendComment(GroupPost p) async {
    if (_sendingComment.contains(p.id)) return;
    final ctrl = _commentCtrlFor(p.id);
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sendingComment.add(p.id));
    try {
      final cm = await guard(
          context, () => _api.addGroupComment(postId: p.id, text: text));
      if (!mounted) return;
      if (cm != null) {
        ctrl.clear();
        setState(() {
          p.comments.add(cm);
          _openComments.add(p.id);
        });
      }
    } finally {
      if (mounted) setState(() => _sendingComment.remove(p.id));
    }
  }

  Future<void> _deleteComment(GroupPost p, GroupComment cm) async {
    final short =
        cm.text.length > 70 ? '${cm.text.substring(0, 70)}…' : cm.text;
    final yes = await confirmDialog(context,
        title: 'Delete comment?',
        message: '“$short” will be permanently deleted.');
    if (!yes) return;
    final ok = await guard(context, () async {
      await _api.deleteGroupComment(postId: p.id, commentId: cm.id);
      return true;
    });
    if (ok == true && mounted) {
      setState(() => p.comments.removeWhere((x) => x.id == cm.id));
    }
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
            : (p.files.isNotEmpty ? p.files.first.name : 'attachment'))
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
      await _api.downloadFile(
          url: url, savePath: target.path, onProgress: (s, t) => report(s, t));
    });
    if (!mounted) return;
    if (ok) {
      showMsg(context, 'Saved to ${target.path}');
    } else {
      showMsg(context, 'Download failed.', error: true);
    }
  }

  void _previewFile(GroupFile f, {int uploadedAt = 0, String uploadedBy = ''}) {
    final df = DriveFile(
      id: f.key,
      name: f.name,
      folder: 'group',
      size: f.size,
      type: f.type,
      uploadedAt: uploadedAt,
      uploadedBy: uploadedBy,
      ver: 1,
      vc: 0,
      url: f.url,
    );
    showFilePreview(context, df);
  }

  // ---------------- reaction & comment widgets ----------------

  Widget _reactionBar(GroupPost p, {GroupComment? comment, bool compact = false}) {
    return _FbReactionBar(
      reactions: comment?.reactions ?? p.reactions,
      me: _me?.username ?? '',
      compact: compact,
      onToggle: (em) => _toggleReaction(p, comment, em),
    );
  }

  Widget _commentsBlock(GroupPost p) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final line = night ? AppColors.nightLine : AppColors.dayLine;
    final avatars = _feed?.avatars ?? {};
    final me = _me?.username ?? '';
    final ctrl = _commentCtrlFor(p.id);
    final sending = _sendingComment.contains(p.id);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final cm in p.comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AvatarWidget(url: avatars[cm.by], name: cm.by, radius: _compact ? 14 : 17, showBadgeTag: !_compact, badge: resolveBadge(cm.by, _feed?.badges)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: night
                            ? AppColors.nightSide2
                            : const Color(0xFFF4F2ED),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  formatDisplayName(cm.by, adminName: _feed?.adminName),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),

                              const SizedBox(width: 6),
                              Text(formatRelative(cm.ts),
                                  style: TextStyle(fontSize: 11, color: muted)),
                              const Spacer(),
                              if (_isAdmin || cm.by == me)
                                InkWell(
                                  onTap: () => _deleteComment(p, cm),
                                  child: Icon(Icons.delete_outline,
                                      size: 15, color: muted),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(cm.text, style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 5),
                          _reactionBar(p, comment: cm, compact: true),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              AvatarWidget(
                  url: avatars[me], name: me.isEmpty ? '?' : me, radius: 14, badge: resolveBadge(me, _feed?.badges), showBadgeTag: false),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  maxLength: 1000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendComment(p),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Write a comment…',
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: line),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Send comment',
                onPressed: sending ? null : () => _sendComment(p),
                icon: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send, size: 18),
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- feed widgets ----------------

  Widget _seenRow(GroupPost p) {
    final me = _me?.username ?? '';
    final viewers = p.seen.keys.where((u) => u != p.by).toList();
    String nameOf(String u) => u == me ? 'you' : formatDisplayName(u, adminName: _feed?.adminName);

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
      padding: EdgeInsets.only(top: _compact ? 8 : 10),
      child: Row(
        children: [
          if (viewers.isNotEmpty)
            _SeenAvatarStack(
              users: viewers,
              avatars: avatars,
              ringColor: theme.cardColor,
              size: _compact ? 20 : 22,
            ),
          if (viewers.isNotEmpty) const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: viewers.map(nameOf).join(', '),
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: _compact ? 11.5 : 12,
                    color: night ? AppColors.nightMuted : AppColors.dayMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileCard(GroupPost p, GroupFile f) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final ext =
        f.name.contains('.') ? f.name.split('.').last.toUpperCase() : '';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _previewFile(f, uploadedAt: p.ts, uploadedBy: p.by),
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
              onPressed: () => _previewFile(f, uploadedAt: p.ts, uploadedBy: p.by),
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
    final line = night ? AppColors.nightLine : AppColors.dayLine;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final me = _me?.username ?? '';
    final mine = p.by == me;
    final displayName = formatDisplayName(p.by, adminName: _feed?.adminName);
    final avatars = _feed?.avatars ?? {};
    final showComments = _openComments.contains(p.id) || p.comments.isNotEmpty;

    final compact = _compact;
    return Card(
      margin: compact
          ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
          : const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shape: p.pinned
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE8A13C), width: 1.2),
            )
          : null,
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 12),
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
                AvatarWidget(url: avatars[p.by], name: p.by, radius: compact ? 18 : 22, badge: resolveBadge(p.by, _feed?.badges)),
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
                                style: TextStyle(
                                    fontSize: compact ? 14 : null,
                                    fontWeight: FontWeight.w700)),
                          ),

                        ],
                      ),
                      Tooltip(
                        message: formatDateTime(p.ts),
                        child: Text(formatRelative(p.ts),
                            style: TextStyle(fontSize: 12, color: muted)),
                      ),
                    ],
                  ),
                ),
                if (_isAdmin)
                  IconButton(
                    tooltip: p.pinned ? 'Unpin' : 'Pin',
                    visualDensity: compact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    icon: Icon(
                        p.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        size: compact ? 18 : 20),
                    onPressed: () => _togglePin(p),
                  ),
                if (_isAdmin || mine)
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: compact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    icon: Icon(Icons.delete_outline, size: compact ? 18 : 20),
                    color: theme.colorScheme.error,
                    onPressed: () => _deletePost(p),
                  ),
              ],
            ),
            if (p.caption.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: compact ? 8 : 10),
                child: Text(p.caption,
                    style: TextStyle(fontSize: compact ? 13.5 : null)),
              ),
            if (p.files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    for (var i = 0; i < p.files.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                        child: _fileCard(p, p.files[i]),
                      ),
                  ],
                ),
              ),
            // Reactions + Comment toggle bar
            Container(
              margin: EdgeInsets.only(top: compact ? 8 : 10),
              padding: EdgeInsets.only(top: compact ? 6 : 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: line)),
              ),
              child: Row(
                children: [
                  Expanded(child: _reactionBar(p, compact: compact)),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      if (_openComments.contains(p.id)) {
                        _openComments.remove(p.id);
                      } else {
                        _openComments.add(p.id);
                      }
                    }),
                    icon: const Icon(Icons.chat_bubble_outline, size: 15),
                    label: Text(p.comments.isEmpty
                        ? 'Comment'
                        : '${p.comments.length}'),
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 30),
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            if (showComments) _commentsBlock(p),
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
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
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
                              child:
                                  _sectionHeader(Icons.push_pin, 'Pinned')),
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
                        SliverToBoxAdapter(child: SizedBox(height: _compact ? 96 : 24)),
                      ],
                    ],
                  ),
                ),
    );
  }
}

/// Facebook-style animated reaction bar (v7.10): overlapping top-3 summary
/// stack + total, count pills, and a reaction dock that springs open with
/// staggered overshoot pops on long-press / add-tap. Selecting a face plays
/// a quick burst (scale-up + fade) before the toggle is sent.
class _FbReactionBar extends StatefulWidget {
  final Map<String, List<String>> reactions;
  final String me;
  final bool compact;
  final void Function(String emoji) onToggle;
  const _FbReactionBar({
    required this.reactions,
    required this.me,
    required this.onToggle,
    this.compact = false,
  });

  @override
  State<_FbReactionBar> createState() => _FbReactionBarState();
}

class _FbReactionBarState extends State<_FbReactionBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dockCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
  bool _dockOpen = false;
  String? _burst;

  @override
  void dispose() {
    _dockCtrl.dispose();
    super.dispose();
  }

  void _openDock() {
    setState(() => _dockOpen = true);
    _dockCtrl.forward(from: 0);
  }

  void _closeDock() => setState(() => _dockOpen = false);

  void _pick(String em) {
    setState(() => _burst = em);
    Future.delayed(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      setState(() {
        _burst = null;
        _dockOpen = false;
      });
      widget.onToggle(em);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final line = night ? AppColors.nightLine : AppColors.dayLine;
    final muted = night ? AppColors.nightMuted : AppColors.dayMuted;
    final rx = widget.reactions;
    final active = _groupEmojis.where((e) => (rx[e] ?? const []).isNotEmpty).toList();
    final total = active.fold<int>(0, (a, e) => a + (rx[e]?.length ?? 0));
    final myEm = active.firstWhere((e) => (rx[e] ?? const []).contains(widget.me),
        orElse: () => '');

    Widget pill(String emoji, List<String> users, bool isMine) {
      return Tooltip(
        message: users.isEmpty
            ? (_rxMeta[emoji]?.$1 ?? 'React')
            : '${_rxMeta[emoji]?.$1 ?? ''} — ${users.join(', ')}',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => widget.onToggle(emoji),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 7 : 9,
                vertical: widget.compact ? 2 : 4),
            decoration: BoxDecoration(
              color: isMine
                  ? brand.withOpacity(0.18)
                  : (night ? AppColors.nightSide2 : const Color(0xFFEFEDE6)),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: isMine ? brand : line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(emoji, style: TextStyle(fontSize: widget.compact ? 12 : 13.5)),
              const SizedBox(width: 4),
              Text('${users.length}',
                  style: TextStyle(
                      fontSize: widget.compact ? 11 : 12,
                      fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
                      color: isMine ? brand : null)),
            ]),
          ),
        ),
      );
    }

    Widget summary() {
      final top = [...active]
        ..sort((a, b) => (rx[b]?.length ?? 0).compareTo(rx[a]?.length ?? 0));
      final faces = top.take(3).toList();
      return Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 20 + (faces.length - 1) * 13.0,
          height: 20,
          child: Stack(children: [
            for (var i = 0; i < faces.length; i++)
              Positioned(
                left: i * 13.0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: night ? AppColors.nightPanel : Colors.white,
                    border: Border.all(
                        color: night ? AppColors.nightPanel : Colors.white,
                        width: 1.5),
                    boxShadow: [
                      BoxShadow(color: line, blurRadius: 0, spreadRadius: 0.5)
                    ],
                  ),
                  child: Center(
                      child: Text(faces[i],
                          style: const TextStyle(fontSize: 11, height: 1))),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 5),
        Text('$total',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: muted)),
      ]);
    }

    Widget dock() {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: night ? AppColors.nightPanel : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: line),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 8))
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < _fbReactions.length; i++)
            AnimatedBuilder(
              animation: _dockCtrl,
              builder: (c, child) {
                final start = i * 0.09;
                final t = ((_dockCtrl.value - start) / (1 - start))
                    .clamp(0.0, 1.0);
                final scale =
                    Curves.elasticOut.transform(t == 1 ? 1 : t) ;
                return Transform.scale(
                  scale: t == 0 ? 0 : scale,
                  child: Opacity(opacity: t == 0 ? 0 : 1, child: child),
                );
              },
              child: Tooltip(
                message: _rxMeta[_fbReactions[i]]?.$1 ?? '',
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => _pick(_fbReactions[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    child: Text(_fbReactions[i],
                        style: const TextStyle(fontSize: 27)),
                  ),
                ),
              ),
            ),
        ]),
      );
    }

    return Stack(clipBehavior: Clip.none, children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_dockOpen) dock(),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (total > 0) summary(),
              for (final em in active)
                pill(em, rx[em]!, (rx[em] ?? const []).contains(widget.me)),
              GestureDetector(
                onLongPress: _openDock,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    if (_dockOpen) {
                      _closeDock();
                    } else if (myEm.isNotEmpty) {
                      widget.onToggle(myEm);
                    } else {
                      widget.onToggle('👍');
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: widget.compact ? 7 : 9,
                        vertical: widget.compact ? 2 : 4),
                    decoration: BoxDecoration(
                      color: night
                          ? AppColors.nightSide2
                          : const Color(0xFFEFEDE6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: line),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(myEm.isNotEmpty ? myEm : '👍',
                          style:
                              TextStyle(fontSize: widget.compact ? 12 : 13.5)),
                      const SizedBox(width: 4),
                      Text(
                        myEm.isNotEmpty
                            ? (_rxMeta[myEm]?.$1 ?? 'React')
                            : 'Like',
                        style: TextStyle(
                          fontSize: widget.compact ? 11 : 12,
                          fontWeight: FontWeight.w700,
                          color: myEm.isNotEmpty
                              ? (_rxMeta[myEm]?.$2 ?? brand)
                              : muted,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add reaction',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: Icon(Icons.add_reaction_outlined,
                    size: widget.compact ? 16 : 18, color: muted),
                onPressed: () => _dockOpen ? _closeDock() : _openDock(),
              ),
            ],
          ),
        ],
      ),
      if (_burst != null)
        Positioned(
          left: 26,
          top: -34,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1.5),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (c, v, child) => Opacity(
              opacity: (1.6 - v).clamp(0.0, 1.0),
              child: Transform.scale(scale: v, child: child),
            ),
            child: Text(_burst!, style: const TextStyle(fontSize: 30)),
          ),
        ),
    ]);
  }
}


/// Overlapping "seen by" faces (Facebook style). Plain circles with a thin
/// card-coloured ring — no animated badge frame, because the frame is ~30%
/// larger than the avatar and was getting clipped by the fixed-size row.
class _SeenAvatarStack extends StatelessWidget {
  final List<String> users;
  final Map<String, String> avatars;
  final Color ringColor;
  final double size;
  const _SeenAvatarStack({
    required this.users,
    required this.avatars,
    required this.ringColor,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    const maxFaces = 5;
    final shown = users.take(maxFaces).toList();
    final step = size * 0.68; // overlap
    final width = size + step * (shown.length - 1);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              top: 0,
              child: Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(1.5),
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: ringColor),
                child: AvatarWidget(
                  url: avatars[shown[i]],
                  name: shown[i],
                  radius: (size - 3) / 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
