import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/dhaka_time.dart';
import '../../data/media.dart';
import '../../data/meta_book.dart';
import '../../data/models.dart';
import '../../data/queue_repository.dart';
import '../../domain/archive_classifier.dart';
import '../../state/app_state.dart';
import '../dialogs/asset_details.dart';
import '../dialogs/purge_overlay.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/dropzone.dart';
import '../widgets/fa.dart';
import '../widgets/queue_card.dart';
import '../widgets/responsive.dart';
import '../widgets/sections.dart';

/// Upload Queue tab: media dropzone, AI metadata JSON bar, smart archive import,
/// 24H / Dual / Battery set uploads, video upload, failed uploads, queue list.
class UploadQueueScreen extends StatelessWidget {
  const UploadQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageBody(children: [
      _MediaUploadCard(),
      SizedBox(height: 16),
      _SmartArchiveCard(),
      SizedBox(height: 16),
      _SetUploadCard(type: 'WALLPAPER_24H', title: '24H Wallpaper Set (Morning → Night)', desc: 'Zedge Dynamic 24H Wallpaper needs exactly 4 images. Each image is auto-resized to 1620×2880 JPEG before queueing.'),
      SizedBox(height: 16),
      _SetUploadCard(type: 'WALLPAPER_DUAL', title: 'Dual Wallpaper Set (Lock + Home)', desc: 'Zedge Dual Wallpaper needs exactly 2 images — lock screen + home screen. Each image is auto-resized to 1620×2880 JPEG before queueing.'),
      SizedBox(height: 16),
      _SetUploadCard(type: 'WALLPAPER_BATTERY', title: 'Battery Wallpaper Set (6 Levels)', desc: 'Zedge Battery Wallpaper needs exactly 6 images in battery-level order. Each image is auto-resized to 1620×2880 JPEG before queueing.'),
      SizedBox(height: 16),
      _VideoUploadCard(),
      SizedBox(height: 16),
      FailedSection(alwaysShow: true),
      SizedBox(height: 16),
      _QueueListCard(),
    ]);
  }
}

/// Runs the smart archive import with all the UI callbacks wired to AppState.
Future<void> runSmartArchiveImport(BuildContext context, List<LocalFile> archives, {String mode = 'queue', String? fallbackType}) async {
  final app = context.app;
  try {
    await app.repo.smartArchiveImport(
      archives,
      mode: mode,
      account: app.activeProject,
      fallbackType: fallbackType,
      distVideoType: app.distVideoType,
      confirm: (m) => confirmDialog(context, m, title: 'Smart Archive Import', okLabel: 'Continue'),
      alert: (m) => alertDialog(context, m, title: 'Smart Archive Import'),
      status: (s) {
        if (mode == 'queue') {
          app.smartArchiveStatus = s;
        } else {
          app.distStatus = s;
          app.distStatusOk = null;
        }
        app.touch();
      },
      toast: app.showToast,
      progress: (pct) {
        app.distProgress = pct;
        app.touch();
      },
      onButton: (l) {
        app.smartArchiveBtn = l;
        app.touch();
      },
      onPointerMoved: app.touch,
    );
  } on UploadBusyException catch (e) {
    await alertDialog(context, e.toString());
  } catch (e) {
    app.showToast('Import failed: ${e.toString().replaceFirst('Exception: ', '')}', 'err');
  }
}

// ---------------------------------------------------------------- media dropzone + metadata JSON bar
class _MediaUploadCard extends StatefulWidget {
  const _MediaUploadCard();
  @override
  State<_MediaUploadCard> createState() => _MediaUploadCardState();
}

class _MediaUploadCardState extends State<_MediaUploadCard> {
  bool _busy = false;
  String _status = '';

  Future<void> _upload(List<LocalFile> input) async {
    final app = context.app;
    var files = await app.repo.zMetaAbsorb(input, app.showToast);
    if (files.isEmpty) return;
    final archives = files.where((f) => f.isArchive).toList();
    if (archives.isNotEmpty) {
      if (!mounted) return;
      await runSmartArchiveImport(context, archives);
      files = files.where((f) => !f.isArchive).toList();
      if (files.isEmpty) return;
    }
    setState(() => _busy = true);
    try {
      await app.repo.handleActiveQueueUpload(
        app.activeProject,
        files,
        app.queueItems,
        confirm: (m) => confirmDialog(context, m, title: 'Duplicate file', okLabel: 'Add anyway'),
        status: (s) => setState(() => _status = s),
        onError: (name, err) => app.showToast('Upload failed for $name: ${err.toString().replaceFirst('Exception: ', '')}', 'err'),
      );
      setState(() => _status = '');
    } on UploadBusyException catch (e) {
      if (mounted) await alertDialog(context, e.toString());
    } catch (e) {
      app.showToast('Upload failed: ${e.toString().replaceFirst('Exception: ', '')}', 'err');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Upload Media Assets', icon: 'fa-cloud-upload-alt'),
        const SizedBox(height: 14),
        DropZone(
          title: 'Drag and drop files here',
          subtitle: 'Or click to browse your desktop files\nSupported: MP3 · JPG/PNG/WEBP · ZIP/RAR (smart import - see below) · metadata .json (loose or inside the ZIP)',
          buttonLabel: 'Choose Files',
          extensions: const ['mp3', 'jpg', 'jpeg', 'png', 'webp', 'zip', 'rar', 'json'],
          busy: _busy,
          busyLabel: _status.isEmpty ? 'Uploading...' : _status,
          height: 170,
          onFiles: _upload,
        ),
        const SizedBox(height: 12),
        _MetaBar(book: app.metaBook),
      ]),
    );
  }
}

class _MetaBar extends StatelessWidget {
  const _MetaBar({required this.book});
  final MetaBook book;
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.pal;
    return AnimatedBuilder(
      animation: book,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: p.border)),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Fa('fa-file-code', size: 13, color: p.primary),
            const SizedBox(width: 8),
            Text('AI metadata JSON', style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 13)),
          ]),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(book.statusText, style: TextStyle(fontSize: 12, color: book.isEmpty ? p.muted : p.text)),
          ),
          ZButton('Load JSON', icon: 'fa-folder-open', small: true, kind: ZBtnKind.soft, onPressed: () async {
            final files = await pickLocalFiles(extensions: const ['json'], title: 'Load metadata JSON');
            if (files.isEmpty) return;
            await app.repo.zMetaAbsorb(files, app.showToast);
          }),
          ZButton('Copy AI prompt', icon: 'fa-copy', small: true, kind: ZBtnKind.ghost, onPressed: () async {
            await Clipboard.setData(ClipboardData(text: MetaBook.promptText()));
            app.showToast('AI prompt copied - paste it into Gemini / ChatGPT with your files', 'ok');
          }),
          ZButton('Clear', icon: 'fa-times', small: true, kind: ZBtnKind.ghost, onPressed: book.isEmpty ? null : book.clear),
          if (book.problems.isNotEmpty)
            Tooltip(message: book.problems.take(8).join('\n'), child: Pill('${book.problems.length} warning(s)', icon: 'fa-exclamation-triangle', small: true, color: p.warn.withValues(alpha: 0.18), fg: p.warn)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- smart archive import
class _SmartArchiveCard extends StatelessWidget {
  const _SmartArchiveCard();
  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    Widget rule(String icon, String text, {String? n}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Fa(icon, size: 12, color: p.primary),
          const SizedBox(width: 6),
          Text.rich(TextSpan(children: [
            if (n != null) ...[const TextSpan(text: 'folder with '), TextSpan(text: n, style: const TextStyle(fontWeight: FontWeight.w800)), const TextSpan(text: ' images → ')],
            TextSpan(text: text),
          ]), style: TextStyle(fontSize: 12, color: p.text)),
        ]);
    final busy = app.smartArchiveBtn != 'Choose Archive';
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Smart Archive Import (ZIP / RAR)', icon: 'fa-file-zipper', subtitle: 'Drop one archive with everything inside - each folder is detected by its image count and queued to the right content type automatically. Nothing to select.'),
        const SizedBox(height: 12),
        Wrap(spacing: 18, runSpacing: 8, children: [
          rule('fa-clone', 'Dual Set', n: '2'),
          rule('fa-clock', '24H Set', n: '4'),
          rule('fa-battery-half', 'Battery Set', n: '6'),
          rule('fa-image', 'other images → Single Wallpapers'),
          rule('fa-music', 'MP3 → Ringtone'),
          rule('fa-film', 'MP4/MOV → Live Wallpaper'),
        ]),
        const SizedBox(height: 14),
        DropZone(
          title: 'Drop ZIP / RAR here',
          subtitle: 'Slot names in file names (morning / night, lock / home, low / full ...) are matched automatically; otherwise file order = slot order.',
          icon: 'fa-file-zipper',
          buttonLabel: app.smartArchiveBtn,
          extensions: const ['zip', 'rar'],
          busy: busy,
          busyLabel: app.smartArchiveBtn,
          height: 140,
          dense: true,
          onFiles: (files) async {
            final archives = files.where((f) => f.isArchive).toList();
            if (archives.isEmpty) {
              if (files.isNotEmpty) await alertDialog(context, 'Drop a .zip or .rar archive here. For loose files use the dropzone above.');
              return;
            }
            await runSmartArchiveImport(context, archives);
          },
        ),
        if (app.smartArchiveStatus.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(app.smartArchiveStatus, style: TextStyle(fontSize: 12.5, color: p.text, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- set uploads (24H / Dual / Battery)
class _SetUploadCard extends StatefulWidget {
  const _SetUploadCard({required this.type, required this.title, required this.desc});
  final String type, title, desc;
  @override
  State<_SetUploadCard> createState() => _SetUploadCardState();
}

class _SetUploadCardState extends State<_SetUploadCard> {
  final Map<String, LocalFile> _files = {};
  String _status = '';
  bool _busy = false;

  SetTypeMeta get meta => kSetTypeMeta[widget.type]!;

  Future<void> _setSlot(String slot, LocalFile f) async {
    if (!f.isImage) {
      await alertDialog(context, 'Only image files are allowed for wallpaper set slots.');
      return;
    }
    setState(() => _files[slot] = f);
  }

  Future<void> _dropped(List<LocalFile> files) async {
    final archives = files.where((f) => f.isArchive).toList();
    if (archives.isNotEmpty) {
      await runSmartArchiveImport(context, archives, fallbackType: widget.type);
      return;
    }
    final imgs = files.where((f) => f.isImage).toList()..sort((a, b) => natCmp(a.name, b.name));
    for (var i = 0; i < imgs.length && i < meta.slots.length; i++) {
      await _setSlot(meta.slots[i], imgs[i]);
    }
  }

  Future<void> _submit() async {
    final app = context.app;
    if (meta.slots.any((s) => _files[s] == null)) return;
    setState(() => _busy = true);
    try {
      await app.repo.submitSet(app.activeProject, widget.type, Map.of(_files), status: (s) => setState(() => _status = s));
      setState(() {
        _files.clear();
        _status = '${meta.label} queued successfully!';
      });
      app.showToast('${meta.label} queued', 'ok');
    } on UploadBusyException catch (e) {
      if (mounted) await alertDialog(context, e.toString());
    } catch (e) {
      setState(() => _status = 'Upload failed - ${e.toString().replaceFirst('Exception: ', '')}');
      app.showToast('${meta.label} upload failed', 'err');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ready = meta.slots.where((s) => _files[s] != null).length;
    final labels = _slotLabels(widget.type);
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle(widget.title, icon: meta.icon, subtitle: widget.desc),
        const SizedBox(height: 14),
        DropZone(
          title: 'Drop ${meta.slots.length} images (or a ZIP/RAR) here',
          subtitle: 'Images fill the slots in file-name order · an archive runs the smart import as ${meta.label}',
          icon: meta.icon,
          buttonLabel: 'Select All ${meta.slots.length} At Once',
          extensions: const ['jpg', 'jpeg', 'png', 'webp', 'zip', 'rar'],
          height: 92,
          dense: true,
          onFiles: _dropped,
        ),
        const SizedBox(height: 12),
        AutoGrid(minTile: 150, gap: 10, maxCols: 6, children: [
          for (var i = 0; i < meta.slots.length; i++) _SlotBox(label: labels[i], file: _files[meta.slots[i]], onPick: () async {
            final f = await pickLocalFiles(multiple: false, extensions: const ['jpg', 'jpeg', 'png', 'webp'], title: '${meta.label} · ${labels[i]}');
            if (f.isNotEmpty) await _setSlot(meta.slots[i], f.first);
          }, onClear: _files[meta.slots[i]] == null ? null : () => setState(() => _files.remove(meta.slots[i]))),
        ]),
        const SizedBox(height: 12),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
          ZButton('Queue ${meta.short} Set', icon: 'fa-cloud-upload-alt', busy: _busy, onPressed: ready == meta.slots.length && !_busy ? _submit : null),
          Text(_busy && _status.isNotEmpty ? _status : (_status.isNotEmpty && ready == 0 ? _status : '$ready / ${meta.slots.length} images selected'), style: TextStyle(fontSize: 12.5, color: p.muted, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }

  List<String> _slotLabels(String type) => switch (type) {
        'WALLPAPER_24H' => const ['Morning', 'Afternoon', 'Evening', 'Night'],
        'WALLPAPER_DUAL' => const ['Lock Screen', 'Home Screen'],
        _ => const ['Critical (0–20%)', 'Low (21–40%)', 'Mid (41–60%)', 'High (61–80%)', 'Full (81–100%)', 'Charging'],
      };
}

class _SlotBox extends StatelessWidget {
  const _SlotBox({required this.label, required this.file, required this.onPick, this.onClear});
  final String label;
  final LocalFile? file;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final f = file;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(p.radiusSm),
      child: Container(
        decoration: BoxDecoration(
          color: f != null ? p.ok.withValues(alpha: 0.08) : p.tintSoft,
          borderRadius: BorderRadius.circular(p.radiusSm),
          border: Border.all(color: f != null ? p.ok.withValues(alpha: 0.6) : p.border, width: f != null ? 1.5 : 1),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (onClear != null) InkWell(onTap: onClear, child: Fa('fa-times', size: 11, color: p.muted)),
          ]),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 9 / 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: f == null
                  ? Container(color: p.bg.withValues(alpha: 0.4), alignment: Alignment.center, child: Fa('fa-image', size: 22, color: p.muted))
                  : _LocalImage(f),
            ),
          ),
          const SizedBox(height: 6),
          Text(f?.name ?? 'Choose image', style: TextStyle(fontSize: 10.5, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

/// Local file preview (path or in-memory bytes).
class _LocalImage extends StatelessWidget {
  const _LocalImage(this.file);
  final LocalFile file;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.bytes(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
        return Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

// ---------------------------------------------------------------- video upload
class _VideoUploadCard extends StatefulWidget {
  const _VideoUploadCard();
  @override
  State<_VideoUploadCard> createState() => _VideoUploadCardState();
}

class _VideoUploadCardState extends State<_VideoUploadCard> {
  String _type = 'LIVE_WALLPAPER';
  LocalFile? _video;
  List<Uint8List> _frames = [];
  Uint8List? _thumb;
  String _status = 'No video selected';
  bool _busy = false;

  Future<void> _setVideo(LocalFile f) async {
    if (!f.isVideo) {
      await alertDialog(context, 'Only MP4 / MOV video files are allowed.');
      return;
    }
    if (f.size > kVideoMaxBytes) {
      await alertDialog(context, 'Video must be 50 MB or smaller.');
      return;
    }
    setState(() {
      _video = f;
      _thumb = null;
      _frames = [];
      _status = 'Capturing 5 frames from video...';
    });
    try {
      final path = f.path ?? await _tmpPath(f);
      final frames = await VideoTools.captureVideoFrames(path, count: 5);
      if (!mounted) return;
      setState(() {
        _frames = frames;
        _thumb = frames.isNotEmpty ? frames.first : null;
        _status = '${frames.length} frames captured - click the best one for the cover.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Frame capture failed - try another video. (${e.toString().replaceFirst('Exception: ', '')})');
    }
  }

  Future<String> _tmpPath(LocalFile f) async {
    final dir = await Directory.systemTemp.createTemp('ahub_video');
    final file = File('${dir.path}/${f.name}');
    await file.writeAsBytes(await f.bytes());
    return file.path;
  }

  Future<void> _submit() async {
    final v = _video, t = _thumb;
    if (v == null || t == null) return;
    final app = context.app;
    setState(() => _busy = true);
    try {
      await app.repo.submitVideoItem(app.activeProject, _type, v, t, status: (s) => setState(() => _status = s));
      final label = kVideoTypeMeta[_type]?.label ?? 'Video';
      setState(() {
        _video = null;
        _thumb = null;
        _frames = [];
        _status = '$label queued successfully!';
      });
      app.showToast('$label queued', 'ok');
    } on UploadBusyException catch (e) {
      if (mounted) await alertDialog(context, e.toString());
    } catch (e) {
      setState(() => _status = 'Upload failed - ${e.toString().replaceFirst('Exception: ', '')}');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('Video Content (Live Wallpaper / Charging Animation)', icon: 'fa-film', subtitle: 'MP4/MOV, max 50 MB, min 1080×1920, max 30s. A 1620×2880 JPEG cover thumbnail is captured automatically from the video.'),
        const SizedBox(height: 14),
        Wrap(spacing: 14, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
          Field('Video type', child: Segmented<String>(options: const [('LIVE_WALLPAPER', 'Live Wallpaper'), ('CHARGING_ANIMATION', 'Charging Animation')], value: _type, onChanged: (v) => setState(() => _type = v))),
          Field(
            'Video File',
            child: SizedBox(
              width: 360,
              child: DropZone(
                title: _video?.name ?? 'Choose video',
                subtitle: _video == null ? 'Drop an MP4 / MOV here' : formatBytes(_video!.size),
                icon: 'fa-file-video',
                buttonLabel: 'Choose video',
                extensions: const ['mp4', 'mov'],
                multiple: false,
                height: 96,
                dense: true,
                onFiles: (fl) async {
                  if (fl.isNotEmpty) await _setVideo(fl.first);
                },
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text('Cover Thumbnail', style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 13)),
        const SizedBox(height: 4),
        Text('5 frames auto-captured — click the best one', style: TextStyle(fontSize: 12, color: p.muted)),
        const SizedBox(height: 10),
        if (_frames.isEmpty)
          Container(height: 80, alignment: Alignment.centerLeft, child: Text(_status, style: TextStyle(fontSize: 12.5, color: p.muted)))
        else
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < _frames.length; i++)
              InkWell(
                onTap: () => setState(() {
                  _thumb = _frames[i];
                  _status = 'Frame ${i + 1} selected as cover thumbnail.';
                }),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 92,
                  height: 164,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: identical(_thumb, _frames[i]) ? p.primary : p.border, width: identical(_thumb, _frames[i]) ? 3 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.memory(_frames[i], fit: BoxFit.cover),
                    if (identical(_thumb, _frames[i])) Positioned(right: 6, top: 6, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle), child: Fa('fa-check', size: 10, color: p.onPrimary))),
                  ]),
                ),
              ),
          ]),
        const SizedBox(height: 12),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
          ZButton('Queue Video', icon: 'fa-cloud-upload-alt', busy: _busy, onPressed: _video != null && _thumb != null && !_busy ? _submit : null),
          if (_frames.isNotEmpty) Text(_status, style: TextStyle(fontSize: 12.5, color: p.muted, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- queue list (filters, pills, grid, bulk delete)
class _QueueListCard extends StatefulWidget {
  const _QueueListCard();
  @override
  State<_QueueListCard> createState() => _QueueListCardState();
}

class _QueueListCardState extends State<_QueueListCard> {
  late final TextEditingController _search;
  bool _bulkBusy = false;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: context.app.queueFilter.search);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(QueueItem item, QueueFilter f) {
    if (f.type != 'ALL' && item.contentType != f.type) return false;
    if (f.status != 'ALL') {
      final st = item.status;
      if (f.status == 'nometa') {
        if (st != 'queued' || item.hasRequiredMetadata) return false;
      } else if (f.status == 'failed' ? !item.isFailed : st != f.status) {
        return false;
      }
    }
    if (f.dateFrom.isNotEmpty || f.dateTo.isNotEmpty) {
      final t = item.timeMs;
      if (t == null) return false;
      if (f.dateFrom.isNotEmpty) {
        final from = DateTime.tryParse('${f.dateFrom}T00:00:00');
        if (from != null && t < from.millisecondsSinceEpoch) return false;
      }
      if (f.dateTo.isNotEmpty) {
        final to = DateTime.tryParse('${f.dateTo}T23:59:59.999');
        if (to != null && t > to.millisecondsSinceEpoch) return false;
      }
    }
    final q = f.search.trim();
    if (q.isNotEmpty) {
      final hay = [item.title, item.name, item.tags, item.category, item.description, item.prompt, item.id].where((s) => s.isNotEmpty).join(' \u0001 ').toLowerCase();
      for (final term in q.toLowerCase().split(RegExp(r'\s+'))) {
        if (term.isNotEmpty && !hay.contains(term)) return false;
      }
    }
    return true;
  }

  Future<void> _pickDate(bool from) async {
    final app = context.app;
    final f = app.queueFilter;
    final cur = DateTime.tryParse(from ? f.dateFrom : f.dateTo) ?? getDhakaDate(0);
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null) return;
    if (from) {
      f.dateFrom = fmtDateKey(d);
    } else {
      f.dateTo = fmtDateKey(d);
    }
    app.uploadPage = 1;
    app.touch();
  }

  Future<void> _bulkDelete(List<QueueItem> matching) async {
    final app = context.app;
    final f = app.queueFilter;
    if (matching.isEmpty) return;
    final label = kQueueTypeLabels[f.type] ?? 'files';
    final uploaded = matching.where((i) => i.status == 'uploaded').length;
    final scope = [
      if (f.type != 'ALL') 'type: $label',
      if (f.status != 'ALL') 'status: ${f.status}',
      if (f.search.trim().isNotEmpty) 'search: "${f.search.trim()}"',
      if (f.dateFrom.isNotEmpty || f.dateTo.isNotEmpty) 'date: ${f.dateFrom.isEmpty ? '…' : f.dateFrom} → ${f.dateTo.isEmpty ? '…' : f.dateTo}',
    ].join(', ');
    final acc = app.accountUpper(app.activeProject);
    final ok = await confirmDialog(
      context,
      'Permanently delete ${matching.length} $label from $acc (queue + R2 files)?\n\nFilter → $scope${uploaded > 0 ? '\n($uploaded of them are already uploaded to Zedge; only their queue records are removed.)' : ''}',
      title: 'Bulk delete',
      okLabel: 'Delete ${matching.length}',
      danger: true,
    );
    if (!ok || !mounted) return;
    if (matching.length >= 25) {
      final again = await confirmDialog(context, 'Really delete ${matching.length} items? Second confirmation.', title: 'Are you sure?', okLabel: 'Yes, delete', danger: true);
      if (!again || !mounted) return;
    }
    setState(() => _bulkBusy = true);
    await runPurge(context, account: app.activeProject, ids: matching.map((i) => i.id).toList(), what: '$label from $acc');
    if (mounted) setState(() => _bulkBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final f = app.queueFilter;
    if (_search.text != f.search) _search.text = f.search;
    final all = [...app.queueItems]..sort((a, b) => b.id.compareTo(a.id));
    final scoped = f.isScoped;
    final sorted = scoped ? all.where((i) => _matches(i, f)).toList() : all;
    final audioLeft = all.where((i) => i.contentType == 'RINGTONE' && i.status == 'queued').length;
    final imageLeft = all.where((i) => i.contentType == 'WALLPAPER' && i.status == 'queued').length;
    final specialLeft = all.where((i) => (i.isSetType || i.isVideoType) && i.status == 'queued').length;
    final totalPages = (sorted.length / kUploadPerPage).ceil().clamp(1, 1 << 30).toInt();
    if (app.uploadPage > totalPages) app.uploadPage = totalPages;
    final start = (app.uploadPage - 1) * kUploadPerPage;
    final slice = sorted.skip(start).take(kUploadPerPage).toList();
    final label = kQueueTypeLabels[f.type] ?? 'files';
    final uploadedMatching = sorted.where((i) => i.status == 'uploaded').length;
    final hint = !scoped
        ? "Pick a content type (or search / date) to enable bulk delete. Deleted items are removed from this account's queue database."
        : (sorted.isEmpty
            ? 'No files match the current filter.'
            : 'Bulk delete removes ${sorted.length} $label from ${app.accountUpper(app.activeProject)}${uploadedMatching > 0 ? ' ($uploadedMatching already uploaded to Zedge — only the queue record is removed).' : '.'}');

    void changed() {
      app.uploadPage = 1;
      app.touch();
    }

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 10, spacing: 10, children: [
          const SectionTitle('Queue Assets List', icon: 'fa-list'),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Pill('Wallpapers: $imageLeft', icon: 'fa-images', color: p.tintChip, fg: p.text, tooltip: 'Image wallpapers queued'),
            Pill('Special: $specialLeft', icon: 'fa-star', color: p.tintChip, fg: p.text, tooltip: 'Special content queued (24H / Dual / Battery / Live / Charging)'),
            Pill('Audios: $audioLeft', icon: 'fa-music', color: p.tintChip, fg: p.text, tooltip: 'Audio tracks queued'),
            Pill('Total: ${all.length}', icon: 'fa-server', color: p.tintChip, fg: p.text, tooltip: 'Total items in database'),
            if (scoped) Pill('Showing: ${sorted.length} of ${all.length}', icon: 'fa-filter', color: p.primary.withValues(alpha: 0.18), fg: p.primary, tooltip: 'Items matching the current search / filter'),
          ]),
        ]),
        const SizedBox(height: 14),
        // toolbar
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search title, tags, category, id…', isDense: true),
              onChanged: (v) {
                f.search = v;
                changed();
              },
            ),
          ),
          ZDropdown<String>(
            value: f.type,
            width: 180,
            items: const [('ALL', 'All types'), ('RINGTONE', 'Ringtones'), ('WALLPAPER', 'Wallpapers'), ('WALLPAPER_24H', '24H sets'), ('WALLPAPER_DUAL', 'Dual sets'), ('WALLPAPER_BATTERY', 'Battery sets'), ('LIVE_WALLPAPER', 'Live wallpapers'), ('CHARGING_ANIMATION', 'Charging animations')],
            onChanged: (v) {
              f.type = v;
              changed();
            },
          ),
          ZDropdown<String>(
            value: f.status,
            width: 160,
            items: const [('ALL', 'Any status'), ('queued', 'Queued'), ('processing', 'Processing'), ('uploaded', 'Uploaded'), ('failed', 'Failed'), ('nometa', 'No metadata')],
            onChanged: (v) {
              f.status = v;
              changed();
            },
          ),
          ZButton(f.dateFrom.isEmpty ? 'From' : 'From ${f.dateFrom}', icon: 'fa-calendar-day', small: true, kind: ZBtnKind.soft, onPressed: () => _pickDate(true)),
          ZButton(f.dateTo.isEmpty ? 'To' : 'To ${f.dateTo}', icon: 'fa-calendar-check', small: true, kind: ZBtnKind.soft, onPressed: () => _pickDate(false)),
          ZButton('Clear', icon: 'fa-times', small: true, kind: ZBtnKind.ghost, onPressed: scoped
              ? () {
                  f.clear();
                  _search.clear();
                  changed();
                }
              : null),
        ]),
        const SizedBox(height: 10),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
          ZButton(scoped ? 'Delete all ${sorted.length} $label' : 'Delete all', icon: 'fa-trash-alt', small: true, kind: ZBtnKind.danger, busy: _bulkBusy, onPressed: scoped && sorted.isNotEmpty && !_bulkBusy ? () => _bulkDelete(sorted) : null),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: Text(hint, style: TextStyle(fontSize: 12, color: p.muted))),
        ]),
        const SizedBox(height: 16),
        if (slice.isEmpty)
          EmptyNote(scoped ? 'No files match your search / filter.' : 'Queue is empty. Select files to upload above!', icon: scoped ? 'fa-search-minus' : 'fa-box-open', big: true)
        else
          AutoGrid(minTile: 240, gap: 14, maxCols: 6, children: [
            for (final it in slice) QueueCard(it, onOpen: () => openAssetDetails(context, it.id), onDelete: () => deleteQueueItemFlow(context, it)),
          ]),
        if (totalPages > 1) ...[
          const SizedBox(height: 16),
          Pagination(page: app.uploadPage, pages: totalPages, onPage: (n) {
            app.uploadPage = n;
            app.touch();
          }),
        ],
      ]),
    );
  }
}
