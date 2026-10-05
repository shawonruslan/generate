import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../cloudinary_api.dart';
import '../app_theme.dart';
import '../gemini_api.dart';
import '../models.dart';
import '../secure_store.dart';
import '../zip_export.dart';
import '../widgets/device_mockup.dart';
import 'settings_screen.dart';

/// One unit of work: a single prompt x a single set variant.
class BatchJob {
  final int index;
  final int promptIndex;
  final String prompt;
  final String variantLabel;
  final String variantSuffix;

  /// First job of a set: generated with text-to-image. The other variants
  /// of the set chain from it via image-to-image for visual consistency.
  final bool isAnchor;

  /// Index of this set's anchor job ([index] itself when [isAnchor]).
  final int anchorIndex;

  /// True for the anchor of a multi-variant set: generated only as a
  /// chaining reference, never shown in results and never saved.
  final bool hidden;

  const BatchJob({
    required this.index,
    required this.promptIndex,
    required this.prompt,
    required this.variantLabel,
    required this.variantSuffix,
    required this.isAnchor,
    required this.anchorIndex,
    required this.hidden,
  });
}

class _ItemState {
  final BatchJob job;
  final GenerationResult? result;
  final Object? error;
  final bool running;

  const _ItemState({
    required this.job,
    this.result,
    this.error,
    this.running = false,
  });

  _ItemState copyWith({
    GenerationResult? result,
    Object? error,
    bool? running,
  }) {
    return _ItemState(
      job: job,
      result: result ?? this.result,
      error: error,
      running: running ?? this.running,
    );
  }
}

/// Listing metadata for one prompt's set, plus which model/key wrote it.
class _SetMeta {
  final SetMetadata meta;
  final String model; // Gemini model id, or 'prompt' for the fallback
  final int keyIndex; // 0-based key number, -1 for the fallback

  const _SetMeta(this.meta, this.model, this.keyIndex);
}

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  SetType _setType = SetType.h24;
  // Mix-set distribution: how many prompts become each concrete set type.
  int _mix24 = 0;
  int _mixBattery = 0;
  int _mixDual = 0;
  int _mixSingle = 0;
  final List<TextEditingController> _promptCtrls = [TextEditingController()];
  final _seedCtrl = TextEditingController();

  String _model = 'nano-banana-2';
  String _ratio = '9:16';
  String _resolution = '1K';
  String _format = 'png';
  int _exportIndex = 0;
  int _displayIndex = 0; // 0 Any display, 1 AMOLED, 2 IPS
  int _colorBoostIndex = 0; // 0 Off, 1 Subtle, 2 Vivid, 3 Neon
  int _h24ArcIndex = 0; // 0 Auto (smart), else SetArcs.h24[i - 1]
  int _batteryArcIndex = 0; // 0 Auto (smart), else SetArcs.battery[i - 1]
  bool _director = false; // AI Set Director plans each set with Gemini
  /// Director plans per prompt index (only when _director was on).
  Map<int, SetDirection> _plans = {};

  // --- AI metadata (Gemini) ---
  /// Concrete set type per prompt index (matters for mix sets).
  Map<int, SetType> _promptTypes = {};
  /// Listing metadata per prompt index.
  final Map<int, _SetMeta> _meta = {};
  bool _writingMeta = false;
  String _metaStatus = '';
  bool _geminiReady = false;
  List<String> _gemKeys = [];
  List<String> _gemModels = [];
  int _gridCols = 3; // result thumbnail columns, 2..6

  CloudinaryCredentials _creds = const CloudinaryCredentials(
      cloudName: '', apiKey: '', apiSecret: '');
  bool _ready = false;

  bool _running = false;
  bool _cancelRequested = false;
  bool _savingAll = false;
  bool _savingZip = false;
  int _done = 0;
  int _total = 0;
  String _current = '';

  List<BatchJob> _jobs = [];
  Map<int, _ItemState> _states = {};

  static const _concurrency = 3;

  @override
  void initState() {
    super.initState();
    _init();
    _loadGemini();
  }

  /// Loads the Gemini key/model pool; metadata buttons enable when at
  /// least one key is saved.
  Future<void> _loadGemini() async {
    try {
      final pool = await GeminiStore.load();
      if (!mounted) return;
      setState(() {
        _gemKeys = pool.keys;
        _gemModels =
            pool.models.isEmpty ? ['gemini-flash-latest'] : pool.models;
        _geminiReady = pool.keys.isNotEmpty;
      });
    } catch (_) {}
  }

  Future<void> _init() async {
    CloudinaryCredentials creds = const CloudinaryCredentials(
        cloudName: '', apiKey: '', apiSecret: '');
    int exportIndex = 0;
    int gridCols = 3;
    try {
      creds = await CredentialStore.load();
      exportIndex = await AppPrefs.lastExport();
      gridCols = await AppPrefs.gridCols();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _creds = creds;
      _exportIndex =
          exportIndex.clamp(0, ExportPresets.all.length - 1);
      _gridCols = gridCols.clamp(2, 6);
      _ready = true;
    });
  }

  Future<void> _setGridCols(int v) async {
    final cols = v.clamp(2, 6);
    setState(() => _gridCols = cols);
    try {
      await AppPrefs.setGridCols(cols);
    } catch (_) {}
  }

  /// Delivery URL honoring the chosen export preset (e.g. 1620x2880 JPG).
  String _displayUrl(String url) =>
      ExportPresets.displayUrl(url, _exportIndex);

  String _exportExt(GenerationResult r) {
    if (ExportPresets.all[_exportIndex].isJpg) return 'jpg';
    if (r.format == 'jpeg') return 'jpg';
    return r.format.isEmpty ? 'png' : r.format;
  }

  String _short(String p, [int n = 44]) =>
      p.length > n ? '${p.substring(0, n)}...' : p;

  int get _promptCount =>
      _promptCtrls.where((c) => c.text.trim().isNotEmpty).length;

  int get _perPrompt => SetTypes.variants[_setType]!.length;

  /// Mix-set helpers.
  int get _mixTotal => _mix24 + _mixBattery + _mixDual + _mixSingle;
  int get _mixImages =>
      _mix24 * SetTypes.variants[SetType.h24]!.length +
      _mixBattery * SetTypes.variants[SetType.battery]!.length +
      _mixDual * SetTypes.variants[SetType.dual]!.length +
      _mixSingle * SetTypes.variants[SetType.single]!.length;

  /// Spreads the current prompt count across the four set types as evenly
  /// as possible (remainder goes to 24-Hour, Battery, Dual in that order).
  void _autoDistribute() {
    final n = _promptCount;
    if (n == 0 || _running) return;
    final base = n ~/ 4;
    final rem = n % 4;
    setState(() {
      _mix24 = base + (rem > 0 ? 1 : 0);
      _mixBattery = base + (rem > 1 ? 1 : 0);
      _mixDual = base + (rem > 2 ? 1 : 0);
      _mixSingle = base;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (!mounted) return;
    try {
      final creds = await CredentialStore.load();
      setState(() => _creds = creds);
    } catch (_) {}
    await _loadGemini();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------ jobs
  Future<void> _start() async {
    final prompts = _promptCtrls
        .map((c) => c.text.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (prompts.isEmpty || _running) return;
    if (_setType == SetType.mix && _mixTotal != prompts.length) {
      _snack('Mix counts must add up to the number of prompts.');
      return;
    }
    if (!_creds.isComplete) {
      _snack('Add your Cloudinary credentials first.');
      await _openSettings();
      return;
    }
    // For a mix set each prompt gets its own concrete set type, assigned in
    // order: 24-Hour first, then Battery, Dual, Single.
    final List<SetType> promptTypes = _setType == SetType.mix
        ? [
            ...List.filled(_mix24, SetType.h24),
            ...List.filled(_mixBattery, SetType.battery),
            ...List.filled(_mixDual, SetType.dual),
            ...List.filled(_mixSingle, SetType.single),
          ]
        : List.filled(prompts.length, _setType);
    // AI Set Director: Gemini plans each set (arc, anchor, palette,
    // per-variant directions) before any image is generated. A failed
    // plan falls back to the static story arcs for that set.
    final plans = <int, SetDirection>{};
    if (_director) {
      if (!_geminiReady) {
        _snack('Add Gemini API keys in Settings to use the AI Set Director.');
        await _openSettings();
        if (!_geminiReady || !mounted) return;
      }
      setState(() {
        _running = true;
        _cancelRequested = false;
        _done = 0;
        _total = prompts.length;
        _current = 'AI directing sets...';
      });
      for (var pi = 0; pi < prompts.length; pi++) {
        if (_cancelRequested) break;
        if (mounted) {
          setState(() {
            _current = 'AI directing set ${pi + 1}/${prompts.length}...';
            _done = pi;
          });
        }
        try {
          final t = promptTypes[pi];
          plans[pi] = await GeminiApi.directSet(
            type: _metaTypeLabel(t),
            variantLabels: [
              for (final v in SetTypes.variants[t]!) v.label
            ],
            prompt: prompts[pi],
            keys: _gemKeys,
            models: _gemModels,
          );
        } catch (_) {
          if (mounted) {
            _snack(
                'AI director failed for set ${pi + 1}; using static arcs.');
          }
        }
        if (mounted) setState(() => _done = pi + 1);
      }
      if (_cancelRequested) {
        if (mounted) {
          setState(() {
            _running = false;
            _current = '';
          });
        }
        return;
      }
    }
    final jobs = <BatchJob>[];
    var idx = 0;
    for (var pi = 0; pi < prompts.length; pi++) {
      final variants =
          _variantsFor(promptTypes[pi], prompts[pi], plans[pi]);
      // Multi-variant sets get a hidden neutral anchor: it is generated
      // first and used only as the chaining reference, never delivered.
      if (variants.length > 1) {
        jobs.add(BatchJob(
          index: idx,
          promptIndex: pi,
          prompt: prompts[pi],
          variantLabel: 'Anchor',
          variantSuffix: '',
          isAnchor: true,
          anchorIndex: idx,
          hidden: true,
        ));
        idx++;
      }
      final setAnchorIndex = variants.length > 1 ? idx - 1 : idx;
      for (var vi = 0; vi < variants.length; vi++) {
        final v = variants[vi];
        jobs.add(BatchJob(
          index: idx++,
          promptIndex: pi,
          prompt: prompts[pi],
          variantLabel: v.label,
          variantSuffix: v.suffix,
          isAnchor: variants.length == 1,
          anchorIndex: setAnchorIndex,
          hidden: false,
        ));
      }
    }
    setState(() {
      _jobs = jobs;
      _states = {for (final j in jobs) j.index: _ItemState(job: j)};
      _promptTypes = {
        for (var pi = 0; pi < prompts.length; pi++) pi: promptTypes[pi]
      };
      _plans = plans;
      _meta.clear();
      _running = true;
      _cancelRequested = false;
      _done = 0;
      _total = jobs.length;
      _current = 'Starting...';
    });
    await _runJobs(jobs);
    if (mounted) {
      setState(() {
        _running = false;
        _current = '';
      });
      final failed =
          _states.values.where((s) => s.error != null && s.result == null);
      _snack(failed.isEmpty
          ? 'All ${_states.length} images generated.'
          : '${_states.length - failed.length} done, ${failed.length} failed. You can retry the failed ones.');
      if (_states.values
          .any((s) => s.result != null && !s.job.hidden)) {
        _ensureFallbackMetadata();
        if (_geminiReady) {
          await _writeAllMetadata();
        }
      }
    }
  }

  Future<void> _retryFailed() async {
    if (_running) return;
    final failed = _states.values
        .where((s) => s.error != null && s.result == null)
        .map((s) => s.job)
        .toList();
    if (failed.isEmpty) return;
    setState(() {
      _running = true;
      _cancelRequested = false;
      for (final j in failed) {
        _states[j.index] = _ItemState(job: j);
      }
      _done = _total - failed.length;
      _current = 'Retrying failed...';
    });
    await _runJobs(failed);
    if (mounted) {
      setState(() {
        _running = false;
        _current = '';
      });
    }
  }

  void _cancel() => setState(() => _cancelRequested = true);

  /// Runs a subset of jobs (single image or whole set regenerate) while a
  /// previous run's results stay on screen.
  Future<void> _runPartial(List<BatchJob> jobs) async {
    if (_running || jobs.isEmpty) return;
    setState(() {
      _running = true;
      _cancelRequested = false;
      for (final j in jobs) {
        _states[j.index] = _ItemState(job: j);
      }
      _done = _states.values
          .where((s) => s.result != null || s.error != null)
          .length;
      _current = 'Regenerating...';
    });
    await _runJobs(jobs);
    if (mounted) {
      setState(() {
        _running = false;
        _current = '';
      });
    }
  }

  /// Regenerates one image. A chained variant reuses its set's anchor; if
  /// the anchor result is gone, the anchor is regenerated first.
  Future<void> _regenerateJob(BatchJob job) async {
    if (_running) return;
    final jobs = <BatchJob>[job];
    if (!job.isAnchor && _states[job.anchorIndex]?.result == null) {
      final anchors =
          _jobs.where((j) => j.index == job.anchorIndex).toList();
      if (anchors.isNotEmpty) jobs.insert(0, anchors.first);
    }
    _snack('Regenerating ${job.variantLabel}...');
    await _runPartial(jobs);
  }

  /// Regenerates a whole set: fresh anchor plus all its variants.
  Future<void> _regenerateSet(int promptIndex) async {
    if (_running) return;
    final jobs = _jobs
        .where((j) => j.promptIndex == promptIndex)
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (jobs.isEmpty) return;
    _snack('Regenerating set ${promptIndex + 1}...');
    await _runPartial(jobs);
  }

  /// Runs jobs with a small worker pool. Safe on Dart's single thread:
  /// the queue pop happens synchronously between awaits.
  ///
  /// Sets are consistency-chained: the first job of each prompt (the anchor)
  /// is generated with text-to-image, then the remaining variants are
  /// generated with image-to-image using the anchor as the reference image,
  /// so subject, objects and background stay identical across the set and
  /// only the variant's own change (lighting, charge stage, framing) applies.
  /// Variation strength: how boldly the light and atmosphere change
  /// across chained variants. The scene itself (subject, objects,
  /// background, layout, composition) always stays identical — only
  /// the lighting and mood transform. The transformation command comes
  /// first so the model actually relights instead of copying the anchor;
  /// the geometry lock follows as a constraint. Same wording as the web studio.
  static const _strengths = [
    (
      'Subtle',
      'Gently shift the lighting of the reference image toward the state described above — a soft change in light direction, color temperature and mood, clearly noticeable when compared side by side. Keep the exact same subject, objects, background, layout, composition, framing and art style: nothing may be added, removed or rearranged.',
    ),
    (
      'Clear',
      'This is a relighting edit, not a copy: transform the light and atmosphere of the reference image to the state described above — new light direction, color temperature, glow, mist and mood, immediately obvious at a glance. Keep the exact same subject, objects, background, layout, composition, framing and art style: nothing may be added, removed or rearranged.',
    ),
    (
      'Strong',
      'Dramatically relight the reference image to the state described above: bold new light direction and color temperature, intense glow and bloom, thick atmosphere, deep shadows — an unmistakable lighting transformation. Keep the exact same subject, objects, background, layout, composition and framing: absolutely nothing may be added, removed or rearranged.',
    ),
  ];
  int _strengthIndex = 1; // Clear, recommended

  String get _chainNote {
    final s = _strengths[_strengthIndex];
    return ', ${s.$2}';
  }

  static const _displays = ['Any display', 'AMOLED', 'IPS'];
  static const _colorBoosts = ['Off', 'Subtle', 'Vivid', 'Neon'];

  /// Style tail appended to every prompt: display tuning + color boost.
  String get _styleSuffix {
    final sb = StringBuffer();
    switch (_displayIndex) {
      case 1:
        sb.write(
            ', deep true blacks, high contrast, vivid colors, optimized for AMOLED displays');
      case 2:
        sb.write(
            ', balanced brightness, natural color reproduction, optimized for IPS displays');
    }
    switch (_colorBoostIndex) {
      case 1:
        sb.write(', subtly enhanced color richness');
      case 2:
        sb.write(', vivid rich colors with enhanced saturation');
      case 3:
        sb.write(', bold electrifying colors, striking chromatic intensity');
    }
    return sb.toString();
  }

  /// Full prompt for a job. Hidden anchors get the neutral base prompt
  /// (plus the director's anchor direction when present); variants get
  /// their own suffix plus the chaining note.
  String _jobPrompt(BatchJob job) {
    final plan = _plans[job.promptIndex];
    if (job.isAnchor) {
      final base =
          job.hidden ? job.prompt : '${job.prompt}${job.variantSuffix}';
      final dir = plan != null && plan.anchorDirection.isNotEmpty
          ? ', ${plan.anchorDirection}'
          : '';
      return '$base$_styleSuffix$dir${SetTypes.noTextGuard}$_proFinish';
    }
    // Palette lock keeps dual/single sets color-coherent. It is skipped
    // for 24-hour and battery sets: those are defined by light and color
    // temperature changing, so locking the palette would kill the variants.
    final type = _promptTypes[job.promptIndex];
    final temporal = type == SetType.h24 || type == SetType.battery;
    final palette = temporal
        ? ''
        : (plan != null && plan.palette.isNotEmpty
            ? ', maintain the exact ${plan.palette.join(' and ')} color palette of the reference image'
            : _paletteLock(job.prompt));
    return '${job.prompt}${job.variantSuffix}$_chainNote$_styleSuffix$palette$_proFinish';
  }

  /// Professional wallpaper finish applied to every set image.
  static const _proFinish =
      ', one strong focal point, clean uncluttered composition, professional wallpaper finish';

  /// Locks the prompt's own color words across the set so every variant
  /// keeps the identical palette (eye-catching packs stay color-coherent).
  static const _colorWords = [
    'cyan', 'magenta', 'pink', 'blue', 'purple', 'violet', 'neon',
    'orange', 'gold', 'golden', 'red', 'green', 'teal', 'turquoise',
    'amber', 'rose', 'yellow', 'indigo',
  ];

  static String _paletteLock(String prompt) {
    final lower = prompt.toLowerCase();
    final found =
        _colorWords.where(lower.contains).take(3).toList();
    if (found.isEmpty) return '';
    return ', maintain the exact ${found.join(' and ')} color palette of the reference image';
  }

  /// Resolves the effective story arc: manual pick, or smart keyword pick.
  static SetArc _effectiveArc(
      List<SetArc> arcs, int index, String autoId) {
    if (index <= 0) {
      return arcs.firstWhere((a) => a.id == autoId,
          orElse: () => arcs.first);
    }
    return arcs[index - 1];
  }

  /// Variant list for a set type and prompt: the AI director's plan
  /// wins when present, otherwise story-arc stages (24h/battery), otherwise
  /// the static variants. Labels never change.
  List<SetVariant> _variantsFor(SetType t, String prompt,
      [SetDirection? plan]) {
    final base = SetTypes.variants[t]!;
    if (plan != null && plan.stages.length == base.length) {
      return [
        for (var i = 0; i < base.length; i++)
          SetVariant(base[i].label,
              ', ${plan.stages[i].direction}${SetTypes.noTextGuard}'),
      ];
    }
    SetArc? arc;
    if (t == SetType.h24) {
      arc = _effectiveArc(
          SetArcs.h24, _h24ArcIndex, SetArcs.suggestH24(prompt));
    } else if (t == SetType.battery) {
      arc = _effectiveArc(
          SetArcs.battery, _batteryArcIndex, SetArcs.suggestBattery(prompt));
    }
    if (arc == null) return base;
    return [
      for (var i = 0; i < base.length; i++)
        SetVariant(
            base[i].label, '${arc.stages[i]}${SetTypes.noTextGuard}'),
    ];
  }

  Future<void> _runJobs(List<BatchJob> jobs) async {
    final api = CloudinaryApi(_creds);
    final seedBase = int.tryParse(_seedCtrl.text.trim());
    // No seed entered: use a fresh random seed per job. Cloudinary returns
    // the same cached image for an identical seedless request, which made
    // "regenerate" pointless. An explicit seed still reproduces exactly.
    final rng = Random();
    int freshSeed() => rng.nextInt(1 << 31);
    final queue = Queue<BatchJob>.from(jobs);
    // Anchor results known so far: from this run, or from a previous run
    // when retrying failed jobs.
    final anchorUrls = <int, String>{
      for (final s in _states.values)
        if (s.job.isAnchor && s.result != null) s.job.index: s.result!.imageUrl,
    };
    final anchorFailed = <int>{
      for (final s in _states.values)
        if (s.job.isAnchor && s.error != null && s.result == null) s.job.index,
    };
    var doneCount = _done;

    Future<void> worker() async {
      while (true) {
        if (_cancelRequested) return;
        if (queue.isEmpty) return;
        final job = queue.removeFirst();

        // A chained variant must wait for its set's anchor image.
        if (!job.isAnchor &&
            !anchorFailed.contains(job.anchorIndex) &&
            !anchorUrls.containsKey(job.anchorIndex)) {
          queue.add(job);
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }

        if (mounted) {
          setState(() {
            _current = '${_short(job.prompt)} - ${job.variantLabel}';
            _states[job.index] = _ItemState(job: job, running: true);
          });
        }
        try {
          if (job.isAnchor) {
            final r = await api.textToImage(
              prompt: _jobPrompt(job),
              modelId: _model,
              aspectRatio: _ratio,
              resolution: _resolution,
              format: _format,
              seed: seedBase == null ? freshSeed() : seedBase + job.index,
            );
            anchorUrls[job.index] = r.imageUrl;
            if (mounted) {
              setState(() {
                _states[job.index] =
                    _states[job.index]!.copyWith(result: r, running: false);
              });
            }
          } else if (anchorFailed.contains(job.anchorIndex)) {
            throw 'Anchor image failed, so this variant was skipped.';
          } else {
            final r = await api.imageToImage(
              prompt: _jobPrompt(job),
              modelId: null, // auto: always resolves to an edit-capable model
              referenceUrls: [anchorUrls[job.anchorIndex]!],
              aspectRatio: _ratio,
              resolution: _resolution,
              format: _format,
              seed: seedBase == null ? freshSeed() : seedBase + job.index,
            );
            if (mounted) {
              setState(() {
                _states[job.index] =
                    _states[job.index]!.copyWith(result: r, running: false);
              });
            }
          }
        } catch (e) {
          if (job.isAnchor) anchorFailed.add(job.index);
          if (mounted) {
            setState(() {
              _states[job.index] =
                  _states[job.index]!.copyWith(error: e, running: false);
            });
          }
        }
        doneCount++;
        if (mounted) {
          setState(() {
            _done = doneCount;
            _current = '';
          });
        }
      }
    }

    await Future.wait([for (var i = 0; i < _concurrency; i++) worker()]);
  }

  // ------------------------------------------------------------ save
  Future<Directory> _saveDir() async {
    try {
      final d = await getDownloadsDirectory();
      if (d != null) return d;
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  Future<void> _saveAll() async {
    final items = _states.values
        .where((s) => s.result != null && !s.job.hidden)
        .toList();
    if (items.isEmpty || _savingAll) return;
    setState(() => _savingAll = true);
    var ok = 0;
    var fail = 0;
    try {
      final dir = await _saveDir();
      for (final it in items) {
        try {
          final r = it.result!;
          final resp = await http
              .get(Uri.parse(_displayUrl(r.imageUrl)))
              .timeout(const Duration(seconds: 90));
          if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
          final ext = _exportExt(r);
          final file = File(
              '${dir.path}${Platform.pathSeparator}set${it.job.promptIndex + 1}-${_slug(it.job.variantLabel)}-$ok.$ext');
          await file.writeAsBytes(resp.bodyBytes);
          ok++;
        } catch (_) {
          fail++;
        }
      }
    } catch (e) {
      _snack('Save failed: $e');
      if (mounted) setState(() => _savingAll = false);
      return;
    }
    if (mounted) setState(() => _savingAll = false);
    _snack('Saved $ok image${ok == 1 ? '' : 's'}'
        '${fail > 0 ? ', $fail failed' : ''}.');
  }

  /// ZIP path for one finished item, e.g. set-01/morning.jpg.
  String _zipPathFor(_ItemState it, String ext) {
    final setFolder =
        'set-${(it.job.promptIndex + 1).toString().padLeft(2, '0')}';
    return '$setFolder/${_slug(it.job.variantLabel)}.$ext';
  }

  /// Prompt indices that have at least one finished, visible image.
  List<int> _resultPromptIndices() {
    final set = <int>{};
    for (final s in _states.values) {
      if (s.result != null && !s.job.hidden) set.add(s.job.promptIndex);
    }
    final list = set.toList()..sort();
    return list;
  }

  String _promptFor(int pi) =>
      _jobs.firstWhere((j) => j.promptIndex == pi).prompt;

  String _conceptFor(String prompt) {
    final clean = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length <= 40 ? clean : clean.substring(0, 40);
  }

  String _metaTypeLabel(SetType t) => switch (t) {
        SetType.h24 => '24-HOUR',
        SetType.dual => 'DUAL',
        SetType.battery => 'BATTERY',
        _ => 'SINGLE',
      };

  /// ZIP path of the first finished image of a set, used as the
  /// metadata.json `file` value.
  String _metaFileFor(int pi) {
    final items = _states.values
        .where((s) =>
            s.job.promptIndex == pi && s.result != null && !s.job.hidden)
        .toList()
      ..sort((a, b) => a.job.index.compareTo(b.job.index));
    if (items.isEmpty) {
      return 'set-${(pi + 1).toString().padLeft(2, '0')}/image.jpg';
    }
    final it = items.first;
    return _zipPathFor(it, _exportExt(it.result!));
  }

  /// Fills every finished set with prompt-derived metadata so the ZIP
  /// always has a metadata.json, even without Gemini keys.
  void _ensureFallbackMetadata() {
    var changed = false;
    for (final pi in _resultPromptIndices()) {
      if (_meta.containsKey(pi)) continue;
      final prompt = _promptFor(pi);
      _meta[pi] = _SetMeta(
        GeminiApi.metadataFromPrompt(
          file: _metaFileFor(pi),
          concept: _conceptFor(prompt),
          prompt: prompt,
        ),
        'prompt',
        -1,
      );
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  /// Writes AI metadata for every finished set, sequentially with
  /// progress, rotating through the Gemini key/model pool.
  Future<void> _writeAllMetadata() async {
    final indices = _resultPromptIndices();
    if (indices.isEmpty || _writingMeta) return;
    if (!_geminiReady) {
      _snack('Add Gemini API keys in Settings first.');
      await _openSettings();
      return;
    }
    setState(() => _writingMeta = true);
    var ok = 0;
    for (var i = 0; i < indices.length; i++) {
      final pi = indices[i];
      if (!mounted) break;
      setState(
          () => _metaStatus = 'Writing metadata ${i + 1}/${indices.length}...');
      final prompt = _promptFor(pi);
      try {
        final gen = await GeminiApi.generate(
          type: _metaTypeLabel(_promptTypes[pi] ?? _setType),
          concept: _conceptFor(prompt),
          prompt: prompt,
          file: _metaFileFor(pi),
          keys: _gemKeys,
          models: _gemModels,
        );
        if (!mounted) break;
        setState(
            () => _meta[pi] = _SetMeta(gen.metadata, gen.model, gen.keyIndex));
        ok++;
      } catch (e) {
        // The prompt-derived fallback stays in place.
        if (mounted) _snack('Metadata failed for set ${pi + 1}.');
      }
    }
    if (mounted) {
      setState(() {
        _writingMeta = false;
        _metaStatus = '';
      });
      _snack('AI metadata written for $ok of ${indices.length} sets.');
    }
  }

  /// Regenerates the AI metadata of one set.
  Future<void> _rewriteMetadata(int pi) async {
    if (_writingMeta || _running) return;
    if (!_geminiReady) {
      _snack('Add Gemini API keys in Settings first.');
      await _openSettings();
      if (!_geminiReady) return;
    }
    setState(() {
      _writingMeta = true;
      _metaStatus = 'Rewriting metadata for set ${pi + 1}...';
    });
    final prompt = _promptFor(pi);
    try {
      final gen = await GeminiApi.generate(
        type: _metaTypeLabel(_promptTypes[pi] ?? _setType),
        concept: _conceptFor(prompt),
        prompt: prompt,
        file: _metaFileFor(pi),
        keys: _gemKeys,
        models: _gemModels,
      );
      if (mounted) {
        setState(
            () => _meta[pi] = _SetMeta(gen.metadata, gen.model, gen.keyIndex));
      }
      _snack('Metadata rewritten for set ${pi + 1}.');
    } catch (e) {
      _snack('Metadata rewrite failed: $e');
    }
    if (mounted) {
      setState(() {
        _writingMeta = false;
        _metaStatus = '';
      });
    }
  }

  /// Downloads every finished image and packs them into a single .zip
  /// (set-01/morning.jpg, set-01/afternoon.jpg, ...), plus a
  /// metadata.json listing entry at the archive root, then opens the
  /// share sheet so the archive can be moved anywhere.
  Future<void> _saveZip() async {
    final items = _states.values
        .where((s) => s.result != null && !s.job.hidden)
        .toList();
    if (items.isEmpty || _savingZip) return;
    setState(() => _savingZip = true);
    _snack('Preparing ZIP...');
    try {
      final entries = <ZipEntryData>[];
      final firstOfSet = <int, _ItemState>{};
      var skipped = 0;
      for (final it in items) {
        try {
          final r = it.result!;
          final resp = await http
              .get(Uri.parse(_displayUrl(r.imageUrl)))
              .timeout(const Duration(seconds: 120));
          if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
          final path = _zipPathFor(it, _exportExt(r));
          entries.add(ZipEntryData(path, resp.bodyBytes));
          firstOfSet.putIfAbsent(it.job.promptIndex, () => it);
        } catch (_) {
          skipped++;
        }
      }
      if (entries.isEmpty) throw Exception('no images could be downloaded');
      // metadata.json at the archive root: one entry per set, with the
      // actual file path used inside this ZIP.
      final metas = <SetMetadata>[];
      final order = firstOfSet.keys.toList()..sort();
      for (final pi in order) {
        final it = firstOfSet[pi]!;
        final path = _zipPathFor(it, _exportExt(it.result!));
        final base = _meta[pi]?.meta;
        metas.add(base == null
            ? GeminiApi.metadataFromPrompt(
                file: path,
                concept: _conceptFor(it.job.prompt),
                prompt: it.job.prompt,
              )
            : SetMetadata(
                file: path,
                title: base.title,
                tags: base.tags,
                category: base.category,
                description: base.description,
              ));
      }
      entries.add(ZipEntryData(
          'metadata.json', utf8.encode(GeminiApi.metadataJson(metas))));
      final zipFile = await buildZipFile(
          'ai-studio-sets-${DateTime.now().millisecondsSinceEpoch}.zip',
          entries);
      if (!mounted) return;
      setState(() => _savingZip = false);
      final imageCount = entries.length - 1; // minus metadata.json
      final skippedNote = skipped > 0 ? ', $skipped skipped' : '';
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Desktop: Save As dialog instead of the mobile share sheet.
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ZIP archive',
          fileName: zipFile.uri.pathSegments.last,
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        if (!mounted) return;
        if (savePath == null) {
          _snack('Save cancelled. The ZIP is at ${zipFile.path}');
          return;
        }
        var dest = savePath;
        if (!dest.toLowerCase().endsWith('.zip')) dest = '$dest.zip';
        if (dest != zipFile.path) {
          await File(dest).writeAsBytes(await zipFile.readAsBytes());
        }
        _snack('ZIP saved ($imageCount images + metadata.json$skippedNote).');
      } else {
        _snack('ZIP ready ($imageCount images + metadata.json$skippedNote).'
            ' Opening share...');
        try {
          await Share.shareXFiles([XFile(zipFile.path)],
              text: 'AI Image Studio sets');
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) setState(() => _savingZip = false);
      _snack('ZIP failed: $e');
    }
  }

  // ------------------------------------------------------------ prompts UI
  Future<void> _bulkAdd() async {
    final ctrl = TextEditingController();
    final add = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Paste multiple prompts'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            minLines: 5,
            decoration: const InputDecoration(
              hintText: 'One prompt per line...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    final lines = ctrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    ctrl.dispose();
    if (add != true || lines.isEmpty) return;
    setState(() {
      for (final line in lines) {
        TextEditingController? empty;
        for (final c in _promptCtrls) {
          if (c.text.trim().isEmpty) {
            empty = c;
            break;
          }
        }
        if (empty != null) {
          empty.text = line;
        } else {
          _promptCtrls.add(TextEditingController(text: line));
        }
      }
    });
  }

  // ------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset('assets/icon/app_icon.png',
                  width: 30, height: 30),
            ),
            const SizedBox(width: 10),
            const Text('Batch Sets',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: screenScrollPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _setTypeCard(),
                  if (_setType == SetType.mix) ...[
                    const SizedBox(height: 12),
                    _mixCard(),
                  ],
                  const SizedBox(height: 12),
                  _promptsCard(),
                  const SizedBox(height: 12),
                  _optionsCard(),
                  const SizedBox(height: 16),
                  _summaryAndGo(),
                  const SizedBox(height: 16),
                  if (_total > 0) _progressCard(),
                  if (_states.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _resultsHeader(),
                    const SizedBox(height: 8),
                    _resultsView(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionCard(
      {required String title, required IconData icon, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _setTypeCard() {
    return _sectionCard(
      title: 'Set type',
      icon: Icons.layers_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in SetType.values)
                ChoiceChip(
                  avatar: Icon(_setIcon(t), size: 18),
                  label: Text(t == SetType.mix
                      ? 'Mix'
                      : '${SetTypes.label(t)} x${SetTypes.variants[t]!.length}'),
                  selected: _setType == t,
                  onSelected: _running
                      ? null
                      : (_) {
                          setState(() => _setType = t);
                          if (t == SetType.mix) _autoDistribute();
                        },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(SetTypes.description(_setType),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  IconData _setIcon(SetType t) => switch (t) {
        SetType.single => Icons.image_outlined,
        SetType.h24 => Icons.schedule_outlined,
        SetType.dual => Icons.view_column_outlined,
        SetType.battery => Icons.battery_charging_full_outlined,
        SetType.mix => Icons.shuffle_outlined,
      };

  /// Distribution editor for a mix set: per-type counts plus auto-distribute.
  Widget _arcDropdown({
    required String label,
    required IconData icon,
    required int value,
    required List<SetArc> arcs,
    required ValueChanged<int?> onChanged,
  }) {
    final hint = value <= 0
        ? 'Smart: auto-picks per prompt from keywords.'
        : arcs[value - 1].hint;
    return DropdownButtonFormField<int>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        prefixIcon: Icon(icon),
      ),
      items: [
        const DropdownMenuItem(
            value: 0, child: Text('Auto (smart)')),
        for (var i = 0; i < arcs.length; i++)
          DropdownMenuItem(
              value: i + 1, child: Text(arcs[i].label)),
      ],
      onChanged: _running ? null : onChanged,
    );
  }

  Widget _mixCard() {
    final scheme = Theme.of(context).colorScheme;
    final n = _promptCount;
    final total = _mixTotal;
    final ok = n > 0 && total == n;
    final statusColor = ok ? Colors.green : scheme.error;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.shuffle_outlined,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Mix distribution',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed:
                      (_running || n == 0) ? null : _autoDistribute,
                  icon:
                      const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Auto distribute'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'How many prompts become each set type. Prompts are '
              'assigned in order: 24-Hour first, then Battery, Dual, Single.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          _mixRow('24-Hour sets', Icons.schedule_outlined, _mix24,
              (v) => setState(() => _mix24 = v), n),
          _mixRow('Battery sets', Icons.battery_charging_full_outlined,
              _mixBattery, (v) => setState(() => _mixBattery = v), n),
          _mixRow('Dual sets', Icons.view_column_outlined, _mixDual,
              (v) => setState(() => _mixDual = v), n),
          _mixRow('Single images', Icons.image_outlined, _mixSingle,
              (v) => setState(() => _mixSingle = v), n),
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                    ok
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    size: 18,
                    color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ok
                        ? 'Total $total / $n prompts - ready to generate.'
                        : 'Total $total / $n prompts - counts must add up to the number of prompts.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _mixRow(String label, IconData icon, int value,
      ValueChanged<int> onChanged, int max) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          IconButton(
            tooltip: 'Decrease',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed:
                (_running || value <= 0) ? null : () => onChanged(value - 1),
          ),
          SizedBox(
            width: 34,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          IconButton(
            tooltip: 'Increase',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: (_running || value >= max)
                ? null
                : () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }

  Widget _promptsCard() {
    return _sectionCard(
      title: 'Prompts',
      icon: Icons.list_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _promptCtrls.length; i++) _promptRow(i),
          Row(
            children: [
              TextButton.icon(
                onPressed: _running
                    ? null
                    : () => setState(
                        () => _promptCtrls.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Add prompt'),
              ),
              TextButton.icon(
                onPressed: _running ? null : _bulkAdd,
                icon: const Icon(Icons.playlist_add_outlined),
                label: const Text('Paste multiple'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _promptRow(int i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: CircleAvatar(
              radius: 14,
              child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _promptCtrls[i],
              maxLines: 3,
              minLines: 1,
              enabled: !_running,
              decoration:
                  InputDecoration(hintText: 'Prompt ${i + 1} - describe the set concept...'),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _promptCtrls.length <= 1 || _running
                ? null
                : () => setState(() {
                      _promptCtrls[i].dispose();
                      _promptCtrls.removeAt(i);
                    }),
          ),
        ],
      ),
    );
  }

  Widget _optionsCard() {
    final scheme = Theme.of(context).colorScheme;
    return _sectionCard(
      title: 'Generation options',
      icon: Icons.tune_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _model,
            decoration: const InputDecoration(
              labelText: 'Model',
              prefixIcon: Icon(Icons.smart_toy_outlined),
            ),
            items: [
              for (final m in AiModels.textToImage)
                DropdownMenuItem(value: m, child: Text(m))
            ],
            onChanged:
                _running ? null : (v) => setState(() => _model = v ?? _model),
          ),
          const SizedBox(height: 14),
          Text('Aspect ratio',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in AspectRatios.all)
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ratioBox(r, scheme),
                      const SizedBox(width: 8),
                      Text(r),
                    ],
                  ),
                  selected: r == _ratio,
                  onSelected: _running
                      ? null
                      : (_) => setState(() => _ratio = r),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _resolution,
                  decoration:
                      const InputDecoration(labelText: 'Resolution'),
                  items: [
                    for (final r in Resolutions.all)
                      DropdownMenuItem(value: r, child: Text(r))
                  ],
                  onChanged: _running
                      ? null
                      : (v) => setState(() => _resolution = v ?? '1K'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _format,
                  decoration: const InputDecoration(labelText: 'Format'),
                  items: [
                    for (final f in OutputFormats.all)
                      DropdownMenuItem(
                          value: f, child: Text(f.toUpperCase()))
                  ],
                  onChanged: _running
                      ? null
                      : (v) => setState(() => _format = v ?? 'png'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            value: _exportIndex,
            decoration: const InputDecoration(
              labelText: 'Export',
              prefixIcon: Icon(Icons.photo_size_select_large_outlined),
            ),
            items: [
              for (var i = 0; i < ExportPresets.all.length; i++)
                DropdownMenuItem(
                    value: i, child: Text(ExportPresets.all[i].label))
            ],
            onChanged: _running
                ? null
                : (v) async {
                    if (v == null) return;
                    setState(() => _exportIndex = v);
                    try {
                      await AppPrefs.setExport(v);
                    } catch (_) {}
                  },
          ),
          const SizedBox(height: 14),
          Text('Display target',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
              'Tunes brightness and contrast for the screen the wallpaper will live on.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _displays.length; i++)
                ChoiceChip(
                  label: Text(_displays[i]),
                  selected: _displayIndex == i,
                  onSelected: _running
                      ? null
                      : (_) => setState(() => _displayIndex = i),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Color boost',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _colorBoosts.length; i++)
                ChoiceChip(
                  label: Text(_colorBoosts[i]),
                  selected: _colorBoostIndex == i,
                  onSelected: _running
                      ? null
                      : (_) => setState(() => _colorBoostIndex = i),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Variation strength',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'How boldly the light and mood change across variants. The scene itself always stays identical — use Strong when frames look too similar.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                    color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _strengths.length; i++)
                ChoiceChip(
                  label: Text(_strengths[i].$1),
                  selected: _strengthIndex == i,
                  onSelected: _running
                      ? null
                      : (_) =>
                          setState(() => _strengthIndex = i),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary:
                const Icon(Icons.psychology_outlined),
            title: const Text('AI Set Director'),
            subtitle: Text(_geminiReady
                ? 'Gemini plans each set\u2019s arc, anchor, palette and stage directions before generating. One AI call per set.'
                : 'Add Gemini API keys in Settings to enable.'),
            value: _director,
            onChanged: _running
                ? null
                : (v) => setState(() => _director = v),
          ),
          const SizedBox(height: 14),
          if (_setType == SetType.h24 || _setType == SetType.mix)
            _arcDropdown(
              label: '24-Hour story arc',
              icon: Icons.schedule_outlined,
              value: _h24ArcIndex,
              arcs: SetArcs.h24,
              onChanged: (v) => setState(() => _h24ArcIndex = v ?? 0),
            ),
          if (_setType == SetType.battery || _setType == SetType.mix) ...[
            if (_setType == SetType.h24 || _setType == SetType.mix)
              const SizedBox(height: 14),
            _arcDropdown(
              label: 'Battery story arc',
              icon: Icons.battery_charging_full_outlined,
              value: _batteryArcIndex,
              arcs: SetArcs.battery,
              onChanged: (v) => setState(() => _batteryArcIndex = v ?? 0),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _seedCtrl,
            enabled: !_running,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Seed base (optional)',
              hintText: 'Each image uses base + index',
              prefixIcon: Icon(Icons.casino_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratioBox(String ratio, ColorScheme scheme) {
    final f = AspectRatios.factors(ratio);
    const h = 18.0;
    final w = (h * f[0] / f[1]).clamp(10.0, 34.0);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary, width: 1.6),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _summaryAndGo() {
    final n = _promptCount;
    final isMix = _setType == SetType.mix;
    final total = isMix ? _mixImages : n * _perPrompt;
    final canGo = !_running && n > 0 && (!isMix || _mixTotal == n);
    final summary = n == 0
        ? 'Add at least one prompt to begin.'
        : isMix
            ? 'Mix: $_mix24 x 24-Hour, $_mixBattery x Battery, '
                '$_mixDual x Dual, $_mixSingle x Single = $total images - 1 credit each'
            : '$n prompt${n == 1 ? '' : 's'} x $_perPrompt = $total image${total == 1 ? '' : 's'}  -  1 credit each';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          summary,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: canGo ? _start : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          icon: _running
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : const Icon(Icons.auto_awesome, size: 22),
          label: Text(_running ? 'Generating sets...' : 'Generate sets'),
        ),
      ],
    );
  }

  Widget _progressCard() {
    final scheme = Theme.of(context).colorScheme;
    final failed =
        _states.values.where((s) => s.error != null && s.result == null).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('$_done / $_total',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (failed > 0 && !_running)
                  TextButton.icon(
                    onPressed: _retryFailed,
                    icon: const Icon(Icons.refresh_outlined),
                    label: Text('Retry $failed failed'),
                  ),
                if (_running)
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.stop_outlined),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _total == 0 ? 0 : _done / _total,
              color: scheme.primary,
            ),
            if (_current.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_current,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultsHeader() {
    final done =
        _states.values.where((s) => s.result != null && !s.job.hidden).length;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.grid_view_outlined,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Results ($done)',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                _zoomStepper(),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _barAction(
                    onPressed: (done == 0 || _writingMeta || _running)
                        ? null
                        : _writeAllMetadata,
                    icon: _writingMeta
                        ? _miniSpinner()
                        : const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: _writingMeta ? 'Writing...' : 'AI metadata',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _barAction(
                    onPressed:
                        (done == 0 || _savingAll) ? null : _saveAll,
                    icon: _savingAll
                        ? _miniSpinner()
                        : const Icon(Icons.download_outlined, size: 18),
                    label: 'Save all',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _barAction(
                    onPressed:
                        (done == 0 || _savingZip) ? null : _saveZip,
                    icon: _savingZip
                        ? _miniSpinner()
                        : const Icon(Icons.folder_zip_outlined, size: 18),
                    label: 'ZIP',
                  ),
                ),
              ],
            ),
            if (_writingMeta && _metaStatus.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child:
                          CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_metaStatus,
                        style:
                            Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Uniform toolbar action button: fixed height, centered icon + label.
  Widget _barAction(
      {required VoidCallback? onPressed,
      required Widget icon,
      required String label}) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        textStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _miniSpinner() => const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2.5));

  /// Grid-density stepper as a single outlined pill control.
  Widget _zoomStepper() {
    final scheme = Theme.of(context).colorScheme;
    Widget step(IconData icon, String tip, VoidCallback? onTap) =>
        IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 18),
          onPressed: onTap,
        );
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          step(Icons.remove_outlined, 'Fewer columns (larger previews)',
              _gridCols > 2 ? () => _setGridCols(_gridCols - 1) : null),
          SizedBox(
            width: 24,
            child: Center(
              child: Text('$_gridCols',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          step(Icons.add_outlined, 'More columns (smaller previews)',
              _gridCols < 6 ? () => _setGridCols(_gridCols + 1) : null),
        ],
      ),
    );
  }

  Widget _resultsView() {
    final order = <int>[];
    final groups = <int, List<_ItemState>>{};
    for (final s in _states.values) {
      if (s.job.hidden) continue; // anchors are reference-only
      groups.putIfAbsent(s.job.promptIndex, () {
        order.add(s.job.promptIndex);
        return [];
      }).add(s);
    }
    return Column(
      children: [for (final pi in order) _promptGroupCard(pi, groups[pi]!)],
    );
  }

  Widget _promptGroupCard(int pi, List<_ItemState> items) {
    items.sort((a, b) => a.job.index.compareTo(b.job.index));
    final prompt = items.first.job.prompt;
    final done = items.where((s) => s.result != null).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Set ${pi + 1} - ${_short(prompt, 64)}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (_plans.containsKey(pi))
                  IconButton(
                    tooltip: 'View AI direction',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.psychology_outlined,
                        size: 18),
                    onPressed: () => _showPlan(pi),
                  ),
                IconButton(
                  tooltip: 'Regenerate set',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_outlined, size: 18),
                  onPressed:
                      _running ? null : () => _regenerateSet(pi),
                ),                Text('$done/${items.length}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (_meta.containsKey(pi)) ...[
              const SizedBox(height: 10),
              _metaCard(pi),
            ],
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridCols,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.62,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => _variantCell(items[i]),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows the AI director's plan for a set.
  Future<void> _showPlan(int pi) async {
    final plan = _plans[pi];
    if (plan == null) return;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget row(String label, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(body, style: textTheme.bodyMedium),
            ],
          ),
        );
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('AI direction \u2014 Set ${pi + 1}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (plan.arc.isNotEmpty) row('Arc', plan.arc),
                if (plan.anchorDirection.isNotEmpty)
                  row('Anchor (hidden reference)',
                      plan.anchorDirection),
                if (plan.palette.isNotEmpty) ...[
                  Text('Palette',
                      style: textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in plan.palette)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius:
                                BorderRadius.circular(999),
                          ),
                          child: Text(c,
                              style: textTheme.labelSmall?.copyWith(
                                  color: scheme.onPrimaryContainer)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                for (final s in plan.stages)
                  row(s.label, s.direction),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  /// Compact listing-metadata card under a set's header, with a
  /// per-set "rewrite with AI" action.
  Widget _metaCard(int pi) {
    final m = _meta[pi]!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(m.meta.title,
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(m.meta.category,
                    style: textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Rewrite metadata with AI',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                onPressed: (_writingMeta || _running)
                    ? null
                    : () => _rewriteMetadata(pi),
              ),
            ],
          ),
          Text(
            m.model == 'prompt'
                ? 'Derived from prompt'
                : '${m.model} · key #${m.keyIndex + 1}',
            style:
                textTheme.bodySmall?.copyWith(color: scheme.outline),
          ),
          if (m.meta.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(m.meta.description, style: textTheme.bodySmall),
          ],
          if (m.meta.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in m.meta.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('#$t', style: textTheme.labelSmall),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _variantCell(_ItemState s) {
    final scheme = Theme.of(context).colorScheme;
    final f = AspectRatios.factors(_ratio);
    final Widget body;
    if (s.result != null) {
      body = InkWell(
        onTap: () => _viewResult(s.result!),
        child: Image.network(
          _displayUrl(s.result!.imageUrl),
          fit: BoxFit.cover,
          loadingBuilder: (c, child, p) => p == null
              ? child
              : const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined),
        ),
      );
    } else if (s.error != null) {
      final msg = s.error is CloudinaryApiException
          ? (s.error as CloudinaryApiException).message
          : '$s.error';
      body = Tooltip(
        message: msg,
        child: Container(
          color: scheme.errorContainer.withOpacity(0.35),
          child: Icon(Icons.error_outline, color: scheme.error),
        ),
      );
    } else if (s.running) {
      body = Container(
        color: scheme.surfaceContainerHighest.withOpacity(0.4),
        child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else {
      body = Container(
        color: scheme.surfaceContainerHighest.withOpacity(0.25),
        child: Icon(Icons.hourglass_empty_outlined,
            color: scheme.outline),
      );
    }
    return Column(
      children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: f[0] / f[1],
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: body,
                ),
                if (s.result != null && !_running)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Tooltip(
                      message: 'Regenerate this image',
                      child: Material(
                        color: scheme.scrim.withOpacity(0.5),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _regenerateJob(s.job),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.refresh_outlined,
                                size: 15, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!s.job.isAnchor)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Tooltip(
                  message: 'Chained from the set anchor image',
                  child: Icon(Icons.link_outlined,
                      size: 12, color: scheme.outline),
                ),
              ),
            Flexible(
              child: Text(s.job.variantLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ],
    );
  }

  void _viewResult(GenerationResult r) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(_displayUrl(r.imageUrl),
                    fit: BoxFit.contain),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.prompt,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Text(
                        '${r.modelId.isEmpty ? 'auto' : r.modelId}  -  ${r.width}x${r.height}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            showDevicePreview(
                              context,
                              imageUrl: _displayUrl(r.imageUrl),
                              title: r.prompt,
                            );
                          },
                          icon: const Icon(
                              Icons.smartphone_outlined,
                              size: 18),
                          label: const Text('Device preview'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                                text: _displayUrl(r.imageUrl)));
                            Navigator.of(context).pop();
                          },
                          child: const Text('Copy URL'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _promptCtrls) {
      c.dispose();
    }
    _seedCtrl.dispose();
    super.dispose();
  }
}
