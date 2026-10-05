import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../cloudinary_api.dart';
import '../models.dart';
import '../secure_store.dart';
import '../zip_export.dart';
import 'settings_screen.dart';

/// One unit of work: a single prompt x a single set variant.
class BatchJob {
  final int index;
  final int promptIndex;
  final String prompt;
  final String variantLabel;
  final String variantSuffix;

  const BatchJob({
    required this.index,
    required this.promptIndex,
    required this.prompt,
    required this.variantLabel,
    required this.variantSuffix,
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
  }) =>
      _ItemState(
        job: job,
        result: result ?? this.result,
        error: error ?? this.error,
        running: running ?? this.running,
      );
}

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  SetType _setType = SetType.h24;
  final List<TextEditingController> _promptCtrls = [TextEditingController()];
  final _seedCtrl = TextEditingController();

  String _model = 'nano-banana-2';
  String _ratio = '9:16';
  String _resolution = '1K';
  String _format = 'png';
  int _exportIndex = 0;

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
  }

  Future<void> _init() async {
    CloudinaryCredentials creds = const CloudinaryCredentials(
        cloudName: '', apiKey: '', apiSecret: '');
    int exportIndex = 0;
    try {
      creds = await CredentialStore.load();
      exportIndex = await AppPrefs.lastExport();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _creds = creds;
      _exportIndex =
          exportIndex.clamp(0, ExportPresets.all.length - 1);
      _ready = true;
    });
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

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (!mounted) return;
    try {
      final creds = await CredentialStore.load();
      setState(() => _creds = creds);
    } catch (_) {}
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
    if (!_creds.isComplete) {
      _snack('Add your Cloudinary credentials first.');
      await _openSettings();
      return;
    }
    final variants = SetTypes.variants[_setType]!;
    final jobs = <BatchJob>[];
    var idx = 0;
    for (var pi = 0; pi < prompts.length; pi++) {
      for (final v in variants) {
        jobs.add(BatchJob(
          index: idx++,
          promptIndex: pi,
          prompt: prompts[pi],
          variantLabel: v.label,
          variantSuffix: v.suffix,
        ));
      }
    }
    setState(() {
      _jobs = jobs;
      _states = {for (final j in jobs) j.index: _ItemState(job: j)};
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

  /// Runs jobs with a small worker pool. Safe on Dart's single thread:
  /// the queue pop happens synchronously between awaits.
  Future<void> _runJobs(List<BatchJob> jobs) async {
    final api = CloudinaryApi(_creds);
    final seedBase = int.tryParse(_seedCtrl.text.trim());
    final queue = Queue<BatchJob>.from(jobs);
    var doneCount = _done;

    Future<void> worker() async {
      while (true) {
        if (_cancelRequested) return;
        if (queue.isEmpty) return;
        final job = queue.removeFirst();
        if (mounted) {
          setState(() {
            _current = '${_short(job.prompt)} - ${job.variantLabel}';
            _states[job.index] = _ItemState(job: job, running: true);
          });
        }
        try {
          final r = await api.textToImage(
            prompt: '${job.prompt}${job.variantSuffix}',
            modelId: _model,
            aspectRatio: _ratio,
            resolution: _resolution,
            format: _format,
            seed: seedBase == null ? null : seedBase + job.index,
          );
          if (mounted) {
            setState(() {
              _states[job.index] =
                  _states[job.index]!.copyWith(result: r, running: false);
            });
          }
        } catch (e) {
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
    final items = _states.values.where((s) => s.result != null).toList();
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

  /// Downloads every finished image and packs them into a single .zip
  /// (set-01/morning.jpg, set-01/afternoon.jpg, ...), then opens the
  /// share sheet so the archive can be moved anywhere.
  Future<void> _saveZip() async {
    final items = _states.values.where((s) => s.result != null).toList();
    if (items.isEmpty || _savingZip) return;
    setState(() => _savingZip = true);
    _snack('Preparing ZIP...');
    try {
      final entries = <ZipEntryData>[];
      var skipped = 0;
      for (final it in items) {
        try {
          final r = it.result!;
          final resp = await http
              .get(Uri.parse(_displayUrl(r.imageUrl)))
              .timeout(const Duration(seconds: 120));
          if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
          final ext = _exportExt(r);
          final setFolder =
              'set-${(it.job.promptIndex + 1).toString().padLeft(2, '0')}';
          entries.add(ZipEntryData(
              '$setFolder/${_slug(it.job.variantLabel)}.$ext',
              resp.bodyBytes));
        } catch (_) {
          skipped++;
        }
      }
      if (entries.isEmpty) throw Exception('no images could be downloaded');
      final zipFile = await buildZipFile(
          'ai-studio-sets-${DateTime.now().millisecondsSinceEpoch}.zip',
          entries);
      if (!mounted) return;
      setState(() => _savingZip = false);
      _snack('ZIP ready (${entries.length} images'
          '${skipped > 0 ? ', $skipped skipped' : ''}). Opening share...');
      try {
        await Share.shareXFiles([XFile(zipFile.path)],
            text: 'AI Image Studio sets');
      } catch (_) {}
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
        title: const Text('Batch Sets',
            style: TextStyle(fontWeight: FontWeight.w700)),
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _setTypeCard(),
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
                  label: Text(
                      '${SetTypes.label(t)} x${SetTypes.variants[t]!.length}'),
                  selected: _setType == t,
                  onSelected: _running
                      ? null
                      : (_) => setState(() => _setType = t),
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
      };

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
    final total = n * _perPrompt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          n == 0
              ? 'Add at least one prompt to begin.'
              : '$n prompt${n == 1 ? '' : 's'} x $_perPrompt = $total image${total == 1 ? '' : 's'}  -  1 credit each',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: (_running || n == 0) ? null : _start,
          icon: _running
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome),
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
        _states.values.where((s) => s.result != null).length;
    return Row(
      children: [
        const Icon(Icons.grid_view_outlined, size: 20),
        const SizedBox(width: 8),
        Text('Results ($done)',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const Spacer(),
        FilledButton.tonalIcon(
          onPressed: (done == 0 || _savingAll) ? null : _saveAll,
          icon: _savingAll
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined),
          label: const Text('Save all'),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: (done == 0 || _savingZip) ? null : _saveZip,
          icon: _savingZip
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.folder_zip_outlined),
          label: const Text('ZIP'),
        ),
      ],
    );
  }

  Widget _resultsView() {
    final order = <int>[];
    final groups = <int, List<_ItemState>>{};
    for (final s in _states.values) {
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
                Text('$done/${items.length}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: body,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(s.job.variantLabel,
            style: Theme.of(context).textTheme.bodySmall),
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
