import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants.dart';
import '../../core/dhaka_time.dart';
import '../../data/models.dart';
import '../../domain/theme_engine.dart';
import '../../domain/upload_errors.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../widgets/common.dart';
import '../widgets/fa.dart';
import '../widgets/phone_mockup.dart';
import '../widgets/queue_card.dart';
import '../widgets/responsive.dart';
import 'purge_overlay.dart';

/// Opens the unified edit / metadata page for a queue item (`openModal(id)` +
/// the v27 "item details as a page" / "mobile preview page" layer).
Future<void> openAssetDetails(BuildContext context, String id) async {
  final app = context.read<AppState>();
  if (app.itemById(id) == null) {
    app.showToast('That file is not in the current queue anymore.', 'warn');
    return;
  }
  final backLabel = kTabLabel[context.read<NavState>().tab] ?? 'Back';
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => AssetDetailsPage(id: id, backLabel: backLabel),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved), child: child),
        );
      },
    ),
  );
}

const Map<String, String> _kSlotFa = {
  'morning': 'fa-sun',
  'afternoon': 'fa-cloud-sun',
  'evening': 'fa-cloud-moon',
  'night': 'fa-moon',
  'lock': 'fa-lock',
  'home': 'fa-home',
  'critical': 'fa-battery-empty',
  'low': 'fa-battery-quarter',
  'mid': 'fa-battery-half',
  'high': 'fa-battery-three-quarters',
  'full': 'fa-battery-full',
  'charging': 'fa-bolt',
};

/// One frame of the auto presentation (set slot or gallery wallpaper).
class _Frame {
  const _Frame({this.slot, required this.url, required this.title});
  final String? slot;
  final String url;
  final String title;
}

class AssetDetailsPage extends StatefulWidget {
  const AssetDetailsPage({super.key, required this.id, required this.backLabel});
  final String id;
  final String backLabel;

  @override
  State<AssetDetailsPage> createState() => _AssetDetailsPageState();
}

class _AssetDetailsPageState extends State<AssetDetailsPage> {
  late QueueItem _snapshot;
  late final String _account;

  // form
  late final TextEditingController _title;
  late final TextEditingController _tags;
  late final TextEditingController _category;
  late final TextEditingController _description;
  String? _scheduled;
  bool _saving = false;
  bool _requeueing = false;
  String _copyState = ''; // '' | busy | done | fail
  String _copyLabel = 'Copy to Other Accounts';
  Timer? _copyReset;

  // presentation
  List<_Frame> _frames = [];
  int _presIndex = 0;
  Timer? _presTimer;
  String? _activeSlot;
  String _imgUrl = '';
  String _imgTitle = '';
  int _fadeKey = 0;

  // media
  Player? _player;
  VideoController? _video;
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  final List<StreamSubscription<dynamic>> _subs = [];

  // v27 mobile preview page
  bool _previewMode = false;
  String _pvBg = 'aurora';
  double _pvZoom = 120;
  bool _lockOn = false;
  bool _fullscreen = false;

  bool get _presPlaying => _presTimer != null;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _account = app.activeProject;
    _snapshot = app.itemById(widget.id)!;
    final item = _snapshot;
    _title = TextEditingController(text: item.title);
    _tags = TextEditingController(text: item.tags);
    _category = TextEditingController(text: item.category);
    _description = TextEditingController(text: item.description);
    _scheduled = item.scheduledDate;
    _setupPreview(app, item);
  }

  void _setupPreview(AppState app, QueueItem item) {
    if (item.isSetType) {
      final slots = item.setSlots;
      _activeSlot = slots.isNotEmpty ? slots.first : null;
      _frames = [
        for (final s in slots)
          if (item.slotUrl(s).isNotEmpty) _Frame(slot: s, url: item.slotUrl(s), title: '${item.displayTitle} - $s'),
      ];
      _showSlot();
      // Auto presentation across the set slots (24H: morning->night, Dual: lock->home, Battery: critical->charging)
      WidgetsBinding.instance.addPostFrameCallback((_) => _presStart());
      return;
    }
    if (item.isVideoType) {
      final p = Player();
      _player = p;
      _video = VideoController(p);
      _bindPlayer(p);
      p.setPlaylistMode(PlaylistMode.loop);
      p.setVolume(0); // muted autoplay like the web <video muted loop>
      if (item.fileUrl.isNotEmpty) p.open(Media(item.fileUrl), play: true);
      _imgUrl = item.thumbUrl;
      return;
    }
    final src = item.mediaSrc;
    if (src.isEmpty) return;
    if (item.isMp3) {
      final p = Player();
      _player = p;
      _bindPlayer(p);
      p.open(Media(src), play: false);
      return;
    }
    _imgUrl = src;
    _imgTitle = item.title.trim().isNotEmpty ? item.title.trim() : (item.name.isNotEmpty ? item.name : 'Focused Image Preview');
    // Rotate through every normal wallpaper in the queue, starting from the one that was opened.
    _frames = [
      for (final q in app.queueItems)
        if (q.contentType == 'WALLPAPER' && !q.isMp3 && q.mediaSrc.isNotEmpty)
          _Frame(url: q.mediaSrc, title: q.title.trim().isNotEmpty ? q.title.trim() : (q.name.isNotEmpty ? q.name : 'Wallpaper')),
    ];
    final startAt = _frames.indexWhere((f) => f.url == src);
    _presIndex = startAt > 0 ? startAt : 0;
  }

  void _bindPlayer(Player p) {
    _subs.add(p.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    }));
    _subs.add(p.stream.position.listen((v) {
      if (mounted) setState(() => _pos = v);
    }));
    _subs.add(p.stream.duration.listen((v) {
      if (mounted) setState(() => _dur = v);
    }));
    _subs.add(p.stream.completed.listen((done) {
      if (done && mounted && _snapshot.isMp3) setState(() => _playing = false);
    }));
  }

  @override
  void dispose() {
    _presTimer?.cancel();
    _copyReset?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    _title.dispose();
    _tags.dispose();
    _category.dispose();
    _description.dispose();
    if (_fullscreen) windowManager.setFullScreen(false);
    super.dispose();
  }

  // ------------------------------------------------------------- presentation
  void _showSlot() {
    final s = _activeSlot;
    if (s == null) return;
    _imgUrl = _snapshot.slotUrl(s);
    _imgTitle = '${_snapshot.displayTitle} - $s';
  }

  void _presShow(int i) {
    if (_frames.isEmpty) return;
    _presIndex = (i + _frames.length) % _frames.length;
    final f = _frames[_presIndex];
    if (f.slot != null) {
      _activeSlot = f.slot;
      _showSlot();
    } else {
      _imgUrl = f.url;
      _imgTitle = f.title;
    }
    _fadeKey++;
    if (mounted) setState(() {});
  }

  void _presStop() {
    _presTimer?.cancel();
    _presTimer = null;
    if (mounted) setState(() {});
  }

  void _presStart() {
    _presTimer?.cancel();
    _presTimer = null;
    if (_frames.length < 2) return;
    final speed = context.read<AppState>().presSpeed;
    _presTimer = Timer.periodic(Duration(milliseconds: speed), (_) => _presShow(_presIndex + 1));
    if (mounted) setState(() {});
  }

  void _cycleSpeed() {
    final app = context.read<AppState>();
    final next = kPresSpeeds[(kPresSpeeds.indexOf(app.presSpeed) + 1) % kPresSpeeds.length];
    app.setPresSpeed(next);
    if (_presPlaying) {
      _presStart();
    } else {
      setState(() {});
    }
  }

  // ------------------------------------------------------------- actions
  Future<void> _save() async {
    final app = context.read<AppState>();
    setState(() => _saving = true);
    try {
      await app.repo.saveModalMetadata(
        _account,
        widget.id,
        title: _title.text,
        tags: _tags.text,
        category: _category.text,
        description: _description.text,
        scheduledDate: _scheduled,
      );
      app.showToast('Saved "${_title.text.trim().isEmpty ? _snapshot.displayTitle : _title.text.trim()}"');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      app.showToast('Failed saving metadata: $e', 'err');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requeue() async {
    final app = context.read<AppState>();
    setState(() => _requeueing = true);
    try {
      await app.repo.requeueSingle(_account, widget.id);
      app.showToast('Requeued "${_snapshot.displayTitle}"');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      app.showToast('Failed requeueing item: $e', 'err');
      if (mounted) setState(() => _requeueing = false);
    }
  }

  Future<void> _copyToOthers() async {
    final app = context.read<AppState>();
    final item = app.itemById(widget.id) ?? _snapshot;
    setState(() {
      _copyState = 'busy';
      _copyLabel = 'Copying...';
    });
    try {
      final others = await app.repo.copyItemToOtherAccounts(_account, item);
      if (!mounted) return;
      setState(() {
        _copyState = 'done';
        _copyLabel = 'Copied to ${others.map((k) => k.toUpperCase()).join(' + ')}';
      });
      app.showToast('Copied to ${others.map(app.accountLabel).join(', ')}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _copyState = 'fail';
        _copyLabel = 'Failed - try again';
      });
      app.showToast('Copy to other accounts failed: $e', 'err');
    }
    _copyReset?.cancel();
    _copyReset = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _copyState = '';
          _copyLabel = 'Copy to Other Accounts';
        });
      }
    });
  }

  Future<void> _delete() async {
    final app = context.read<AppState>();
    final ok = await confirmDialog(
      context,
      'Permanently delete this file?\n\nThis removes it from the queue AND deletes its file(s) from R2 storage.',
      title: 'Delete file',
      okLabel: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    _presStop();
    _player?.pause();
    final res = await runPurge(context, account: app.activeProject, ids: [widget.id]);
    if (res != null && mounted) Navigator.of(context).pop();
  }

  Future<void> _pickScheduled() async {
    final now = getDhakaDate(0);
    final init = parseDateKey(_scheduled ?? '') ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      helpText: 'Scheduled upload date',
    );
    if (d != null) setState(() => _scheduled = fmtDateKey(d));
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    try {
      await windowManager.setFullScreen(_fullscreen);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _exitPreview() {
    if (_fullscreen) _toggleFullscreen();
    setState(() {
      _previewMode = false;
      _lockOn = false;
    });
  }

  // ------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final app = context.appWatch;
    final p = app.palette;
    final live = app.itemById(widget.id);
    final item = live ?? _snapshot;
    if (live != null) _snapshot = live;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_previewMode) {
            if (!_fullscreen) _exitPreview();
          } else {
            Navigator.of(context).maybePop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: p.bg,
          body: Stack(children: [
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [p.primary.withValues(alpha: 0.10), p.bg, p.accent.withValues(alpha: 0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight)))),
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: _previewMode ? _buildPreviewPage(context, item) : _buildDetailsPage(context, item, live == null),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ============================================================ details page
  Widget _buildDetailsPage(BuildContext context, QueueItem item, bool gone) {
    final p = context.pal;
    final width = MediaQuery.sizeOf(context).width;
    final stacked = width < 1040;
    return Column(key: const ValueKey('details'), children: [
      _PageBar(
        backLabel: 'Back to ${widget.backLabel}',
        crumbs: ['Home', widget.backLabel, 'Asset details'],
        onBack: () => Navigator.of(context).maybePop(),
        trailing: ZButton('Mobile preview', icon: 'fa-mobile-screen-button', small: true, onPressed: () => setState(() => _previewMode = true)),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: width < Bp.xs ? 12 : 24, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // header
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.displayTitleOrId, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: p.text)),
                          const SizedBox(height: 3),
                          Text('Modify publishing fields and review storage reference metadata', style: TextStyle(fontSize: 12.5, color: p.muted)),
                        ]),
                      ),
                      ZIconButton('fa-times', tooltip: 'Close', onPressed: () => Navigator.of(context).maybePop()),
                    ]),
                  ),
                  if (gone)
                    Container(
                      margin: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: p.warn.withValues(alpha: 0.12), border: Border.all(color: p.warn.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(p.radiusSm)),
                      child: Row(children: [
                        Fa('fa-triangle-exclamation', size: 14, color: p.warn),
                        const SizedBox(width: 10),
                        Expanded(child: Text('This file is no longer in the live queue (deleted or moved). You are looking at the last known copy.', style: TextStyle(fontSize: 12.5, color: p.text))),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: stacked
                        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _buildLeft(context, item, stacked: true),
                            const SizedBox(height: 22),
                            _buildForm(context, item),
                          ])
                        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: width < Bp.md ? 360 : 440, child: _buildLeft(context, item, stacked: false)),
                            const SizedBox(width: 26),
                            Expanded(child: _buildForm(context, item)),
                          ]),
                  ),
                  // footer
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
                    decoration: BoxDecoration(color: p.tintSoft, border: Border(top: BorderSide(color: p.border)), borderRadius: BorderRadius.vertical(bottom: Radius.circular(p.radiusLg))),
                    child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.end, children: [
                      ZButton('Save Changes', icon: 'fa-save', busy: _saving, onPressed: (_saving || gone) ? null : _save),
                      ZButton('Requeue', icon: 'fa-rotate-right', kind: ZBtnKind.soft, busy: _requeueing, onPressed: (_requeueing || gone) ? null : _requeue),
                      ZButton(
                        _copyLabel,
                        icon: _copyState == 'done' ? 'fa-check' : (_copyState == 'fail' ? 'fa-exclamation-triangle' : 'fa-share-nodes'),
                        kind: _copyState == 'done' ? ZBtnKind.success : (_copyState == 'fail' ? ZBtnKind.danger : ZBtnKind.soft),
                        busy: _copyState == 'busy',
                        onPressed: (_copyState == 'busy' || gone) ? null : _copyToOthers,
                      ),
                      ZButton('Delete', icon: 'fa-trash-alt', kind: ZBtnKind.danger, onPressed: gone ? null : _delete),
                      ZButton('Close', kind: ZBtnKind.ghost, onPressed: () => Navigator.of(context).maybePop()),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------- left column
  Widget _buildLeft(BuildContext context, QueueItem item, {required bool stacked}) {
    final app = context.appWatch;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: _buildPreviewFrame(context, item, phoneWidth: stacked ? 240 : 250)),
      const SizedBox(height: 18),
      _buildMetaInfo(context, item, app),
    ]);
  }

  /// `.modal-preview-frame` (phone + device chooser + presentation bar + slot chips + audio controls).
  Widget _buildPreviewFrame(BuildContext context, QueueItem item, {required double phoneWidth, bool forPreviewPage = false}) {
    final app = context.appWatch;
    final p = app.palette;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      PhoneMockup(deviceId: app.previewDeviceId, width: phoneWidth, showLockClock: _lockOn && forPreviewPage, child: _buildScreen(context, item)),
      const SizedBox(height: 14),
      DeviceChooser(active: app.previewDeviceId, onChanged: app.setPreviewDevice),
      if (_frames.length > 1) ...[
        const SizedBox(height: 10),
        _PresentationBar(
          playing: _presPlaying,
          count: '${_frames.isEmpty ? 0 : _presIndex + 1} / ${_frames.length}',
          speedLabel: '${app.presSpeed ~/ 1000}s',
          onPrev: () {
            _presStop();
            _presShow(_presIndex - 1);
          },
          onNext: () {
            _presStop();
            _presShow(_presIndex + 1);
          },
          onPlay: () => _presPlaying ? _presStop() : _presStart(),
          onSpeed: _cycleSpeed,
        ),
      ],
      if (item.isSetType && item.setSlots.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: item.setSlots.map((s) {
            final on = s == _activeSlot;
            return Pill(
              '${s[0].toUpperCase()}${s.substring(1)}',
              icon: _kSlotFa[s] ?? 'fa-image',
              small: true,
              color: on ? p.primary : p.tintChip,
              fg: on ? p.onPrimary : p.text,
              onTap: () {
                _presStop();
                setState(() {
                  _activeSlot = s;
                  _showSlot();
                  final fi = _frames.indexWhere((f) => f.slot == s);
                  if (fi >= 0) _presIndex = fi;
                  _fadeKey++;
                });
              },
            );
          }).toList(),
        ),
      ],
      if (item.isMp3 && _player != null) ...[
        const SizedBox(height: 12),
        SizedBox(width: phoneWidth + 60, child: _AudioBar(playing: _playing, pos: _pos, dur: _dur, onToggle: () => _playing ? _player!.pause() : _player!.play(), onSeek: (v) => _player!.seek(v))),
      ],
    ]);
  }

  /// Phone screen content per content type.
  Widget _buildScreen(BuildContext context, QueueItem item) {
    final p = context.pal;
    if (item.isVideoType && _video != null) {
      return Video(controller: _video!, fit: BoxFit.cover, controls: AdaptiveVideoControls);
    }
    if (item.isMp3) {
      final prog = _dur.inMilliseconds == 0 ? 0.0 : _pos.inMilliseconds / _dur.inMilliseconds;
      return PhoneAudioScreen(title: item.name.isNotEmpty ? item.name : 'Audio Track', playing: _playing, progress: prog);
    }
    if (_imgUrl.isEmpty) {
      return Container(color: const Color(0xff0b0d14), child: Center(child: Fa('fa-image', size: 36, color: Colors.white.withValues(alpha: 0.35))));
    }
    return Tooltip(
      message: 'Click to open full view focus preview',
      waitDuration: const Duration(milliseconds: 700),
      child: GestureDetector(
        onTap: () => _openFocusZoom(context, _imgUrl, _imgTitle),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOut,
          child: SizedBox.expand(
            key: ValueKey('$_fadeKey:$_imgUrl'),
            child: Stack(fit: StackFit.expand, children: [
              NetImage(_imgUrl, fit: BoxFit.cover),
              Positioned(
                right: 8,
                bottom: 20,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(8)),
                  child: Fa('fa-magnifying-glass-plus', size: 11, color: p.onInk),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// `modalMetaInfo` - colourful badges + failure / processing / metadata boxes + tags.
  Widget _buildMetaInfo(BuildContext context, QueueItem item, AppState app) {
    final p = app.palette;
    final ctype = item.contentType;
    final setMeta = kSetTypeMeta[ctype];
    final vidMeta = kVideoTypeMeta[ctype];
    final fileTypeLabel = ctype == 'RINGTONE' ? 'Audio Track' : (setMeta?.label ?? vidMeta?.label ?? 'Wallpaper Image');
    final fileTypeIcon = ctype == 'RINGTONE' ? 'fa-music' : (setMeta?.icon ?? vidMeta?.icon ?? 'fa-images');
    final status = item.status;
    final statusIcon = status == 'uploaded' ? 'fa-check-circle' : (status == 'processing' ? 'fa-spinner' : (status == 'failed' ? 'fa-exclamation-triangle' : 'fa-clock'));
    final sc = statusColor(status, p);
    final tags = item.tagList;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        _Badge(icon: statusIcon, label: 'Status', value: status.toUpperCase(), color: sc, spin: status == 'processing'),
        _Badge(icon: fileTypeIcon, label: 'Type', value: fileTypeLabel, color: ctype == 'RINGTONE' ? p.accent : p.primary),
        _Badge(icon: 'fa-folder', label: 'Category', value: item.category.isNotEmpty ? item.category : 'UNCLASSIFIED', color: p.info),
        _Badge(icon: 'fa-hdd', label: 'Size', value: formatBytes(item.size), color: p.muted),
      ]),
      if (item.isFailed) ...[
        const SizedBox(height: 12),
        _InfoBox(
          color: p.danger,
          icon: 'fa-triangle-exclamation',
          title: 'Why this upload failed',
          children: [
            Text(explainUploadError(item.error), style: TextStyle(fontSize: 12.5, color: p.text, height: 1.4)),
            if (item.error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(item.error, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: p.onInk, height: 1.4)),
              ),
            ],
            if (item.failedAt != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Fa('fa-clock', size: 11, color: p.muted),
                const SizedBox(width: 6),
                Text('Failed at ${fmtDhakaStamp(item.failedAt)} (Dhaka)', style: TextStyle(fontSize: 11.5, color: p.muted)),
              ]),
            ],
          ],
        ),
      ],
      ..._audioProcessing(item, p),
      if (status == 'queued' && !item.hasRequiredMetadata) ...[
        const SizedBox(height: 12),
        _InfoBox(
          color: p.warn,
          icon: 'fa-tags',
          title: 'Metadata missing - upload blocked',
          children: [
            Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, color: p.text, height: 1.4), children: [
              const TextSpan(text: 'Missing: '),
              TextSpan(text: item.metadataMissingFields.join(', '), style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: '. Fill the fields below and save - the bot will pick it up on its next run.'),
            ])),
          ],
        ),
      ],
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.tintCard, borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: p.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Fa('fa-hashtag', size: 12, color: p.primary),
            const SizedBox(width: 8),
            Text('Active Search Tags', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.text)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.isEmpty
                ? [Pill('No tags defined', small: true, outline: true, fg: p.muted)]
                : tags.map((t) => Pill(t, small: true, color: p.tintChip, fg: p.text)).toList(),
          ),
        ]),
      ),
      if (item.prompt.trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        _InfoBox(
          color: p.accent,
          icon: 'fa-wand-magic-sparkles',
          title: 'Generation prompt',
          children: [SelectableText(item.prompt.trim(), style: TextStyle(fontSize: 12, color: p.text, height: 1.45))],
        ),
      ],
    ]);
  }

  /// `audioProcessingHtml(item)` - ringtone audit trail.
  List<Widget> _audioProcessing(QueueItem item, ZedgePalette p) {
    if (item.contentType != 'RINGTONE' || !item.hasAutoProcessFlag) return const [];
    String f(dynamic v, [String unit = '']) => v == null ? '–' : '$v$unit';
    if (!item.autoProcess) {
      return [
        const SizedBox(height: 12),
        _InfoBox(color: p.muted, icon: 'fa-sliders-h', title: 'Auto-process was OFF for this ringtone', children: [
          Text('Uploaded as generated (no silence trim, no volume boost).', style: TextStyle(fontSize: 12.5, color: p.text)),
        ]),
      ];
    }
    if (!item.processed) {
      return [
        const SizedBox(height: 12),
        _InfoBox(color: p.warn, icon: 'fa-triangle-exclamation', title: 'RAW audio — silence trim / volume boost FAILED', children: [
          Text(item.processError.isNotEmpty ? item.processError : 'ffmpeg processing failed', style: TextStyle(fontSize: 12.5, color: p.text)),
        ]),
      ];
    }
    final pr = item.processing;
    TextStyle ks = TextStyle(fontSize: 12.5, color: p.text, height: 1.5);
    Widget kv(String k, String v) => Text.rich(TextSpan(style: ks, children: [TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w800)), TextSpan(text: v)]));
    return [
      const SizedBox(height: 12),
      _InfoBox(color: p.ok, icon: 'fa-wave-square', title: 'Audio processed (silence trim + volume boost)', children: [
        kv('Length', '${f(pr['durationBefore'], 's')} → ${f(pr['durationAfter'], 's')} (trimmed ${f(pr['trimmedSec'], 's')})'),
        kv('Peak', '${f(pr['peakBeforeDb'], ' dB')} → ${f(pr['peakAfterDb'], ' dB')}'),
        kv('Gain', '+${f(pr['gainDb'], ' dB')} (normalize ${f(pr['normalizeDb'], ' dB')} + boost ${f(pr['boostPct'], '%')})'),
        Text.rich(TextSpan(style: ks, children: [
          const TextSpan(text: 'Silence threshold: ', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: '${f(pr['silenceThreshold'])} · '),
          const TextSpan(text: 'Pad: ', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: f(pr['padMs'], ' ms')),
        ])),
      ]),
    ];
  }

  // ------------------------------------------------------------- right column (form)
  Widget _buildForm(BuildContext context, QueueItem item) {
    final p = context.pal;
    InputDecoration deco(String hint) => InputDecoration(hintText: hint);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _FormLabel(icon: 'fa-heading', text: 'Item Title'),
      TextField(controller: _title, decoration: deco('Title used in publishing')),
      const SizedBox(height: 16),
      _FormLabel(icon: 'fa-tags', text: 'Search Tags'),
      TextField(controller: _tags, decoration: deco('Tags (e.g. cute, neon, cartoon)')),
      const SizedBox(height: 16),
      _FormLabel(icon: 'fa-folder-open', text: 'Main Category'),
      TextField(controller: _category, decoration: deco('CATEGORY (Upper Case)'), textCapitalization: TextCapitalization.characters),
      const SizedBox(height: 16),
      _FormLabel(icon: 'fa-align-left', text: 'Publishing Description'),
      TextField(controller: _description, decoration: deco('Describe the media context...'), minLines: 4, maxLines: 8),
      const SizedBox(height: 16),
      _FormLabel(icon: 'fa-thumbtack', text: 'Scheduled Upload Date (optional)'),
      Row(children: [
        Expanded(
          child: InkWell(
            onTap: _pickScheduled,
            borderRadius: BorderRadius.circular(p.radiusSm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: p.tintCard, borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: _scheduled == null ? p.border : p.primary.withValues(alpha: 0.7))),
              child: Row(children: [
                Fa('fa-calendar-alt', size: 13, color: _scheduled == null ? p.muted : p.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _scheduled == null ? 'Not pinned - automatic rotation' : '${fmtPinDate(_scheduled)}  ·  $_scheduled',
                    style: TextStyle(fontSize: 13, color: _scheduled == null ? p.muted : p.text, fontWeight: _scheduled == null ? FontWeight.w500 : FontWeight.w700),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ZButton('Pick date', icon: 'fa-calendar-day', kind: ZBtnKind.soft, small: true, onPressed: _pickScheduled),
        if (_scheduled != null) ...[
          const SizedBox(width: 6),
          ZIconButton('fa-times', tooltip: 'Clear date (back to automatic rotation)', onPressed: () => setState(() => _scheduled = null)),
        ],
      ]),
      const SizedBox(height: 6),
      Text('Pin this file to a specific day. Leave empty for automatic rotation order.', style: TextStyle(fontSize: 11.5, color: p.muted)),
      const SizedBox(height: 22),
      // storage reference metadata
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: p.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Fa('fa-database', size: 12, color: p.primary),
            const SizedBox(width: 8),
            Text('Storage reference', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.text)),
          ]),
          const SizedBox(height: 8),
          KV('Queue ID', item.id),
          KV('Account', context.appWatch.accountLabel(_account)),
          KV('File name', item.name.isNotEmpty ? item.name : '–'),
          KV('Content type', item.contentType),
          if (item.createdAt != null) KV('Added', fmtDhakaStamp(item.createdAt is num ? item.createdAt as num : null)),
          if (item.fileUrl.isNotEmpty)
            KV('R2 URL', item.fileUrl, vWidget: Row(mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: Text(item.fileUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.muted))),
              const SizedBox(width: 6),
              ZIconButton('fa-copy', size: 26, tooltip: 'Copy URL', onPressed: () {
                Clipboard.setData(ClipboardData(text: item.fileUrl));
                context.app.showToast('URL copied');
              }),
            ])),
          if (item.isSetType)
            for (final s in item.setSlots)
              if (item.slotUrl(s).isNotEmpty) KV('Slot · $s', item.slotUrl(s).split('/').last),
          if (item.isVideoType && item.thumbUrl.isNotEmpty) KV('Thumbnail', item.thumbUrl.split('/').last),
        ]),
      ),
    ]);
  }

  // ============================================================ v27 mobile preview page
  Widget _buildPreviewPage(BuildContext context, QueueItem item) {
    final app = context.appWatch;
    final p = app.palette;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < Bp.sm;
    final phoneW = (250 * _pvZoom / 100).clamp(160, 520).toDouble();

    final tools = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Segmented<String>(
        small: true,
        options: const [('aurora', 'Aurora'), ('dark', 'Dark'), ('light', 'Light'), ('blur', 'Blur')],
        value: _pvBg,
        onChanged: (v) => setState(() => _pvBg = v),
      ),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Fa('fa-mobile-screen', size: 12, color: p.muted),
        const SizedBox(width: 6),
        Text('Size', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
        SizedBox(
          width: 150,
          child: Slider(value: _pvZoom, min: 80, max: 180, divisions: 20, label: '${_pvZoom.round()}%', onChanged: (v) => setState(() => _pvZoom = v)),
        ),
      ]),
      ZButton('Lock screen', icon: 'fa-lock', small: true, kind: _lockOn ? ZBtnKind.primary : ZBtnKind.ghost, onPressed: () => setState(() => _lockOn = !_lockOn)),
      ZButton(_fullscreen ? 'Exit fullscreen' : 'Fullscreen', icon: _fullscreen ? 'fa-compress' : 'fa-expand', small: true, kind: ZBtnKind.ghost, onPressed: _toggleFullscreen),
    ]);

    return Column(key: const ValueKey('preview'), children: [
      Container(
        padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 24, vertical: 12),
        decoration: BoxDecoration(color: p.headerColor.withValues(alpha: 0.75), border: Border(bottom: BorderSide(color: p.border))),
        child: Flex(
          direction: narrow ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            ZButton('Back to details', icon: 'fa-arrow-left', small: true, kind: ZBtnKind.ghost, onPressed: _exitPreview),
            SizedBox(width: narrow ? 0 : 16, height: narrow ? 10 : 0),
            Expanded(
              flex: narrow ? 0 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(item.displayTitleOrId, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text)),
                Text('See the file exactly like it looks on a phone', style: TextStyle(fontSize: 11.5, color: p.muted)),
              ]),
            ),
            SizedBox(width: narrow ? 0 : 16, height: narrow ? 10 : 0),
            tools,
          ],
        ),
      ),
      Expanded(
        child: Flex(
          direction: width < 1100 ? Axis.vertical : Axis.horizontal,
          children: [
            Expanded(
              flex: width < 1100 ? 3 : 1,
              child: _PreviewStage(
                bg: _pvBg,
                imgUrl: _imgUrl,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Center(child: _buildPreviewFrame(context, item, phoneWidth: phoneW, forPreviewPage: true)),
                ),
              ),
            ),
            if (!_fullscreen)
              Container(
                width: width < 1100 ? double.infinity : 380,
                height: width < 1100 ? 260 : null,
                decoration: BoxDecoration(color: p.sidebarColor.withValues(alpha: 0.85), border: Border(left: width < 1100 ? BorderSide.none : BorderSide(color: p.border), top: width < 1100 ? BorderSide(color: p.border) : BorderSide.none)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: p.text)),
                    const SizedBox(height: 12),
                    _buildMetaInfo(context, item, app),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: p.tintSoft, borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: p.border)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Fa('fa-lightbulb', size: 13, color: p.warn),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(TextSpan(style: TextStyle(fontSize: 12, color: p.muted, height: 1.45), children: const [
                            TextSpan(text: 'Switch iOS / Android frame under the phone, drag '),
                            TextSpan(text: 'Size', style: TextStyle(fontWeight: FontWeight.w800)),
                            TextSpan(text: ', toggle '),
                            TextSpan(text: 'Lock screen', style: TextStyle(fontWeight: FontWeight.w800)),
                            TextSpan(text: ' for a real-device look, or go '),
                            TextSpan(text: 'Fullscreen', style: TextStyle(fontWeight: FontWeight.w800)),
                            TextSpan(text: ' to show a client.'),
                          ])),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}

// =================================================================== pieces

class _PageBar extends StatelessWidget {
  const _PageBar({required this.backLabel, required this.crumbs, required this.onBack, this.trailing});
  final String backLabel;
  final List<String> crumbs;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final narrow = MediaQuery.sizeOf(context).width < Bp.xs;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 24, vertical: 10),
      decoration: BoxDecoration(color: p.headerColor.withValues(alpha: 0.75), border: Border(bottom: BorderSide(color: p.border))),
      child: Row(children: [
        ZButton(backLabel, icon: 'fa-arrow-left', small: true, kind: ZBtnKind.ghost, onPressed: onBack),
        if (!narrow) ...[
          const SizedBox(width: 16),
          Expanded(
            child: Row(children: [
              for (var i = 0; i < crumbs.length; i++) ...[
                if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Fa('fa-chevron-right', size: 9, color: p.muted)),
                Text(crumbs[i], style: TextStyle(fontSize: 12.5, color: i == crumbs.length - 1 ? p.text : p.muted, fontWeight: i == crumbs.length - 1 ? FontWeight.w800 : FontWeight.w500)),
              ],
            ]),
          ),
        ] else
          const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.value, required this.color, this.spin = false});
  final String icon, label, value;
  final Color color;
  final bool spin;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: color.withValues(alpha: 0.45))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        spin ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: color)) : Fa(icon, size: 12, color: color),
        const SizedBox(width: 8),
        Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, color: p.text), children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: value),
        ])),
      ]),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.color, required this.icon, required this.title, required this.children});
  final Color color;
  final String icon, title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(p.radiusSm), border: Border.all(color: color.withValues(alpha: 0.45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Fa(icon, size: 13, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.text))),
        ]),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel({required this.icon, required this.text});
  final String icon, text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        Fa(icon, size: 12, color: p.primary),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.text)),
      ]),
    );
  }
}

/// `#presentationBar` - prev / play-pause / next / "i / n" / speed.
class _PresentationBar extends StatelessWidget {
  const _PresentationBar({
    required this.playing,
    required this.count,
    required this.speedLabel,
    required this.onPrev,
    required this.onNext,
    required this.onPlay,
    required this.onSpeed,
  });
  final bool playing;
  final String count, speedLabel;
  final VoidCallback onPrev, onNext, onPlay, onSpeed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: p.tintCard, borderRadius: BorderRadius.circular(999), border: Border.all(color: p.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ZIconButton('fa-backward-step', size: 30, tooltip: 'Previous', onPressed: onPrev),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Auto presentation',
          child: InkWell(
            onTap: onPlay,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(gradient: playing ? p.primaryGradient : null, color: playing ? null : p.tintChip, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Fa(playing ? 'fa-pause' : 'fa-play', size: 12, color: playing ? p.onPrimary : p.text),
            ),
          ),
        ),
        const SizedBox(width: 4),
        ZIconButton('fa-forward-step', size: 30, tooltip: 'Next', onPressed: onNext),
        const SizedBox(width: 8),
        Text(count, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Change speed',
          child: InkWell(
            onTap: onSpeed,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: p.tintChip, borderRadius: BorderRadius.circular(999)),
              child: Text(speedLabel, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: p.text)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// `<audio controls>` replacement for ringtones.
class _AudioBar extends StatelessWidget {
  const _AudioBar({required this.playing, required this.pos, required this.dur, required this.onToggle, required this.onSeek});
  final bool playing;
  final Duration pos, dur;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final total = dur.inMilliseconds.toDouble();
    final v = total <= 0 ? 0.0 : pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: p.tintCard, borderRadius: BorderRadius.circular(999), border: Border.all(color: p.border)),
      child: Row(children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(gradient: p.primaryGradient, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Fa(playing ? 'fa-pause' : 'fa-play', size: 12, color: p.onPrimary),
          ),
        ),
        const SizedBox(width: 6),
        Text(_fmt(pos), style: TextStyle(fontSize: 11, color: p.muted, fontFeatures: const [ui.FontFeature.tabularFigures()])),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: const RoundSliderOverlayShape(overlayRadius: 12)),
            child: Slider(value: v, min: 0, max: total <= 0 ? 1 : total, onChanged: total <= 0 ? null : (x) => onSeek(Duration(milliseconds: x.round()))),
          ),
        ),
        Text(_fmt(dur), style: TextStyle(fontSize: 11, color: p.muted, fontFeatures: const [ui.FontFeature.tabularFigures()])),
      ]),
    );
  }
}

/// `.v27-pv-stage[data-bg]` backgrounds: aurora / dark / light / blur.
class _PreviewStage extends StatelessWidget {
  const _PreviewStage({required this.bg, required this.imgUrl, required this.child});
  final String bg;
  final String imgUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget backdrop;
    switch (bg) {
      case 'dark':
        backdrop = const DecoratedBox(decoration: BoxDecoration(color: Color(0xff07080c)));
        break;
      case 'light':
        backdrop = const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xfff6f7fb), Color(0xffe9ecf5)], begin: Alignment.topCenter, end: Alignment.bottomCenter)));
        break;
      case 'blur':
        backdrop = Stack(fit: StackFit.expand, children: [
          if (imgUrl.isNotEmpty) NetImage(imgUrl, fit: BoxFit.cover) else const DecoratedBox(decoration: BoxDecoration(color: Color(0xff0b0d14))),
          ClipRect(child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(color: Colors.black.withValues(alpha: 0.35)))),
        ]);
        break;
      default:
        backdrop = Stack(fit: StackFit.expand, children: [
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xff06111f), Color(0xff0b1a2c)], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
          Positioned(top: -120, left: -80, child: _Glow(color: p.primary.withValues(alpha: 0.55), size: 420)),
          Positioned(bottom: -140, right: -60, child: _Glow(color: p.accent.withValues(alpha: 0.45), size: 480)),
          Positioned(top: 120, right: 160, child: _Glow(color: const Color(0xff34d399).withValues(alpha: 0.35), size: 260)),
        ]);
    }
    return Stack(fit: StackFit.expand, children: [backdrop, child]);
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      );
}

// =================================================================== zoom module

/// `openFocusZoom(src, title)` - premium focus/zoom dialog (0.2 .. 5.0, step 0.2).
Future<void> _openFocusZoom(BuildContext context, String src, String title) {
  if (src.isEmpty) return Future.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.85),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, a, b) => _FocusZoom(src: src, title: title),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1).animate(anim), child: child)),
  );
}

class _FocusZoom extends StatefulWidget {
  const _FocusZoom({required this.src, required this.title});
  final String src, title;
  @override
  State<_FocusZoom> createState() => _FocusZoomState();
}

class _FocusZoomState extends State<_FocusZoom> {
  final TransformationController _tc = TransformationController();
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _tc.addListener(() {
      final s = _tc.value.getMaxScaleOnAxis();
      if ((s - _scale).abs() > 0.001 && mounted) setState(() => _scale = s);
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _setScale(double s) {
    _scale = s.clamp(0.2, 5.0).toDouble();
    _tc.value = Matrix4.diagonal3Values(_scale, _scale, 1);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final size = MediaQuery.sizeOf(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.equal): () => _setScale(_scale + 0.2),
        const SingleActivator(LogicalKeyboardKey.add): () => _setScale(_scale + 0.2),
        const SingleActivator(LogicalKeyboardKey.minus): () => _setScale(_scale - 0.2),
        const SingleActivator(LogicalKeyboardKey.digit0): () => _setScale(1),
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: size.width * 0.94,
              height: size.height * 0.92,
              decoration: BoxDecoration(color: const Color(0xff0b0d14), borderRadius: BorderRadius.circular(p.radiusLg), border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
                  child: Row(children: [
                    Expanded(child: Text(widget.title.isEmpty ? 'Focused Image View' : widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
                    _ZoomBtn(icon: 'fa-minus', tooltip: 'Zoom Out', onTap: () => _setScale(_scale - 0.2)),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Reset Scale',
                      child: InkWell(
                        onTap: () => _setScale(1),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                          child: Text('${(_scale * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _ZoomBtn(icon: 'fa-plus', tooltip: 'Zoom In', onTap: () => _setScale(_scale + 0.2)),
                    const SizedBox(width: 10),
                    _ZoomBtn(icon: 'fa-times', tooltip: 'Close Overlay', onTap: () => Navigator.of(context).pop(), danger: true),
                  ]),
                ),
                Expanded(
                  child: InteractiveViewer(
                    transformationController: _tc,
                    minScale: 0.2,
                    maxScale: 5,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    child: Center(child: NetImage(widget.src, fit: BoxFit.contain)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Scroll / pinch to zoom · drag to pan · + / − / 0 keys · Esc to close', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  const _ZoomBtn({required this.icon, required this.tooltip, required this.onTap, this.danger = false});
  final String icon, tooltip;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: danger ? const Color(0xffef4444).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Fa(icon, size: 12, color: danger ? const Color(0xffff8a8a) : Colors.white),
          ),
        ),
      );
}
