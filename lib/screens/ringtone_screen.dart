import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_theme.dart';
import '../ringtone/ringtone_models.dart';
import '../ringtone/ringtone_publish.dart';
import '../ringtone/ringtone_service.dart';
import '../ringtone/ringtone_texts.dart';
import '../ringtone/stable_audio.dart';
import '../ringtone/stable_audio_browser.dart';
import '../widgets/ui_kit.dart';

class RingtoneScreen extends StatefulWidget {
  const RingtoneScreen({super.key, this.service});
  final RingtoneService? service;
  @override
  State<RingtoneScreen> createState() => _RingtoneScreenState();
}

class _RingtoneScreenState extends State<RingtoneScreen> {
  late final RingtoneService s;
  AudioPlayer? _player;
  AudioPlayer get player => _player ??= AudioPlayer()
    ..onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = '');
    });
  final prompts = TextEditingController(),
      master = TextEditingController(),
      negative = TextEditingController(),
      banned = TextEditingController(),
      instruments = TextEditingController(),
      token = TextEditingController(),
      refresh = TextEditingController(),
      ffpath = TextEditingController(),
      search = TextEditingController();
  Timer? timer;
  String tab = 'All',
      accountFilter = 'All',
      categoryFilter = 'All',
      playing = '';

  @override
  void initState() {
    super.initState();
    s = widget.service ?? RingtoneService.instance;
    s.addListener(changed);
    s.init().then((_) {
      if (!mounted) return;
      prompts.text = s.promptsText;
      master.text = s.config.masterPrompt;
      negative.text = s.config.negativePrompt;
      banned.text = s.config.bannedWords;
      instruments.text = s.config.instruments;
      ffpath.text = s.ffmpegPath;
      setState(() {});
    }).catchError((Object e) {
      snack('Could not initialize: $e');
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    s.removeListener(changed);
    if (s.ready) unawaited(s.saveConfig());
    _player?.dispose();
    for (final c in [
      prompts,
      master,
      negative,
      banned,
      instruments,
      token,
      refresh,
      ffpath,
      search
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void snack(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void save() {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 400), () => s.saveConfig());
  }

  void change(void Function() f) {
    setState(f);
    save();
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

  Widget drop(String label, String value, List<String> options,
      ValueChanged<String> onChange,
      {Map<String, String>? labels}) {
    final values = options.toSet().toList();
    return DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      value: values.contains(value) ? value : values.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final v in values)
          DropdownMenuItem(
              value: v,
              child: Text(labels?[v] ?? v, overflow: TextOverflow.ellipsis))
      ],
      onChanged: s.running
          ? null
          : (v) {
              if (v != null) change(() => onChange(v));
            },
    );
  }

  Widget toggle(String label, bool value, ValueChanged<bool> f,
          {String? subtitle}) =>
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: subtitle == null ? null : Text(subtitle),
          value: value,
          onChanged: s.running ? null : (v) => change(() => f(v)));
  Widget slider(String label, double value, double min, double max,
          int divisions, ValueChanged<double> f,
          {String suffix = ''}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label: ${value.toStringAsFixed(0)}$suffix'),
        Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: s.running ? null : (v) => change(() => f(v)))
      ]);
  Widget field(TextEditingController ctrl, String label, ValueChanged<String> f,
          {int lines = 1, String? hint}) =>
      TextField(
          controller: ctrl,
          enabled: !s.running,
          maxLines: lines,
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder()),
          onChanged: (v) {
            f(v);
            save();
          });
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
        appBar: AppBar(title: const Text('Ringtone Studio')),
        body: !s.ready
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: screenScrollPadding(context, 16, 980),
                children: [
                    card(Icons.music_note, 'Create sounds', [
                      drop(
                          'Sound type', c.soundType, RingtoneOptions.soundTypes,
                          (v) {
                        c.soundType = v;
                        c.lengthSeconds = v == 'Notification' ? 3 : 20;
                        c.audioShape =
                            v == 'Notification' ? 'oneshot' : 'track';
                      }),
                      drop('Audio shape', c.audioShape, RingtoneOptions.shapes,
                          (v) => c.audioShape = v,
                          labels: RingtoneOptions.shapeLabels),
                      field(prompts, 'Ideas — one per line',
                          (v) => s.promptsText = v,
                          lines: 4,
                          hint: 'Leave empty for smart automatic ideas'),
                      slider(
                          'Automatic ideas (when empty)',
                          s.autoCount.toDouble(),
                          1,
                          100,
                          99,
                          (v) => s.autoCount = v.round()),
                      slider('Duration', c.lengthSeconds.toDouble(), 1, 60, 59,
                          (v) => c.lengthSeconds = v.round(),
                          suffix: ' seconds'),
                      slider('Takes', c.takesCount.toDouble(), 1, 4, 3,
                          (v) => c.takesCount = v.round()),
                      drop(
                          'Time signature',
                          c.timeSignature,
                          RingtoneOptions.timeSignatures,
                          (v) => c.timeSignature = v),
                      toggle('Gemini prompt enhancer', c.useGeminiEnhancer,
                          (v) => c.useGeminiEnhancer = v,
                          subtitle:
                              'Gemini still creates the listing metadata.'),
                      toggle('Auto-publish to distribution queue',
                          c.autoPublish, (v) => c.autoPublish = v,
                          subtitle:
                              'Requires distribution settings and MP3 encoding.'),
                      if (c.autoPublish)
                        drop(
                            'Target account',
                            c.targetAccount,
                            [
                              '',
                              RingtonePublisher.allAccounts,
                              ...accounts,
                              if (c.targetAccount.isNotEmpty &&
                                  c.targetAccount !=
                                      RingtonePublisher.allAccounts &&
                                  !accounts.contains(c.targetAccount))
                                c.targetAccount,
                            ],
                            (v) => c.targetAccount = v,
                            labels: {
                              '': 'First configured account',
                              RingtonePublisher.allAccounts: 'All accounts',
                              if (c.targetAccount.isNotEmpty &&
                                  c.targetAccount !=
                                      RingtonePublisher.allAccounts &&
                                  !accounts.contains(c.targetAccount))
                                c.targetAccount:
                                    'Unavailable: ${c.targetAccount}',
                            }),
                    ]),
                    card(Icons.tune, 'Sound design', [
                      toggle('Automatic BPM', c.bpm == 0,
                          (v) => c.bpm = v ? 0 : 120),
                      if (c.bpm != 0)
                        slider('BPM', c.bpm.toDouble(), 40, 240, 200,
                            (v) => c.bpm = v.round()),
                      Wrap(spacing: 6, children: [
                        for (final e in RingtoneOptions.bpmPresets.entries)
                          ActionChip(
                              label: Text('${e.value} ${e.key}'),
                              onPressed: s.running
                                  ? null
                                  : () => change(() => c.bpm = e.key))
                      ]),
                      field(
                          instruments, 'Instruments', (v) => c.instruments = v,
                          hint: 'Auto or comma-separated instruments'),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        for (final i in RingtoneOptions.instruments)
                          FilterChip(
                              label: Text(i),
                              selected: c.instruments
                                  .split(',')
                                  .map((e) => e.trim())
                                  .contains(i),
                              onSelected: s.running
                                  ? null
                                  : (selected) {
                                      final a = c.instruments
                                          .split(',')
                                          .map((e) => e.trim())
                                          .where((e) =>
                                              e.isNotEmpty && e != 'Auto')
                                          .toList();
                                      if (selected) {
                                        a.add(i);
                                      } else {
                                        a.remove(i);
                                      }
                                      change(() {
                                        c.instruments =
                                            a.isEmpty ? 'Auto' : a.join(', ');
                                        instruments.text = c.instruments;
                                      });
                                    })
                      ]),
                      drop('Genre', c.genre, RingtoneOptions.genres,
                          (v) => c.genre = v),
                      drop('Mood', c.mood, RingtoneOptions.moods,
                          (v) => c.mood = v),
                      drop('Key', c.musicalKey, RingtoneOptions.keys,
                          (v) => c.musicalKey = v),
                      drop('Structure', c.structure, RingtoneOptions.structures,
                          (v) => c.structure = v),
                      drop('Production', c.production,
                          RingtoneOptions.productions, (v) => c.production = v),
                    ]),
                    card(Icons.edit_note, 'Prompt and policy', [
                      field(negative, 'Negative prompt',
                          (v) => c.negativePrompt = v,
                          lines: 3),
                      field(banned, 'Banned words', (v) => c.bannedWords = v,
                          lines: 2),
                      field(master, 'Gemini master prompt',
                          (v) => c.masterPrompt = v,
                          lines: 6),
                      TextButton(
                          onPressed: s.running
                              ? null
                              : () => change(() {
                                    c.masterPrompt = defaultMasterPrompt;
                                    master.text = c.masterPrompt;
                                  }),
                          child: const Text('Reset master prompt')),
                    ]),
                    card(Icons.equalizer, 'Mastering', [
                      toggle('Auto-process audio', c.autoProcess,
                          (v) => c.autoProcess = v),
                      toggle('Trim silence', c.trimSilence,
                          (v) => c.trimSilence = v),
                      slider('Volume boost', c.volumeBoostPct.toDouble(), 50,
                          400, 35, (v) => c.volumeBoostPct = v.round(),
                          suffix: '%'),
                      Text(
                          'Silence threshold: ${c.silenceThreshold.toStringAsFixed(4)}'),
                      Slider(
                          value: c.silenceThreshold.clamp(0.0005, 0.2),
                          min: 0.0005,
                          max: 0.2,
                          onChanged: s.running
                              ? null
                              : (v) => change(() => c.silenceThreshold = v)),
                      slider('Padding', c.padMs.toDouble(), 0, 500, 50,
                          (v) => c.padMs = v.round(),
                          suffix: ' ms'),
                      slider('Fade in', c.fadeInMs.toDouble(), 0, 2000, 100,
                          (v) => c.fadeInMs = v.round(),
                          suffix: ' ms'),
                      slider('Fade out', c.fadeOutMs.toDouble(), 0, 3000, 100,
                          (v) => c.fadeOutMs = v.round(),
                          suffix: ' ms'),
                      drop('MP3 bitrate', c.bitrate, RingtoneOptions.bitrates,
                          (v) => c.bitrate = v),
                      TextFormField(
                          initialValue: '${c.seed}',
                          enabled: !s.running,
                          keyboardType: const TextInputType.numberWithOptions(
                              signed: true),
                          decoration: const InputDecoration(
                              labelText: 'Seed (-1 = random)'),
                          onChanged: (v) {
                            c.seed = int.tryParse(v) ?? -1;
                            save();
                          }),
                    ]),
                    card(
                        Icons.account_circle_outlined, 'Stable Audio account', [
                      Text(s.stableAudio.hasToken
                          ? '${s.stableAudio.activeLabel.isEmpty ? 'Token connected' : s.stableAudio.activeLabel}'
                              '${s.stableAudio.tokenExpiry == null ? '' : ' • expires ${s.stableAudio.tokenExpiry!.toLocal()}'}'
                              '${s.stableAudio.hasRefreshToken ? ' • auto-refresh ready' : ''}'
                          : 'No token connected'),
                      Text(s.stableAudio.credits == null
                          ? 'Credits: unavailable'
                          : 'Credits: ${s.stableAudio.credits!.remaining} / ${s.stableAudio.credits!.total}'),
                      if (s.stableAudio.accounts.length > 1)
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final acc in s.stableAudio.accounts)
                            InputChip(
                              label: Text(
                                '${acc.label.isEmpty ? acc.id : acc.label}'
                                '${acc.lastRemaining != null ? ' (${acc.lastRemaining})' : ''}',
                              ),
                              selected: acc.id == s.stableAudio.activeAccountId,
                              onSelected: s.running
                                  ? null
                                  : (_) => act(() async {
                                        await s.stableAudio.selectAccount(acc.id);
                                        await s.stableAudio.fetchCredits();
                                        changed();
                                      }),
                              onDeleted: s.running
                                  ? null
                                  : () => act(() async {
                                        await s.stableAudio.removeAccount(acc.id);
                                        changed();
                                      }),
                            ),
                        ]),
                      toggle('Auto-refresh token', c.autoRefreshToken,
                          (v) => c.autoRefreshToken = v,
                          subtitle:
                              'Renews short-lived access tokens automatically before they expire.'),
                      toggle('Auto-rotate account when credits are low',
                          c.autoRotateAccount, (v) => c.autoRotateAccount = v,
                          subtitle:
                              'Switches to another saved account or creates a fresh 50-credit account automatically.'),
                      TextField(
                          controller: token,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                              labelText: 'Access token or token JSON',
                              border: OutlineInputBorder())),
                      TextField(
                          controller: refresh,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                              labelText: 'Refresh token (optional)',
                              border: OutlineInputBorder())),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (StableAudioBrowser.supported)
                          FilledButton.icon(
                              onPressed: s.running
                                  ? null
                                  : () => act(() async {
                                        snack(
                                            'Opening browser for Stable Audio sign-in...');
                                        final ok =
                                            await s.signInStableAudioBrowser();
                                        changed();
                                        snack(ok
                                            ? 'Stable Audio account connected.'
                                            : 'Sign-in cancelled or token not captured.');
                                      }),
                              icon: const Icon(Icons.login),
                              label: const Text('Sign in with browser')),
                        FilledButton(
                            onPressed: s.running
                                ? null
                                : () => act(() async {
                                      final a = StableAudioClient.parsePasted(
                                          token.text);
                                      if (a.access.isEmpty)
                                        throw Exception(
                                            'Paste a valid access token or token JSON.');
                                      await s.stableAudio.addAccount(
                                          accessToken: a.access,
                                          refreshToken:
                                              refresh.text.trim().isNotEmpty
                                                  ? refresh.text.trim()
                                                  : a.refresh,
                                          makeActive: true);
                                      token.clear();
                                      refresh.clear();
                                      await s.stableAudio.fetchCredits();
                                      changed();
                                      snack(
                                          'Stable Audio token saved securely.');
                                    }),
                            child: const Text('Connect')),
                        if (StableAudioBrowser.supported ||
                            s.stableAudio.accounts.length > 1)
                          OutlinedButton.icon(
                              onPressed: s.running
                                  ? null
                                  : () => act(() async {
                                        snack('Rotating Stable Audio token...');
                                        final ok =
                                            await s.rotateStableAudioAccount(
                                                createNew: s.stableAudio.accounts
                                                        .length <=
                                                    1);
                                        changed();
                                        snack(ok
                                            ? 'Rotated to ${s.stableAudio.activeLabel}.'
                                            : 'Token rotation failed.');
                                      }),
                              icon: const Icon(Icons.autorenew),
                              label: const Text('Rotate token')),
                        if (s.stableAudio.hasRefreshToken)
                          OutlinedButton(
                              onPressed: s.running
                                  ? null
                                  : () => act(() async {
                                        final ok =
                                            await s.refreshStableAudioToken();
                                        changed();
                                        snack(ok
                                            ? 'Access token refreshed.'
                                            : 'Token refresh failed.');
                                      }),
                              child: const Text('Refresh token')),
                        OutlinedButton(
                            onPressed: s.running
                                ? null
                                : () => act(() async {
                                      await s.stableAudio.fetchCredits();
                                      changed();
                                      snack('Credit check complete.');
                                    }),
                            child: const Text('Refresh credits')),
                        TextButton(
                            onPressed: s.running
                                ? null
                                : () => act(() async {
                                      await s.stableAudio.disconnect();
                                      token.clear();
                                      refresh.clear();
                                      changed();
                                    }),
                            child: const Text('Disconnect')),
                      ]),
                      const Text(
                          'Connect with your browser, paste a token/JSON, or rotate accounts. Tokens are stored securely on this device.'),
                    ]),
                    card(Icons.build_outlined, 'Mastering engine', [
                      Text(s.ffmpeg == null
                          ? 'Built-in FFmpeg did not start. Reinstall the app; local WAV output still works.'
                          : 'FFmpeg ${s.ffmpeg!.version} • ${s.ffmpeg!.path}'),
                      TextField(
                          controller: ffpath,
                          decoration: const InputDecoration(
                              labelText: 'Custom FFmpeg path (optional)',
                              border: OutlineInputBorder())),
                      Wrap(spacing: 8, children: [
                        OutlinedButton(
                            onPressed: s.running
                                ? null
                                : () => act(() async {
                                      await s.setFfmpegPath(ffpath.text);
                                      snack(s.ffmpeg == null
                                          ? 'FFmpeg not found.'
                                          : 'FFmpeg ready.');
                                    }),
                            child: const Text('Use path / rescan')),
                      ]),
                    ]),
                    card(Icons.play_circle_outline, 'Generate', [
                      Text(s.task),
                      if (s.running && s.total > 0)
                        LinearProgressIndicator(
                            value: (s.completed / s.total).clamp(0, 1)),
                      Wrap(spacing: 8, children: [
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
                        OutlinedButton.icon(
                            onPressed: s.running ? s.stop : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop')),
                        TextButton(
                            onPressed: s.clearLogs,
                            child: const Text('Clear log'))
                      ]),
                      if (s.logs.isNotEmpty)
                        SelectableText(s.logs.reversed.take(25).join('\n'),
                            style: Theme.of(context).textTheme.bodySmall),
                    ]),
                    libraryCard(),
                  ]));
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
      for (final i in items)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.title,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                          '${i.category} • ${i.lengthSeconds.toStringAsFixed(1)}s • ${i.published ? 'Queued: ${i.dbName}' : 'Local'} • ${i.isMp3 ? 'MP3' : 'WAV'}'),
                      Text(i.tags,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      Wrap(spacing: 4, children: [
                        IconButton(
                            tooltip: playing == i.id ? 'Stop' : 'Play',
                            icon: Icon(playing == i.id
                                ? Icons.stop
                                : Icons.play_arrow),
                            onPressed: () => act(() async {
                                  if (playing == i.id) {
                                    await player.stop();
                                    if (mounted) setState(() => playing = '');
                                  } else {
                                    final path = await s.ensureLocal(i);
                                    await player.stop();
                                    await player.play(DeviceFileSource(path));
                                    if (mounted) setState(() => playing = i.id);
                                  }
                                })),
                        IconButton(
                            tooltip: 'Edit metadata',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => editItem(i)),
                        IconButton(
                            tooltip: 'Export',
                            icon: const Icon(Icons.save_alt),
                            onPressed: () => act(() async {
                                  final dir = await FilePicker.platform
                                      .getDirectoryPath(
                                          dialogTitle:
                                              'Save ringtone to folder');
                                  if (dir != null) {
                                    final f =
                                        await s.exportTo(i, Directory(dir));
                                    snack('Saved to ${f.path}');
                                  }
                                })),
                        IconButton(
                            tooltip: 'Share',
                            icon: const Icon(Icons.share_outlined),
                            onPressed: () => act(() async {
                                  final path = await s.ensureLocal(i);
                                  await Share.shareXFiles([XFile(path)],
                                      text: i.title);
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
                      ])
                    ])))
    ]);
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
    if (ok == true)
      await act(() async {
        await s.updateMeta(i,
            title: title.text,
            tags: tags.text,
            category: cat,
            description: desc.text);
        snack('Listing saved.');
      });
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
    if (name != null)
      await act(() async {
        await s.publish(i, name);
        snack('Published to $name.');
      });
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
    if (yes == true)
      await act(() async {
        if (playing == i.id) {
          await player.stop();
          playing = '';
        }
        await s.delete(i);
      });
  }
}
