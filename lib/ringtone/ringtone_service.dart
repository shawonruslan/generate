import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../cloud_sync.dart';
import '../distribute.dart';
import '../gemini_session_manager.dart';
import '../gemini_web.dart';
import '../keep_awake.dart';
import '../secure_store.dart';
import 'audio_master.dart';
import 'ringtone_metadata.dart';
import 'ringtone_models.dart';
import 'ringtone_policy.dart';
import 'ringtone_publish.dart';
import 'stable_audio.dart';
import 'stable_audio_browser.dart';
import 'stable_audio_http_accounts.dart';

/// Outcome of one prompt of a batch.
class RingtoneBatchResult {
  final String prompt;
  final bool ok;
  final String title;
  final int tracks;
  final String error;
  const RingtoneBatchResult(
      {required this.prompt,
      required this.ok,
      this.title = '',
      this.tracks = 0,
      this.error = ''});
}

/// Ringtone Studio engine: the workflow's `generateAndPushOne` +
/// `runGenerationBatch` + library routes, as an app service.
///
/// Gemini writes the Stable Audio prompt and the listing text, Stable
/// Audio renders 1-4 takes, each take is mastered, kept in the local
/// library and (optionally) uploaded to R2 + the Firebase queue.
class RingtoneService extends ChangeNotifier {
  static final RingtoneService instance = RingtoneService();

  RingtoneService({
    RingtoneAsker? asker,
    StableAudioClient? stableAudio,
    RingtonePublisher? publisher,
    http.Client? httpClient,
    Future<Directory> Function()? dataDir,
    Future<DistConfig> Function()? distLoader,
    Future<FfmpegInfo?> Function(String custom)? ffmpegFinder,
    this.persist = true,
  })  : _http = httpClient ?? http.Client(),
        stableAudio = stableAudio ?? StableAudioClient(httpClient: httpClient),
        publisher = publisher ?? RingtonePublisher(httpClient: httpClient),
        _dataDir = dataDir ?? _defaultDir,
        _distLoader = distLoader ?? DistributeStore.load,
        _ffmpegFinder = ffmpegFinder ??
            ((c) => FfmpegLocator.find(custom: c, refresh: true)) {
    engine = RingtoneMetadataEngine(asker ?? _askGemini)..onLog = log;
    this.stableAudio.onLog = log;
    this.stableAudio.onTokenChanged = notifyListeners;
    this.stableAudio.onAutoCreateAccount = _createStableAudioAccount;
  }

  final http.Client _http;
  final StableAudioClient stableAudio;
  final RingtonePublisher publisher;
  late final RingtoneMetadataEngine engine;
  final Future<Directory> Function() _dataDir;
  final Future<DistConfig> Function() _distLoader;
  final Future<FfmpegInfo?> Function(String custom) _ffmpegFinder;

  /// False in tests: nothing is written to preferences.
  final bool persist;

  static Future<Directory> _defaultDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}ringtones');
  }

  static const _kConfig = 'ringtone_config_v1';
  static const _kFfmpeg = 'ringtone_ffmpeg_path';
  static const _kPrompts = 'ringtone_prompts';
  static const _kAutoCount = 'ringtone_auto_count';

  RingtoneConfig config = RingtoneConfig();
  String ffmpegPath = '';
  String promptsText = '';
  int autoCount = 5;

  FfmpegInfo? ffmpeg;
  DistConfig dist = const DistConfig(r2WorkerUrl: '', accounts: []);
  bool _ready = false;
  bool get ready => _ready;

  bool running = false;
  bool stopRequested = false;
  String task = 'Ready';
  int completed = 0;
  int total = 0;
  final List<String> logs = [];
  List<RingtoneBatchResult> lastResults = const [];

  /// Newest first.
  final List<RingtoneItem> library = [];

  bool get distConfigured =>
      dist.r2WorkerUrl.trim().isNotEmpty &&
      RingtonePublisher.resolveTargets(dist, '').isNotEmpty;

  void log(String line) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    logs.add('[${two(t.hour)}:${two(t.minute)}:${two(t.second)}] $line');
    if (logs.length > 400) logs.removeRange(0, logs.length - 400);
    notifyListeners();
  }

  void _task(String s) {
    task = s;
    if (KeepAwake.supported) {
      KeepAwake.progress('ringtone', text: s, done: completed, total: total);
    }
    notifyListeners();
  }

  // ---- Gemini ----

  GeminiWebClient? _gemini;

  Future<String> _askGemini(String prompt) async {
    final c = _gemini ??= await GeminiSessionManager.savedClient();
    if (c == null) {
      throw Exception('Gemini is not connected. Open Settings > Gemini web '
          'session and use "Sign in with Google" first.');
    }
    try {
      return await c.ask(prompt,
          attempts: 2, freshChat: true, timeout: const Duration(seconds: 60));
    } on GeminiWebException catch (e) {
      // Build a new client next time: the session may have been renewed.
      if (e.expired) _gemini = null;
      rethrow;
    }
  }

  // ---- start-up / persistence ----

  Future<void>? _initing;

  Future<void> init() => _initing ??= _init();

  Future<void> _init() async {
    if (persist) {
      try {
        final p = await AppPrefs.prefs();
        final raw = p.getString(_kConfig);
        if (raw != null && raw.isNotEmpty) {
          config = RingtoneConfig.fromJson(
              (jsonDecode(raw) as Map).cast<String, dynamic>());
        }
        ffmpegPath = p.getString(_kFfmpeg) ?? '';
        promptsText = p.getString(_kPrompts) ?? '';
        autoCount = (p.getInt(_kAutoCount) ?? 5).clamp(1, 100);
      } catch (_) {}
    }
    config.normalize();
    _syncStableAudioFlags();
    try {
      await stableAudio.load();
      if (config.autoRefreshToken &&
          stableAudio.hasRefreshToken &&
          (!stableAudio.hasToken || stableAudio.tokenExpired)) {
        if (await stableAudio.refreshToken()) {
          await stableAudio.fetchCredits(allowRefresh: false);
        }
      }
    } catch (_) {}
    await _loadLibrary();
    await refreshEnvironment();
    _ready = true;
    notifyListeners();
  }

  void _syncStableAudioFlags() {
    stableAudio.autoRefreshEnabled = config.autoRefreshToken;
    stableAudio.autoRotateEnabled = config.autoRotateAccount;
  }

  Future<bool>? _accountAction;
  Future<StableAudioAccount?>? _accountCreation;
  bool get accountBusy => _accountAction != null || _accountCreation != null;

  /// Creates a fresh account through the REAL browser flow (Android WebView /
  /// desktop Chrome via CDP). AuthKit's signup form requires the browser
  /// "signals" fingerprint its own JS collects on the page (see HAR:
  /// POST /sign-up carries a ~3.5 KB base64 signals payload, preceded by a
  /// signing action that seals the __wuid cookie). A plain HTTP client sends
  /// empty signals and AuthKit silently refuses to advance past the first
  /// form — that was the "AuthKit did not advance to the next form" failure.
  /// The pure-HTTP path is kept only as a last resort on platforms with no
  /// browser engine, where it will surface the server's real rejection.
  Future<StableAudioAccount?> _createStableAudioAccount() {
    final active = _accountCreation;
    if (active != null) return active;
    final Future<StableAudioAccount?> run;
    if (StableAudioBrowser.supported) {
      run = StableAudioBrowser.autoCreateAccount(onLog: log);
    } else {
      run = StableAudioHttpAccounts.autoCreateAccount(
          onLog: log, httpClient: _http);
    }
    final tracked = run.whenComplete(() {
      _accountCreation = null;
      notifyListeners();
    });
    _accountCreation = tracked;
    notifyListeners();
    return tracked;
  }

  /// Rotates to another saved account, or creates a fresh one through the
  /// browser signup flow when [createNew] is true.
  Future<bool> rotateStableAudioAccount({bool createNew = false}) {
    final active = _accountAction;
    if (active != null) return active;
    final run = _rotateStableAudioAccount(createNew: createNew);
    final tracked = run.whenComplete(() {
      _accountAction = null;
      notifyListeners();
    });
    _accountAction = tracked;
    notifyListeners();
    return tracked;
  }

  Future<bool> _rotateStableAudioAccount({required bool createNew}) async {
    await stableAudio.load();
    final originalId = stableAudio.activeAccountId;
    try {
      if (createNew) {
        final created = await _createStableAudioAccount();
        if (created == null) return false;
        await stableAudio.addAccount(
          accessToken: created.accessToken,
          refreshToken: created.refreshToken,
          clientId: created.clientId,
          label: created.label,
          makeActive: true,
        );
        await stableAudio.fetchCredits(allowRefresh: false);
        if (stableAudio.termsRequired) {
          try {
            await stableAudio.acceptTerms();
            log('Stable Audio terms auto-accepted for the new account.');
          } catch (_) {
            log('Terms auto-accept failed once - generation will retry it.');
          }
        }
        return true;
      }
      return await stableAudio.rotateToNextAccount(
        minCredits: config.takesCount * 4,
        createIfNone: true,
      );
    } catch (_) {
      if (originalId.isNotEmpty) await stableAudio.selectAccount(originalId);
      rethrow;
    }
  }

  /// Manual accept from Settings; generation auto-accepts on its own.
  Future<bool> acceptStableAudioTerms() async {
    final ok = await stableAudio.acceptTerms();
    notifyListeners();
    return ok;
  }

  Future<bool> refreshStableAudioToken() async {
    final ok = await stableAudio.refreshToken();
    if (ok) await stableAudio.fetchCredits(allowRefresh: false);
    notifyListeners();
    return ok;
  }

  /// Re-reads the distribution accounts and looks for ffmpeg again.
  Future<void> refreshEnvironment() async {
    try {
      dist = await _distLoader();
    } catch (_) {}
    try {
      ffmpeg = await _ffmpegFinder(ffmpegPath);
    } catch (_) {
      ffmpeg = null;
    }
    notifyListeners();
  }

  Future<void> saveConfig() async {
    config.normalize();
    _syncStableAudioFlags();
    notifyListeners();
    if (!persist) return;
    try {
      final p = await AppPrefs.prefs();
      await p.setString(_kConfig, jsonEncode(config.toJson()));
      await p.setString(_kPrompts, promptsText);
      await p.setInt(_kAutoCount, autoCount);
      // Ringtone settings are part of cloud sync (debounced push).
      CloudSync.notifyChanged();
    } catch (_) {}
  }

  Future<void> setFfmpegPath(String path) async {
    ffmpegPath = path.trim();
    if (persist) {
      try {
        await (await AppPrefs.prefs()).setString(_kFfmpeg, ffmpegPath);
      } catch (_) {}
    }
    await refreshEnvironment();
  }

  Future<File> _libraryFile() async {
    final d = await _dataDir();
    await d.create(recursive: true);
    return File('${d.path}${Platform.pathSeparator}library.json');
  }

  Future<Directory> _audioDir() async {
    final d =
        Directory('${(await _dataDir()).path}${Platform.pathSeparator}audio');
    await d.create(recursive: true);
    return d;
  }

  Future<void> _loadLibrary() async {
    try {
      final f = await _libraryFile();
      if (!f.existsSync()) return;
      final items = RingtoneItem.decodeList(await f.readAsString());
      for (final i in items) {
        i.isNewSession = false;
        // The audio file was removed outside the app.
        if (i.localPath.isNotEmpty && !File(i.localPath).existsSync()) {
          i.localPath = '';
        }
      }
      // Local-only entries without their file are of no use.
      items.removeWhere((i) => i.localPath.isEmpty && !i.published);
      library
        ..clear()
        ..addAll(items);
      _sort();
    } catch (_) {}
  }

  Future<void>? _saving;
  bool _saveAgain = false;

  /// Writes the library file; overlapping calls are folded into one
  /// trailing write so two saves never interleave in the same file.
  Future<void> _saveLibrary() async {
    if (_saving != null) {
      _saveAgain = true;
      return _saving;
    }
    final done = () async {
      do {
        _saveAgain = false;
        try {
          final f = await _libraryFile();
          final tmp = File('${f.path}.tmp');
          await tmp.writeAsString(RingtoneItem.encodeList(library),
              flush: true);
          await tmp.rename(f.path);
        } catch (_) {}
      } while (_saveAgain);
    }();
    _saving = done;
    try {
      await done;
    } finally {
      _saving = null;
    }
  }

  void _sort() {
    library.sort((a, b) {
      final n = (b.isNewSession ? 1 : 0) - (a.isNewSession ? 1 : 0);
      return n != 0 ? n : b.createdAt.compareTo(a.createdAt);
    });
  }

  // ---- batch ----

  /// The prompt box, one idea per line; empty box = [autoCount] smart
  /// auto concepts ('' entries).
  static List<String> promptList(String text, int autoCount) {
    final lines = [
      for (final l in text.split('\n'))
        if (l.trim().isNotEmpty) l.trim()
    ];
    return lines.isNotEmpty ? lines : List.filled(autoCount.clamp(1, 100), '');
  }

  /// What stops a run before it starts ('' = good to go).
  String preflight(List<String> prompts) {
    for (final p in prompts) {
      if (p.isEmpty) continue;
      final issues = RingtonePolicy.issues(title: p);
      if (issues.isNotEmpty) {
        return 'Prompt "$p" is blocked by the content policy: ${issues.join('; ')}';
      }
    }
    if (config.autoPublish) {
      if (!distConfigured) {
        return 'Auto-publish is on, but no distribution account / R2 worker is set up. '
            'Add them under Settings > Distribution, or turn auto-publish off to keep the tones on this device.';
      }
      final selected = config.targetAccount.trim();
      if (selected.isNotEmpty &&
          selected != RingtonePublisher.allAccounts &&
          !dist.accounts.any((a) =>
              a.name.toLowerCase() == selected.toLowerCase() &&
              a.dbUrl.trim().isNotEmpty)) {
        return 'The selected distribution account is no longer configured. Choose an account again.';
      }
      if (ffmpeg == null) {
        return 'Auto-publish needs MP3 files, and MP3 encoding needs ffmpeg. '
            'Install it from the "Mastering engine" card, or turn auto-publish off.';
      }
    }
    return '';
  }

  void stop() {
    if (!running) return;
    stopRequested = true;
    _task('Stopping after the current step...');
  }

  /// Runs [prompts] ('' = auto concept). Returns one result per prompt.
  Future<List<RingtoneBatchResult>> run(List<String> prompts) async {
    if (running) throw Exception('A generation batch is already running.');
    await init();
    await refreshEnvironment();
    final cfg = config.copy()..normalize();
    final problem = preflight(prompts);
    if (problem.isNotEmpty) throw Exception(problem);

    // Local runs render once; published runs render a separate set of
    // takes per account, like the workflow, so no two accounts ever
    // upload the same audio.
    final targets = cfg.autoPublish
        ? RingtonePublisher.resolveTargets(dist, cfg.targetAccount)
        : const <DistAccount?>[null];

    running = true;
    stopRequested = false;
    completed = 0;
    total = prompts.length * cfg.takesCount * targets.length;
    lastResults = const [];
    KeepAwake.start('ringtone', 'Ringtone Studio',
        text: 'Starting...', done: 0, total: total);
    _task('Starting...');
    final results = <RingtoneBatchResult>[];
    var fatal = false;
    try {
      for (var i = 0; i < prompts.length && !stopRequested && !fatal; i++) {
        final prompt = prompts[i];
        final label = prompt.isEmpty ? 'Smart auto concept' : '"$prompt"';
        log('[${i + 1}/${prompts.length}] $label (${cfg.takesCount} take${cfg.takesCount == 1 ? '' : 's'})');
        try {
          final made = <RingtoneItem>[];
          for (final t in targets) {
            if (stopRequested) break;
            made.addAll(await _generateOne(prompt, t, cfg));
          }
          results.add(RingtoneBatchResult(
              prompt: prompt.isEmpty ? 'Auto-generated' : prompt,
              ok: made.isNotEmpty,
              title: made.isEmpty ? '' : made.first.title,
              tracks: made.length,
              error: made.isEmpty ? 'Stopped' : ''));
        } catch (e) {
          log('Prompt ${i + 1} failed: $e');
          results.add(RingtoneBatchResult(
              prompt: prompt.isEmpty ? 'Auto-generated' : prompt,
              ok: false,
              error: '$e'));
          // Every remaining prompt would hit the same wall.
          if (_stopsBatch(e)) {
            fatal = true;
            final left = prompts.length - i - 1;
            if (left > 0)
              log('Batch halted - $left prompt${left == 1 ? '' : 's'} not started.');
          }
        }
      }
    } finally {
      running = false;
      lastResults = results;
      final failed = results.where((r) => !r.ok).length;
      final skipped = prompts.length - results.length;
      task = stopRequested
          ? 'Stopped - $completed take${completed == 1 ? '' : 's'} finished'
          : fatal
              ? 'Halted: ${results.last.error}'
              : failed > 0
                  ? 'Done - $completed take${completed == 1 ? '' : 's'}, $failed prompt${failed == 1 ? '' : 's'} failed'
                  : 'Done - $completed take${completed == 1 ? '' : 's'} ready';
      if (skipped > 0 && !fatal) task += ' ($skipped not started)';
      stopRequested = false;
      KeepAwake.stop('ringtone');
      await _saveLibrary();
      notifyListeners();
    }
    return results;
  }

  static bool _stopsBatch(Object e) {
    if (e is StableAudioException) {
      return e.kind == StableAudioFailure.auth ||
          e.kind == StableAudioFailure.credits;
    }
    if (e is GeminiWebException) return e.expired;
    return e.toString().contains('Gemini is not connected');
  }

  String _who(DistAccount? t) => t == null ? '' : '[${t.name}] ';

  Future<List<RingtoneItem>> _generateOne(
      String prompt, DistAccount? target, RingtoneConfig cfg) async {
    final who = _who(target);
    final durSec = cfg.lengthSeconds.clamp(1, 60);

    final meta = await engine.generateCompliant(prompt, cfg,
        cancelled: () => stopRequested,
        onAttempt: (a) => _task(
            '${who}Writing prompt & listing text with Gemini (try $a/3)...'));
    if (stopRequested) return const [];
    log('${who}Title: "${meta.title}" | ${meta.category} | ${cfg.audioShape} | ${durSec}s');

    _task(
        '${who}Rendering ${cfg.takesCount} take${cfg.takesCount == 1 ? '' : 's'} of "${meta.title}" on Stable Audio...');
    final job = await stableAudio.compose(meta.enhancedPrompt, cfg);
    log('${who}Render started (job ${job.jobId}, seed ${job.baseSeed}).');
    // Credits are spent once the job exists: wait it out even when Stop
    // is pressed, so the takes that were paid for are not thrown away.
    final stems = await stableAudio.waitForStems(job.jobId,
        onProgress: (d, t) => _task(
            '${who}Rendering "${meta.title}" on Stable Audio ($d/$t takes)...'));
    final totalTakes = stems.length;

    _task('${who}Writing $totalTakes different titles, tags & descriptions...');
    final metas = await engine.uniqueTakes(meta, totalTakes, cfg);
    final created = <RingtoneItem>[];
    final audioDir = await _audioDir();

    for (var idx = 0; idx < totalTakes; idx++) {
      final stem = stems[idx];
      final n = idx + 1;
      final m = idx < metas.length ? metas[idx] : meta;
      try {
        _task('${who}Downloading take $n/$totalTakes ("${m.title}")...');
        final wav = await stableAudio.downloadStem(job.jobId, stem);

        _task('${who}Mastering take $n/$totalTakes ("${m.title}")...');
        final r = await AudioMaster.process(wav, cfg, ffmpeg);
        if (r.error.isNotEmpty) {
          log('${who}Mastering failed on take $n, kept the plain render: ${r.error}');
        }
        final afterDur = r.stats?['durationAfter'];
        final createdAt = DateTime.now().millisecondsSinceEpoch;
        final id = 'local_${createdAt}_$n';
        final file =
            File('${audioDir.path}${Platform.pathSeparator}$id.${r.extension}');
        await file.writeAsBytes(r.bytes, flush: true);

        final item = RingtoneItem(
          id: id,
          title: m.title,
          tags: m.tags,
          category: m.category,
          description: m.description,
          prompt: prompt.isNotEmpty ? prompt : meta.enhancedPrompt,
          enhancedPrompt: job.finalPrompt,
          negativePrompt: cfg.negativePrompt,
          localPath: file.path,
          fileName: '${_slug(m.title)}.${r.extension}',
          mimeType: r.mime,
          sizeBytes: r.bytes.length,
          lengthSeconds: afterDur is num
              ? afterDur.toDouble()
              : (stem.durationSeconds ?? durSec.toDouble()),
          audioSeed: stem.seed ?? (job.baseSeed + idx),
          audioShape: cfg.audioShape,
          musicalKey: cfg.musicalKey,
          timeSignature: cfg.timeSignature,
          takeIndex: n,
          takesTotal: totalTakes,
          wizardJobId: job.jobId,
          processed: r.processed,
          processing: r.stats,
          processError: r.error,
          isNewSession: true,
          createdAt: createdAt,
        );
        library.insert(0, item);
        created.add(item);

        if (target != null) {
          try {
            _task('${who}Uploading take $n/$totalTakes ("${m.title}")...');
            await _publish(item, target, r.bytes, cfg.autoProcess);
            log('${who}Queued take $n/$totalTakes "${m.title}" -> ${item.firebaseKey}');
          } catch (e) {
            // The take is safe in the library; "Publish" retries it.
            log('${who}Take $n is saved on this device, but publishing failed: $e');
          }
        } else {
          log('Take $n/$totalTakes "${m.title}" saved (${item.lengthSeconds.toStringAsFixed(1)}s).');
        }
        completed++;
        notifyListeners();
        unawaited(_saveLibrary());
      } catch (e) {
        log('${who}Take $n/$totalTakes failed: $e');
      }
      // Stop skips the takes not downloaded yet.
      if (stopRequested) break;
    }
    if (created.isEmpty && !stopRequested) {
      throw Exception('None of the $totalTakes takes could be downloaded.');
    }
    return created;
  }

  static String _slug(String title) {
    final s = title
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'tone' : s;
  }

  // ---- library actions ----

  Future<void> _publish(RingtoneItem item, DistAccount target, Uint8List mp3,
      bool autoProcess) async {
    final fileName = publisher.generateFilename(target.name);
    final fileUrl = await publisher.uploadToR2(
        bytes: mp3,
        fileName: fileName,
        workerUrl: dist.r2WorkerUrl,
        folder: target.r2Folder);
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    String key;
    try {
      key = await publisher.pushRecord(
          target,
          dist.queuePath,
          RingtonePublisher.buildRecord(
              item: item,
              fileName: fileName,
              fileUrl: fileUrl,
              size: mp3.length,
              autoProcess: autoProcess,
              createdAt: createdAt));
    } catch (e) {
      // No queue entry points at the upload: do not leave it behind.
      try {
        await publisher.deleteFromR2(fileUrl, dist.r2WorkerUrl);
      } catch (_) {}
      rethrow;
    }
    item
      ..dbName = target.name
      ..firebaseKey = key
      ..fileUrl = fileUrl;
  }

  /// Sends a local take to [accountName]'s queue. WAV takes (made
  /// without ffmpeg) are encoded to MP3 first.
  Future<void> publish(RingtoneItem item, String accountName) async {
    if (item.published) throw Exception('This tone is already in a queue.');
    await refreshEnvironment();
    if (!distConfigured) {
      throw Exception(
          'Set up an account and the R2 worker under Settings > Distribution first.');
    }
    final matches = dist.accounts
        .where((a) =>
            a.name.toLowerCase() == accountName.trim().toLowerCase() &&
            a.dbUrl.trim().isNotEmpty)
        .toList();
    if (matches.isEmpty) {
      throw Exception(
          'The selected distribution account is no longer configured.');
    }
    final target = matches.first;
    final issues = RingtonePolicy.issues(
        title: item.title, tags: item.tags, description: item.description);
    if (issues.isNotEmpty) {
      throw Exception('Fix the listing text first: ${issues.join('; ')}');
    }
    if (item.localPath.isEmpty || !File(item.localPath).existsSync()) {
      throw Exception(
          'The audio file of this tone is no longer on this device.');
    }
    var bytes = await File(item.localPath).readAsBytes();
    if (!item.isMp3) {
      final ff = ffmpeg;
      if (ff == null) {
        throw Exception(
            'The queue takes MP3 only and this take is a WAV. Install ffmpeg from the "Mastering engine" card, then publish again.');
      }
      bytes = await AudioMaster.toMp3(bytes, ff, config.bitrate);
      final old = File(item.localPath);
      final mp3 =
          File(item.localPath.replaceFirst(RegExp(r'\.[^.\\/]+$'), '.mp3'));
      await mp3.writeAsBytes(bytes, flush: true);
      item
        ..localPath = mp3.path
        ..mimeType = 'audio/mpeg'
        ..sizeBytes = bytes.length
        ..fileName = item.fileName.replaceFirst(RegExp(r'\.[^.]+$'), '.mp3');
      try {
        if (old.path != mp3.path) old.deleteSync();
      } catch (_) {}
    }
    await _publish(item, target, bytes, item.processed);
    log('Published "${item.title}" to ${target.name}.');
    await _saveLibrary();
    notifyListeners();
  }

  DistAccount? _account(String name) {
    for (final a in dist.accounts) {
      if (a.name == name) return a;
    }
    return null;
  }

  /// Saves edited listing text (and patches the queue entry when the
  /// tone is published). Returns the cleaned values that were stored.
  Future<RingtoneMeta> updateMeta(RingtoneItem item,
      {required String title,
      required String tags,
      required String category,
      required String description}) async {
    final ct = RingtonePolicy.cleanTitle(title);
    final cd = RingtonePolicy.cleanDescription(description);
    final clean = RingtoneMeta(
      enhancedPrompt: item.enhancedPrompt,
      title: ct.isNotEmpty ? ct : title.trim(),
      tags: RingtonePolicy.cleanTags(tags).join(', '),
      category: RingtonePolicy.cleanCategory(category),
      description: cd.isNotEmpty ? cd : description.trim(),
    );
    if (clean.title.isEmpty) throw Exception('The title cannot be empty.');
    final issues = RingtonePolicy.issues(
        title: clean.title, tags: clean.tags, description: clean.description);
    if (issues.isNotEmpty) {
      throw Exception('Not saved - content policy: ${issues.join('; ')}');
    }
    if (item.published) {
      final a = _account(item.dbName);
      if (a == null) {
        throw Exception(
            'Account "${item.dbName}" is no longer in Settings > Distribution.');
      }
      await publisher.patchRecord(a, dist.queuePath, item.firebaseKey, {
        'title': clean.title,
        'tags': clean.tags,
        'category': clean.category,
        'description': clean.description,
      });
    }
    item
      ..title = clean.title
      ..tags = clean.tags
      ..category = clean.category
      ..description = clean.description;
    await _saveLibrary();
    notifyListeners();
    return clean;
  }

  /// Removes a tone: its queue entry and R2 file (when published) and
  /// the local file. The R2 file is deleted first, as in the workflow,
  /// so a failed delete never leaves an orphan nobody points at.
  Future<void> delete(RingtoneItem item) async {
    if (item.published) {
      final a = _account(item.dbName);
      if (a == null) {
        throw Exception(
            'Account "${item.dbName}" is no longer in Settings > Distribution, so its queue entry cannot be removed.');
      }
      final shared = library.any((o) =>
          !identical(o, item) &&
          o.fileUrl.isNotEmpty &&
          o.fileUrl == item.fileUrl);
      if (item.fileUrl.isNotEmpty && !shared) {
        await publisher.deleteFromR2(item.fileUrl, dist.r2WorkerUrl);
      }
      await publisher.deleteRecord(a, dist.queuePath, item.firebaseKey);
    }
    if (item.localPath.isNotEmpty) {
      try {
        final f = File(item.localPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    library.remove(item);
    await _saveLibrary();
    notifyListeners();
  }

  /// Pulls the tones waiting in every account's queue into the library
  /// (workflow `syncFirebaseRingtones`). Returns how many were added;
  /// [errors] collects the accounts that could not be read.
  Future<int> syncQueue({List<String>? errors}) async {
    await refreshEnvironment();
    final known = {
      for (final i in library)
        if (i.published) '${i.dbName}:${i.firebaseKey}'
    };
    var added = 0;
    for (final a in RingtonePublisher.resolveTargets(
        dist, RingtonePublisher.allAccounts)) {
      try {
        final remote = await publisher.fetchQueue(a, dist.queuePath);
        final live = {for (final r in remote) r.firebaseKey};
        for (final r in remote) {
          if (known.add('${a.name}:${r.firebaseKey}')) {
            library.add(r);
            added++;
          }
        }
        // Entries the uploader has taken out of the queue: keep the
        // local audio (as an unpublished tone), drop pure references.
        for (final i in [...library]) {
          if (i.dbName != a.name || !i.published) continue;
          if (live.contains(i.firebaseKey)) continue;
          if (i.localPath.isEmpty) {
            library.remove(i);
          } else {
            i
              ..dbName = ''
              ..firebaseKey = ''
              ..fileUrl = '';
          }
        }
      } catch (e) {
        errors?.add('${a.name}: $e');
        log('Queue sync (${a.name}): $e');
      }
    }
    _sort();
    await _saveLibrary();
    notifyListeners();
    return added;
  }

  /// A playable local file for [item]; queue-only tones are downloaded
  /// into the cache on first use.
  Future<String> ensureLocal(RingtoneItem item) async {
    if (item.localPath.isNotEmpty && File(item.localPath).existsSync()) {
      return item.localPath;
    }
    if (item.fileUrl.isEmpty) {
      throw Exception('This tone has no audio file.');
    }
    http.Response r;
    try {
      r = await _http
          .get(Uri.parse(item.fileUrl))
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw Exception('Could not download the audio: $e');
    }
    if (r.statusCode < 200 || r.statusCode >= 300 || r.bodyBytes.length < 200) {
      throw Exception('Could not download the audio (HTTP ${r.statusCode}).');
    }
    final safe = item.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final f =
        File('${(await _audioDir()).path}${Platform.pathSeparator}$safe.mp3');
    await f.writeAsBytes(r.bodyBytes, flush: true);
    item
      ..localPath = f.path
      ..sizeBytes = item.sizeBytes == 0 ? r.bodyBytes.length : item.sizeBytes;
    unawaited(_saveLibrary());
    notifyListeners();
    return f.path;
  }

  /// Copies the audio of [item] into [dir] under a readable name;
  /// returns the new file.
  Future<File> exportTo(RingtoneItem item, Directory dir) async {
    final src = File(await ensureLocal(item));
    final ext = src.path.split('.').last;
    await dir.create(recursive: true);
    final base = _slug(item.title);
    var out = File('${dir.path}${Platform.pathSeparator}$base.$ext');
    for (var i = 2; out.existsSync(); i++) {
      out = File('${dir.path}${Platform.pathSeparator}${base}_$i.$ext');
    }
    return src.copy(out.path);
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }
}
