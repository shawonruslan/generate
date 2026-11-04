import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'app_widgets.dart';

/// File preview kinds, detected by extension (mirrors the web app's
/// kindOf(): image / video / audio / pdf / code / other), plus zip.
enum PreviewKind { image, video, audio, pdf, code, zip, other }

const _imgExt = {
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'avif', 'ico'
};
const _vidExt = {'mp4', 'webm', 'mov', 'm4v', 'ogv'};
const _audExt = {'mp3', 'wav', 'ogg', 'oga', 'm4a', 'aac', 'flac', 'opus'};
const _codeExt = {
  'js', 'mjs', 'cjs', 'jsx', 'ts', 'tsx', 'py', 'java', 'kt', 'kts',
  'c', 'h', 'cpp', 'cc', 'hpp', 'cs', 'go', 'rs', 'php', 'rb', 'swift',
  'dart', 'html', 'htm', 'xml', 'vue', 'css', 'scss', 'less', 'json',
  'yml', 'yaml', 'sh', 'bash', 'zsh', 'ps1', 'bat', 'cmd', 'sql', 'lua',
  'md', 'markdown', 'ini', 'cfg', 'conf', 'toml', 'gradle', 'r', 'pl',
  'diff', 'patch', 'graphql', 'txt', 'log', 'csv', 'tsv', 'srt', 'gitignore',
};
const _codeNames = {
  'dockerfile', 'makefile', 'readme', 'license', 'changelog'
};

/// Detect the preview kind by file extension, falling back to the mime
/// type the worker reported.
PreviewKind previewKindFor(String name, [String mime = '']) {
  final n = name.toLowerCase();
  final dot = n.lastIndexOf('.');
  final ext = dot >= 0 ? n.substring(dot + 1) : '';
  final base = dot >= 0 ? n.substring(0, dot) : n;
  if (ext == 'pdf') return PreviewKind.pdf;
  if (ext == 'zip') return PreviewKind.zip;
  if (_imgExt.contains(ext)) return PreviewKind.image;
  if (_vidExt.contains(ext)) return PreviewKind.video;
  if (_audExt.contains(ext)) return PreviewKind.audio;
  if (_codeExt.contains(ext) ||
      _codeNames.contains(n) ||
      _codeNames.contains(base)) return PreviewKind.code;
  if (isImageMime(mime)) return PreviewKind.image;
  if (isVideoMime(mime)) return PreviewKind.video;
  if (isAudioMime(mime)) return PreviewKind.audio;
  if (isPdfMime(mime)) return PreviewKind.pdf;
  return PreviewKind.other;
}

String _kindLabel(PreviewKind k) {
  switch (k) {
    case PreviewKind.image:
      return 'Image';
    case PreviewKind.video:
      return 'Video';
    case PreviewKind.audio:
      return 'Audio';
    case PreviewKind.pdf:
      return 'PDF';
    case PreviewKind.code:
      return 'Text';
    case PreviewKind.zip:
      return 'ZIP';
    case PreviewKind.other:
      return 'File';
  }
}

/// Entry point: shows the preview dialog for a file. Locked files
/// (no signed url) get a locked notice instead.
Future<void> showFilePreview(BuildContext context, DriveFile f) {
  if (f.url == null) {
    return showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_outline),
            SizedBox(width: 8),
            Text('Locked file'),
          ],
        ),
        content: Text(
          'Admin ei file lock kore rekhechen'
          '${f.locked?['reason'] != null ? ' — "${f.locked!['reason']}"' : ''}. '
          'Unlock na kora porjonto download / preview kora jabe na.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close')),
        ],
      ),
    );
  }
  final kind = previewKindFor(f.name, f.type);
  final parentContext = context;
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (c) => _PreviewDialog(
        file: f, kind: kind, parentContext: parentContext),
  );
}

/// Download a file to the downloads/documents dir with a progress dialog.
Future<void> downloadPreviewFile(BuildContext context, DriveFile f) async {
  if (f.url == null) {
    showMsg(context, 'This file is locked — download unavailable.',
        error: true);
    return;
  }
  final session = context.read<SessionProvider>();
  final dir = await getDownloadsDirectory() ??
      await getApplicationDocumentsDirectory();
  final savePath =
      '${dir.path}${Platform.pathSeparator}${cleanName(f.name)}';
  final ok = await ProgressDialog.show(
    context,
    title: 'Downloading ${f.name}',
    task: (prog) => session.api.downloadFile(
      url: f.url!,
      savePath: savePath,
      onProgress: (rec, total) => prog(rec, total),
    ),
  );
  if (ok && context.mounted) showMsg(context, 'Saved to $savePath');
}

/// Fetch raw bytes for preview (image / code / zip) via the signed url.
Future<Uint8List?> _fetchBytes(String url) async {
  try {
    final r = await Dio().get<List<int>>(url,
        options: Options(responseType: ResponseType.bytes));
    final data = r.data;
    if (data == null || data.isEmpty) return null;
    return Uint8List.fromList(data);
  } catch (_) {
    return null;
  }
}

String _mmss(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Dialog shell
// ---------------------------------------------------------------------------

class _PreviewDialog extends StatelessWidget {
  final DriveFile file;
  final PreviewKind kind;
  final BuildContext parentContext;
  const _PreviewDialog(
      {required this.file,
      required this.kind,
      required this.parentContext});

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final f = file;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  FileTypeIcon(name: f.name, mime: f.type, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          '${_kindLabel(kind)} · ${formatBytes(f.size)} · v${f.ver}',
                          style: TextStyle(
                              fontSize: 12,
                              color: night
                                  ? AppColors.nightMuted
                                  : AppColors.dayMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Download',
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () {
                      Navigator.pop(context);
                      downloadPreviewFile(parentContext, f);
                    },
                  ),
                  IconButton(
                    tooltip: 'Copy download link',
                    icon: const Icon(Icons.link_outlined),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: f.url ?? ''));
                      showMsg(context, 'Download link copied');
                    },
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _PreviewBody(
                  file: f, kind: kind, parentContext: parentContext),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  final DriveFile file;
  final PreviewKind kind;
  final BuildContext parentContext;
  const _PreviewBody(
      {required this.file,
      required this.kind,
      required this.parentContext});

  @override
  Widget build(BuildContext context) {
    final url =
        context.read<SessionProvider>().api.previewUrl(file.url!);
    switch (kind) {
      case PreviewKind.image:
        return _ImageBody(url: url, name: file.name);
      case PreviewKind.video:
        return _VideoBody(url: url);
      case PreviewKind.audio:
        return _AudioBody(url: url, file: file);
      case PreviewKind.pdf:
        return _PdfBody(url: url);
      case PreviewKind.code:
        return _CodeBody(url: url, file: file);
      case PreviewKind.zip:
        return _ZipBody(url: url, file: file);
      case PreviewKind.other:
        return _OtherBody(file: file, parentContext: parentContext);
    }
  }
}

Widget _centerMsg(String msg, {IconData icon = Icons.info_outline}) =>
    Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.grey),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center),
          ],
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------

class _ImageBody extends StatefulWidget {
  final String url;
  final String name;
  const _ImageBody({required this.url, required this.name});
  @override
  State<_ImageBody> createState() => _ImageBodyState();
}

class _ImageBodyState extends State<_ImageBody> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fetchBytes(widget.url).then((b) {
      if (!mounted) return;
      setState(() {
        if (b == null) {
          _failed = true;
        } else {
          _bytes = b;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _centerMsg(
          'Ei image ta khola gelo na. Download kore dekhun.',
          icon: Icons.broken_image_outlined);
    }
    final b = _bytes;
    if (b == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4,
      child: Center(child: Image.memory(b, fit: BoxFit.contain)),
    );
  }
}

// ---------------------------------------------------------------------------
// Video
// ---------------------------------------------------------------------------

class _VideoBody extends StatefulWidget {
  final String url;
  const _VideoBody({required this.url});
  @override
  State<_VideoBody> createState() => _VideoBodyState();
}

class _VideoBodyState extends State<_VideoBody> {
  late final VideoPlayerController _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _centerMsg(
          'Ei video format e chole na. Download kore dekhun.',
          icon: Icons.videocam_off_outlined);
    }
    if (!_c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final v = _c.value;
    final pos = v.position;
    final dur = v.duration;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: v.aspectRatio,
              child: VideoPlayer(_c),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              IconButton(
                icon: Icon(v.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled),
                iconSize: 36,
                onPressed: () {
                  setState(() {
                    v.isPlaying ? _c.pause() : _c.play();
                  });
                },
              ),
              Text(_mmss(pos),
                  style: const TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  min: 0,
                  max: dur.inMilliseconds.toDouble().clamp(1, 1 << 62),
                  value: pos.inMilliseconds
                      .toDouble()
                      .clamp(0, dur.inMilliseconds.toDouble()),
                  onChanged: (x) =>
                      _c.seekTo(Duration(milliseconds: x.round())),
                ),
              ),
              Text(_mmss(dur),
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Audio
// ---------------------------------------------------------------------------

class _AudioBody extends StatefulWidget {
  final String url;
  final DriveFile file;
  const _AudioBody({required this.url, required this.file});
  @override
  State<_AudioBody> createState() => _AudioBodyState();
}

class _AudioBodyState extends State<_AudioBody> {
  late final AudioPlayer _p;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _p = AudioPlayer();
    _p.setUrl(widget.url).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    if (_failed) {
      return _centerMsg('Audio play kora gelo na. Download kore shunun.',
          icon: Icons.audiotrack_outlined);
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FileTypeIcon(
              name: widget.file.name, mime: widget.file.type, size: 72),
          const SizedBox(height: 16),
          Text(widget.file.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(formatBytes(widget.file.size),
              style: TextStyle(
                  fontSize: 12,
                  color: night
                      ? AppColors.nightMuted
                      : AppColors.dayMuted)),
          const SizedBox(height: 20),
          StreamBuilder<PlayerState>(
            stream: _p.playerStateStream,
            builder: (c, snap) {
              final playing = snap.data?.playing ?? false;
              final processing =
                  snap.data?.processingState ?? ProcessingState.idle;
              if (processing == ProcessingState.loading ||
                  processing == ProcessingState.buffering) {
                return const CircularProgressIndicator();
              }
              return IconButton(
                iconSize: 56,
                icon: Icon(playing
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled),
                onPressed: () {
                  if (playing) {
                    _p.pause();
                  } else {
                    _p.play();
                  }
                },
              );
            },
          ),
          StreamBuilder<Duration>(
            stream: _p.positionStream,
            builder: (c, posSnap) {
              final pos = posSnap.data ?? Duration.zero;
              return StreamBuilder<Duration?>(
                stream: _p.durationStream,
                builder: (c, durSnap) {
                  final dur = durSnap.data ?? Duration.zero;
                  final max = dur.inMilliseconds.toDouble();
                  return Row(
                    children: [
                      Text(_mmss(pos),
                          style: const TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: max <= 0 ? 1 : max,
                          value: pos.inMilliseconds
                              .toDouble()
                              .clamp(0, max <= 0 ? 1 : max),
                          onChanged: (x) => _p.seek(
                              Duration(milliseconds: x.round())),
                        ),
                      ),
                      Text(_mmss(dur),
                          style: const TextStyle(fontSize: 12)),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PDF
// ---------------------------------------------------------------------------

class _PdfBody extends StatefulWidget {
  final String url;
  const _PdfBody({required this.url});
  @override
  State<_PdfBody> createState() => _PdfBodyState();
}

class _PdfBodyState extends State<_PdfBody> {
  late final PdfViewerController _ctl;
  int _page = 1;
  int _pages = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _ctl = PdfViewerController();
    _ctl.addListener(_onCtl);
  }

  void _onCtl() {
    if (!mounted) return;
    final p = _ctl.pageNumber;
    final n = _ctl.pageCount;
    if (p != _page || n != _pages) {
      setState(() {
        _page = p;
        _pages = n;
      });
    }
  }

  @override
  void dispose() {
    _ctl.removeListener(_onCtl);
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _centerMsg('PDF khola gelo na. Download kore dekhun.',
          icon: Icons.picture_as_pdf_outlined);
    }
    return Column(
      children: [
        Expanded(
          child: PdfViewer.uri(
            Uri.parse(widget.url),
            controller: _ctl,
            params: PdfViewerParams(
              loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
                  const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ),
        if (_pages > 0)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _page > 1
                      ? () => _ctl.goToPage(pageNumber: _page - 1)
                      : null,
                ),
                Text('Page $_page / $_pages',
                    style: const TextStyle(fontSize: 13)),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _page < _pages
                      ? () => _ctl.goToPage(pageNumber: _page + 1)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Code / text
// ---------------------------------------------------------------------------

class _CodeBody extends StatefulWidget {
  final String url;
  final DriveFile file;
  const _CodeBody({required this.url, required this.file});
  @override
  State<_CodeBody> createState() => _CodeBodyState();
}

class _CodeBodyState extends State<_CodeBody> {
  static const _max = 2 * 1024 * 1024;
  String? _text;
  bool _failed = false;
  bool _binary = false;
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await _fetchBytes(widget.url);
    if (!mounted) return;
    if (b == null) {
      setState(() => _failed = true);
      return;
    }
    var bytes = b;
    if (bytes.length > _max) {
      bytes = bytes.sublist(0, _max);
      _truncated = true;
    }
    final head = bytes.length > 4000 ? bytes.sublist(0, 4000) : bytes;
    if (head.contains(0)) {
      setState(() => _binary = true);
      return;
    }
    String text;
    try {
      text = String.fromCharCodes(bytes);
    } catch (_) {
      setState(() => _binary = true);
      return;
    }
    setState(() => _text = text);
  }

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    if (_failed) {
      return _centerMsg('File load hocche na. Download kore dekhun.',
          icon: Icons.code_outlined);
    }
    if (_binary) {
      return _centerMsg(
          'Eta binary file — text hisebe dekhano jay na.',
          icon: Icons.insert_drive_file_outlined);
    }
    final text = _text;
    if (text == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final lines = text.split('\n');
    if (lines.length > 1 && lines.last.isEmpty) lines.removeLast();
    final gutterW = (lines.length.toString().length * 9.0) + 16;
    return Column(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: night
                      ? AppColors.nightLine
                      : AppColors.dayLine),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.code, size: 16),
              const SizedBox(width: 6),
              Text(
                '${lines.length} lines · ${formatBytes(widget.file.size)}',
                style: TextStyle(
                    fontSize: 12,
                    color: night
                        ? AppColors.nightMuted
                        : AppColors.dayMuted),
              ),
              if (_truncated)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('(first 2 MB shown)',
                      style: TextStyle(fontSize: 12)),
                ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  showMsg(context, 'Copied to clipboard');
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: gutterW,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < lines.length; i++)
                            Text('${i + 1}',
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    height: 1.5,
                                    color: night
                                        ? AppColors.nightMuted
                                        : AppColors.dayMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SelectableText(
                      text,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ZIP contents
// ---------------------------------------------------------------------------

class _ZipEntry {
  final String name;
  final int size;
  final bool isDir;
  _ZipEntry(this.name, this.size, this.isDir);
}

class _ZipBody extends StatefulWidget {
  final String url;
  final DriveFile file;
  const _ZipBody({required this.url, required this.file});
  @override
  State<_ZipBody> createState() => _ZipBodyState();
}

class _ZipBodyState extends State<_ZipBody> {
  static const _maxZip = 200 * 1024 * 1024;
  List<_ZipEntry>? _entries;
  bool _failed = false;
  bool _tooBig = false;

  @override
  void initState() {
    super.initState();
    if (widget.file.size > _maxZip) {
      _tooBig = true;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    final b = await _fetchBytes(widget.url);
    if (!mounted) return;
    if (b == null) {
      setState(() => _failed = true);
      return;
    }
    try {
      final archive = ZipDecoder().decodeBytes(b);
      final list = <_ZipEntry>[];
      for (final f in archive.files) {
        list.add(_ZipEntry(f.name, f.size, f.isDirectory));
      }
      list.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      setState(() => _entries = list);
    } catch (_) {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    if (_tooBig) {
      return _centerMsg(
          'Zip onek boro (${formatBytes(widget.file.size)}) — vitore ki ache dekhte download korun.',
          icon: Icons.folder_zip_outlined);
    }
    if (_failed) {
      return _centerMsg('Zip khola gelo na. Download kore dekhun.',
          icon: Icons.folder_zip_outlined);
    }
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return _centerMsg('Khali zip file.',
          icon: Icons.folder_zip_outlined);
    }
    return Column(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.centerLeft,
          child: Text('${entries.length} items',
              style: TextStyle(
                  fontSize: 12,
                  color:
                      night ? AppColors.nightMuted : AppColors.dayMuted)),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (c, i) {
              final e = entries[i];
              return ListTile(
                dense: true,
                leading: Icon(
                  e.isDir
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 20,
                ),
                title: Text(e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
                trailing: e.isDir
                    ? null
                    : Text(formatBytes(e.size),
                        style: TextStyle(
                            fontSize: 11,
                            color: night
                                ? AppColors.nightMuted
                                : AppColors.dayMuted)),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Other / unknown
// ---------------------------------------------------------------------------

class _OtherBody extends StatelessWidget {
  final DriveFile file;
  final BuildContext parentContext;
  const _OtherBody({required this.file, required this.parentContext});

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final f = file;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileTypeIcon(name: f.name, mime: f.type, size: 72),
            const SizedBox(height: 16),
            Text(f.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              '${formatBytes(f.size)} · uploaded ${formatRelativeMs(f.uploadedAt)}',
              style: TextStyle(
                  fontSize: 12,
                  color:
                      night ? AppColors.nightMuted : AppColors.dayMuted),
            ),
            const SizedBox(height: 16),
            const Text('Ei file er preview nai.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
              onPressed: () {
                Navigator.pop(context);
                downloadPreviewFile(parentContext, f);
              },
            ),
          ],
        ),
      ),
    );
  }
}
