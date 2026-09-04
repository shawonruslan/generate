import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../services/upload_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/stat_card.dart';
import '../widgets/ui.dart';

/// One unit of work: a single file, a set (N files) or a video.
class _Group {
  _Group({required this.label, required this.contentType, required this.files});

  final String label;
  final String contentType;
  final List<PickedFile> files;
  ZedgeAccount? target;
  String status = 'pending';
  String? error;
}

/// Distribute: bulk round-robin upload across Zedge 1 / 2 / 3.
class DistributeTab extends StatefulWidget {
  const DistributeTab({super.key});

  @override
  State<DistributeTab> createState() => _DistributeTabState();
}

class _DistributeTabState extends State<DistributeTab> {
  String _mode = 'SINGLE';
  List<PickedFile> _files = <PickedFile>[];
  List<_Group> _groups = <_Group>[];
  final Set<String> _sessionNames = <String>{};
  final List<String> _log = <String>[];
  int _pointer = 0;
  bool _running = false;
  int _done = 0;

  static const List<MapEntry<String, String>> _modes =
      <MapEntry<String, String>>[
    MapEntry<String, String>('SINGLE', 'Single (JPEG / MP3)'),
    MapEntry<String, String>('WALLPAPER_24H', '24H sets (x4)'),
    MapEntry<String, String>('WALLPAPER_DUAL', 'Dual sets (x2)'),
    MapEntry<String, String>('WALLPAPER_BATTERY', 'Battery sets (x4)'),
    MapEntry<String, String>('LIVE_WALLPAPER', 'Live wallpapers'),
    MapEntry<String, String>('CHARGING_ANIMATION', 'Charging animations'),
  ];

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((SharedPreferences p) {
      if (mounted) setState(() => _pointer = p.getInt('distPointer') ?? 0);
    });
  }

  void _note(String m) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, m);
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<void> _pick() async {
    final List<String> ext = _mode == 'SINGLE'
        ? <String>[...kImageExt, ...kAudioExt]
        : isVideoType(_mode)
            ? kVideoExt
            : kImageExt;
    final List<PickedFile> files = await pickFiles(extensions: ext);
    if (files.isEmpty) return;
    setState(() {
      _files = <PickedFile>[..._files, ...files]
        ..sort((PickedFile a, PickedFile b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _groups = <_Group>[];
    });
  }

  /// Builds the plan: validates chunking and assigns round-robin targets.
  String? _plan() {
    final List<_Group> groups = <_Group>[];
    if (_files.isEmpty) return 'Pick files first';

    if (_mode == 'SINGLE') {
      for (final PickedFile f in _files) {
        groups.add(_Group(
          label: f.name,
          contentType: f.isAudio ? 'AUDIO' : 'WALLPAPER',
          files: <PickedFile>[f],
        ));
      }
    } else if (isSetType(_mode)) {
      final int n = kSetSlots[_mode]!.length;
      if (_files.length % n != 0) {
        return '${metaFor(_mode).label} needs a multiple of $n images '
            '(${_files.length} selected). Files are grouped in name order.';
      }
      for (int i = 0; i < _files.length; i += n) {
        final List<PickedFile> chunk = _files.sublist(i, i + n);
        groups.add(_Group(
          label: '${metaFor(_mode).label} #${groups.length + 1}  (${chunk.first.name} ...)',
          contentType: _mode,
          files: chunk,
        ));
      }
    } else {
      for (final PickedFile f in _files) {
        if (f.size > kVideoMaxBytes) return '${f.name} exceeds 50 MB';
        groups.add(_Group(label: f.name, contentType: _mode, files: <PickedFile>[f]));
      }
    }

    int p = _pointer;
    for (final _Group g in groups) {
      final bool dup = g.files.any((PickedFile f) => _sessionNames.contains(f.name));
      if (dup) {
        g.status = 'skipped';
        g.error = 'already uploaded in this session';
        continue;
      }
      g.target = kAccounts[p % kAccounts.length];
      p++;
    }
    setState(() => _groups = groups);
    return null;
  }

  Future<void> _run() async {
    final AppState state = context.read<AppState>();
    final List<_Group> todo =
        _groups.where((_Group g) => g.status == 'pending').toList();
    if (todo.isEmpty) return;
    final bool ok = await confirmDialog(
      context,
      title: 'Distribute ${todo.length} item(s)?',
      message: 'Round-robin starting at ${todo.first.target?.label}. '
          'Images are resized to ${kImageTargetWidth}x$kImageTargetHeight before upload.',
      confirmLabel: 'Start',
    );
    if (!ok || !mounted) return;
    if (!state.beginUpload('Distributing...')) {
      showSnack(context, 'Another upload is already in progress', error: true);
      return;
    }
    setState(() {
      _running = true;
      _done = 0;
    });
    int index = 0;
    for (final _Group g in todo) {
      index++;
      final ZedgeAccount target = g.target!;
      setState(() => g.status = 'uploading');
      state.reportUpload(
          '${index}/${todo.length} -> ${target.label}: ${g.label}', (index - 1) / todo.length);
      try {
        Map<String, dynamic> row;
        if (g.contentType == 'AUDIO' || g.contentType == 'WALLPAPER') {
          row = await prepareSingleRow(g.files.first, target, log: _note);
        } else if (isSetType(g.contentType)) {
          final List<String> slots = kSetSlots[g.contentType]!;
          final Map<String, PickedFile> slotFiles = <String, PickedFile>{};
          for (int i = 0; i < slots.length; i++) {
            slotFiles[slots[i]] = g.files[i];
          }
          row = await prepareSetRow(g.contentType, slotFiles, target, state.dhakaNow,
              log: _note);
        } else {
          row = await prepareVideoRow(g.contentType, g.files.first, null, target,
              log: _note);
        }
        row['distributedTo'] = target.label;
        await state.addQueueItemTo(target, row);
        for (final PickedFile f in g.files) {
          _sessionNames.add(f.name);
        }
        setState(() {
          g.status = 'done';
          _done++;
        });
        _note('OK  ${g.label} -> ${target.label}');
      } catch (e) {
        setState(() {
          g.status = 'failed';
          g.error = '$e';
        });
        _note('FAIL ${g.label}: $e');
      }
      _pointer = (_pointer + 1) % kAccounts.length;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('distPointer', _pointer);
    state.endUpload();
    if (mounted) {
      setState(() => _running = false);
      showSnack(context, 'Distribution finished: $_done/${todo.length} uploaded');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final bool busy = state.uploading || _running;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool wide = c.maxWidth >= 900;
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 8, wide ? 24 : 14, 32),
          children: <Widget>[
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionTitle(
                    icon: Icons.hub_rounded,
                    title: 'Distribute to all accounts',
                    subtitle:
                        'Round-robin Zedge 1 > Zedge 2 > Zedge 3 - sets are grouped in file-name order',
                    gradient: Zc.accentGradient,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: kAccounts.map((ZedgeAccount a) {
                      final bool next = kAccounts[_pointer % kAccounts.length].id == a.id;
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: next ? Zc.goldGradient : null,
                            color: next ? null : Zc.cream,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: next ? Zc.goldDeep : Zc.line),
                          ),
                          child: Column(
                            children: <Widget>[
                              Text(
                                a.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: Zc.ink,
                                ),
                              ),
                              Text(
                                next ? 'NEXT TARGET' : 'node ready',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w800,
                                  color: next ? Zc.ink : Zc.muted,
                                ),
                              ),
                              Text(
                                '${_groups.where((_Group g) => g.target?.id == a.id && g.status == 'done').length} sent',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Zc.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _modes.map((MapEntry<String, String> m) {
                      final bool on = m.key == _mode;
                      return ChoiceChip(
                        label: Text(m.value),
                        selected: on,
                        showCheckmark: false,
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
                                  _files = <PickedFile>[];
                                  _groups = <_Group>[];
                                }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: busy ? null : _pick,
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        label: Text(_files.isEmpty
                            ? 'Select files'
                            : 'Add more (${_files.length} selected)'),
                      ),
                      GradientButton(
                        label: 'Preview plan',
                        icon: Icons.account_tree_rounded,
                        dense: true,
                        gradient: Zc.secondaryGradient,
                        onPressed: busy || _files.isEmpty
                            ? null
                            : () {
                                final String? err = _plan();
                                if (err != null) showSnack(context, err, error: true);
                              },
                      ),
                      GradientButton(
                        label: _running ? 'Distributing...' : 'Start distribution',
                        icon: Icons.rocket_launch_rounded,
                        dense: true,
                        busy: _running,
                        onPressed: busy ||
                                _groups.where((_Group g) => g.status == 'pending').isEmpty
                            ? null
                            : _run,
                      ),
                      if (_files.isNotEmpty && !busy)
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _files = <PickedFile>[];
                            _groups = <_Group>[];
                          }),
                          icon: const Icon(Icons.clear_all_rounded, size: 16),
                          label: const Text('Clear'),
                        ),
                    ],
                  ),
                  if (_running) ...<Widget>[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: _groups.isEmpty ? null : _done / _groups.length,
                        minHeight: 8,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_groups.isNotEmpty)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SectionTitle(
                      icon: Icons.checklist_rounded,
                      title: 'Plan (${_groups.length} groups)',
                      subtitle:
                          '${_groups.where((_Group g) => g.status == 'done').length} done - '
                          '${_groups.where((_Group g) => g.status == 'failed').length} failed - '
                          '${_groups.where((_Group g) => g.status == 'skipped').length} skipped',
                    ),
                    const SizedBox(height: 12),
                    ..._groups.map((_Group g) => _GroupRow(group: g)),
                  ],
                ),
              )
            else if (_files.isNotEmpty)
              Panel(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _files
                      .map((PickedFile f) => Chip(
                            label: Text(f.name, style: const TextStyle(fontSize: 11)),
                            onDeleted: busy
                                ? null
                                : () => setState(() => _files.remove(f)),
                          ))
                      .toList(),
                ),
              ),
            if (_log.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: Zc.darkGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
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
        );
      },
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final _Group group;

  Color get _color {
    switch (group.status) {
      case 'done':
        return Zc.okDeep;
      case 'failed':
        return Zc.danger;
      case 'uploading':
        return Zc.info;
      case 'skipped':
        return Zc.muted;
      default:
        return Zc.goldDeep;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Zc.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Zc.line),
      ),
      child: Row(
        children: <Widget>[
          if (group.files.first.isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(group.files.first.bytes,
                  width: 32, height: 52, fit: BoxFit.cover),
            )
          else
            Container(
              width: 32,
              height: 52,
              decoration: BoxDecoration(
                gradient: Zc.darkGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                group.files.first.isAudio ? Icons.music_note_rounded : Icons.movie_rounded,
                color: Zc.gold,
                size: 16,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: Zc.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    TagPill(
                      text: metaFor(group.contentType).short,
                      color: Zc.typeColor(group.contentType),
                    ),
                    TagPill(text: '${group.files.length} file(s)', color: Zc.muted),
                    if (group.error != null)
                      TagPill(text: group.error!, color: _color),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                group.target?.label ?? '-',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Zc.ink,
                ),
              ),
              TagPill(text: group.status.toUpperCase(), color: _color, filled: true),
            ],
          ),
        ],
      ),
    );
  }
}
