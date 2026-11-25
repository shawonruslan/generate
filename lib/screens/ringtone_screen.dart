import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../distribute.dart';
import '../gemini_web.dart';
import '../ringtone/account_creator.dart';
import '../ringtone/account_rotation.dart';
import '../ringtone/audio_mastering.dart';
import '../ringtone/ringtone_constants.dart';
import '../ringtone/ringtone_data.dart';
import '../ringtone/ringtone_engine.dart';
import '../ringtone/stable_audio.dart';

/// One generated ringtone take in the session library.
class RingtoneItem {
  String title;
  String tags;
  String category;
  String description;
  final String prompt;
  final String enhancedPrompt;
  final String negativePrompt;
  final String filePath;
  final String fileName;
  final String mime;
  final int size;
  final double durationSec;
  // Not final: _pushItem records the panel account the tone was
  // actually pushed to, which can differ from the generation target
  // (manual push lets the user pick another account).
  String account;
  final int takeIndex;
  final int takesTotal;
  final int seed;
  final String audioShape;
  final String musicalKey;
  final String timeSignature;
  final int lengthSeconds;
  final Map<String, dynamic>? dsp;
  String? firebaseKey;
  String? fileUrl;
  String status; // local | pushed | failed
  RingtoneItem({
    required this.title,
    required this.tags,
    required this.category,
    required this.description,
    required this.prompt,
    required this.enhancedPrompt,
    required this.negativePrompt,
    required this.filePath,
    required this.fileName,
    required this.mime,
    required this.size,
    required this.durationSec,
    required this.account,
    required this.takeIndex,
    required this.takesTotal,
    required this.seed,
    required this.audioShape,
    required this.musicalKey,
    required this.timeSignature,
    required this.lengthSeconds,
    required this.dsp,
    this.status = 'local',
  });
}

/// Ringtone Studio — the Generator Hub workflow's ringtone mode,
/// in-app: Gemini writes the studio prompt + Zedge metadata, Stable
/// Audio renders the takes, the DSP chain masters them, and finished
/// tones push to the same R2 + Firebase panel queue as images.
class RingtoneScreen extends StatefulWidget {
  const RingtoneScreen({super.key});
  @override
  State<RingtoneScreen> createState() => _RingtoneScreenState();
}

class _RingtoneScreenState extends State<RingtoneScreen> {
  final RingtoneSettings _s = RingtoneSettings();
  final _promptsCtrl = TextEditingController();
  final _customInstCtrl = TextEditingController();
  final _negativeCtrl =
      TextEditingController(text: kDefaultNegativePrompt);
  final _bannedCtrl = TextEditingController(text: kDefaultBannedWords);
  final _masterCtrl = TextEditingController(text: kDefaultMasterPrompt);
  final _autoCountCtrl = TextEditingController(text: '5');
  final _padCtrl = TextEditingController(text: '100');
  final _fadeInCtrl = TextEditingController(text: '30');
  final _fadeOutCtrl = TextEditingController(text: '350');
  final _seedCtrl = TextEditingController(text: '-1');
  final Set<String> _instruments = {};
  String _genreLabel = 'Auto (Smart Variety)';
  String _mood = 'Auto';
  String _key = 'Auto';
  String _structureLabel = 'Auto Structure';
  String _productionLabel = 'Studio Mastered';
  String _target = '';
  bool _autoUpload = true;

  DistConfig _dist = const DistConfig();
  GeminiWebClient? _web;
  String _gemNote = '';
  StableAudioApi? _sa;
  String _saStatus = 'No token';
  bool _generating = false;
  bool _stop = false;
  String _status = 'Ready — enter prompts or use Auto-Discovery.';
  int _done = 0, _total = 0;
  final List<String> _logs = [];
  final List<RingtoneItem> _items = [];
  final AudioPlayer _player = AudioPlayer();
  String? _playingPath;
  String _filter = '';

  /// Account pool + rotation (the workflow's auto-rotating 50-credit
  /// Stable Audio accounts). `late` so the log callback can bind to the
  /// widget's own log box.
  late final StableAudioRotator _rot = StableAudioRotator(onLog: _log);
  bool _autoRotate = true;
  bool _autoCreate = false;

  @override
  void initState() {
    super.initState();
    _init();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingPath = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _promptsCtrl.dispose();
    _customInstCtrl.dispose();
    _negativeCtrl.dispose();
    _bannedCtrl.dispose();
    _masterCtrl.dispose();
    _autoCountCtrl.dispose();
    _padCtrl.dispose();
    _fadeInCtrl.dispose();
    _fadeOutCtrl.dispose();
    _seedCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ringtone_settings_v1');
      if (raw != null) {
        final m = Map<String, dynamic>.from(jsonDecode(raw));
        _s.soundType = (m['soundType'] ?? _s.soundType).toString();
        _s.audioShape = (m['audioShape'] ?? _s.audioShape).toString();
        _s.takesCount = (m['takesCount'] as num?)?.toInt() ?? 4;
        _s.timeSignature = (m['timeSignature'] ?? '4/4').toString();
        _s.lengthSeconds = (m['lengthSeconds'] as num?)?.toInt() ?? 20;
        _negativeCtrl.text = (m['negativePrompt'] ?? '').toString().isEmpty
            ? kDefaultNegativePrompt
            : m['negativePrompt'].toString();
        _bannedCtrl.text = (m['bannedWords'] ?? '').toString().isEmpty
            ? kDefaultBannedWords
            : m['bannedWords'].toString();
        _masterCtrl.text = (m['masterPrompt'] ?? '').toString().isEmpty
            ? kDefaultMasterPrompt
            : m['masterPrompt'].toString();
        _autoUpload = m['autoUpload'] != false;
        _autoRotate = m['autoRotate'] != false;
        _autoCreate = m['autoCreate'] == true;
      }
    } catch (_) {}
    final dist = await DistributeStore.load();
    final (web, note) = await loadGeminiClient();

    // Account pool: migration from the v1.17 single token happens inside
    // StableAudioPool.load(), so an existing token keeps working.
    try {
      await _rot.load();
    } catch (e) {
      _log('Account pool could not be read: $e');
    }
    _rot.autoRotate = _autoRotate;
    _rot.autoCreate = _autoCreate;
    _rot.creator = (log) => StableAudioAccountCreator.create(onStatus: log);

    final sa = await StableAudioApi.load();
    sa.bindRotator(_rot);
    final active = _rot.current;
    if (active != null) sa.useAccount(active);

    if (!mounted) return;
    setState(() {
      _dist = dist;
      _web = web;
      _gemNote = note;
      _sa = sa;
      _saStatus = _accountStatus;
      if (_target.isEmpty) {
        _target = dist.accounts.isNotEmpty
            ? (dist.accounts.any((a) => a.name == 'zedge_2')
                ? 'zedge_2'
                : dist.accounts.first.name)
            : '';
      }
    });
    if (_rot.accounts.isNotEmpty) _refreshBalance();
  }

  /// AppBar summary: `Acct 2/4 · 37/50 cr`.
  String get _accountStatus {
    if (_rot.isEmpty) return 'No account';
    final acc = _rot.current;
    if (acc == null) return 'No account';
    return 'Acct ${_rot.index + 1}/${_rot.accounts.length} · '
        '${acc.creditsLabel}';
  }

  void _syncAccountStatus() {
    if (!mounted) return;
    setState(() => _saStatus = _accountStatus);
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'ringtone_settings_v1',
          jsonEncode({
            'soundType': _s.soundType,
            'audioShape': _s.audioShape,
            'takesCount': _s.takesCount,
            'timeSignature': _s.timeSignature,
            'lengthSeconds': _s.lengthSeconds,
            'negativePrompt': _negativeCtrl.text,
            'bannedWords': _bannedCtrl.text,
            'masterPrompt': _masterCtrl.text,
            'autoUpload': _autoUpload,
            'autoRotate': _autoRotate,
            'autoCreate': _autoCreate,
          }));
    } catch (_) {}
  }

  Future<void> _refreshBalance() async {
    if (_rot.accounts.isEmpty) {
      if (mounted) setState(() => _saStatus = 'No account');
      return;
    }
    await _rot.refreshAllCredits();
    _syncAccountStatus();
  }

  /// Manual rotation — the workflow's "Rotate Token" button.
  Future<void> _rotateNow() async {
    if (_rot.accounts.isEmpty && !_autoCreate) {
      _snack('Add a Stable Audio account first.');
      return;
    }
    setState(() => _saStatus = 'Rotating…');
    final ok = await _rot.rotate(reason: 'manual');
    final acc = _rot.current;
    if (acc != null) _sa?.useAccount(acc);
    _syncAccountStatus();
    if (!ok) {
      _snack('No account with credits left — add another account.');
    }
  }

  void _log(String line) {
    if (!mounted) return;
    setState(() {
      _logs.add(line);
      while (_logs.length > 180) _logs.removeAt(0);
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── Accounts (auto rotation) ──────────────────────────────────
  Future<void> _accountsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final accounts = _rot.accounts;
          final activeIdx = _rot.index;
          return AlertDialog(
            title: const Text('Stable Audio accounts'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Every Stable Audio account gets 50 credits (≈12 four-take '
                    'jobs). The studio rotates automatically when a JWT is '
                    'rejected or the credits run out — the same behaviour as '
                    'the cloud workflow.',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(ctx).colorScheme.outline),
                  ),
                  const SizedBox(height: 10),
                  if (accounts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No accounts yet. Add a token or let the app '
                          'create one for you.'),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: accounts.length,
                        itemBuilder: (_, i) {
                          final a = accounts[i];
                          final isActive = i == activeIdx;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              isActive
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 18,
                              color: isActive
                                  ? Theme.of(ctx).colorScheme.primary
                                  : null,
                            ),
                            title: Text(a.label,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${a.creditsLabel} · '
                                '${a.hasRefresh ? 'refresh token' : 'access token only'}'
                                '${a.autoCreated ? ' · auto-created' : ''}'),
                            onTap: () async {
                              await _rot.activate(i);
                              final acc = _rot.current;
                              if (acc != null) _sa?.useAccount(acc);
                              _syncAccountStatus();
                              setLocal(() {});
                            },
                            trailing: IconButton(
                              tooltip: 'Remove account',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () async {
                                await _rot.removeAt(i);
                                final acc = _rot.current;
                                if (acc != null) _sa?.useAccount(acc);
                                _syncAccountStatus();
                                setLocal(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Auto-rotate when credits run out'),
                    subtitle: const Text(
                        'Checks the balance before every job and switches to '
                        'the next account instead of failing the take.'),
                    value: _autoRotate,
                    onChanged: (v) async {
                      setState(() => _autoRotate = v);
                      _rot.autoRotate = v;
                      await _savePrefs();
                      setLocal(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Auto-create accounts (desktop)'),
                    subtitle: const Text(
                        'When every account is empty, sign up for a fresh '
                        '50-credit account in a browser window (temp-mail OTP).'),
                    value: _autoCreate,
                    onChanged: (v) async {
                      setState(() => _autoCreate = v);
                      _rot.autoCreate = v;
                      await _savePrefs();
                      setLocal(() {});
                    },
                  ),
                ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _addAccountDialog();
                },
                child: const Text('Add token'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _createAccountNow();
                },
                child: const Text('Auto-create'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _rotateNow();
                },
                child: const Text('Rotate now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Adds one account to the pool by pasting its bearer token.
  Future<void> _addAccountDialog() async {
    final tokCtrl =
        TextEditingController(text: await StableAudioStore.token());
    final refCtrl =
        TextEditingController(text: await StableAudioStore.refreshToken());
    final mailCtrl = TextEditingController();
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Stable Audio account'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Paste the bearer token from a signed-in stableaudio.com '
                'session. Add its WorkOS refresh token too and the studio can '
                'renew the session instead of burning a new account.'),
            const SizedBox(height: 12),
            TextField(
                controller: tokCtrl,
                decoration: const InputDecoration(
                    labelText: 'Access token (Bearer)'),
                maxLines: 3),
            const SizedBox(height: 8),
            TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                    labelText: 'Refresh token (optional, recommended)'),
                maxLines: 2),
            const SizedBox(height: 8),
            TextField(
                controller: mailCtrl,
                decoration: const InputDecoration(
                    labelText: 'Label / email (optional)'),
                maxLines: 1),
          ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add account')),
        ],
      ),
    );
    if (saved == true && tokCtrl.text.trim().isNotEmpty) {
      final acc = await _rot.addAccount(
        token: tokCtrl.text,
        refreshToken: refCtrl.text,
        email: mailCtrl.text,
      );
      _sa?.useAccount(acc);
      _syncAccountStatus();
      _snack('Account added — ${acc.creditsLabel}.');
    }
  }

  /// Browser + temp-mail signup (workflow `createStableAudioAccount`).
  Future<void> _createAccountNow() async {
    if (_rot.busy) {
      _snack('Account creation is already running.');
      return;
    }
    setState(() => _status = 'Creating a Stable Audio account…');
    final acc = await _rot.createAccount();
    final cur = _rot.current;
    if (cur != null) _sa?.useAccount(cur);
    _syncAccountStatus();
    _snack(acc == null
        ? 'Account creation did not complete — see the log.'
        : 'New account ready: ${acc.creditsLabel}.');
  }

  // ─── Settings sync from UI controls ────────────────────────────
  void _syncSettings() {
    _s.negativePrompt = _negativeCtrl.text;
    _s.bannedWords = _bannedCtrl.text;
    _s.masterPrompt = _masterCtrl.text;
    final custom = _customInstCtrl.text.trim();
    final parts = [
      ..._instruments.map((label) => kInstrumentChips[label] ?? label),
      if (custom.isNotEmpty) custom,
    ];
    _s.instruments = parts.isEmpty ? 'Auto' : parts.join(', ');
    _s.genre = kGenreOptions[_genreLabel] ?? 'Auto';
    _s.mood = _mood;
    _s.musicalKey = _key;
    _s.structure = kStructureOptions[_structureLabel] ?? 'Auto';
    _s.production = kProductionOptions[_productionLabel] ??
        'crisp modern studio mastered production with clear mids';
    _s.padMs = int.tryParse(_padCtrl.text) ?? 100;
    _s.fadeInMs = int.tryParse(_fadeInCtrl.text) ?? 30;
    _s.fadeOutMs = int.tryParse(_fadeOutCtrl.text) ?? 350;
    _s.seed = int.tryParse(_seedCtrl.text) ?? -1;
  }

  int get _promptLines => _promptsCtrl.text
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .length;

  // ─── Generation pipeline ───────────────────────────────────────
  Future<void> _generate() async {
    _syncSettings();
    await _savePrefs();
    if (_web == null) {
      final (web, note) = await loadGeminiClient();
      if (!mounted) return;
      setState(() {
        _web = web;
        _gemNote = note;
      });
    }
    if (_web == null) {
      _snack(
          'No Gemini session. Sign in inside the Image to Prompt browser once, or save a cookie export in Settings.');
      return;
    }
    final sa = _sa ?? await StableAudioApi.load();
    sa.bindRotator(_rot);
    _sa = sa;
    if (_rot.isEmpty && !_autoCreate) {
      _snack('Add a Stable Audio account first (top-right account button).');
      return;
    }
    final lines = _promptsCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final autoCount =
        (int.tryParse(_autoCountCtrl.text) ?? 5).clamp(1, 100);
    final prompts = <String?>[
      if (lines.isNotEmpty) ...lines else ...List.filled(autoCount, null),
    ];
    final targets = _target == 'all_accounts'
        ? _dist.accounts
        : _dist.accounts.where((a) => a.name == _target).toList();
    final effectiveTargets =
        targets.isEmpty ? <DistAccount?>[null] : targets;
    setState(() {
      _generating = true;
      _stop = false;
      _done = 0;
      _total = prompts.length * _s.takesCount * effectiveTargets.length;
      _status = 'Generating…';
    });
    final composer = RingtoneComposer(_web!, AutoDiscovery());
    final ffmpeg = await findFfmpeg();
    final rng = Random();
    try {
      for (final acc in effectiveTargets) {
        if (_stop) break;
        for (final prompt in prompts) {
          if (_stop) break;
          try {
            await _generateOne(
                composer, sa, prompt, acc, ffmpeg, rng);
          } catch (e) {
            _log('Failed: $e');
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _generating = false;
          _status = _stop
              ? 'Stopped. $_done/$_total takes done.'
              : 'Done. $_done/$_total takes generated.';
        });
      }
      _refreshBalance();
    }
  }

  Future<void> _generateOne(
    RingtoneComposer composer,
    StableAudioApi sa,
    String? prompt,
    DistAccount? acc,
    String? ffmpeg,
    Random rng,
  ) async {
    // Policy: a user prompt that itself violates policy is blocked.
    if (prompt != null) {
      final iss = ZedgePolicy.issues(prompt: prompt);
      if (iss.isNotEmpty) {
        throw Exception('Zedge policy blocked prompt: ${iss.first}');
      }
    }
    // 1) Gemini: enhanced prompt + metadata, policy-checked, up to 3
    // attempts like the workflow.
    RingtoneMeta? meta;
    List<RingtoneMeta>? takeMetas;
    for (var attempt = 1; attempt <= 3; attempt++) {
      final m = await composer.generate(prompt, _s);
      final en = ZedgePolicy.enforce(
        title: m.title,
        tags: m.tags,
        description: m.description,
        prompt: m.enhancedPrompt,
        category: m.category,
        audio: true,
      );
      if (en.issues.isNotEmpty) {
        _log('Policy issues (${en.issues.first}) — regenerating '
            '($attempt/3)');
        continue;
      }
      meta = RingtoneMeta(
        enhancedPrompt: m.enhancedPrompt,
        title: m.title,
        tags: en.tags.join(', '),
        category: m.category,
        description: m.description,
      );
      takeMetas =
          await composer.uniqueTakeMetas(meta, _s.takesCount, _s);
      break;
    }
    if (meta == null || takeMetas == null) {
      throw Exception('Metadata kept failing the Zedge policy check.');
    }
    _log('Prompt ready: "${meta.title}" (${meta.category})');

    // 2) Stable Audio: one job, all takes — through the rotation pool
    // (workflow ensureStableAudioTokenAndCredits: JWT refresh, credit
    // check, then rotate if this account cannot pay for the takes).
    final ready = await _rot.ensureReady(_s.takesCount);
    if (!ready) {
      throw Exception('No Stable Audio account with credits available.');
    }
    final activeAcc = _rot.current;
    if (activeAcc != null) sa.useAccount(activeAcc);
    _syncAccountStatus();
    final finalPrompt = buildStableAudioPrompt(meta.enhancedPrompt, _s);
    final baseSeed =
        _s.seed >= 0 ? _s.seed : 100000000 + rng.nextInt(800000000);
    final stems = await sa.compose(
      prompt: finalPrompt,
      s: _s,
      baseSeed: baseSeed,
      onStatus: (st) {
        if (mounted) setState(() => _status = st);
      },
    );
    _log('Stable Audio returned ${stems.length} take(s).');

    // 3) Per take: master, save locally, optionally push to panel.
    final dir = await getApplicationDocumentsDirectory();
    final toneDir = Directory('${dir.path}/ringtones');
    if (!await toneDir.exists()) await toneDir.create(recursive: true);
    for (var i = 0; i < stems.length; i++) {
      if (_stop) break;
      final tm = takeMetas[i < takeMetas.length ? i : takeMetas.length - 1];
      // MP3 ONLY — Zedge accepts nothing else. Mastering runs through
      // the bundled ffmpeg (all platforms), with a PATH ffmpeg as the
      // desktop second try. If both fail the take is skipped with an
      // error — a WAV is never saved or uploaded.
      final ff = await masterWithFfmpegKit(stems[i], _s) ??
          (ffmpeg != null
              ? await masterWithFfmpeg(stems[i], _s, ffmpeg)
              : null);
      if (ff == null) {
        _log('Take ${i + 1} skipped: MP3 mastering failed (ffmpeg '
            'unavailable). Zedge accepts MP3 only, so nothing was saved.');
        continue;
      }
      final outBytes = ff.$1;
      final stats = ff.$2;
      const ext = 'mp3';
      const mime = 'audio/mpeg';
      final safeTitle =
          tm.title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
      final fileName = 'ringtone_${DateTime.now().millisecondsSinceEpoch}'
          '_${i + 1}_$safeTitle.$ext';
      final file = File('${toneDir.path}/$fileName');
      await file.writeAsBytes(outBytes);
      final item = RingtoneItem(
        title: tm.title,
        tags: tm.tags,
        category: tm.category,
        description: tm.description,
        prompt: prompt ?? '',
        enhancedPrompt: finalPrompt,
        negativePrompt: _s.negativePrompt,
        filePath: file.path,
        fileName: fileName,
        mime: mime,
        size: outBytes.length,
        durationSec: stats.durationAfter > 0
            ? stats.durationAfter
            : _s.lengthSeconds.toDouble(),
        account: acc?.name ?? '',
        takeIndex: i,
        takesTotal: stems.length,
        seed: baseSeed + i,
        audioShape: _s.audioShape,
        musicalKey: _s.musicalKey,
        timeSignature: _s.timeSignature,
        lengthSeconds: _s.lengthSeconds,
        dsp: stats.toJson(),
      );
      if (mounted) setState(() => _items.insert(0, item));
      _log('Take ${i + 1}: "${tm.title}" mastered '
          '(peak ${stats.peakAfterDb.toStringAsFixed(1)} dB).');
      if (_autoUpload && acc != null && _dist.r2WorkerUrl.isNotEmpty) {
        await _pushItem(item, acc, silent: true);
      }
      if (mounted) setState(() => _done++);
    }
  }

  Future<void> _pushItem(RingtoneItem item, DistAccount acc,
      {bool silent = false}) async {
    try {
      final bytes = await File(item.filePath).readAsBytes();
      final r2Name = ringtoneFileName(acc.name, Random());
      final url = await uploadFileToR2(
        bytes: bytes,
        fileName: r2Name,
        mime: item.mime,
        workerUrl: _dist.r2WorkerUrl,
        folder: acc.r2Folder,
        subfolder: 'ringtone',
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final record = <String, dynamic>{
        'name': r2Name,
        'type': item.mime,
        'size': item.size,
        'width': null,
        'height': null,
        'isMp3': item.mime == 'audio/mpeg',
        'contentType': 'RINGTONE',
        'fileUrl': url,
        'title': item.title,
        'tags': item.tags,
        'category': item.category,
        'description': item.description,
        'policyCheck': 'passed',
        'policyCheckedAt': now,
        'status': 'queued',
        'prompt': item.prompt,
        'enhancedPrompt': item.enhancedPrompt,
        'negativePrompt': item.negativePrompt,
        'audioSeed': item.seed,
        'audioModel': 'stable-audio-wizard',
        'audioShape': item.audioShape,
        'musicalKey': item.musicalKey,
        'timeSignature': item.timeSignature,
        'lengthSeconds': item.durationSec.round(),
        'takeIndex': item.takeIndex,
        'takesTotal': item.takesTotal,
        'autoProcess': _s.autoProcess,
        'processed': item.dsp != null,
        'processing': item.dsp,
        'source': 'mh-content-making-studio',
        'createdAt': now,
      };
      final key = await pushToDatabase(
        dbUrl: acc.dbUrl,
        queuePath: _dist.queuePath,
        record: record,
        secret: acc.secret,
      );
      item.firebaseKey = key;
      item.fileUrl = url;
      item.account = acc.name;
      item.status = 'pushed';
      if (mounted) setState(() {});
      _log('Pushed "${item.title}" to ${acc.name} ($key).');
    } catch (e) {
      item.status = 'failed';
      if (mounted) setState(() {});
      if (!silent) _snack('Upload failed: $e');
      _log('Upload failed for "${item.title}": $e');
    }
  }

  // ─── Playback / item actions ───────────────────────────────────
  Future<void> _togglePlay(RingtoneItem item) async {
    if (_playingPath == item.filePath) {
      await _player.pause();
      setState(() => _playingPath = null);
      return;
    }
    await _player.stop();
    await _player.play(DeviceFileSource(item.filePath));
    setState(() => _playingPath = item.filePath);
  }

  Future<void> _editItem(RingtoneItem item) async {
    final titleCtrl = TextEditingController(text: item.title);
    final tagsCtrl = TextEditingController(text: item.tags);
    final descCtrl = TextEditingController(text: item.description);
    var cat = item.category;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit metadata'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: titleCtrl,
                maxLength: 30,
                decoration:
                    const InputDecoration(labelText: 'Title (max 25)')),
            DropdownButtonFormField<String>(
              initialValue: kRingtoneCategories.contains(cat) ? cat : 'OTHER',
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in kRingtoneCategories)
                  DropdownMenuItem(value: c, child: Text(c))
              ],
              onChanged: (v) => cat = v ?? cat,
            ),
            TextField(
                controller: tagsCtrl,
                decoration: const InputDecoration(
                    labelText: 'Tags (comma-separated single words)')),
            TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Short description (max 5 words)')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final en = ZedgePolicy.enforce(
      title: titleCtrl.text,
      tags: tagsCtrl.text,
      description: descCtrl.text,
      prompt: item.enhancedPrompt,
      category: cat,
      audio: true,
    );
    item.title = cleanRingtoneTitle(titleCtrl.text);
    item.tags = en.tags.join(', ');
    item.category = cat;
    item.description = cleanRingtoneDescription(descCtrl.text);
    if (item.firebaseKey != null && item.account.isNotEmpty) {
      final acc =
          _dist.accounts.where((a) => a.name == item.account).firstOrNull;
      if (acc != null) {
        try {
          await patchQueueRecord(
            dbUrl: acc.dbUrl,
            queuePath: _dist.queuePath,
            key: item.firebaseKey!,
            secret: acc.secret,
            patch: {
              'title': item.title,
              'tags': item.tags,
              'category': item.category,
              'description': item.description,
            },
          );
          _snack('Saved and patched in the panel.');
        } catch (e) {
          _snack('Saved locally; panel patch failed: $e');
        }
      }
    }
    if (mounted) setState(() {});
  }

  // ─── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _items
        .where((i) =>
            _filter.isEmpty ||
            i.title.toLowerCase().contains(_filter) ||
            i.tags.toLowerCase().contains(_filter) ||
            i.enhancedPrompt.toLowerCase().contains(_filter))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ringtone Studio'),
        actions: [
          TextButton.icon(
            onPressed: _accountsDialog,
            icon: const Icon(Icons.switch_account, size: 18),
            label: Text('Stable Audio: $_saStatus'),
          ),
          IconButton(
            tooltip: 'Rotate to the next Stable Audio account',
            icon: const Icon(Icons.sync, size: 20),
            onPressed: _rotateNow,
          ),
          IconButton(
            tooltip: 'Refresh credits for every account',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _refreshBalance,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _web == null
                ? 'Gemini: not connected — sign in in the Image to Prompt browser once.'
                : 'Gemini: ready${_gemNote.isNotEmpty ? ' ($_gemNote)' : ''}',
            style: TextStyle(color: scheme.outline, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _accountsSection(scheme),
          _promptsSection(scheme),
          _soundSection(scheme),
          _negativeSection(scheme),
          _masterSection(scheme),
          _masteringSection(scheme),
          const SizedBox(height: 12),
          _generateBar(scheme),
          if (_logs.isNotEmpty) _logBox(scheme),
          const SizedBox(height: 16),
          Row(children: [
            Text('Generated audios (${_items.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Filter by title, tag, prompt…',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (v) =>
                    setState(() => _filter = v.trim().toLowerCase()),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          for (final item in shown) _itemCard(item, scheme),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                  'No ringtones yet this session. Add prompt lines (or leave empty for Auto-Discovery) and tap Generate.',
                  style: TextStyle(color: scheme.outline)),
            ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(icon, size: 20),
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: children,
      ),
    );
  }

  /// Compact pool summary + the rotation controls. The workflow exposed a
  /// single "Rotate Token" button in its top bar; this is the same idea
  /// with the whole pool visible.
  Widget _accountsSection(ColorScheme scheme) {
    final acc = _rot.current;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.switch_account, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Stable Audio accounts',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text('${_rot.accounts.length} in pool',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            ]),
            const SizedBox(height: 6),
            Text(
              acc == null
                  ? 'No account yet — Stable Audio gives 50 credits per '
                      'account, so the studio rotates through a pool.'
                  : 'Active: ${acc.label} · ${acc.creditsLabel} · '
                      '${_autoRotate ? 'auto-rotate on' : 'auto-rotate off'}'
                      '${_autoCreate ? ' · auto-create on' : ''}',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(
                onPressed: _generating ? null : _rotateNow,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Rotate'),
              ),
              OutlinedButton.icon(
                onPressed: _generating ? null : _addAccountDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add token'),
              ),
              OutlinedButton.icon(
                onPressed: _generating ? null : _createAccountNow,
                icon: const Icon(Icons.person_add_alt, size: 16),
                label: const Text('Auto-create'),
              ),
              OutlinedButton.icon(
                onPressed: _generating ? null : _accountsDialog,
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Manage'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _promptsSection(ColorScheme scheme) {
    return _section('Prompts', Icons.list_alt_outlined, [
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Ringtone', label: Text('Ringtone (Full)')),
            ButtonSegment(value: 'Notification', label: Text('Notification')),
            ButtonSegment(value: 'Alarm', label: Text('Alarm Tone')),
          ],
          selected: {_s.soundType},
          onSelectionChanged: (v) => setState(() {
            _s.soundType = v.first;
            if (_s.soundType == 'Notification') {
              _s.lengthSeconds = 3;
              _s.audioShape = 'oneshot';
            } else {
              if (_s.lengthSeconds <= 3) _s.lengthSeconds = 20;
              if (_s.audioShape == 'oneshot') _s.audioShape = 'track';
            }
          }),
        ),
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'track', label: Text('Track')),
            ButtonSegment(value: 'loop', label: Text('Loop')),
            ButtonSegment(value: 'oneshot', label: Text('One-Shot')),
          ],
          selected: {_s.audioShape},
          onSelectionChanged: (v) => setState(() {
            _s.audioShape = v.first;
            if (_s.audioShape == 'oneshot') _s.lengthSeconds = 3;
            if (_s.audioShape == 'loop' && _s.lengthSeconds < 8) {
              _s.lengthSeconds = 20;
            }
          }),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _promptsCtrl,
        maxLines: 9,
        minLines: 4,
        decoration: const InputDecoration(
          labelText: 'Line-by-line prompts (one tone per line)',
          hintText:
              'Warm kalimba and soft Rhodes electric piano sunrise melody',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 6),
      Row(children: [
        TextButton(
          onPressed: () => setState(() => _promptsCtrl.text =
              (_s.soundType == 'Notification'
                      ? kSamplePromptsNotification
                      : kSamplePromptsRingtone)
                  .join('\n')),
          child: const Text('Load presets'),
        ),
        TextButton(
          onPressed: () => setState(() => _promptsCtrl.clear()),
          child: const Text('Clear'),
        ),
        const Spacer(),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _autoCountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Auto-count', isDense: true),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Slider(
            value: _s.lengthSeconds.toDouble(),
            min: 1,
            max: 60,
            divisions: 59,
            label: '${_s.lengthSeconds}s',
            onChanged: (v) =>
                setState(() => _s.lengthSeconds = v.round()),
          ),
        ),
        Text('${_s.lengthSeconds}s'),
      ]),
      Wrap(spacing: 6, children: [
        for (final (label, secs) in [
          ('3s One-Shot', 3),
          ('4s Chime', 4),
          ('5s Alert', 5),
          ('15s Short', 15),
          ('20s Loop/Track', 20),
          ('25s Ringtone', 25),
          ('30s Full', 30),
        ])
          ChoiceChip(
            label: Text(label),
            selected: _s.lengthSeconds == secs,
            onSelected: (_) => setState(() => _s.lengthSeconds = secs),
          ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: _s.takesCount,
            decoration:
                const InputDecoration(labelText: 'Tracks per prompt'),
            items: const [
              DropdownMenuItem(value: 4, child: Text('4 Tracks (All 4 Takes)')),
              DropdownMenuItem(value: 3, child: Text('3 Tracks')),
              DropdownMenuItem(value: 2, child: Text('2 Tracks')),
              DropdownMenuItem(value: 1, child: Text('1 Track')),
            ],
            onChanged: (v) => setState(() => _s.takesCount = v ?? 4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _s.timeSignature,
            decoration: const InputDecoration(labelText: 'Time signature'),
            items: const [
              DropdownMenuItem(value: '4/4', child: Text('4/4 (Standard)')),
              DropdownMenuItem(value: '3/4', child: Text('3/4 (Waltz)')),
              DropdownMenuItem(value: '6/8', child: Text('6/8 (Compound)')),
              DropdownMenuItem(value: '2/4', child: Text('2/4 (March)')),
            ],
            onChanged: (v) => setState(() => _s.timeSignature = v ?? '4/4'),
          ),
        ),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Gemini prompt enhancement'),
        subtitle: const Text(
            'Expand short ideas into rich studio prompts via Gemini'),
        value: _s.useGeminiEnhancer,
        onChanged: (v) => setState(() => _s.useGeminiEnhancer = v),
      ),
    ]);
  }

  Widget _soundSection(ColorScheme scheme) {
    return _section('BPM / Instruments', Icons.music_note_outlined, [
      Row(children: [
        const Text('Tempo'),
        const SizedBox(width: 8),
        Checkbox(
          value: _s.bpm == null,
          onChanged: (v) =>
              setState(() => _s.bpm = (v ?? false) ? null : 120),
        ),
        const Text('Auto BPM'),
        const Spacer(),
        Text(_s.bpm == null ? 'Auto' : '${_s.bpm} BPM'),
      ]),
      Slider(
        value: (_s.bpm ?? 120).toDouble(),
        min: 60,
        max: 200,
        divisions: 140,
        onChanged: _s.bpm == null
            ? null
            : (v) => setState(() => _s.bpm = v.round()),
      ),
      Wrap(spacing: 6, children: [
        for (final (label, bpm) in [
          ('Auto', null),
          ('75 Chill', 75),
          ('92 Lofi', 92),
          ('108 Groove', 108),
          ('120 Upbeat', 120),
          ('128 Club', 128),
          ('145 Fast', 145),
        ])
          ChoiceChip(
            label: Text(label),
            selected: _s.bpm == bpm,
            onSelected: (_) => setState(() => _s.bpm = bpm),
          ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        const Text('Lead & backing instruments'),
        const Spacer(),
        TextButton(
          onPressed: () => setState(() => _instruments.clear()),
          child: const Text('Reset (Auto)'),
        ),
      ]),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final label in kInstrumentChips.keys)
          FilterChip(
            label: Text(label),
            selected: _instruments.contains(label),
            onSelected: (v) => setState(() =>
                v ? _instruments.add(label) : _instruments.remove(label)),
          ),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _customInstCtrl,
        decoration: const InputDecoration(
          labelText: 'Custom instruments',
          hintText: 'Shamisen, Fretless Bass, Glockenspiel',
          isDense: true,
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _genreLabel,
        decoration: const InputDecoration(labelText: 'Genre style'),
        items: [
          for (final l in kGenreOptions.keys)
            DropdownMenuItem(value: l, child: Text(l))
        ],
        onChanged: (v) => setState(() => _genreLabel = v ?? _genreLabel),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _mood,
            decoration: const InputDecoration(labelText: 'Mood & vibe'),
            items: [
              for (final m in kMoodOptions)
                DropdownMenuItem(
                    value: m,
                    child: Text(m == 'Auto' ? 'Auto (Smart Variety)' : m))
            ],
            onChanged: (v) => setState(() => _mood = v ?? 'Auto'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _key,
            decoration: const InputDecoration(labelText: 'Musical scale / key'),
            items: [
              for (final k in kMusicalKeys)
                DropdownMenuItem(
                    value: k, child: Text(k == 'Auto' ? 'Auto Scale' : k))
            ],
            onChanged: (v) => setState(() => _key = v ?? 'Auto'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _structureLabel,
            decoration: const InputDecoration(labelText: 'Hook structure'),
            items: [
              for (final l in kStructureOptions.keys)
                DropdownMenuItem(value: l, child: Text(l))
            ],
            onChanged: (v) =>
                setState(() => _structureLabel = v ?? _structureLabel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _productionLabel,
            decoration: const InputDecoration(labelText: 'Production mix'),
            items: [
              for (final l in kProductionOptions.keys)
                DropdownMenuItem(value: l, child: Text(l))
            ],
            onChanged: (v) =>
                setState(() => _productionLabel = v ?? _productionLabel),
          ),
        ),
      ]),
    ]);
  }

  Widget _negativeSection(ColorScheme scheme) {
    return _section('Negative', Icons.block_outlined, [
      TextField(
        controller: _negativeCtrl,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'Negative prompt (anti-garbage audio guard)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in kNegativePresets.entries)
          ActionChip(
            label: Text(e.key),
            onPressed: () {
              final cur = _negativeCtrl.text
                  .split(',')
                  .map((x) => x.trim().toLowerCase())
                  .toSet();
              final add = e.value
                  .split(',')
                  .map((x) => x.trim())
                  .where((x) => !cur.contains(x.toLowerCase()))
                  .toList();
              if (add.isEmpty) return;
              setState(() => _negativeCtrl.text =
                  '${_negativeCtrl.text.trim()}, ${add.join(', ')}');
            },
          ),
        TextButton(
          onPressed: () =>
              setState(() => _negativeCtrl.text = kDefaultNegativePrompt),
          child: const Text('Reset default'),
        ),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _bannedCtrl,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Banned title words (excluded from Zedge titles)',
          border: OutlineInputBorder(),
        ),
      ),
    ]);
  }

  Widget _masterSection(ColorScheme scheme) {
    const vars = [
      '{{IDEA}}', '{{SOUND_TYPE}}', '{{DURATION}}', '{{BPM}}',
      '{{INSTRUMENTS}}', '{{GENRE}}', '{{MOOD}}', '{{KEY}}',
      '{{STRUCTURE}}', '{{PRODUCTION}}', '{{NEGATIVE_PROMPT}}',
      '{{ZEDGE_POLICY_RULES}}', '{{RENDERER_RULES}}', '{{CRAFT_RULES}}',
      '{{BANNED_WORDS}}', '{{VALID_CATEGORIES}}',
    ];
    return _section('Master prompt', Icons.terminal_outlined, [
      TextField(
        controller: _masterCtrl,
        maxLines: 12,
        decoration: const InputDecoration(
          labelText: 'Master prompt template (Gemini)',
          hintText:
              'Keep the output tags ([ENHANCED_PROMPT], [TITLE], [KEYWORDS], [CATEGORY], [DESCRIPTION]) intact.',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final v in vars)
          ActionChip(
            label: Text(v, style: const TextStyle(fontSize: 11)),
            onPressed: () {
              final t = _masterCtrl.text;
              final sel = _masterCtrl.selection;
              final at = sel.isValid ? sel.start : t.length;
              setState(() {
                _masterCtrl.text =
                    '${t.substring(0, at)}$v${t.substring(at)}';
              });
            },
          ),
      ]),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () =>
              setState(() => _masterCtrl.text = kDefaultMasterPrompt),
          child: const Text('Reset default'),
        ),
      ),
    ]);
  }

  Widget _masteringSection(ColorScheme scheme) {
    return _section('Mastering', Icons.tune_outlined, [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('FFmpeg-style auto-mastering'),
        subtitle: const Text(
            'Peak normalization to -1 dBFS + brickwall limiter, MP3 out via the bundled ffmpeg (Zedge accepts MP3 only).'),
        value: _s.autoProcess,
        onChanged: (v) => setState(() => _s.autoProcess = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Trim leading/trailing silence (fill full duration)'),
        value: _s.trimSilence,
        onChanged: (v) => setState(() => _s.trimSilence = v),
      ),
      Row(children: [
        const Text('Volume boost'),
        Expanded(
          child: Slider(
            value: _s.volumeBoostPct.toDouble(),
            min: 100,
            max: 400,
            divisions: 30,
            onChanged: (v) =>
                setState(() => _s.volumeBoostPct = v.round()),
          ),
        ),
        Text('${_s.volumeBoostPct}%'),
      ]),
      Row(children: [
        const Text('Silence threshold'),
        Expanded(
          child: Slider(
            value: _s.silenceThreshold,
            min: 0.005,
            max: 0.08,
            divisions: 15,
            onChanged: (v) => setState(() => _s.silenceThreshold = v),
          ),
        ),
        Text(_s.silenceThreshold.toStringAsFixed(3)),
      ]),
      Row(children: [
        for (final (label, ctrl) in [
          ('Edge pad (ms)', _padCtrl),
          ('Fade in (ms)', _fadeInCtrl),
          ('Fade out (ms)', _fadeOutCtrl),
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: label, isDense: true),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _s.bitrate,
            decoration: const InputDecoration(labelText: 'MP3 bitrate'),
            items: const [
              DropdownMenuItem(
                  value: '192k', child: Text('192 kbps (Standard HD)')),
              DropdownMenuItem(
                  value: '320k', child: Text('320 kbps (Studio Master)')),
            ],
            onChanged: (v) => setState(() => _s.bitrate = v ?? '192k'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _seedCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Audio seed (-1 = random)', isDense: true),
          ),
        ),
      ]),
    ]);
  }

  Widget _generateBar(ColorScheme scheme) {
    final n = _promptLines;
    final label = _generating
        ? 'Generating…'
        : (n > 0
            ? 'Generate $n Prompts (${n * _s.takesCount} Tracks)'
            : 'Auto-Generate ${(int.tryParse(_autoCountCtrl.text) ?? 5)} Prompts');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _target.isEmpty ? null : _target,
            decoration:
                const InputDecoration(labelText: 'Target panel account'),
            items: [
              for (final a in _dist.accounts)
                DropdownMenuItem(value: a.name, child: Text(a.name)),
              if (_dist.accounts.length > 1)
                const DropdownMenuItem(
                    value: 'all_accounts',
                    child: Text('all_accounts (unique per DB)')),
            ],
            onChanged: (v) => setState(() => _target = v ?? ''),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Upload to panel automatically'),
            value: _autoUpload,
            onChanged: (v) => setState(() => _autoUpload = v),
          ),
        ),
      ]),
      if (_dist.accounts.isEmpty)
        Text(
            'No panel accounts configured — tones stay local. Add accounts in Settings → Distribution to upload.',
            style: TextStyle(color: scheme.error, fontSize: 12)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _generating ? null : _generate,
            icon: const Icon(Icons.play_arrow, size: 20),
            label: Text(label),
          ),
        ),
        if (_generating) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => setState(() {
              _stop = true;
              _status = 'Stopping after current step…';
            }),
            child: const Text('Stop'),
          ),
        ],
      ]),
      const SizedBox(height: 8),
      if (_generating || _total > 0)
        LinearProgressIndicator(
            value: _total == 0 ? null : _done / _total),
      const SizedBox(height: 4),
      Text('$_status  ($_done/$_total)',
          style: TextStyle(color: scheme.outline, fontSize: 13)),
    ]);
  }

  Widget _logBox(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 160),
        child: SingleChildScrollView(
          reverse: true,
          child: Text(_logs.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ),
      ),
    );
  }

  Widget _itemCard(RingtoneItem item, ColorScheme scheme) {
    final playing = _playingPath == item.filePath;
    final dsp = item.dsp;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(
              icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
              onPressed: () => _togglePlay(item),
            ),
            Expanded(
              child: Text(item.title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Chip(
              label: Text(item.status == 'pushed'
                  ? 'In panel (${item.account})'
                  : item.status),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final b in [
              item.category,
              '${item.durationSec.toStringAsFixed(1)}s',
              item.audioShape,
              if (item.musicalKey != 'Auto') item.musicalKey,
              'Take ${item.takeIndex + 1}/${item.takesTotal}',
              if (dsp != null)
                'Peak ${(dsp['peakAfterDb'] as num).toStringAsFixed(1)} dB',
            ])
              Chip(label: Text(b), visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 4),
          Text('Zedge desc: ${item.description}   Seed: ${item.seed}',
              style: TextStyle(color: scheme.outline, fontSize: 12)),
          Text('Tags: ${item.tags}',
              style: TextStyle(color: scheme.outline, fontSize: 12)),
          Text('Audio prompt: ${item.enhancedPrompt}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.outline, fontSize: 12)),
          Row(children: [
            TextButton(
                onPressed: () => _editItem(item),
                child: const Text('Edit')),
            TextButton(
              onPressed: () => Share.shareXFiles([XFile(item.filePath)],
                  subject: item.title),
              child: const Text('MP3'),
            ),
            if (item.status != 'pushed' && item.account.isEmpty)
              TextButton(
                onPressed: _dist.accounts.isEmpty
                    ? null
                    : () {
                        final acc = _dist.accounts.firstWhere(
                            (a) => a.name == _target,
                            orElse: () => _dist.accounts.first);
                        _pushItem(item, acc);
                      },
                child: const Text('Upload to panel'),
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Delete local file',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () async {
                try {
                  await File(item.filePath).delete();
                } catch (_) {}
                setState(() => _items.remove(item));
              },
            ),
          ]),
        ]),
      ),
    );
  }
}
