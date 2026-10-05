import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloudinary_api.dart';
import '../app_theme.dart';
import '../models.dart';
import '../secure_store.dart';
import '../widgets/device_mockup.dart';
import 'batch_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {super.key, required this.mode, required this.onThemeChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HistoryItem {
  final String url;
  final String prompt;
  final String model;
  final String ratio;
  final int ts;

  _HistoryItem({
    required this.url,
    required this.prompt,
    required this.model,
    required this.ratio,
    required this.ts,
  });

  Map<String, dynamic> toJson() =>
      {'url': url, 'prompt': prompt, 'model': model, 'ratio': ratio, 'ts': ts};

  factory _HistoryItem.fromJson(Map<String, dynamic> j) => _HistoryItem(
        url: j['url'] as String,
        prompt: (j['prompt'] ?? '') as String,
        model: (j['model'] ?? '') as String,
        ratio: (j['ratio'] ?? '1:1') as String,
        ts: (j['ts'] as num?)?.toInt() ?? 0,
      );
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0; // 0 = text-to-image, 1 = image-to-image
  final _promptCtrl = TextEditingController();
  final _seedCtrl = TextEditingController();
  final List<TextEditingController> _refCtrls = [TextEditingController()];

  String _model = 'nano-banana-2';
  String _imgModel = 'auto'; // 'auto' or a '-edit' model id
  String _ratio = '1:1';
  String _resolution = '1K';
  String _format = 'png';
  int _exportIndex = 0;

  CloudinaryCredentials _creds = const CloudinaryCredentials(
      cloudName: '', apiKey: '', apiSecret: '');
  bool _ready = false;
  bool _loading = false;
  bool _saving = false;
  String _status = '';
  GenerationResult? _result;
  CloudinaryApiException? _error;
  List<_HistoryItem> _history = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    CloudinaryCredentials creds = const CloudinaryCredentials(
        cloudName: '', apiKey: '', apiSecret: '');
    try {
      creds = await CredentialStore.load();
    } catch (_) {}
    String ratio = '1:1', res = '1K', fmt = 'png';
    String? lastTxt, lastImg;
    List<String> hist = [];
    int exportIndex = 0;
    try {
      ratio = await AppPrefs.lastRatio();
      res = await AppPrefs.lastResolution();
      fmt = await AppPrefs.lastFormat();
      lastTxt = await AppPrefs.lastModel(false);
      lastImg = await AppPrefs.lastModel(true);
      hist = await AppPrefs.history();
      exportIndex = await AppPrefs.lastExport();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _creds = creds;
      _ratio = AspectRatios.all.contains(ratio) ? ratio : '1:1';
      _resolution = Resolutions.all.contains(res) ? res : '1K';
      _format = OutputFormats.all.contains(fmt) ? fmt : 'png';
      _exportIndex = exportIndex.clamp(0, ExportPresets.all.length - 1);
      if (lastTxt != null && AiModels.textToImage.contains(lastTxt)) {
        _model = lastTxt;
      }
      if (lastImg != null &&
          (lastImg == 'auto' || AiModels.imageToImage.contains(lastImg))) {
        _imgModel = lastImg;
      }
      _history = hist.map((s) {
        try {
          return _HistoryItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }).whereType<_HistoryItem>().toList();
      _ready = true;
    });
  }

  String _statusLabel(String s) => switch (s) {
        'pending' => 'Queued on Cloudinary...',
        'processing' => 'Generating your image...',
        _ => 'Working... ($s)',
      };

  /// Delivery URL honoring the chosen export preset (e.g. 1620x2880 JPG).
  String _displayUrl(String url) => ExportPresets.displayUrl(url, _exportIndex);

  String _exportExt(GenerationResult r) {
    if (ExportPresets.all[_exportIndex].isJpg) return 'jpg';
    if (r.format == 'jpeg') return 'jpg';
    return r.format.isEmpty ? 'png' : r.format;
  }

  Future<void> _generate() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty || _loading) return;
    if (!_creds.isComplete) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add your Cloudinary credentials first.')),
      );
      await _openSettings();
      return;
    }
    final refs =
        _refCtrls.map((c) => c.text.trim()).where((u) => u.isNotEmpty).toList();
    if (_tab == 1 && refs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one reference image URL.')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _status = 'Sending request...';
    });
    final api = CloudinaryApi(_creds);
    try {
      final seed = int.tryParse(_seedCtrl.text.trim());
      final GenerationResult r;
      if (_tab == 0) {
        r = await api.textToImage(
          prompt: prompt,
          modelId: _model,
          aspectRatio: _ratio,
          resolution: _resolution,
          format: _format,
          seed: seed,
          onStatus: (s) {
            if (mounted) setState(() => _status = _statusLabel(s));
          },
        );
        await AppPrefs.setLastModel(false, _model);
      } else {
        r = await api.imageToImage(
          prompt: prompt,
          modelId: _imgModel == 'auto' ? null : _imgModel,
          referenceUrls: refs,
          aspectRatio: _ratio,
          resolution: _resolution,
          format: _format,
          seed: seed,
          onStatus: (s) {
            if (mounted) setState(() => _status = _statusLabel(s));
          },
        );
        await AppPrefs.setLastModel(true, _imgModel);
      }
      await AppPrefs.setLastRatio(_ratio);
      await AppPrefs.setLastResolution(_resolution);
      await AppPrefs.setLastFormat(_format);
      if (!mounted) return;
      setState(() {
        _result = r;
        _loading = false;
        _status = '';
        _history.insert(
            0,
            _HistoryItem(
              url: r.imageUrl,
              prompt: prompt,
              model: _tab == 0
                  ? _model
                  : (_imgModel == 'auto' ? 'auto' : _imgModel),
              ratio: _ratio,
              ts: DateTime.now().millisecondsSinceEpoch,
            ));
        if (_history.length > 24) _history = _history.sublist(0, 24);
      });
      try {
        await AppPrefs.setHistory(
            _history.map((h) => jsonEncode(h.toJson())).toList());
      } catch (_) {}
    } on CloudinaryApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _status = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = CloudinaryApiException(
            category: 'client_error', code: 'UNEXPECTED', message: '$e');
        _loading = false;
        _status = '';
      });
    }
  }

  Future<Directory> _saveDir() async {
    try {
      final d = await getDownloadsDirectory();
      if (d != null) return d;
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  Future<void> _saveImage() async {
    final r = _result;
    if (r == null || _saving) return;
    setState(() => _saving = true);
    try {
      final resp = await http
          .get(Uri.parse(_displayUrl(r.imageUrl)))
          .timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200) {
        throw Exception('Download failed (HTTP ${resp.statusCode})');
      }
      final dir = await _saveDir();
      final ext = _exportExt(r);
      final file = File(
          '${dir.path}${Platform.pathSeparator}ai-studio-${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(resp.bodyBytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareImage() async {
    final r = _result;
    if (r == null) return;
    try {
      final resp = await http
          .get(Uri.parse(_displayUrl(r.imageUrl)))
          .timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200) {
        throw Exception('Download failed (HTTP ${resp.statusCode})');
      }
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}${Platform.pathSeparator}ai-studio-share.${_exportExt(r)}');
      await file.writeAsBytes(resp.bodyBytes);
      await Share.shareXFiles([XFile(file.path)], text: r.prompt);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _copyLink() async {
    final r = _result;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: _displayUrl(r.imageUrl)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Image URL copied.')));
  }

  Future<void> _openInBrowser() async {
    final r = _result;
    if (r == null) return;
    final uri = Uri.parse(_displayUrl(r.imageUrl));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (!mounted) return;
    try {
      final creds = await CredentialStore.load();
      setState(() => _creds = creds);
    } catch (_) {}
  }

  void _toggleTheme() {
    widget.onThemeChanged(
        widget.mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 34,
                height: 34,
                errorBuilder: (_, __, ___) => Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      Color(0xFF4F46E5),
                      Color(0xFF8B5CF6)
                    ]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('AI Image Studio',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Batch sets',
            icon: const Icon(Icons.layers_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const BatchScreen())),
          ),
          IconButton(
            tooltip:
                widget.mode == ThemeMode.dark ? 'Light mode' : 'Dark mode',
            icon: Icon(widget.mode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            onPressed: _toggleTheme,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 900;
              final form = _buildForm();
              final result = _buildResultColumn();
              if (wide) {
                return SingleChildScrollView(
                  padding: screenScrollPadding(context, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: form),
                      const SizedBox(width: 20),
                      Expanded(flex: 6, child: result),
                    ],
                  ),
                );
              }
              return SingleChildScrollView(
                padding: screenScrollPadding(context),
                child: Column(
                  children: [
                    form,
                    const SizedBox(height: 16),
                    result,
                  ],
                ),
              );
            }),
    );
  }

  Widget _buildForm() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
                value: 0,
                icon: Icon(Icons.text_fields),
                label: Text('Text to Image')),
            ButtonSegment(
                value: 1,
                icon: Icon(Icons.image_outlined),
                label: Text('Image to Image')),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: 12),
        if (!_creds.isComplete) _credentialsWarning(scheme),
        _sectionCard(
          title: 'Prompt',
          icon: Icons.edit_outlined,
          child: TextField(
            controller: _promptCtrl,
            maxLines: 5,
            minLines: 3,
            maxLength: 16384,
            decoration: const InputDecoration(
              hintText: 'Describe the image you want to create...',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Model & Size',
          icon: Icons.tune_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: _tab == 0 ? _model : _imgModel,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  prefixIcon: Icon(Icons.smart_toy_outlined),
                ),
                items: _modelItems(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    if (_tab == 0) {
                      _model = v;
                    } else {
                      _imgModel = v;
                    }
                  });
                },
              ),
              const SizedBox(height: 14),
              Text('Aspect ratio',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              _ratioPicker(scheme),
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
                      onChanged: (v) =>
                          setState(() => _resolution = v ?? '1K'),
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
                      onChanged: (v) => setState(() => _format = v ?? 'png'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: _exportIndex,
                decoration: const InputDecoration(
                  labelText: 'Export',
                  prefixIcon:
                      Icon(Icons.photo_size_select_large_outlined),
                ),
                items: [
                  for (var i = 0; i < ExportPresets.all.length; i++)
                    DropdownMenuItem(
                        value: i,
                        child: Text(ExportPresets.all[i].label))
                ],
                onChanged: (v) async {
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
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Seed (optional)',
                  hintText: 'Leave empty for random',
                  prefixIcon: Icon(Icons.casino_outlined),
                ),
              ),
            ],
          ),
        ),
        if (_tab == 1) ...[
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Reference images',
            icon: Icons.collections_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'Paste up to 4 image URLs. Mention them in the prompt as [1], [2], ...'),
                const SizedBox(height: 10),
                for (var i = 0; i < _refCtrls.length; i++) _refRow(i, scheme),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _refCtrls.length >= 4
                        ? null
                        : () => setState(
                            () => _refCtrls.add(TextEditingController())),
                    icon: const Icon(Icons.add),
                    label: const Text('Add reference'),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _generate,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          icon: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : const Icon(Icons.auto_awesome, size: 22),
          label: Text(_loading ? 'Generating...' : 'Generate image'),
        ),
        if (_loading) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(color: scheme.primary),
          const SizedBox(height: 6),
          Text(_status,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center),
        ],
      ],
    );
  }

  List<DropdownMenuItem<String>> _modelItems() {
    if (_tab == 0) {
      return [
        for (final m in AiModels.textToImage)
          DropdownMenuItem(value: m, child: Text(m))
      ];
    }
    return [
      const DropdownMenuItem(value: 'auto', child: Text('Auto (recommended)')),
      for (final m in AiModels.imageToImage)
        DropdownMenuItem(value: m, child: Text(m)),
    ];
  }

  Widget _ratioPicker(ColorScheme scheme) {
    return Wrap(
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
            onSelected: (_) => setState(() => _ratio = r),
          ),
      ],
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

  Widget _refRow(int index, ColorScheme scheme) {
    final url = _refCtrls[index].text.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: url.isEmpty
                ? Icon(Icons.image_outlined, color: scheme.outline)
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                        Icons.broken_image_outlined,
                        color: scheme.error),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _refCtrls[index],
              decoration: InputDecoration(
                labelText: 'Reference [${index + 1}] URL',
                hintText: 'https://...',
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _refCtrls.length <= 1
                ? null
                : () => setState(() {
                      _refCtrls[index].dispose();
                      _refCtrls.removeAt(index);
                    }),
          ),
        ],
      ),
    );
  }

  Widget _credentialsWarning(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.error.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.key_off_outlined, color: scheme.error),
          const SizedBox(width: 12),
          const Expanded(
              child: Text(
                  'Cloudinary credentials are missing. Add them to start generating.')),
          TextButton(onPressed: _openSettings, child: const Text('Set up')),
        ],
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

  Widget _buildResultColumn() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) _errorCard(scheme),
        if (_result != null)
          _resultCard(scheme)
        else if (_error == null && !_loading)
          _emptyResult(scheme),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 16),
          _historyCard(scheme),
        ],
      ],
    );
  }

  Widget _emptyResult(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.image_search_outlined,
                size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text('Your creation will appear here',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              'Write a prompt, pick a model and ratio, then hit Generate.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(ColorScheme scheme) {
    final e = _error!;
    return Card(
      color: scheme.errorContainer.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Generation failed',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: scheme.error)),
                  const SizedBox(height: 4),
                  Text(e.message),
                  const SizedBox(height: 6),
                  Text('${e.category} / ${e.code}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.outline)),
                ],
              ),
            ),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _error = null)),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(ColorScheme scheme) {
    final r = _result!;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio:
                r.width > 0 && r.height > 0 ? r.width / r.height : 1,
            child: Image.network(
              _displayUrl(r.imageUrl),
              fit: BoxFit.contain,
              loadingBuilder: (c, child, progress) => progress == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 48)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(Icons.smart_toy_outlined,
                        r.modelId.isEmpty ? 'auto' : r.modelId),
                    if (r.width > 0)
                      _chip(Icons.aspect_ratio_outlined,
                          '${r.width} x ${r.height}'),
                    if (r.seed != null)
                      _chip(Icons.casino_outlined, 'seed ${r.seed}'),
                    if (r.quotaRemaining != null && r.quotaLimit != null)
                      _chip(Icons.bolt_outlined,
                          'quota ${r.quotaRemaining}/${r.quotaLimit}'),
                    _chip(Icons.photo_size_select_large_outlined,
                        ExportPresets.all[_exportIndex].label),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _saving ? null : _saveImage,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_outlined),
                      label: const Text('Save'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _shareImage,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _copyLink,
                      icon: const Icon(Icons.link_outlined),
                      label: const Text('Copy URL'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openInBrowser,
                      icon: const Icon(Icons.open_in_new_outlined),
                      label: const Text('Open'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: scheme.onSecondaryContainer)),
        ],
      ),
    );
  }

  Widget _historyCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_outlined,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Recent',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    setState(() => _history = []);
                    try {
                      await AppPrefs.setHistory([]);
                    } catch (_) {}
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _history.length,
              itemBuilder: (_, i) {
                final h = _history[i];
                return InkWell(
                  onTap: () => _showHistoryItem(h),
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      h.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: scheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showHistoryItem(_HistoryItem h) {
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
                child:
                    Image.network(_displayUrl(h.url), fit: BoxFit.contain),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(h.prompt,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Text('${h.model}  -  ${h.ratio}',
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
                              imageUrl: _displayUrl(h.url),
                              title: h.prompt,
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
                                text: _displayUrl(h.url)));
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
    _promptCtrl.dispose();
    _seedCtrl.dispose();
    for (final c in _refCtrls) {
      c.dispose();
    }
    super.dispose();
  }
}
