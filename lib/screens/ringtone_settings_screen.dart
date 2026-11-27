import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../ringtone/ringtone_models.dart';
import '../ringtone/ringtone_publish.dart';
import '../ringtone/ringtone_service.dart';
import '../ringtone/ringtone_texts.dart';
import '../ringtone/stable_audio.dart';
import '../ringtone/stable_audio_browser.dart';
import '../ringtone/stable_audio_http_accounts.dart';
import '../widgets/ui_kit.dart';

/// Dedicated Ringtone Studio settings page.
///
/// Until v1.19.2 every setting lived as a long stack of cards on the
/// studio screen itself: fixing a setting meant scrolling past
/// hundreds of controls, then scrolling again to reach Generate, then
/// again to see the results. Now the studio screen is only Create +
/// Library with an always-visible Generate bar, and everything
/// configurable lives here, grouped by section. On wide screens
/// (Windows) a section index stays pinned on the left; on phones the
/// sections are one clean list. All values write to the same
/// RingtoneService config the studio screen uses - nothing about the
/// generation pipeline changed.
class RingtoneSettingsScreen extends StatefulWidget {
  const RingtoneSettingsScreen({super.key, required this.service});
  final RingtoneService service;
  @override
  State<RingtoneSettingsScreen> createState() =>
      _RingtoneSettingsScreenState();
}

class _RingtoneSettingsScreenState extends State<RingtoneSettingsScreen> {
  late final RingtoneService s = widget.service;
  final master = TextEditingController(),
      negative = TextEditingController(),
      banned = TextEditingController(),
      instruments = TextEditingController(),
      token = TextEditingController(),
      refresh = TextEditingController(),
      ffpath = TextEditingController();
  Timer? timer;
  final _keys = <String, GlobalKey>{
    for (final id in [
      'sound',
      'design',
      'ai',
      'mastering',
      'account',
      'engine'
    ])
      id: GlobalKey()
  };

  @override
  void initState() {
    super.initState();
    s.addListener(changed);
    s.init().then((_) {
      if (!mounted) return;
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
    for (final c in [master, negative, banned, instruments, token, refresh, ffpath]) {
      c.dispose();
    }
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

  Widget card(String id, IconData icon, String title, List<Widget> children,
          {String? subtitle}) =>
      Padding(
          key: _keys[id],
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

  void _jumpTo(String id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = s.config;
    final sections = <Widget>[
      card('sound', Icons.music_note, 'Sound', [
        drop('Sound type', c.soundType, RingtoneOptions.soundTypes, (v) {
          c.soundType = v;
          c.lengthSeconds = v == 'Notification' ? 3 : 20;
          c.audioShape = v == 'Notification' ? 'oneshot' : 'track';
        }),
        drop('Audio shape', c.audioShape, RingtoneOptions.shapes,
            (v) => c.audioShape = v,
            labels: RingtoneOptions.shapeLabels),
        slider('Duration', c.lengthSeconds.toDouble(), 1, 60, 59,
            (v) => c.lengthSeconds = v.round(),
            suffix: ' seconds'),
        slider('Takes', c.takesCount.toDouble(), 1, 4, 3,
            (v) => c.takesCount = v.round()),
        drop('Time signature', c.timeSignature, RingtoneOptions.timeSignatures,
            (v) => c.timeSignature = v),
        slider('Automatic ideas (when the ideas box is empty)',
            s.autoCount.toDouble(), 1, 100, 99, (v) => s.autoCount = v.round()),
      ]),
      card('design', Icons.tune, 'Sound design', [
        toggle('Automatic BPM', c.bpm == 0, (v) => c.bpm = v ? 0 : 120),
        if (c.bpm != 0)
          slider('BPM', c.bpm.toDouble(), 40, 240, 200,
              (v) => c.bpm = v.round()),
        Wrap(spacing: 6, children: [
          for (final e in RingtoneOptions.bpmPresets.entries)
            ActionChip(
                label: Text('${e.value} ${e.key}'),
                onPressed:
                    s.running ? null : () => change(() => c.bpm = e.key))
        ]),
        field(instruments, 'Instruments', (v) => c.instruments = v,
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
                            .where((e) => e.isNotEmpty && e != 'Auto')
                            .toList();
                        if (selected) {
                          a.add(i);
                        } else {
                          a.remove(i);
                        }
                        change(() {
                          c.instruments = a.isEmpty ? 'Auto' : a.join(', ');
                          instruments.text = c.instruments;
                        });
                      })
        ]),
        drop('Genre', c.genre, RingtoneOptions.genres, (v) => c.genre = v),
        drop('Mood', c.mood, RingtoneOptions.moods, (v) => c.mood = v),
        drop('Key', c.musicalKey, RingtoneOptions.keys,
            (v) => c.musicalKey = v),
        drop('Structure', c.structure, RingtoneOptions.structures,
            (v) => c.structure = v),
        drop('Production', c.production, RingtoneOptions.productions,
            (v) => c.production = v),
      ]),
      card('ai', Icons.edit_note, 'AI and publishing', [
        toggle('Gemini prompt enhancer', c.useGeminiEnhancer,
            (v) => c.useGeminiEnhancer = v,
            subtitle: 'Gemini still creates the listing metadata.'),
        toggle('Auto-publish to distribution queue', c.autoPublish,
            (v) => c.autoPublish = v,
            subtitle: 'Requires distribution settings and MP3 encoding.'),
        if (c.autoPublish)
          drop(
              'Target account',
              c.targetAccount,
              [
                '',
                RingtonePublisher.allAccounts,
                ...accounts,
                if (c.targetAccount.isNotEmpty &&
                    c.targetAccount != RingtonePublisher.allAccounts &&
                    !accounts.contains(c.targetAccount))
                  c.targetAccount,
              ],
              (v) => c.targetAccount = v,
              labels: {
                '': 'First configured account',
                RingtonePublisher.allAccounts: 'All accounts',
                if (c.targetAccount.isNotEmpty &&
                    c.targetAccount != RingtonePublisher.allAccounts &&
                    !accounts.contains(c.targetAccount))
                  c.targetAccount: 'Unavailable: ${c.targetAccount}',
              }),
        field(negative, 'Negative prompt', (v) => c.negativePrompt = v,
            lines: 3),
        field(banned, 'Banned words', (v) => c.bannedWords = v, lines: 2),
        field(master, 'Gemini master prompt', (v) => c.masterPrompt = v,
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
      card('mastering', Icons.equalizer, 'Mastering', [
        toggle('Auto-process audio', c.autoProcess, (v) => c.autoProcess = v),
        toggle('Trim silence', c.trimSilence, (v) => c.trimSilence = v),
        slider('Volume boost', c.volumeBoostPct.toDouble(), 50, 400, 35,
            (v) => c.volumeBoostPct = v.round(),
            suffix: '%'),
        Text('Silence threshold: ${c.silenceThreshold.toStringAsFixed(4)}'),
        Slider(
            value: c.silenceThreshold.clamp(0.0005, 0.2),
            min: 0.0005,
            max: 0.2,
            onChanged:
                s.running ? null : (v) => change(() => c.silenceThreshold = v)),
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
            keyboardType:
                const TextInputType.numberWithOptions(signed: true),
            decoration:
                const InputDecoration(labelText: 'Seed (-1 = random)'),
            onChanged: (v) {
              c.seed = int.tryParse(v) ?? -1;
              save();
            }),
      ]),
      card('account', Icons.account_circle_outlined, 'Stable Audio account', [
        Text(s.stableAudio.hasToken
            ? '${s.stableAudio.activeLabel.isEmpty ? 'Token connected' : s.stableAudio.activeLabel}'
                '${s.stableAudio.tokenExpiry == null ? '' : ' • expires ${s.stableAudio.tokenExpiry!.toLocal()}'}'
                '${s.stableAudio.hasRefreshToken ? ' • auto-refresh ready' : ''}'
            : 'No token connected'),
        if (s.accountBusy) const LinearProgressIndicator(),
        if (s.stableAudio.termsRequired)
          const Text(
              'This account requires terms acceptance before generation.'),
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
                onSelected: (s.running || s.accountBusy)
                    ? null
                    : (_) => act(() async {
                          await s.stableAudio.selectAccount(acc.id);
                          await s.stableAudio.fetchCredits();
                          changed();
                        }),
                onDeleted: (s.running || s.accountBusy)
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
        toggle('Auto-rotate account when credits are low', c.autoRotateAccount,
            (v) => c.autoRotateAccount = v,
            subtitle:
                'Switches accounts automatically; a fresh account is created in the built-in browser so AuthKit verification passes.'),
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
                labelText: 'Refresh token (can connect without access token)',
                border: OutlineInputBorder())),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (StableAudioBrowser.supported || StableAudioHttpAccounts.supported)
            FilledButton.icon(
                onPressed: (s.running || s.accountBusy)
                    ? null
                    : () => act(() async {
                          snack('Creating Stable Audio account...');
                          final ok = await s.rotateStableAudioAccount(
                              createNew: true);
                          changed();
                          snack(ok
                              ? 'Stable Audio account connected.'
                              : 'Account creation did not complete.');
                        }),
                icon: const Icon(Icons.login),
                label: const Text('Create account')),
          FilledButton(
              onPressed: (s.running || s.accountBusy)
                  ? null
                  : () => act(() async {
                        final a = StableAudioClient.parsePasted(token.text);
                        final rt = refresh.text.trim().isNotEmpty
                            ? refresh.text.trim()
                            : a.refresh;
                        if (a.access.isEmpty && rt.isEmpty) {
                          throw Exception(
                              'Paste an access token, refresh token, or token JSON.');
                        }
                        await s.stableAudio.addAccount(
                            accessToken: a.access,
                            refreshToken: refresh.text.trim().isNotEmpty
                                ? refresh.text.trim()
                                : a.refresh,
                            makeActive: true);
                        if (a.access.isEmpty &&
                            !await s.stableAudio.refreshToken()) {
                          throw Exception(
                              'Refresh token could not be exchanged. Reconnect this account.');
                        }
                        token.clear();
                        refresh.clear();
                        await s.stableAudio.fetchCredits();
                        changed();
                        snack('Stable Audio token saved securely.');
                      }),
              child: const Text('Connect')),
          if (StableAudioBrowser.supported ||
              StableAudioHttpAccounts.supported ||
              s.stableAudio.accounts.length > 1)
            OutlinedButton.icon(
                onPressed: (s.running || s.accountBusy)
                    ? null
                    : () => act(() async {
                          snack('Rotating Stable Audio account...');
                          final ok = await s.rotateStableAudioAccount(
                              createNew: StableAudioBrowser.supported ||
                                  StableAudioHttpAccounts.supported);
                          changed();
                          snack(ok
                              ? 'Rotated to ${s.stableAudio.activeLabel}.'
                              : 'Token rotation failed.');
                        }),
                icon: const Icon(Icons.autorenew),
                label: const Text('Rotate token')),
          if (s.stableAudio.hasRefreshToken)
            OutlinedButton(
                onPressed: (s.running || s.accountBusy)
                    ? null
                    : () => act(() async {
                          final ok = await s.refreshStableAudioToken();
                          changed();
                          snack(ok
                              ? 'Access token refreshed.'
                              : 'Token refresh failed.');
                        }),
                child: const Text('Refresh token')),
          if (s.stableAudio.hasToken)
            OutlinedButton.icon(
                onPressed: (s.running || s.accountBusy)
                    ? null
                    : () => act(() async {
                          final accepted = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Stable Audio terms'),
                              content: const Text(
                                  'Accept Stable Audio Terms of Service for the active account? '
                                  'Review: https://stableaudio.com/terms\n\n'
                                  'Marketing opt-in will remain off.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Accept terms')),
                              ],
                            ),
                          );
                          if (accepted != true) return;
                          final ok = await s.acceptStableAudioTerms();
                          changed();
                          snack(ok
                              ? 'Stable Audio terms updated.'
                              : 'Terms update failed.');
                        }),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(s.stableAudio.termsRequired
                    ? 'Accept terms (required)'
                    : 'Review / accept terms')),
          OutlinedButton(
              onPressed: (s.running || s.accountBusy)
                  ? null
                  : () => act(() async {
                        await s.stableAudio.fetchCredits();
                        changed();
                        snack('Credit check complete.');
                      }),
              child: const Text('Refresh credits')),
          TextButton(
              onPressed: (s.running || s.accountBusy)
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
            'Create an account in the built-in browser (AuthKit requires its in-page verification), connect tokens, or rotate accounts. Tokens are stored securely on this device.'),
      ]),
      card('engine', Icons.build_outlined, 'Mastering engine', [
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
    ];

    final menu = <(String, IconData, String)>[
      ('sound', Icons.music_note, 'Sound'),
      ('design', Icons.tune, 'Sound design'),
      ('ai', Icons.edit_note, 'AI and publishing'),
      ('mastering', Icons.equalizer, 'Mastering'),
      ('account', Icons.account_circle_outlined, 'Stable Audio account'),
      ('engine', Icons.build_outlined, 'Mastering engine'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Ringtone Settings')),
      body: !s.ready
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, box) {
              final list = ListView(
                padding: screenScrollPadding(context, 16, 980),
                children: sections,
              );
              if (box.maxWidth < 900) return list;
              // Windows / wide: pinned section index on the left, the
              // settings list on the right - no hunting by scroll.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 240,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                      children: [
                        for (final m in menu)
                          ListTile(
                            leading: Icon(m.$2),
                            title: Text(m.$3),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            onTap: () => _jumpTo(m.$1),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: list),
                ],
              );
            }),
    );
  }
}
