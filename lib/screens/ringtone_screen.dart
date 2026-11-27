import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_theme.dart';
import '../ringtone/ringtone_models.dart';
import '../ringtone/ringtone_service.dart';
import '../widgets/ui_kit.dart';
import 'ringtone_settings_screen.dart';

/// Ringtone Studio working screen: Create + Library only.
///
/// Until v1.19.2 this screen was one long scroll of settings cards
/// with Generate near the bottom and the results below that. All
/// settings now live on their own page (RingtoneSettingsScreen, the
/// gear icon / "All settings"), this screen shows a one-line summary
/// of the active settings, and Generate sits in a bar pinned to the
/// bottom of the screen - visible without any scrolling, on Android
/// and Windows alike. Results (Library) start right under Create.
class RingtoneScreen extends StatefulWidget {
  const RingtoneScreen({super.key, this.service});
  final RingtoneService? service;
  @override
  State<RingtoneScreen> createState() => _RingtoneScreenState();
}

class _RingtoneScreenState extends State<RingtoneScreen> {
  late final RingtoneService s;
  AudioPlayer? _player;
  AudioPlayer get player => _player ??= AudioPlayer();
  StreamSubscription<Duration>? _posSub, _durSub;
  StreamSubscription<void>? _doneSub;
  StreamSubscription<PlayerState>? _stateSub;
  final prompts = TextEditingController(), search = TextEditingController();
  String tab = 'All',
      accountFilter = 'All',
      categoryFilter = 'All',
      playing = '';

  /// Live playback state for the result-card player (v1.19.3): the
  /// active card shows a seekable progress bar with elapsed / total
  /// time and a speed control instead of a bare play/stop toggle.
  bool isPlaying = false;
  Duration pos = Duration.zero, dur = Duration.zero;
  double rate = 1.0;

  @override
  void initState() {
    super.initState();
    s = widget.service ?? RingtoneService.instance;
    s.addListener(changed);
    _posSub = player.onPositionChanged.listen((p) {
      if (mounted) setState(() => pos = p);
    });
    _durSub = player.onDurationChanged.listen((d) {
      if (mounted) setState(() => dur = d);
    });
    _doneSub = player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          playing = '';
          isPlaying = false;
          pos = Duration.zero;
        });
      }
    });
    _stateSub = player.onPlayerStateChanged.listen((st) {
      if (mounted) setState(() => isPlaying = st == PlayerState.playing);
    });
    s.init().then((_) {
      if (!mounted) return;
      prompts.text = s.promptsText;
      setState(() {});
    }).catchError((Object e) {
      snack('Could not initialize: $e');
    });
  }

  @override
  void dispose() {
    s.removeListener(changed);
    if (s.ready) unawaited(s.saveConfig());
    _posSub?.cancel();
    _durSub?.cancel();
    _doneSub?.cancel();
    _stateSub?.cancel();
    _player?.dispose();
    prompts.dispose();
    search.dispose();
    super.dispose();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void snack(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> act(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      snack('$e');
    }
  }

  List<String> get accounts => [
        for (final a in s.dist.accounts)
          if (a.name.trim().isNotEmpty && a.dbUrl.trim().isNotEmpty) a.name
      ];

  Future<void> openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RingtoneSettingsScreen(service: s)));
    changed(); // summary chips reflect any changes
  }

  Widget drop(String label, String value, List<String> options,
      ValueChanged<String> onChange) {
    final values = options.toSet().toList();
    return DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      value: values.contains(value) ? value : values.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final v in values)
          DropdownMenuItem(
              value: v, child: Text(v, overflow: TextOverflow.ellipsis))
      ],
      onChanged: s.running
          ? null
          : (v) {
              if (v != null) setState(() => onChange(v));
            },
    );
  }

  Widget card(IconData icon, String title, List<Widget> children,
          {String? subtitle}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SectionCard(
              icon: icon,
              title: title,
              subtitle: subtitle,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final w in children)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 10), child: w)
                  ])));

  @override
  Widget build(BuildContext context) {
    final c = s.config;
    return Scaffold(
        appBar: AppBar(
          title: const Text('Ringtone Studio'),
          actions: [
            IconButton(
              tooltip: 'Ringtone Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: s.ready ? openSettings : null,
            ),
          ],
        ),
        bottomNavigationBar: !s.ready ? null : _generateBar(context),
        body: !s.ready
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: screenScrollPadding(context, 16, 980),
                children: [
                    card(Icons.music_note, 'Create sounds', [
                      TextField(
                          controller: prompts,
                          enabled: !s.running,
                          maxLines: 4,
                          decoration: const InputDecoration(
                              labelText: 'Ideas — one per line',
                              hintText:
                                  'Leave empty for smart automatic ideas',
                              border: OutlineInputBorder()),
                          onChanged: (v) => s.promptsText = v),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final chip in [
                          c.soundType,
                          '${c.lengthSeconds}s • ${c.takesCount} takes',
                          c.genre,
                          c.mood,
                          c.bpm == 0 ? 'BPM Auto' : 'BPM ${c.bpm}',
                          if (c.useGeminiEnhancer) 'Gemini enhancer',
                          if (c.autoPublish) 'Auto-publish',
                          s.stableAudio.hasToken
                              ? 'Account: ${s.stableAudio.activeLabel.isEmpty ? 'connected' : s.stableAudio.activeLabel}'
                                  '${s.stableAudio.credits == null ? '' : ' • ${s.stableAudio.credits!.remaining} credits'}'
                              : 'No Stable Audio account',
                        ])
                          Chip(
                              label: Text(chip),
                              visualDensity: VisualDensity.compact),
                      ]),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: openSettings,
                          icon: const Icon(Icons.tune),
                          label: const Text('All settings'),
                        ),
                      ),
                    ]),
                    libraryCard(),
                    if (s.logs.isNotEmpty)
                      card(Icons.terminal_outlined, 'Generation log', [
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: s.clearLogs,
                              child: const Text('Clear log')),
                        ),
                        SelectableText(
                            s.logs.reversed.take(25).join('\n'),
                            style: Theme.of(context).textTheme.bodySmall),
                      ]),
                  ]));
  }

  /// Generate / Stop + live progress, pinned to the bottom of the
  /// screen so it is reachable without scrolling on any device.
  Widget _generateBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (s.running && s.total > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(
                    value: (s.completed / s.total).clamp(0, 1)),
              ),
            Row(children: [
              Expanded(
                child: Text(s.task,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 12),
              if (s.running)
                OutlinedButton.icon(
                    onPressed: s.stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop')),
              if (s.running) const SizedBox(width: 8),
              FilledButton.icon(
                  onPressed: s.running
                      ? null
                      : () => act(() async {
                            await s.saveConfig();
                            final list = RingtoneService.promptList(
                                prompts.text, s.autoCount);
                            await s.run(list);
                          }),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate')),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget libraryCard() {
    final q = search.text.toLowerCase();
    final items = s.library
        .where((i) =>
            (tab == 'All' ||
                (tab == 'New' ? i.isNewSession : !i.isNewSession)) &&
            (accountFilter == 'All' ||
                (accountFilter == 'Local'
                    ? !i.published
                    : i.dbName == accountFilter)) &&
            (categoryFilter == 'All' || i.category == categoryFilter) &&
            ('${i.title} ${i.tags} ${i.description}'.toLowerCase().contains(q)))
        .toList();
    return card(Icons.library_music_outlined, 'Library', [
      Wrap(spacing: 8, children: [
        for (final t in ['All', 'New', 'Old'])
          ChoiceChip(
              label: Text(t),
              selected: tab == t,
              onSelected: (_) => setState(() => tab = t))
      ]),
      TextField(
          controller: search,
          decoration: const InputDecoration(
              labelText: 'Search library', prefixIcon: Icon(Icons.search)),
          onChanged: (_) => setState(() {})),
      drop(
          'Account filter',
          accountFilter,
          [
            'All',
            'Local',
            ...accounts,
            ...s.library.map((i) => i.dbName).where((n) => n.isNotEmpty)
          ],
          (v) => accountFilter = v),
      drop('Category filter', categoryFilter, ['All', ...ringtoneCategories],
          (v) => categoryFilter = v),
      OutlinedButton.icon(
          onPressed: s.running
              ? null
              : () => act(() async {
                    final errors = <String>[];
                    final n = await s.syncQueue(errors: errors);
                    snack(
                        'Synced $n tones${errors.isEmpty ? '' : '; errors: ${errors.join('; ')}'}');
                  }),
          icon: const Icon(Icons.sync),
          label: const Text('Sync queue')),
      if (items.isEmpty) const Text('No tones found.'),
      for (final i in items) _toneCard(i)
    ]);
  }

  static String _fmt(Duration d) {
    final t = d.isNegative ? Duration.zero : d;
    return '${t.inMinutes}:${(t.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  static String _fmtBytes(int b) {
    if (b <= 0) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Play / pause the card's tone; tapping the active card pauses or
  /// resumes it, tapping another card switches playback to it.
  Future<void> togglePlay(RingtoneItem i) async {
    await act(() async {
      if (playing == i.id) {
        if (isPlaying) {
          await player.pause();
        } else {
          await player.resume();
        }
        return;
      }
      final path = await s.ensureLocal(i);
      await player.stop();
      if (mounted) {
        setState(() {
          playing = i.id;
          pos = Duration.zero;
          dur = Duration(milliseconds: (i.lengthSeconds * 1000).round());
          rate = 1.0;
        });
      }
      await player.play(DeviceFileSource(path));
    });
  }

  /// One generated tone as a proper player card: big play/pause
  /// button, seekable progress with elapsed / total time, playback
  /// speed for the active tone, meta chips (category, format, size,
  /// take, queue state) and an even action row.
  Widget _toneCard(RingtoneItem i) {
    final theme = Theme.of(context);
    final active = playing == i.id;
    final total = active && dur > Duration.zero
        ? dur
        : Duration(milliseconds: (i.lengthSeconds * 1000).round());
    final shownPos = active ? pos : Duration.zero;
    final progress = total.inMilliseconds > 0
        ? (shownPos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton.filled(
                tooltip: active && isPlaying ? 'Pause' : 'Play',
                iconSize: 28,
                icon: Icon(active && isPlaying
                    ? Icons.pause
                    : Icons.play_arrow),
                onPressed: () => togglePlay(i),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final chip in [
                        i.category,
                        i.isMp3 ? 'MP3' : 'WAV',
                        if (_fmtBytes(i.sizeBytes).isNotEmpty)
                          _fmtBytes(i.sizeBytes),
                        if (i.takesTotal > 1)
                          'Take ${i.takeIndex}/${i.takesTotal}',
                        if (i.musicalKey.isNotEmpty) 'Key ${i.musicalKey}',
                        i.published ? 'Queued: ${i.dbName}' : 'Local',
                      ])
                        Chip(
                          label: Text(chip),
                          visualDensity: VisualDensity.compact,
                          labelStyle: theme.textTheme.labelSmall,
                        ),
                    ]),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: progress,
                onChanged: active
                    ? (v) {
                        final target = Duration(
                            milliseconds:
                                (v * total.inMilliseconds).round());
                        setState(() => pos = target);
                        player.seek(target);
                      }
                    : null,
              ),
            ),
            Row(children: [
              Text(_fmt(shownPos), style: theme.textTheme.bodySmall),
              const Spacer(),
              if (active)
                TextButton(
                  onPressed: () => act(() async {
                    const rates = [1.0, 1.25, 1.5, 2.0];
                    final next =
                        rates[(rates.indexOf(rate) + 1) % rates.length];
                    await player.setPlaybackRate(next);
                    if (mounted) setState(() => rate = next);
                  }),
                  child: Text('${rate}x speed'),
                ),
              Text(_fmt(total), style: theme.textTheme.bodySmall),
            ]),
            if (i.tags.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(i.tags,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ),
            const Divider(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              IconButton(
                  tooltip: 'Edit metadata',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => editItem(i)),
              IconButton(
                  tooltip: 'Export',
                  icon: const Icon(Icons.save_alt_outlined),
                  onPressed: () => act(() async {
                        final dir = await FilePicker.platform
                            .getDirectoryPath(
                                dialogTitle: 'Save ringtone to folder');
                        if (dir != null) {
                          final f = await s.exportTo(i, Directory(dir));
                          snack('Saved to ${f.path}');
                        }
                      })),
              IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () => act(() async {
                        final path = await s.ensureLocal(i);
                        await Share.shareXFiles([XFile(path)], text: i.title);
                      })),
              if (!i.published)
                IconButton(
                    tooltip: 'Publish',
                    icon: const Icon(Icons.cloud_upload_outlined),
                    onPressed: () => publishItem(i)),
              IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => deleteItem(i)),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> editItem(RingtoneItem i) async {
    final title = TextEditingController(text: i.title),
        tags = TextEditingController(text: i.tags),
        desc = TextEditingController(text: i.description);
    String cat = ringtoneCategories.contains(i.category) ? i.category : 'OTHER';
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialog) => AlertDialog(
                    title: const Text('Edit listing'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: title,
                          decoration:
                              const InputDecoration(labelText: 'Title')),
                      TextField(
                          controller: tags,
                          decoration: const InputDecoration(labelText: 'Tags')),
                      DropdownButtonFormField<String>(
                          value: cat,
                          isExpanded: true,
                          items: [
                            for (final c in ringtoneCategories)
                              DropdownMenuItem(value: c, child: Text(c))
                          ],
                          onChanged: (v) => setDialog(() => cat = v ?? cat)),
                      TextField(
                          controller: desc,
                          maxLines: 3,
                          decoration:
                              const InputDecoration(labelText: 'Description'))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Save'))
                    ])));
    if (ok == true) {
      await act(() async {
        await s.updateMeta(i,
            title: title.text,
            tags: tags.text,
            category: cat,
            description: desc.text);
        snack('Listing saved.');
      });
    }
    title.dispose();
    tags.dispose();
    desc.dispose();
  }

  Future<void> publishItem(RingtoneItem i) async {
    await s.refreshEnvironment();
    if (!mounted) return;
    if (accounts.isEmpty) {
      snack('Configure a distribution account in Settings first.');
      return;
    }
    final name = await showDialog<String>(
        context: context,
        builder: (ctx) =>
            SimpleDialog(title: const Text('Publish to account'), children: [
              for (final a in accounts)
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, a), child: Text(a))
            ]));
    if (name != null) {
      await act(() async {
        await s.publish(i, name);
        snack('Published to $name.');
      });
    }
  }

  Future<void> deleteItem(RingtoneItem i) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete tone?'),
                content: Text(i.published
                    ? 'This also deletes its queue entry and R2 file.'
                    : 'This deletes the local audio file.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'))
                ]));
    if (yes == true) {
      await act(() async {
        if (playing == i.id) {
          await player.stop();
          playing = '';
          isPlaying = false;
          pos = Duration.zero;
        }
        await s.delete(i);
      });
    }
  }
}
