import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../cloudinary_api.dart';
import '../gemini_accounts.dart';
import '../gemini_image.dart';
import '../gemini_web.dart';
import '../local_upscale.dart';
import '../secure_store.dart';
import 'google_login_screen.dart';

/// "Gemini Fast" — the Gemini HD Studio pipeline inside the app:
/// Gemini web session (no Cloudinary generate / polling) for
/// text-to-image, image-to-image and image-to-prompt, plus the
/// extension's Cloudinary e_upscale + exact 1620x2880 JPG finish.
class GeminiFastScreen extends StatefulWidget {
  const GeminiFastScreen({super.key});

  @override
  State<GeminiFastScreen> createState() => _GeminiFastScreenState();
}

enum _Mode { textToImage, imageToImage, imageToPrompt }

class _GeminiFastScreenState extends State<GeminiFastScreen> {
  _Mode _mode = _Mode.textToImage;
  final _prompt = TextEditingController();
  final _extra = TextEditingController();
  String _aspect = '9:16';
  bool _autoUpscale = true;
  bool _fastUpscale = true;

  GeminiImageClient? _gemini;
  CloudinaryCredentials? _creds;
  String _setupNote = 'Loading...';

  Uint8List? _input;
  String _inputName = 'image.jpg';
  Uint8List? _output;
  String _outputExt = 'jpg';
  bool _upscaled = false;
  String _promptResult = '';

  bool _busy = false;
  String _status = '';
  final List<String> _timings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var note = '';
    try {
      _gemini = await GeminiAccounts.client();
      _gemini!.onAccountSwitch = (m) {
        _timings.add(m);
        _snack(m);
      };
    } on GeminiWebException catch (e) {
      _gemini = null;
      note = e.message;
    } catch (e) {
      note = 'Gemini session could not be read: $e';
    }
    try {
      _creds = await CredentialStore.load();
    } catch (_) {}
    if (mounted) setState(() => _setupNote = note);
  }

  Future<T> _step<T>(String label, Future<T> Function() fn) async {
    setState(() => _status = '$label...');
    final sw = Stopwatch()..start();
    final r = await fn();
    _timings.add('$label: ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
    return r;
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f == null) return;
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    setState(() {
      _input = bytes;
      _inputName = f.name;
    });
  }

  Future<void> _run() async {
    final g = _gemini;
    if (g == null) return _snack(_setupNote);
    if (_mode != _Mode.textToImage && _input == null) {
      return _snack('Pick an image first.');
    }
    if (_mode != _Mode.imageToPrompt && _prompt.text.trim().isEmpty) {
      return _snack('Write a prompt first.');
    }
    setState(() {
      _busy = true;
      _timings.clear();
      _output = null;
      _upscaled = false;
      _promptResult = '';
    });
    final total = Stopwatch()..start();
    try {
      if (_mode == _Mode.imageToPrompt) {
        final p = await _step('Gemini image to prompt',
            () => g.imageToPrompt(_input!, filename: _inputName,
                extra: _extra.text));
        setState(() => _promptResult = p);
      } else {
        final reply = await _step(
            _mode == _Mode.imageToImage
                ? 'Upload + Gemini generate'
                : 'Gemini generate',
            () => g.generateWithFailover(_prompt.text,
                image: _mode == _Mode.imageToImage ? _input : null,
                filename: _inputName,
                aspectRatio: _aspect));
        final hd = await _step('Download full-res (=s0)',
            () => g.fetchHd(reply.urls.first));
        setState(() {
          _output = hd.bytes;
          _outputExt = hd.ext;
        });
        if (_autoUpscale) await _upscale();
      }
      _timings.add('Total: ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
    } on GeminiWebException catch (e) {
      _snack(e.expired
          ? '${e.message} Re-export the Gemini session in Settings.'
          : e.message);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() { _busy = false; _status = ''; });
    }
  }

  (int, int) get _target {
    switch (_aspect) {
      case '1:1':
        return (2048, 2048);
      case '16:9':
        return (2880, 1620);
      case '4:3':
        return (2400, 1800);
      case '3:4':
        return (1800, 2400);
      default:
        return (1620, 2880);
    }
  }

  Future<void> _upscale() async {
    final src = _output;
    final creds = _creds;
    if (src == null) return;
    if (creds == null || !creds.isComplete) {
      return _snack('Add Cloudinary credentials in Settings for AI Upscale.');
    }
    final (w, h) = _target;
    final out = await _step('AI Upscale ${w}x$h',
        () => LocalUpscale(creds).upscale(src,
            targetWidth: w, targetHeight: h, fast: _fastUpscale,
            onStatus: (s) { if (mounted) setState(() => _status = s); }));
    setState(() {
      _output = out;
      _outputExt = 'jpg';
      _upscaled = true;
    });
  }

  Future<void> _manualUpscale() async {
    setState(() => _busy = true);
    try {
      await _upscale();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() { _busy = false; _status = ''; });
    }
  }

  Future<File> _writeOutput() async {
    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}'
        'gemini_${DateTime.now().millisecondsSinceEpoch}'
        '${_upscaled ? '_upscaled' : ''}.$_outputExt');
    return f.writeAsBytes(_output!);
  }

  Future<void> _save() async {
    try {
      final f = await _writeOutput();
      _snack('Saved: ${f.path}');
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  Future<void> _share() async {
    final f = await _writeOutput();
    await Share.shareXFiles([XFile(f.path)], text: _prompt.text);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Gemini Fast')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_setupNote.isNotEmpty && _gemini == null)
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(child: Text(_setupNote)),
                  FilledButton.icon(
                    onPressed: () async {
                      final n = await Navigator.of(context).push<int>(
                          MaterialPageRoute(
                              builder: (_) => const GoogleLoginScreen()));
                      if (n != null) await _load();
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in with Google'),
                  ),
                ]),
              ),
            ),
          if (_gemini != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                const Icon(Icons.account_circle_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('Gemini: ${_gemini!.activeAccount}'
                    '${_gemini!.accounts.length > 1 ? '  ·  ${_gemini!.accounts.length} accounts, auto-switch ${_gemini!.autoSwitch ? 'on' : 'off'}' : ''}')),
              ]),
            ),
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.textToImage,
                  label: Text('Text to image'), icon: Icon(Icons.text_fields)),
              ButtonSegment(value: _Mode.imageToImage,
                  label: Text('Image to image'), icon: Icon(Icons.image)),
              ButtonSegment(value: _Mode.imageToPrompt,
                  label: Text('Image to prompt'),
                  icon: Icon(Icons.description_outlined)),
            ],
            selected: {_mode},
            onSelectionChanged: _busy
                ? null
                : (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          if (_mode != _Mode.textToImage) ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(_input == null ? 'Pick image' : _inputName),
            ),
            if (_input != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                    height: 180,
                    child: Image.memory(_input!, fit: BoxFit.contain)),
              ),
            const SizedBox(height: 12),
          ],
          if (_mode == _Mode.imageToPrompt)
            TextField(
              controller: _extra,
              decoration: const InputDecoration(
                  labelText: 'Extra instruction (optional)',
                  hintText: 'e.g. make it a 9:16 phone wallpaper prompt'),
            )
          else ...[
            TextField(
              controller: _prompt,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                  labelText: _mode == _Mode.imageToImage
                      ? 'How to change the image'
                      : 'Prompt',
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Aspect'),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _aspect,
                items: const ['9:16', '1:1', '16:9', '3:4', '4:3']
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: _busy ? null : (v) => setState(() => _aspect = v!),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Auto AI Upscale (${_target.$1}x${_target.$2} JPG)'),
              subtitle: const Text('Cloudinary e_upscale, like Gemini HD Studio'),
              value: _autoUpscale,
              onChanged: _busy ? null : (v) => setState(() => _autoUpscale = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fast upscale (512 → 4x)'),
              subtitle: const Text('Off = full e_upscale on original (slower)'),
              value: _fastUpscale,
              onChanged: _busy ? null : (v) => setState(() => _fastUpscale = v),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bolt),
            label: Text(_mode == _Mode.imageToPrompt
                ? 'Get prompt'
                : 'Generate'),
          ),
          if (_status.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status)),
          if (_timings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_timings.join('  ·  '),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          if (_promptResult.isNotEmpty) ...[
            const SizedBox(height: 16),
            SelectableText(_promptResult),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _promptResult));
                  _snack('Prompt copied');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => setState(() {
                  _prompt.text = _promptResult;
                  _mode = _Mode.textToImage;
                }),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate from this prompt'),
              ),
            ]),
          ],
          if (_output != null) ...[
            const SizedBox(height: 16),
            Image.memory(_output!, fit: BoxFit.contain),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.download),
                  label: const Text('Save')),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.share),
                  label: const Text('Share')),
              if (!_upscaled)
                OutlinedButton.icon(
                    onPressed: _busy ? null : _manualUpscale,
                    icon: const Icon(Icons.hd_outlined),
                    label: const Text('AI Upscale')),
            ]),
          ],
        ],
      ),
    );
  }
}
