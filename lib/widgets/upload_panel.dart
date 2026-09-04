import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../services/upload_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Upload panel of the Upload Queue tab - every content type of the dashboard:
/// single JPEG/MP3 (multi-select), 24H / Dual / Battery sets and videos.
class UploadPanel extends StatefulWidget {
  const UploadPanel({super.key});

  @override
  State<UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends State<UploadPanel> {
  String _mode = 'SINGLE';
  final Map<String, PickedFile> _slotFiles = <String, PickedFile>{};
  PickedFile? _video;
  PickedFile? _cover;
  List<PickedFile> _singles = <PickedFile>[];
  final List<String> _log = <String>[];

  static const List<MapEntry<String, String>> _modes =
      <MapEntry<String, String>>[
    MapEntry<String, String>('SINGLE', 'Wallpaper / MP3'),
    MapEntry<String, String>('WALLPAPER_24H', '24H Set'),
    MapEntry<String, String>('WALLPAPER_DUAL', 'Dual Set'),
    MapEntry<String, String>('WALLPAPER_BATTERY', 'Battery Set'),
    MapEntry<String, String>('LIVE_WALLPAPER', 'Live Wallpaper'),
    MapEntry<String, String>('CHARGING_ANIMATION', 'Charging Animation'),
  ];

  void _note(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 40) _log.removeLast();
    });
  }

  void _reset() {
    _slotFiles.clear();
    _video = null;
    _cover = null;
    _singles = <PickedFile>[];
  }

  // ------------------------------------------------------------- pickers

  Future<void> _pickSingles() async {
    final List<PickedFile> files = await pickFiles(
      extensions: <String>[...kImageExt, ...kAudioExt],
      title: 'Select wallpapers (JPEG) or ringtones (MP3)',
    );
    if (files.isEmpty) return;
    setState(() => _singles = <PickedFile>[..._singles, ...files]);
  }

  Future<void> _pickSlot(String slot) async {
    final List<PickedFile> files = await pickFiles(
      extensions: kImageExt,
      multiple: false,
      title: 'Image for "$slot"',
    );
    if (files.isEmpty) return;
    setState(() => _slotFiles[slot] = files.first);
  }

  Future<void> _pickAllSlots(List<String> slots) async {
    final List<PickedFile> files = await pickFiles(
      extensions: kImageExt,
      title: 'Select ${slots.length} images at once (sorted by name)',
    );
    if (files.isEmpty) return;
    if (files.length != slots.length) {
      showSnack(context,
          'Pick exactly ${slots.length} images (${files.length} selected)',
          error: true);
      return;
    }
    files.sort((PickedFile a, PickedFile b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      for (int i = 0; i < slots.length; i++) {
        _slotFiles[slots[i]] = files[i];
      }
    });
  }

  Future<void> _pickVideo() async {
    final List<PickedFile> files = await pickFiles(
      extensions: kVideoExt,
      multiple: false,
      title: 'Select MP4 / MOV (max 50 MB)',
    );
    if (files.isEmpty) return;
    if (files.first.size > kVideoMaxBytes) {
      showSnack(context, 'Video exceeds the 50 MB limit', error: true);
      return;
    }
    setState(() => _video = files.first);
  }

  Future<void> _pickCover() async {
    final List<PickedFile> files = await pickFiles(
      extensions: kImageExt,
      multiple: false,
      title: 'Cover image (optional)',
    );
    if (files.isEmpty) return;
    setState(() => _cover = files.first);
  }

  // ------------------------------------------------------------- submit

  Future<void> _submit() async {
    final AppState state = context.read<AppState>();
    if (!state.beginUpload('Preparing upload...')) {
      showSnack(context, 'Another upload is already in progress', error: true);
      return;
    }
    int done = 0;
    try {
      if (_mode == 'SINGLE') {
        if (_singles.isEmpty) throw Exception('Pick at least one file');
        final List<PickedFile> files = List<PickedFile>.from(_singles);
        for (int i = 0; i < files.length; i++) {
          final PickedFile f = files[i];
          if (state.nameExists(f.name)) {
            final bool ok = await confirmDialog(
              context,
              title: 'Duplicate name',
              message:
                  '"${f.name}" already exists in ${state.account.label}. Upload anyway?',
              confirmLabel: 'Upload anyway',
            );
            if (!ok) {
              _note('Skipped duplicate ${f.name}');
              continue;
            }
          }
          state.reportUpload(
              'Uploading ${i + 1}/${files.length}: ${f.name}', i / files.length);
          final Map<String, dynamic> row =
              await prepareSingleRow(f, state.account, log: _note);
          await state.addQueueItem(row);
          done++;
          _note('Queued ${row['name']}');
        }
      } else if (isSetType(_mode)) {
        final List<String> slots = kSetSlots[_mode]!;
        final List<String> missing =
            slots.where((String s) => !_slotFiles.containsKey(s)).toList();
        if (missing.isNotEmpty) {
          throw Exception('Missing slot(s): ${missing.join(', ')}');
        }
        state.reportUpload('Uploading ${metaFor(_mode).label}...', 0.1);
        final Map<String, dynamic> row = await prepareSetRow(
          _mode,
          Map<String, PickedFile>.from(_slotFiles),
          state.account,
          state.dhakaNow,
          log: (String m) {
            _note(m);
            state.reportUpload(m);
          },
        );
        await state.addQueueItem(row);
        done = 1;
        _note('Queued ${row['name']}');
      } else {
        final PickedFile? video = _video;
        if (video == null) throw Exception('Pick a video first');
        state.reportUpload('Uploading ${video.name}...', 0.1);
        final Map<String, dynamic> row = await prepareVideoRow(
          _mode,
          video,
          _cover,
          state.account,
          log: (String m) {
            _note(m);
            state.reportUpload(m);
          },
        );
        await state.addQueueItem(row);
        done = 1;
        _note('Queued ${row['name']}');
      }
      if (mounted) {
        showSnack(context,
            done == 0 ? 'Nothing uploaded' : '$done item(s) added to ${state.account.label}');
        setState(_reset);
      }
    } catch (e) {
      _note('ERROR: $e');
      if (mounted) showSnack(context, 'Upload failed: $e', error: true);
    } finally {
      state.endUpload();
    }
  }

  // ------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final bool busy = state.uploading;

    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(
            icon: Icons.cloud_upload_rounded,
            title: 'Upload to ${state.account.label}',
            subtitle:
                'Images auto-resize to ${kImageTargetWidth}x$kImageTargetHeight JPEG - MP3 ringtones - MP4/MOV up to 50 MB',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _modes.map((MapEntry<String, String> m) {
              final bool on = m.key == _mode;
              return ChoiceChip(
                label: Text(m.value),
                selected: on,
                showCheckmark: false,
                avatar: Icon(
                  m.key == 'SINGLE'
                      ? Icons.image_rounded
                      : Zc.typeIcon(m.key),
                  size: 15,
                  color: on ? Zc.ink : Zc.muted,
                ),
                selectedColor: Zc.gold,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: on ? Zc.ink : Zc.inkSoft,
                ),
                onSelected: busy
                    ? null
                    : (_) => setState(() {
                          _mode = m.key;
                          _reset();
                        }),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (_mode == 'SINGLE') _singleBody(busy),
          if (isSetType(_mode)) _setBody(busy),
          if (isVideoType(_mode)) _videoBody(busy),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              GradientButton(
                label: busy ? 'Uploading...' : 'Upload & queue',
                icon: Icons.rocket_launch_rounded,
                busy: busy,
                onPressed: busy ? null : _submit,
              ),
              const SizedBox(width: 10),
              if (_hasSelection && !busy)
                TextButton.icon(
                  onPressed: () => setState(_reset),
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('Clear'),
                ),
            ],
          ),
          if (_log.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 130),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: Zc.darkGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _log.join('\n'),
                  style: const TextStyle(
                    color: Color(0xFFFFE873),
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _hasSelection =>
      _singles.isNotEmpty || _slotFiles.isNotEmpty || _video != null;

  Widget _singleBody(bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DropZone(
          icon: Icons.add_photo_alternate_rounded,
          title: _singles.isEmpty
              ? 'Select JPEG wallpapers or MP3 ringtones'
              : '${_singles.length} file(s) selected',
          subtitle: 'Multi-select supported - each file becomes one queue row',
          onTap: busy ? null : _pickSingles,
        ),
        if (_singles.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _singles
                .map(
                  (PickedFile f) => InputChip(
                    avatar: Icon(
                      f.isAudio ? Icons.music_note_rounded : Icons.image_rounded,
                      size: 15,
                    ),
                    label: Text(
                      '${f.name} - ${(f.size / 1024).toStringAsFixed(0)} KB',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onDeleted: busy
                        ? null
                        : () => setState(() => _singles.remove(f)),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _setBody(bool busy) {
    final List<String> slots = kSetSlots[_mode]!;
    final TypeMeta meta = metaFor(_mode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${meta.label}: ${slots.length} images - ${slots.join(' / ')}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Zc.inkSoft,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _pickAllSlots(slots),
              icon: const Icon(Icons.select_all_rounded, size: 15),
              label: Text('Select all ${slots.length} at once'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final int cols = c.maxWidth >= 720 ? slots.length.clamp(2, 4) : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.78,
              children: slots.map((String slot) {
                final PickedFile? f = _slotFiles[slot];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: busy ? null : () => _pickSlot(slot),
                  child: Container(
                    decoration: BoxDecoration(
                      color: f == null ? Zc.cream : Zc.panel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: f == null ? Zc.line : Zc.okDeep,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: f == null
                              ? const Center(
                                  child: Icon(Icons.add_rounded,
                                      color: Zc.muted, size: 28),
                                )
                              : ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(15)),
                                  child: Image.memory(
                                    f.bytes,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    gaplessPlayback: true,
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: <Widget>[
                              Text(
                                slot.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w900,
                                  color: Zc.ink,
                                ),
                              ),
                              Text(
                                f?.name ?? 'tap to choose',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Zc.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _videoBody(bool busy) {
    final TypeMeta meta = metaFor(_mode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DropZone(
          icon: Icons.movie_rounded,
          title: _video == null
              ? 'Select ${meta.label} video (MP4 / MOV)'
              : '${_video!.name} - ${(_video!.size / 1048576).toStringAsFixed(1)} MB',
          subtitle: 'Max 50 MB - vertical 9:16 recommended',
          onTap: busy ? null : _pickVideo,
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _DropZone(
                icon: Icons.image_rounded,
                dense: true,
                title: _cover == null
                    ? 'Cover image (optional)'
                    : 'Cover: ${_cover!.name}',
                subtitle: _cover == null
                    ? 'Without a cover a branded placeholder is generated'
                    : 'Resized to ${kImageTargetWidth}x$kImageTargetHeight',
                onTap: busy ? null : _pickCover,
              ),
            ),
            if (_cover != null)
              IconButton(
                onPressed: () => setState(() => _cover = null),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ],
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.dense = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(dense ? 12 : 20),
        decoration: BoxDecoration(
          color: Zc.cream,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE6DCBE), width: 1.5),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: dense ? 36 : 48,
              height: dense ? 36 : 48,
              decoration: BoxDecoration(
                gradient: Zc.goldGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Zc.ink, size: dense ? 18 : 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: dense ? 12.5 : 14,
                      color: Zc.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: Zc.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.folder_open_rounded, color: Zc.muted),
          ],
        ),
      ),
    );
  }
}
