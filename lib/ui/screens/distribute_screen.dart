import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../data/media.dart';
import '../../data/meta_book.dart';
import '../../data/queue_repository.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/dropzone.dart';
import '../widgets/fa.dart';
import 'upload_queue_screen.dart';

/// Distribute Content tab (`handleDistributionUpload` / `handleSetDistribution`):
/// round-robin flow nodes, video / image mode pickers, dropzone, progress, metadata JSON bar.
class DistributeScreen extends StatefulWidget {
  const DistributeScreen({super.key});
  @override
  State<DistributeScreen> createState() => _DistributeScreenState();
}

class _DistributeScreenState extends State<DistributeScreen> {
  bool _busy = false;

  void _status(String m, [bool? ok]) {
    final app = context.app;
    app.distStatus = m;
    app.distStatusOk = ok ?? (m.contains('failed') || m.contains('Error') ? false : null);
    app.touch();
  }

  Future<void> _handle(List<LocalFile> input) async {
    final app = context.app;
    var files = await app.repo.zMetaAbsorb(input, app.showToast);
    if (files.isEmpty) return;
    final mode = app.distImageMode;
    final archives = files.where((f) => f.isArchive).toList();
    if (archives.isNotEmpty) {
      final loose = files.where((f) => !f.isArchive).toList();
      if (!mounted) return;
      await runSmartArchiveImport(context, archives, mode: 'distribute', fallbackType: kSetTypeMeta.containsKey(mode) ? mode : null);
      if (loose.isNotEmpty) await _handle(loose);
      return;
    }
    setState(() => _busy = true);
    try {
      if (kSetTypeMeta.containsKey(mode)) {
        final meta = kSetTypeMeta[mode]!;
        final r = await app.repo.distributeSets(
          files,
          mode,
          confirm: (m) => confirmDialog(context, m, title: 'Distribute sets', okLabel: 'Continue'),
          status: _status,
          progress: (pct) {
            app.distProgress = pct;
            app.touch();
          },
          onPointerMoved: app.touch,
        );
        if (r != null) {
          final (ok, fail) = r;
          if (fail > 0) {
            _status('Set distribution completed. $ok set(s) OK, $fail failed.', false);
          } else {
            _status('Successfully distributed $ok ${meta.label}(s) across the accounts!', true);
          }
        }
      } else {
        final (ok, fail) = await app.repo.distributeFiles(
          files,
          distVideoType: app.distVideoType,
          confirm: (m) => confirmDialog(context, m, title: 'Already distributed', okLabel: 'Distribute again'),
          status: _status,
          progress: (pct) {
            app.distProgress = pct;
            app.touch();
          },
          onPointerMoved: app.touch,
        );
        if (fail > 0) {
          _status('Distribution completed. $ok successful, $fail failed.', false);
        } else {
          _status('Successfully distributed all $ok file(s)!', true);
        }
      }
    } on UploadBusyException catch (e) {
      if (mounted) await alertDialog(context, e.toString());
    } catch (e) {
      _status('Distribution failed: ${e.toString().replaceFirst('Exception: ', '')}', false);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final order = app.repo.distOrder;
    final pointer = order.isEmpty ? 0 : app.repo.distPointer % order.length;
    final setMeta = kSetTypeMeta[app.distImageMode];
    final ok = app.distStatusOk;
    final statusColor = ok == true ? p.ok : (ok == false ? p.warn : p.text);

    return PageBody(children: [
      GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionTitle('Multi-Account Distribution', icon: 'fa-share-nodes', subtitle: 'Distribute any content type — ringtones (MP3), wallpapers (images), live wallpapers & charging animations (MP4/MOV) — evenly across Zedge accounts in order. 24H / Dual / Battery sets: pick a set mode below and select all images at once — they are grouped automatically and each complete set goes to one account.'),
          const SizedBox(height: 18),
          // flow nodes
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 700;
            final nodes = <Widget>[];
            for (var i = 0; i < order.length; i++) {
              final active = i == pointer;
              nodes.add(_FlowBubble(label: app.accountSpaced(order[i]), index: i + 1, active: active));
              if (i < order.length - 1) nodes.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Fa(narrow ? 'fa-arrow-down' : 'fa-arrow-right', size: 14, color: p.muted)));
            }
            return narrow ? Column(children: nodes) : Row(mainAxisAlignment: MainAxisAlignment.center, children: nodes);
          }),
          const SizedBox(height: 16),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: app.distProgress.clamp(0, 1).toDouble(), minHeight: 8, color: p.primary, backgroundColor: p.tintSoft)),
          const SizedBox(height: 10),
          Row(children: [
            if (ok == true) ...[Fa('fa-check-circle', size: 14, color: p.ok), const SizedBox(width: 6)] else if (ok == false) ...[Fa('fa-exclamation-triangle', size: 14, color: p.warn), const SizedBox(width: 6)],
            Expanded(child: Text(app.distStatus, style: TextStyle(fontSize: 13, color: statusColor, fontWeight: ok != null ? FontWeight.w800 : FontWeight.w600))),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            Field(
              'MP4/MOV files queue as:',
              child: Segmented<String>(options: const [('LIVE_WALLPAPER', 'Live Wallpaper'), ('CHARGING_ANIMATION', 'Charging Animation')], value: app.distVideoType, onChanged: (v) {
                app.distVideoType = v;
                app.touch();
              }),
            ),
            Field(
              'Image files queue as:',
              child: ZDropdown<String>(
                value: app.distImageMode,
                width: 280,
                items: const [('WALLPAPER', 'Single Wallpapers'), ('WALLPAPER_24H', '24H Sets (4 images = 1 set)'), ('WALLPAPER_DUAL', 'Dual Sets (2 images = 1 set)'), ('WALLPAPER_BATTERY', 'Battery Sets (6 images = 1 set)')],
                onChanged: (v) {
                  app.distImageMode = v;
                  app.touch();
                },
              ),
            ),
          ]),
          if (setMeta != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: p.primary.withValues(alpha: 0.3))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Fa(setMeta.icon, size: 14, color: p.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, color: p.text, height: 1.5), children: [
                    TextSpan(text: '${setMeta.label} mode: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const TextSpan(text: 'just select '),
                    TextSpan(text: 'any ${setMeta.slots.length} images per set', style: const TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: ' — no renaming needed, Zedge detects the set automatically on upload. Selecting several sets at once? First ${setMeta.slots.length} files (name order) = Set 1, next ${setMeta.slots.length} = Set 2... Each complete set goes to one account (Set 1 → ZEDGE 1, Set 2 → ZEDGE 2, ...).'),
                  ])),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          DropZone(
            title: 'Select distribution files (any type)',
            subtitle: 'MP3 → Ringtone  |  Image → Wallpaper or Sets (mode above)  |  MP4/MOV → Video (type above)\nMP3 · JPG/PNG/WEBP (auto-resized 1620×2880) · MP4/MOV ≤50MB (cover thumbnail auto-captured)',
            icon: 'fa-share-nodes',
            buttonLabel: 'Select Files',
            extensions: const ['mp3', 'jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'zip', 'rar', 'json'],
            busy: _busy,
            busyLabel: 'Distributing…',
            height: 170,
            onFiles: _handle,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(p.radiusSm)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Fa('fa-file-zipper', size: 13, color: p.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(style: TextStyle(fontSize: 12, color: p.muted, height: 1.5), children: const [
                  TextSpan(text: 'ZIP / RAR = smart import: ', style: TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: 'folders are detected by image count (2 = Dual, 4 = 24H, 6 = Battery), other images = single wallpapers, MP3 = ringtone, MP4/MOV = video. Each set / file goes to the next account in turn. The image-mode picker above only applies to loose (non-archive) images.'),
                ])),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          _DistMetaBar(book: app.metaBook),
        ]),
      ),
    ]);
  }
}

class _FlowBubble extends StatelessWidget {
  const _FlowBubble({required this.label, required this.index, required this.active});
  final String label;
  final int index;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 150,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: active ? p.primaryGradient : null,
        color: active ? null : p.tintSoft,
        borderRadius: BorderRadius.circular(p.radiusMd),
        border: Border.all(color: active ? Colors.transparent : p.border),
        boxShadow: active ? [BoxShadow(color: p.primary.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 8))] : null,
      ),
      child: Column(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: active ? p.onPrimary.withValues(alpha: 0.2) : p.surface, border: Border.all(color: active ? p.onPrimary.withValues(alpha: 0.5) : p.border)),
          child: Fa('fa-database', size: 15, color: active ? p.onPrimary : p.muted),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 12.5, color: active ? p.onPrimary : p.text)),
        Text(active ? 'next target' : 'account $index', style: TextStyle(fontSize: 10.5, color: active ? p.onPrimary.withValues(alpha: 0.85) : p.muted)),
      ]),
    );
  }
}

class _DistMetaBar extends StatelessWidget {
  const _DistMetaBar({required this.book});
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
          Row(mainAxisSize: MainAxisSize.min, children: [Fa('fa-file-code', size: 13, color: p.primary), const SizedBox(width: 8), Text('AI metadata JSON', style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 13))]),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: Text(book.statusText, style: TextStyle(fontSize: 12, color: book.isEmpty ? p.muted : p.text))),
          ZButton('Load JSON', icon: 'fa-folder-open', small: true, kind: ZBtnKind.soft, onPressed: () async {
            final files = await pickLocalFiles(extensions: const ['json'], title: 'Load metadata JSON');
            if (files.isNotEmpty) await app.repo.zMetaAbsorb(files, app.showToast);
          }),
          ZButton('Copy AI prompt', icon: 'fa-copy', small: true, kind: ZBtnKind.ghost, onPressed: () async {
            await Clipboard.setData(ClipboardData(text: MetaBook.promptText()));
            app.showToast('AI prompt copied - paste it into Gemini / ChatGPT with your files', 'ok');
          }),
          ZButton('Clear', icon: 'fa-times', small: true, kind: ZBtnKind.ghost, onPressed: book.isEmpty ? null : book.clear),
        ]),
      ),
    );
  }
}
