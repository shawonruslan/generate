import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../browser_inject.dart';
import '../gemini_web.dart';
import '../image_to_prompt.dart';
import '../prompt_library.dart';
import '../secure_store.dart';
import 'batch_screen.dart';
import 'settings_screen.dart';

/// One image waiting for image -> prompt.
class _PromptTask {
  final String id; // overlay id inside the page ('' for target/region picks)
  final String src; // http(s) / data: / blob: URL, or '' for screenshot-only
  final String page;
  final String key; // de-dup key
  /// Screenshot crop of the image's area, taken when it was picked. Used
  /// when the site refuses to hand over the file (locked / protected).
  final PreparedImage? shot;
  _PromptTask(this.id, this.src, this.page, {String? key, this.shot})
      : key = key ?? src;
}

/// One image source found under a target-mode tap.
class _Found {
  final String src;
  final String kind;
  final int w;
  final int h;
  const _Found(this.src, this.kind, this.w, this.h);
}

/// In-app Web browser. Every image on every page gets a sparkle button
/// (image -> prompt through the Gemini web cookie session) and a tick box;
/// ticked images are processed one by one and every prompt lands in the
/// app-wide Prompts list.
///
/// Pops with a prompt string when the user picks "Use in Text to Image".
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  static const _home = 'https://www.google.com/imghp';
  static const _kLastUrl = 'browser_last_url';
  static const _kStyle = 'browser_prompt_style';
  static const _kDeep = 'browser_deep_scan';

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _urlCtrl = TextEditingController();
  final _urlFocus = FocusNode();
  final _lib = PromptLibrary.instance;

  InAppWebViewController? _web;
  String _startUrl = '';
  bool _booted = false;
  double _progress = 0;
  bool _canBack = false;
  bool _canForward = false;
  bool _overlay = true;
  PromptStyle _style = PromptStyle.detailed;
  bool _deep = false; // deep scan: CSS backgrounds, canvas, lazy images
  String _mode = ''; // '' | 'target' | 'region'
  int _shotSeq = 0;

  GeminiWebClient? _gemini;
  String _geminiNote = '';

  // queue
  final Queue<_PromptTask> _queue = Queue();
  final Set<String> _queuedSrc = {};
  bool _running = false;
  bool _cancel = false;
  int _done = 0;
  int _failed = 0;
  int _total = 0;
  String _current = '';
  String _lastError = '';
  final List<_PromptTask> _failedTasks = [];

  // in-page grab replies
  final Map<String, Completer<String>> _grabs = {};
  int _grabSeq = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _lib.load();
    await _loadGemini();
    var start = _home;
    try {
      final p = await AppPrefs.prefs();
      start = p.getString(_kLastUrl) ?? _home;
      final st = p.getInt(_kStyle) ?? 0;
      _style = PromptStyle.values[st.clamp(0, PromptStyle.values.length - 1)];
      _deep = p.getBool(_kDeep) ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _startUrl = start;
      _urlCtrl.text = start;
      _booted = true;
    });
  }

  Future<void> _loadGemini() async {
    try {
      final raw = await GeminiWebStore.load();
      if (raw.trim().isEmpty) {
        _gemini = null;
        _geminiNote = 'No Gemini web session saved.';
        return;
      }
      final session = GeminiWebSession.parse(raw);
      _gemini = GeminiWebClient(session);
      _geminiNote = session.summary;
    } on GeminiWebException catch (e) {
      _gemini = null;
      _geminiNote = e.message;
    } catch (e) {
      _gemini = null;
      _geminiNote = '$e';
    }
  }

  void _snack(String msg, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await _loadGemini();
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ navigation
  String _normalize(String input) {
    final t = input.trim();
    if (t.isEmpty) return _home;
    final looksUrl = !t.contains(' ') &&
        (t.startsWith('http://') ||
            t.startsWith('https://') ||
            RegExp(r'^[\w-]+(\.[\w-]+)+(:\d+)?(/.*)?$').hasMatch(t));
    if (looksUrl) {
      return t.startsWith('http') ? t : 'https://$t';
    }
    return 'https://www.google.com/search?tbm=isch&q=${Uri.encodeQueryComponent(t)}';
  }

  Future<void> _go(String input) async {
    final url = _normalize(input);
    _urlFocus.unfocus();
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _syncNav(WebUri? url) async {
    final c = _web;
    if (c == null) return;
    final back = await c.canGoBack();
    final fwd = await c.canGoForward();
    if (!mounted) return;
    setState(() {
      _canBack = back;
      _canForward = fwd;
      if (url != null && !_urlFocus.hasFocus) _urlCtrl.text = url.toString();
    });
    if (url != null && url.toString().startsWith('http')) {
      try {
        (await AppPrefs.prefs()).setString(_kLastUrl, url.toString());
      } catch (_) {}
    }
  }

  Future<void> _inject() async {
    try {
      await _web?.evaluateJavascript(source: browserInjectJs);
      await _web?.evaluateJavascript(
          source: 'window.__aisSetVisible && window.__aisSetVisible($_overlay);'
              'window.__aisSetDeep && window.__aisSetDeep($_deep);'
              "window.__aisMode && window.__aisMode('$_mode');");
    } catch (_) {}
  }

  Future<void> _setDeep(bool v) async {
    setState(() => _deep = v);
    try {
      (await AppPrefs.prefs()).setBool(_kDeep, v);
      await _web?.evaluateJavascript(
          source: 'window.__aisSetDeep && window.__aisSetDeep($v);');
    } catch (_) {}
    _snack(v
        ? 'Deep scan on: background, canvas and lazy-loaded images get icons too.'
        : 'Deep scan off.');
  }

  Future<void> _setMode(String m) async {
    setState(() => _mode = m);
    try {
      await _web?.evaluateJavascript(
          source: "window.__aisMode && window.__aisMode('$m');");
    } catch (_) {}
  }

  // ------------------------------------------------------------ capture
  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  static List<double>? _rect(dynamic r) {
    if (r is! List || r.length < 4) return null;
    return r.take(4).map(_num).toList();
  }

  /// Screenshots the WebView (with our overlay hidden) and crops [rects].
  Future<List<PreparedImage?>> _capture(
      List<List<double>> rects, double vw) async {
    final none = List<PreparedImage?>.filled(rects.length, null);
    final c = _web;
    if (c == null || rects.isEmpty) return none;
    try {
      await c.evaluateJavascript(
          source: 'window.__aisHideUi && window.__aisHideUi(true);');
      await Future.delayed(const Duration(milliseconds: 90));
      final Uint8List? png = await c.takeScreenshot(
          screenshotConfiguration:
              ScreenshotConfiguration(compressFormat: CompressFormat.PNG));
      await c.evaluateJavascript(
          source: 'window.__aisHideUi && window.__aisHideUi(false);');
      if (png == null || png.isEmpty) return none;
      return await _cropInIsolate(png, vw, rects);
    } catch (_) {
      try {
        await c.evaluateJavascript(
            source: 'window.__aisHideUi && window.__aisHideUi(false);');
      } catch (_) {}
      return none;
    }
  }

  // Static so the isolate closure captures only sendable values.
  static Future<List<PreparedImage?>> _cropInIsolate(
          Uint8List png, double vw, List<List<double>> rects) =>
      Isolate.run(() => ImageToPrompt.cropShots(png, vw, rects));

  static bool _onScreen(List<double> r, double vw, double vh) =>
      r[2] > 0 &&
      r[3] > 0 &&
      r[0] < vw &&
      r[1] < vh &&
      r[0] + r[2] > 0 &&
      r[1] + r[3] > 0;

  Future<void> _setOverlay(bool v) async {
    setState(() => _overlay = v);
    try {
      await _web?.evaluateJavascript(
          source: 'window.__aisSetVisible && window.__aisSetVisible($v);');
    } catch (_) {}
  }

  Future<void> _mark(String id, String state, [String note = '']) async {
    try {
      final safeId = jsonEncode(id);
      final safeNote = jsonEncode(note);
      await _web?.evaluateJavascript(
          source:
              "window.__aisSetState && window.__aisSetState($safeId, '$state', $safeNote);");
    } catch (_) {}
  }

  // ------------------------------------------------------------ queue
  bool _needGemini() {
    if (_gemini != null) return false;
    _snack('Add your Gemini web cookie session in Settings first.',
        action: SnackBarAction(label: 'Settings', onPressed: _openSettings));
    return true;
  }

  Future<void> _onPromptRequest(List<dynamic> args) async {
    if (args.isEmpty || args.first is! List) return;
    final raws = (args.first as List).whereType<Map>().toList();
    if (_needGemini()) {
      for (final raw in raws) {
        _mark('${raw['id']}', '');
      }
      return;
    }
    // One screenshot covers every visible picked image: it is the fallback
    // when the site refuses the file itself (hot-link / locked images).
    final idx = <int>[];
    final rects = <List<double>>[];
    double vw = 0;
    for (var i = 0; i < raws.length; i++) {
      final r = _rect(raws[i]['rect']);
      final w = _num(raws[i]['vw']), h = _num(raws[i]['vh']);
      if (r != null && w > 0 && _onScreen(r, w, h)) {
        idx.add(i);
        rects.add(r);
        vw = w;
      }
    }
    final shots = rects.isEmpty
        ? const <PreparedImage?>[]
        : await _capture(rects, vw);
    final tasks = <_PromptTask>[];
    for (var i = 0; i < raws.length; i++) {
      final raw = raws[i];
      final src = (raw['src'] ?? '').toString();
      final at = idx.indexOf(i);
      final shot = at >= 0 && at < shots.length ? shots[at] : null;
      if (src.isEmpty && shot == null) {
        _mark('${raw['id']}', 'error', 'Nothing readable here.');
        continue;
      }
      tasks.add(_PromptTask(
          (raw['id'] ?? '').toString(), src, (raw['page'] ?? '').toString(),
          key: src.isEmpty || src.startsWith('data:')
              ? 'shot:${_shotSeq++}'
              : src,
          shot: shot));
    }
    _enqueue(tasks);
  }

  /// Target / region pick from the page.
  Future<void> _onTarget(List<dynamic> args) async {
    if (args.isEmpty || args.first is! Map) return;
    final m = args.first as Map;
    if (_needGemini()) return;
    final rect = _rect(m['rect']);
    final vw = _num(m['vw']);
    final page = '${m['page'] ?? ''}';
    final shot =
        rect == null ? null : (await _capture([rect], vw)).firstOrNull;
    final sources = ((m['sources'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => _Found('${e['src'] ?? ''}', '${e['kind'] ?? ''}',
            _num(e['w']).round(), _num(e['h']).round()))
        .where((f) => f.src.isNotEmpty)
        .toList();
    String keyFor(String src) =>
        src.startsWith('data:') ? 'shot:${_shotSeq++}' : src;

    if (m['region'] == true || sources.isEmpty) {
      if (shot == null) {
        _snack('Could not capture that area. Try a slightly bigger box.');
        return;
      }
      _enqueue([
        _PromptTask('', '', page, key: 'shot:${_shotSeq++}', shot: shot)
      ]);
      return;
    }
    if (sources.length == 1) {
      final f = sources.first;
      _enqueue([_PromptTask('', f.src, page, key: keyFor(f.src), shot: shot)]);
      return;
    }
    // Several layers under the tap (e.g. a protection overlay + the real
    // photo + a blurred preview): let the user choose.
    final picked = await _pickSources(sources, shot);
    if (picked == null || picked.isEmpty) return;
    _enqueue([
      for (final i in picked)
        if (i < 0)
          _PromptTask('', '', page, key: 'shot:${_shotSeq++}', shot: shot)
        else
          _PromptTask('', sources[i].src, page,
              key: keyFor(sources[i].src), shot: shot),
    ]);
  }

  Widget _thumb(String src, String page) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined, color: scheme.outline),
    );
    if (src.startsWith('data:')) {
      final m = RegExp(r'^data:[^,]*;base64,(.*)$', dotAll: true).firstMatch(src);
      if (m == null) return fallback;
      try {
        return Image.memory(base64Decode(m.group(1)!),
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
      } catch (_) {
        return fallback;
      }
    }
    if (!src.startsWith('http')) return fallback;
    return Image.network(src,
        fit: BoxFit.cover,
        headers: {
          'User-Agent': geminiWebUserAgent,
          if (page.startsWith('http')) 'Referer': page,
        },
        errorBuilder: (_, __, ___) => fallback);
  }

  /// Returns indexes into [sources]; -1 stands for the screenshot.
  Future<List<int>?> _pickSources(
      List<_Found> sources, PreparedImage? shot) {
    final chosen = <int>{0};
    final page = _urlCtrl.text;
    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final entries = <MapEntry<int, Widget>>[
            for (var i = 0; i < sources.length; i++)
              MapEntry(i, _thumb(sources[i].src, page)),
            if (shot != null)
              MapEntry(-1, Image.memory(shot.bytes, fit: BoxFit.cover)),
          ];
          String label(int i) {
            if (i < 0) return 'Screenshot of area';
            final f = sources[i];
            final kind = switch (f.kind) {
              'img' => 'Image',
              'canvas' => 'Canvas',
              'video' => 'Video poster',
              'image' => 'SVG image',
              _ => 'Background',
            };
            return f.w > 0 && f.h > 0 ? '$kind · ${f.w}×${f.h}' : kind;
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${entries.length} images found under your tap',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Hidden layers included. Tick the ones to turn into prompts.',
                      style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Flexible(
                    child: GridView.count(
                      shrinkWrap: true,
                      crossAxisCount:
                          MediaQuery.sizeOf(ctx).width > 700 ? 4 : 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.8,
                      children: [
                        for (final e in entries)
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setSheet(() {
                              if (!chosen.remove(e.key)) chosen.add(e.key);
                            }),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: e.value),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Icon(
                                          chosen.contains(e.key)
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          color: chosen.contains(e.key)
                                              ? Colors.green
                                              : Colors.white,
                                          shadows: const [
                                            Shadow(blurRadius: 4)
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(label(e.key),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(ctx).textTheme.bodySmall),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: chosen.isEmpty
                        ? null
                        : () => Navigator.of(ctx).pop(chosen.toList()..sort()),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                        'Generate ${chosen.length} prompt${chosen.length == 1 ? '' : 's'}'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _enqueue(List<_PromptTask> tasks) {
    var added = 0;
    for (final t in tasks) {
      if (_queuedSrc.contains(t.key)) continue;
      _queuedSrc.add(t.key);
      _queue.add(t);
      added++;
    }
    if (added == 0 || !mounted) return;
    setState(() {
      if (!_running) {
        _done = 0;
        _failed = 0;
        _total = 0;
        _lastError = '';
        _failedTasks.clear();
      }
      _total += added;
    });
    if (!_running) _runQueue();
  }

  Future<void> _runQueue() async {
    final web = _gemini;
    if (web == null) return;
    setState(() {
      _running = true;
      _cancel = false;
    });
    var first = true;
    while (_queue.isNotEmpty && !_cancel) {
      final t = _queue.removeFirst();
      // Gentle pacing: back-to-back uploads trip Gemini's rate limit.
      if (!first) await Future.delayed(const Duration(milliseconds: 2500));
      first = false;
      if (_cancel) {
        _queue.addFirst(t);
        break;
      }
      if (mounted) {
        setState(() => _current =
            'Writing prompt ${_done + _failed + 1} of $_total...');
      }
      await _mark(t.id, 'running');
      try {
        // Real file first (full quality, no blur/watermark overlay), then
        // the in-page grab, then the screenshot taken when it was picked.
        PreparedImage? image;
        if (t.src.startsWith('data:')) {
          image = ImageToPrompt.fromDataUrl(t.src);
        } else if (t.src.isNotEmpty) {
          image = await ImageToPrompt.download(t.src, t.page);
          image ??= await _grabInPage(t.src);
        }
        image ??= t.shot;
        if (image == null) {
          throw 'Could not read this image. Use Target or Region mode on it.';
        }
        final prompt = await ImageToPrompt.generate(
            web: web, image: image, style: _style);
        await _lib.add(
            prompt: prompt,
            imageUrl: t.src.startsWith('http') ? t.src : '',
            pageUrl: t.page);
        await _mark(t.id, 'done');
        if (mounted) setState(() => _done++);
      } catch (e) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        await _mark(t.id, 'error', msg);
        _failedTasks.add(t);
        if (mounted) {
          setState(() {
            _failed++;
            _lastError = msg;
          });
        }
        if (e is GeminiWebException && e.expired) {
          _cancel = true;
          _snack('Gemini session expired. Re-export your cookies in Settings.',
              action:
                  SnackBarAction(label: 'Settings', onPressed: _openSettings));
        }
      } finally {
        _queuedSrc.remove(t.key);
      }
    }
    // Cancelled: clear whatever was still waiting.
    while (_queue.isNotEmpty) {
      final t = _queue.removeFirst();
      _queuedSrc.remove(t.key);
      await _mark(t.id, '');
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _current = '';
    });
    _snack(_failed == 0
        ? '$_done prompt${_done == 1 ? '' : 's'} added to your Prompts list.'
        : '$_done added, $_failed failed. $_lastError');
  }

  /// Puts every failed image back in the queue.
  void _retryFailed() {
    if (_running || _failedTasks.isEmpty) return;
    final again = List<_PromptTask>.from(_failedTasks);
    _failedTasks.clear();
    setState(() {
      _total = again.length;
      _done = 0;
      _failed = 0;
      _lastError = '';
    });
    for (final t in again) {
      _queuedSrc.add(t.key);
      _queue.add(t);
      _mark(t.id, 'queued');
    }
    _runQueue();
  }

  Future<PreparedImage?> _grabInPage(String src) async {
    final c = _web;
    if (c == null) return null;
    final id = 'g${_grabSeq++}';
    final done = Completer<String>();
    _grabs[id] = done;
    try {
      final safe = src.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      await c.evaluateJavascript(
          source: "window.__aisGrab && window.__aisGrab('$id', '$safe');");
      final dataUrl =
          await done.future.timeout(const Duration(seconds: 40), onTimeout: () => '');
      if (dataUrl.isEmpty) return null;
      return ImageToPrompt.fromDataUrl(dataUrl);
    } catch (_) {
      return null;
    } finally {
      _grabs.remove(id);
    }
  }

  // ------------------------------------------------------------ prompts
  Future<void> _sendToBatch(List<PromptEntry> items) async {
    if (items.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BatchScreen(
            initialPrompts: items.reversed.map((e) => e.prompt).toList())));
  }

  Future<void> _editPrompt(PromptEntry e) async {
    final ctrl = TextEditingController(text: e.prompt);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit prompt'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            minLines: 4,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) await _lib.update(e.id, ctrl.text);
    ctrl.dispose();
  }

  Widget _promptsDrawer() {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    return Drawer(
      width: width > 700 ? 460 : width * 0.92,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _lib,
          builder: (context, _) {
            final items = _lib.items;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  child: Row(
                    children: [
                      Icon(Icons.list_alt_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Prompts (${items.length})',
                            style: textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        onPressed: items.isEmpty
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                _sendToBatch(items);
                              },
                        icon: const Icon(Icons.layers_outlined, size: 18),
                        label: const Text('Send all to Batch'),
                      ),
                      OutlinedButton.icon(
                        onPressed: items.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(
                                    text: items.reversed
                                        .map((e) => e.prompt)
                                        .join('\n')));
                                _snack('${items.length} prompts copied, one per line.');
                              },
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: const Text('Copy all'),
                      ),
                      TextButton.icon(
                        onPressed: items.isEmpty
                            ? null
                            : () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Clear Prompts list?'),
                                    content: Text(
                                        'Removes all ${items.length} saved prompts from this device.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: const Text('Cancel')),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(true),
                                          child: const Text('Clear')),
                                    ],
                                  ),
                                );
                                if (ok == true) await _lib.clear();
                              },
                        style: TextButton.styleFrom(
                            foregroundColor: scheme.error),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Tap the sparkle on any image to turn it into a prompt, '
                              'or tick several images and press Generate. '
                              'For locked or hidden images use Target mode, '
                              'or Region capture for any area.',
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: scheme.outline),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _promptTile(items[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _promptTile(PromptEntry e) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: e.imageUrl.startsWith('http')
                      ? Image.network(
                          e.imageUrl,
                          fit: BoxFit.cover,
                          headers: {
                            'User-Agent': geminiWebUserAgent,
                            if (e.pageUrl.startsWith('http'))
                              'Referer': e.pageUrl,
                          },
                          errorBuilder: (_, __, ___) => Container(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(Icons.image_outlined,
                                color: scheme.outline),
                          ),
                        )
                      : Container(
                          color: scheme.surfaceContainerHighest,
                          child:
                              Icon(Icons.image_outlined, color: scheme.outline),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  e.prompt,
                  maxLines: 6,
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: e.prompt));
                  _snack('Prompt copied.');
                },
              ),
              IconButton(
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _editPrompt(e),
              ),
              IconButton(
                tooltip: 'Use in Text to Image',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.text_fields, size: 18),
                onPressed: () {
                  Navigator.of(context).pop(); // drawer
                  Navigator.of(context).pop(e.prompt);
                },
              ),
              IconButton(
                tooltip: 'Send to Batch',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.layers_outlined, size: 18),
                onPressed: () {
                  Navigator.of(context).pop();
                  _sendToBatch([e]);
                },
              ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
                onPressed: () => _lib.remove(e.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_canBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _canBack) _web?.goBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        endDrawer: _promptsDrawer(),
        appBar: AppBar(
          titleSpacing: 0,
          title: SizedBox(
            height: 40,
            child: TextField(
              controller: _urlCtrl,
              focusNode: _urlFocus,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: _go,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search or type a URL',
                prefixIcon: const Icon(Icons.public, size: 18),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: _canBack ? () => _web?.goBack() : null,
            ),
            IconButton(
              tooltip: 'Forward',
              icon: const Icon(Icons.arrow_forward_ios, size: 18),
              onPressed: _canForward ? () => _web?.goForward() : null,
            ),
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () => _web?.reload(),
            ),
            PopupMenuButton<String>(
              tooltip: 'Options',
              onSelected: (v) async {
                if (v == 'overlay') {
                  _setOverlay(!_overlay);
                } else if (v == 'deep') {
                  _setDeep(!_deep);
                } else if (v == 'target' || v == 'region') {
                  _setMode(_mode == v ? '' : v);
                } else if (v == 'settings') {
                  _openSettings();
                } else if (v.startsWith('style:')) {
                  final s = PromptStyle.values[int.parse(v.substring(6))];
                  setState(() => _style = s);
                  try {
                    (await AppPrefs.prefs()).setInt(_kStyle, s.index);
                  } catch (_) {}
                }
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: 'overlay',
                  checked: _overlay,
                  child: const Text('Show image icons'),
                ),
                CheckedPopupMenuItem(
                  value: 'deep',
                  checked: _deep,
                  child: const Text('Deep scan (backgrounds, canvas, lazy)'),
                ),
                CheckedPopupMenuItem(
                  value: 'target',
                  checked: _mode == 'target',
                  child: const Text('Target mode (locked / hidden images)'),
                ),
                CheckedPopupMenuItem(
                  value: 'region',
                  checked: _mode == 'region',
                  child: const Text('Region capture'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                    enabled: false, child: Text('Prompt style')),
                for (final s in PromptStyle.values)
                  CheckedPopupMenuItem(
                    value: 'style:${s.index}',
                    checked: _style == s,
                    child: Text(PromptStyles.label(s)),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Gemini session settings'),
                ),
              ],
            ),
            AnimatedBuilder(
              animation: _lib,
              builder: (_, __) => IconButton(
                tooltip: 'Prompts list',
                icon: Badge(
                  isLabelVisible: _lib.length > 0,
                  label: Text('${_lib.length}'),
                  child: const Icon(Icons.list_alt_outlined),
                ),
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
            ),
            const SizedBox(width: 4),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: _progress > 0 && _progress < 1
                ? LinearProgressIndicator(value: _progress, minHeight: 3)
                : const SizedBox(height: 3),
          ),
        ),
        body: Column(
          children: [
            if (_gemini == null && _booted)
              MaterialBanner(
                content: Text(
                    'Image to prompt uses your Gemini web cookie session. $_geminiNote'),
                leading: Icon(Icons.key_outlined, color: scheme.error),
                actions: [
                  TextButton(
                      onPressed: _openSettings, child: const Text('Set up')),
                ],
              ),
            Expanded(
              child: !_booted
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(children: [
                      InAppWebView(
                      initialUrlRequest:
                          URLRequest(url: WebUri(_normalize(_startUrl))),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        javaScriptCanOpenWindowsAutomatically: false,
                        supportMultipleWindows: false,
                        mediaPlaybackRequiresUserGesture: true,
                        useHybridComposition: true,
                        allowsInlineMediaPlayback: true,
                        isInspectable: false,
                      ),
                      initialUserScripts: UnmodifiableListView<UserScript>([
                        UserScript(
                          source: browserInjectJs,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_END,
                          forMainFrameOnly: true,
                        ),
                      ]),
                      onWebViewCreated: (c) {
                        _web = c;
                        c.addJavaScriptHandler(
                          handlerName: 'aisPrompt',
                          callback: (args) {
                            _onPromptRequest(args);
                            return true;
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'aisTarget',
                          callback: (args) {
                            _onTarget(args);
                            return true;
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'aisMode',
                          callback: (args) {
                            if (mounted) setState(() => _mode = '');
                            return true;
                          },
                        );
                        c.addJavaScriptHandler(
                          handlerName: 'aisGrab',
                          callback: (args) {
                            if (args.length >= 2) {
                              final done = _grabs['${args[0]}'];
                              if (done != null && !done.isCompleted) {
                                done.complete('${args[1] ?? ''}');
                              }
                            }
                            return true;
                          },
                        );
                      },
                      onLoadStart: (c, url) => _syncNav(url),
                      onLoadStop: (c, url) async {
                        await _inject();
                        await _syncNav(url);
                      },
                      onUpdateVisitedHistory: (c, url, _) => _syncNav(url),
                      onProgressChanged: (c, p) {
                        if (mounted) setState(() => _progress = p / 100);
                      },
                    ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _modeFab(scheme, 'target', Icons.gps_fixed,
                                'Target any image, even locked or hidden'),
                            const SizedBox(height: 8),
                            _modeFab(scheme, 'region', Icons.crop_free,
                                'Drag a box to capture any area'),
                          ],
                        ),
                      ),
                    ]),
            ),
            if (_running || _total > 0) _queueBar(scheme),
          ],
        ),
      ),
    );
  }

  Widget _modeFab(
      ColorScheme scheme, String m, IconData icon, String tooltip) {
    final on = _mode == m;
    return FloatingActionButton.small(
      heroTag: 'ais_mode_$m',
      tooltip: tooltip,
      backgroundColor: on ? scheme.primary : scheme.surfaceContainerHighest,
      foregroundColor: on ? scheme.onPrimary : scheme.onSurface,
      onPressed: () => _setMode(on ? '' : m),
      child: Icon(icon),
    );
  }

  Widget _queueBar(ColorScheme scheme) {
    final processed = _done + _failed;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              if (_running)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
              else
                Icon(
                    _failed == 0
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    color: _failed == 0 ? Colors.green : scheme.error,
                    size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _running
                          ? _current
                          : '$_done done${_failed > 0 ? ', $_failed failed' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                        value: _total == 0 ? 0 : processed / _total),
                    if (!_running && _lastError.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(_lastError,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_running)
                TextButton(
                  onPressed: () => setState(() => _cancel = true),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  child: const Text('Cancel'),
                )
              else ...[
                if (_failedTasks.isNotEmpty)
                  TextButton(
                    onPressed: _retryFailed,
                    child: Text('Retry ${_failedTasks.length}'),
                  ),
                TextButton(
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  child: const Text('View prompts'),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _total = 0;
                    _done = 0;
                    _failed = 0;
                    _failedTasks.clear();
                  }),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancel = true;
    for (final g in _grabs.values) {
      if (!g.isCompleted) g.complete('');
    }
    _urlCtrl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }
}
