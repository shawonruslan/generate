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
import '../../domain/theme_engine.dart';
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

  void _clear() => setState(() {
        _video = null;
        _thumb = null;
        _frames = [];
        _status = 'No video selected';
      });

  int get _thumbIndex => _thumb == null ? -1 : _frames.indexWhere((f) => identical(f, _thumb));

  /// 0 = pick a video, 1 = capturing, 2 = choose cover, 3 = ready to queue.
  int get _step => _video == null ? 0 : (_frames.isEmpty ? 1 : (_thumb == null ? 2 : 3));

  ({String icon, Color color}) _statusStyle(ZedgePalette p) {
    final s = _status.toLowerCase();
    if (s.contains('failed')) return (icon: 'fa-triangle-exclamation', color: p.danger);
    if (s.contains('queued successfully')) return (icon: 'fa-circle-check', color: p.ok);
    if (s.contains('capturing') || s.contains('uploading') || s.contains('resizing') || s.contains('...')) return (icon: 'fa-spinner', color: p.info);
    if (s.contains('selected as cover') || s.contains('captured')) return (icon: 'fa-check', color: p.primary);
    return (icon: 'fa-circle-info', color: p.muted);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final meta = kVideoTypeMeta[_type]!;
    final st = _statusStyle(p);
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle(
          'Video Content (Live Wallpaper / Charging Animation)',
          icon: 'fa-film',
          subtitle: 'MP4/MOV, max 50 MB, min 1080×1920, max 30s. A 1620×2880 JPEG cover thumbnail is captured automatically from the video.',
          trailing: _VideoStepper(step: _step),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 820;
          final types = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _StepLabel(n: 1, text: 'Video type', done: true, active: _step == 0),
            const SizedBox(height: 8),
            for (final k in const ['LIVE_WALLPAPER', 'CHARGING_ANIMATION']) ...[
              _VideoTypeOption(
                meta: kVideoTypeMeta[k]!,
                selected: _type == k,
                enabled: !_busy,
                desc: k == 'LIVE_WALLPAPER' ? 'Loops on the lock & home screen. Vertical 9:16, up to 30 s.' : 'Plays when the phone is plugged in. Short vertical loop, up to 30 s.',
                chips: k == 'LIVE_WALLPAPER' ? const ['1080×1920+', '≤ 30 s', 'MP4 / MOV'] : const ['1080×1920+', '≤ 30 s', 'Loop'],
                onTap: () => setState(() => _type = k),
              ),
              if (k == 'LIVE_WALLPAPER') const SizedBox(height: 8),
            ],
          ]);
          final drop = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _StepLabel(n: 2, text: 'Video file', done: _video != null, active: _step == 0 && _video == null),
            const SizedBox(height: 8),
            if (_video == null)
              DropZone(
                title: 'Drop your ${meta.label.toLowerCase()} video here',
                subtitle: 'MP4 or MOV · max ${formatBytes(kVideoMaxBytes)} · vertical 1080×1920 or larger',
                icon: 'fa-file-video',
                buttonLabel: 'Choose video',
                extensions: const ['mp4', 'mov'],
                multiple: false,
                height: wide ? 176 : 150,
                onFiles: (fl) async {
                  if (fl.isNotEmpty) await _setVideo(fl.first);
                },
              )
            else
              _VideoFileTile(
                file: _video!,
                meta: meta,
                thumb: _thumb,
                busy: _busy || (_frames.isEmpty && !_status.toLowerCase().contains('failed')),
                onReplace: _busy
                    ? null
                    : () async {
                        final fl = await pickLocalFiles(multiple: false, extensions: const ['mp4', 'mov']);
                        if (fl.isNotEmpty) await _setVideo(fl.first);
                      },
                onRemove: _busy ? null : _clear,
              ),
          ]);
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 300, child: types),
              const SizedBox(width: 16),
              Expanded(child: drop),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [types, const SizedBox(height: 14), drop]);
        }),
        const SizedBox(height: 16),
        // ---- cover thumbnail filmstrip
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.tintSoft.withValues(alpha: p.isDark ? 0.35 : 0.6), borderRadius: BorderRadius.circular(p.radiusMd), border: Border.all(color: p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _StepLabel(n: 3, text: 'Cover thumbnail', done: _thumb != null, active: _step == 2),
              Text('5 frames are captured automatically - click the best one. It becomes the 1620×2880 JPEG cover on Zedge.', style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
            const SizedBox(height: 12),
            _FrameStrip(
              frames: _frames,
              selected: _thumbIndex,
              capturing: _video != null && _frames.isEmpty && !_status.toLowerCase().contains('failed'),
              onPick: _busy
                  ? null
                  : (i) => setState(() {
                        _thumb = _frames[i];
                        _status = 'Frame ${i + 1} selected as cover thumbnail.';
                      }),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        // ---- footer: status + queue button
        LayoutBuilder(builder: (context, c) {
          final status = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: st.color.withValues(alpha: p.isDark ? 0.14 : 0.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: st.color.withValues(alpha: 0.35))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (st.icon == 'fa-spinner') SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: st.color)) else Fa(st.icon, size: 12, color: st.color),
              const SizedBox(width: 8),
              Flexible(child: Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.text, fontWeight: FontWeight.w600))),
            ]),
          );
          final btn = ZButton(
            _video == null ? 'Queue Video' : 'Queue ${meta.label}',
            icon: 'fa-cloud-upload-alt',
            busy: _busy,
            tooltip: _video == null ? 'Add a video first' : (_thumb == null ? 'Pick a cover frame first' : 'Add to the upload queue'),
            onPressed: _video != null && _thumb != null && !_busy ? _submit : null,
          );
          if (c.maxWidth < 560) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [status, const SizedBox(height: 10), btn]);
          }
          return Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: status)), const SizedBox(width: 12), btn]);
        }),
      ]),
    );
  }
}

/// "1 Type · 2 Video · 3 Cover · Queue" progress chips in the card header.
class _VideoStepper extends StatelessWidget {
  const _VideoStepper({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const labels = ['Type', 'Video', 'Cover', 'Queue'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.surfaceHover.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(999), border: Border.all(color: p.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) Container(width: 14, height: 1.5, color: i <= step ? p.primary : p.border),
          Builder(builder: (_) {
            final done = i < step || (i == 3 && step == 3);
            final active = i == step;
            return Tooltip(
              message: 'Step ${i + 1}: ${labels[i]}',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(horizontal: active ? 10 : 8, vertical: 5),
                decoration: BoxDecoration(
                  gradient: active ? p.buttonGradient : null,
                  color: active ? null : (done ? p.ok.withValues(alpha: 0.16) : Colors.transparent),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (done) Fa('fa-check', size: 9, color: active ? p.buttonFg : p.ok) else Text('${i + 1}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: active ? p.buttonFg : p.muted)),
                  const SizedBox(width: 5),
                  Text(labels[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: active ? p.buttonFg : (done ? p.ok : p.muted))),
                ]),
              ),
            );
          }),
        ],
      ]),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.n, required this.text, required this.done, required this.active});
  final int n;
  final String text;
  final bool done, active;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = done ? p.ok : (active ? p.primary : p.muted);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(color: done ? p.ok : (active ? p.primary : p.surfaceHover), shape: BoxShape.circle, border: Border.all(color: done || active ? Colors.transparent : p.border)),
        alignment: Alignment.center,
        child: done ? Fa('fa-check', size: 9, color: Colors.white) : Text('$n', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: active ? p.onPrimary : p.muted)),
      ),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 13)),
      if (done) ...[const SizedBox(width: 6), Text('done', style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.w700))],
    ]);
  }
}

/// Big selectable option card for Live Wallpaper / Charging Animation.
class _VideoTypeOption extends StatefulWidget {
  const _VideoTypeOption({required this.meta, required this.selected, required this.enabled, required this.desc, required this.chips, required this.onTap});
  final VideoTypeMeta meta;
  final bool selected, enabled;
  final String desc;
  final List<String> chips;
  final VoidCallback onTap;

  @override
  State<_VideoTypeOption> createState() => _VideoTypeOptionState();
}

class _VideoTypeOptionState extends State<_VideoTypeOption> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final on = widget.selected;
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: on ? LinearGradient(colors: [p.primary.withValues(alpha: p.isDark ? 0.22 : 0.14), p.accent.withValues(alpha: p.isDark ? 0.12 : 0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
            color: on ? null : p.surfaceHover.withValues(alpha: _hover ? 0.9 : 0.55),
            borderRadius: BorderRadius.circular(p.radiusSm + 2),
            border: Border.all(color: on ? p.primary : (_hover ? p.primary.withValues(alpha: 0.5) : p.border), width: on ? 1.6 : 1),
            boxShadow: on ? [BoxShadow(color: p.primary.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 6))] : null,
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: on ? p.primaryGradient : null,
                color: on ? null : p.tintChip,
                borderRadius: BorderRadius.circular(13),
                boxShadow: on ? [BoxShadow(color: p.primary.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 5))] : null,
              ),
              alignment: Alignment.center,
              child: Fa(widget.meta.icon, size: 17, color: on ? p.onPrimary : p.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(widget.meta.label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: p.text))),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: on ? p.primary : Colors.transparent, border: Border.all(color: on ? p.primary : p.muted.withValues(alpha: 0.6), width: 1.6)),
                    child: on ? Fa('fa-check', size: 9, color: p.onPrimary) : null,
                  ),
                ]),
                const SizedBox(height: 3),
                Text(widget.desc, style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.35)),
                const SizedBox(height: 8),
                Wrap(spacing: 5, runSpacing: 5, children: [
                  for (final c in widget.chips)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: on ? p.primary.withValues(alpha: 0.16) : p.tintChip, borderRadius: BorderRadius.circular(6)),
                      child: Text(c, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: on ? p.text : p.muted, letterSpacing: 0.2)),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Selected video row: cover preview, name, size, replace / remove.
class _VideoFileTile extends StatelessWidget {
  const _VideoFileTile({required this.file, required this.meta, required this.thumb, required this.busy, required this.onReplace, required this.onRemove});
  final LocalFile file;
  final VideoTypeMeta meta;
  final Uint8List? thumb;
  final bool busy;
  final VoidCallback? onReplace, onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final okSize = file.size <= kVideoMaxBytes;
    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceHover.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(p.radiusMd),
        border: Border.all(color: p.primary.withValues(alpha: 0.5), width: 1.4),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 64,
          height: 96,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
          clipBehavior: Clip.antiAlias,
          child: thumb != null
              ? Image.memory(thumb!, fit: BoxFit.cover, gaplessPlayback: true)
              : Center(child: busy ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.primary)) : Fa('fa-file-video', size: 20, color: Colors.white.withValues(alpha: 0.6))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Pill(meta.short, icon: meta.icon, small: true, color: p.primary, fg: p.onPrimary),
              const SizedBox(width: 8),
              Pill(file.name.split('.').last.toUpperCase(), small: true, color: p.tintChip, fg: p.text),
            ]),
            const SizedBox(height: 8),
            Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: p.text)),
            const SizedBox(height: 4),
            Row(children: [
              Fa(okSize ? 'fa-circle-check' : 'fa-triangle-exclamation', size: 11, color: okSize ? p.ok : p.danger),
              const SizedBox(width: 6),
              Text('${formatBytes(file.size)} of ${formatBytes(kVideoMaxBytes)} allowed', style: TextStyle(fontSize: 11.5, color: p.muted)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              ZButton('Replace video', icon: 'fa-rotate', small: true, kind: ZBtnKind.ghost, onPressed: onReplace),
              ZButton('Remove', icon: 'fa-xmark', small: true, kind: ZBtnKind.ghost, onPressed: onRemove),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Five-frame filmstrip with dashed placeholders while empty / capturing.
class _FrameStrip extends StatelessWidget {
  const _FrameStrip({required this.frames, required this.selected, required this.capturing, required this.onPick});
  final List<Uint8List> frames;
  final int selected;
  final bool capturing;
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return LayoutBuilder(builder: (context, c) {
      final count = frames.isEmpty ? 5 : frames.length;
      const gap = 10.0;
      final maxW = ((c.maxWidth - gap * (count - 1)) / count).clamp(70.0, 118.0);
      final w = maxW.toDouble();
      final h = w * 16 / 9;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (var i = 0; i < count; i++)
          if (frames.isEmpty)
            _FramePlaceholder(index: i, width: w, height: h, capturing: capturing)
          else
            _FrameThumb(bytes: frames[i], index: i, width: w, height: h, selected: i == selected, onTap: onPick == null ? null : () => onPick!(i)),
      ]);
    });
  }
}

class _FramePlaceholder extends StatelessWidget {
  const _FramePlaceholder({required this.index, required this.width, required this.height, required this.capturing});
  final int index;
  final double width, height;
  final bool capturing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: p.surfaceHover.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: capturing ? p.primary.withValues(alpha: 0.6) : p.border, width: 1.2),
      ),
      child: Stack(fit: StackFit.expand, children: [
        if (capturing)
          _Shimmer(delay: index * 120)
        else
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Fa('fa-image', size: 16, color: p.muted.withValues(alpha: 0.5)),
              const SizedBox(height: 6),
              Text('Frame ${index + 1}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.muted.withValues(alpha: 0.7))),
            ]),
          ),
        Positioned(left: 6, top: 6, child: _FrameNo(n: index + 1, color: p.muted.withValues(alpha: 0.55))),
      ]),
    );
  }
}

class _FrameThumb extends StatefulWidget {
  const _FrameThumb({required this.bytes, required this.index, required this.width, required this.height, required this.selected, required this.onTap});
  final Uint8List bytes;
  final int index;
  final double width, height;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_FrameThumb> createState() => _FrameThumbState();
}

class _FrameThumbState extends State<_FrameThumb> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final on = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover && !on ? 1.04 : 1,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? p.primary : (_hover ? p.primary.withValues(alpha: 0.6) : p.border), width: on ? 3 : 1),
              boxShadow: on ? [BoxShadow(color: p.primary.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6))] : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              Image.memory(widget.bytes, fit: BoxFit.cover, gaplessPlayback: true),
              if (!on) Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: _hover ? 0.05 : 0.25))),
              Positioned(left: 6, top: 6, child: _FrameNo(n: widget.index + 1, color: Colors.white, dark: true)),
              if (on)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)]), child: Fa('fa-check', size: 9, color: p.onPrimary)),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                  alignment: Alignment.center,
                  child: Text(on ? 'COVER' : 'Use as cover', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: on ? p.primaryLight : Colors.white.withValues(alpha: 0.9))),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FrameNo extends StatelessWidget {
  const _FrameNo({required this.n, required this.color, this.dark = false});
  final int n;
  final Color color;
  final bool dark;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: dark ? Colors.black.withValues(alpha: 0.55) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Text('$n', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color)),
      );
}

/// Soft moving highlight used inside placeholders while frames are captured.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.delay});
  final int delay;
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.repeat();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1 + _c.value * 3, -1),
            end: Alignment(_c.value * 3, 1),
            colors: [Colors.transparent, p.primary.withValues(alpha: 0.28), Colors.transparent],
          ),
        ),
      ),
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
