import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../gemini_web.dart';
import '../secure_store.dart';
import 'chromium_browser.dart';

enum ImagePromptState { queued, running, done, error }

/// One web picture -> prompt job.
class ImagePromptItem {
  ImagePromptItem({
    required this.id,
    required this.src,
    required this.pageUrl,
    this.pageTitle = '',
    this.alt = '',
    this.state = ImagePromptState.queued,
    this.prompt = '',
    this.error = '',
    this.addedToList = false,
    DateTime? createdAt,
    this.sessionId = '',
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String src;
  final String pageUrl;
  final String pageTitle;
  final String alt;
  ImagePromptState state;
  String prompt;
  String error;
  bool addedToList;
  final DateTime createdAt;

  /// CDP session of the tab the picture came from (not persisted).
  String sessionId;

  bool get isThumbnailable =>
      src.startsWith('http://') || src.startsWith('https://');

  Map<String, dynamic> toJson() => {
        'id': id,
        'src': src.startsWith('data:') && src.length > 4096 ? '' : src,
        'page': pageUrl,
        'title': pageTitle,
        'alt': alt,
        'state': state.name,
        'prompt': prompt,
        'error': error,
        'added': addedToList,
        'at': createdAt.millisecondsSinceEpoch,
      };

  static ImagePromptItem? fromJson(dynamic j) {
    if (j is! Map) return null;
    var st = ImagePromptState.values.firstWhere(
        (s) => s.name == j['state'],
        orElse: () => ImagePromptState.error);
    // Jobs that never finished before the app closed come back as failed
    // (retryable) instead of silently restarting.
    var err = (j['error'] ?? '').toString();
    if (st == ImagePromptState.queued || st == ImagePromptState.running) {
      st = ImagePromptState.error;
      err = 'Interrupted (app was closed). Retry to run it again.';
    }
    return ImagePromptItem(
      id: (j['id'] ?? '').toString(),
      src: (j['src'] ?? '').toString(),
      pageUrl: (j['page'] ?? '').toString(),
      pageTitle: (j['title'] ?? '').toString(),
      alt: (j['alt'] ?? '').toString(),
      state: st,
      prompt: (j['prompt'] ?? '').toString(),
      error: err,
      addedToList: j['added'] == true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (j['at'] as num?)?.toInt() ?? 0),
    );
  }
}

/// Prompts waiting to be dropped into the Batch Sets "Prompts" list. The
/// Batch screen consumes them when it is open (or the next time it opens).
class PromptListBridge {
  PromptListBridge._();
  static final PromptListBridge instance = PromptListBridge._();

  static const _kPending = 'pending_batch_prompts';
  final ValueNotifier<List<String>> pending = ValueNotifier(const []);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await AppPrefs.prefs();
      final saved = p.getStringList(_kPending) ?? const [];
      if (saved.isNotEmpty) pending.value = [...pending.value, ...saved];
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await AppPrefs.prefs();
      await p.setStringList(_kPending, pending.value);
    } catch (_) {}
  }

  void add(Iterable<String> prompts) {
    final clean =
        prompts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (clean.isEmpty) return;
    pending.value = [...pending.value, ...clean];
    _save();
  }

  /// Hands every pending prompt to the caller and empties the queue.
  List<String> take() {
    final out = pending.value;
    if (out.isEmpty) return const [];
    pending.value = const [];
    _save();
    return out;
  }
}

/// Where the Gemini web cookies come from.
enum GeminiCookieSource { auto, chromium, saved }

/// App-wide service: owns the Chromium connection, the picture queue
/// (processed strictly one by one) and the finished prompt list.
class ImagePromptService extends ChangeNotifier {
  ImagePromptService._();
  static final ImagePromptService instance = ImagePromptService._();

  static const _kItems = 'img_prompt_items';
  static const _kInstruction = 'img_prompt_instruction';
  static const _kAutoAdd = 'img_prompt_auto_add';
  static const _kExe = 'img_prompt_browser_path';
  static const _kSource = 'img_prompt_cookie_source';
  static const _kHome = 'img_prompt_home_url';

  static const defaultInstruction =
      'You are an expert prompt engineer for AI image generators '
      '(Midjourney, Flux, Imagen, nano-banana). Study the attached image '
      'and write ONE detailed text-to-image prompt that would recreate it '
      'as closely as possible. Cover: main subject and details, '
      'composition and framing, camera angle / lens, lighting, colour '
      'palette, art style or medium, mood, background and textures. '
      'Do not mention that this is a reference image, do not name real '
      'people, no lists, no commentary. Write a single paragraph of 60-120 '
      'words. Return it exactly in this format:\n'
      '[PROMPT]\n<the prompt>\n[/PROMPT]';

  final List<ImagePromptItem> items = [];
  ChromiumBrowser? _browser;
  StreamSubscription? _reqSub;
  StreamSubscription? _chgSub;

  String instruction = defaultInstruction;
  bool autoAddToList = true;
  String browserPath = '';
  String homeUrl = 'https://www.pinterest.com/';
  GeminiCookieSource cookieSource = GeminiCookieSource.auto;

  bool connecting = false;
  bool _working = false;
  bool _stopRequested = false;
  String status = '';
  String lastError = '';
  String geminiNote = '';

  GeminiWebClient? _client;
  String _clientKey = '';
  bool _loaded = false;

  ChromiumBrowser? get browser => _browser;
  bool get browserConnected => _browser?.isConnected ?? false;
  bool get working => _working;
  int get queuedCount =>
      items.where((i) => i.state == ImagePromptState.queued).length;
  int get doneCount =>
      items.where((i) => i.state == ImagePromptState.done).length;
  ImagePromptItem? get runningItem {
    for (final i in items) {
      if (i.state == ImagePromptState.running) return i;
    }
    return null;
  }

  // -------------------------------------------------------------- storage
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await PromptListBridge.instance.load();
    try {
      final p = await AppPrefs.prefs();
      instruction = p.getString(_kInstruction) ?? defaultInstruction;
      if (instruction.trim().isEmpty) instruction = defaultInstruction;
      autoAddToList = p.getBool(_kAutoAdd) ?? true;
      browserPath = p.getString(_kExe) ?? '';
      homeUrl = p.getString(_kHome) ?? homeUrl;
      cookieSource = GeminiCookieSource.values.firstWhere(
          (s) => s.name == p.getString(_kSource),
          orElse: () => GeminiCookieSource.auto);
      final raw = p.getString(_kItems);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final j in list) {
            final it = ImagePromptItem.fromJson(j);
            if (it != null) items.add(it);
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _saveItems() async {
    try {
      final p = await AppPrefs.prefs();
      final keep = items.take(400).map((i) => i.toJson()).toList();
      await p.setString(_kItems, jsonEncode(keep));
    } catch (_) {}
  }

  Future<void> saveSettings({
    String? instruction,
    bool? autoAddToList,
    String? browserPath,
    String? homeUrl,
    GeminiCookieSource? cookieSource,
  }) async {
    if (instruction != null) {
      this.instruction =
          instruction.trim().isEmpty ? defaultInstruction : instruction;
    }
    if (autoAddToList != null) this.autoAddToList = autoAddToList;
    if (browserPath != null) this.browserPath = browserPath.trim();
    if (homeUrl != null) this.homeUrl = homeUrl.trim();
    if (cookieSource != null) {
      this.cookieSource = cookieSource;
      _client = null;
      _clientKey = '';
    }
    notifyListeners();
    try {
      final p = await AppPrefs.prefs();
      await p.setString(_kInstruction, this.instruction);
      await p.setBool(_kAutoAdd, this.autoAddToList);
      await p.setString(_kExe, this.browserPath);
      await p.setString(_kHome, this.homeUrl);
      await p.setString(_kSource, this.cookieSource.name);
    } catch (_) {}
  }

  // -------------------------------------------------------------- browser
  static String normalizeUrl(String input) {
    var u = input.trim();
    if (u.isEmpty) return 'https://www.google.com/';
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(u)) return u;
    if (!u.contains(' ') && u.contains('.')) return 'https://$u';
    return 'https://www.google.com/search?tbm=isch&q=${Uri.encodeQueryComponent(u)}';
  }

  /// Opens [url] in the controlled Chromium window, starting it if needed.
  Future<void> open(String url) async {
    final target = normalizeUrl(url);
    lastError = '';
    if (browserConnected) {
      try {
        await _browser!.openTab(target);
        return;
      } catch (_) {
        await _dropBrowser();
      }
    }
    connecting = true;
    status = 'Starting Chromium...';
    notifyListeners();
    try {
      final b = await ChromiumBrowser.launch(
          preferredExecutable: browserPath, startUrl: target);
      _browser = b;
      _reqSub = b.requests.listen(_onRequest);
      _chgSub = b.changes.listen((_) {
        if (!b.isConnected) {
          status = 'Browser closed.';
          _dropBrowser();
        }
        notifyListeners();
      });
      status = 'Connected to ${_exeName(b.executable)}';
    } catch (e) {
      lastError = '$e';
      status = '';
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  static String _exeName(String path) {
    final n = path.split(RegExp(r'[\\/]')).last.toLowerCase();
    if (n.contains('msedge')) return 'Microsoft Edge';
    if (n.contains('brave')) return 'Brave';
    if (path.toLowerCase().contains('chromium')) return 'Chromium';
    return 'Google Chrome';
  }

  Future<void> _dropBrowser() async {
    await _reqSub?.cancel();
    await _chgSub?.cancel();
    _reqSub = null;
    _chgSub = null;
    _browser = null;
    if (_clientKey == 'chromium') {
      _client = null;
      _clientKey = '';
    }
    notifyListeners();
  }

  Future<void> closeBrowser() async {
    final b = _browser;
    await _dropBrowser();
    await b?.closeBrowser();
    status = 'Browser closed.';
    notifyListeners();
  }

  // ---------------------------------------------------------------- queue
  void _onRequest(WebImageRequest r) {
    var added = 0;
    for (final ref in r.images) {
      // Skip a picture that is already waiting / being analysed.
      final dup = items.any((i) =>
          i.src == ref.src &&
          (i.state == ImagePromptState.queued ||
              i.state == ImagePromptState.running));
      if (dup) continue;
      items.insert(
          0,
          ImagePromptItem(
            id: '${DateTime.now().microsecondsSinceEpoch}-$added',
            src: ref.src,
            pageUrl: r.pageUrl,
            pageTitle: r.pageTitle,
            alt: ref.alt,
            sessionId: r.sessionId,
          ));
      added++;
      _browser?.notifyPage(r.sessionId, ref.src, 'queued');
    }
    if (added == 0) return;
    status = added == 1 ? 'Picture queued.' : '$added pictures queued.';
    notifyListeners();
    _saveItems();
    _pump();
  }

  void retry(ImagePromptItem it) {
    if (it.state == ImagePromptState.running) return;
    it.state = ImagePromptState.queued;
    it.error = '';
    notifyListeners();
    _pump();
  }

  void retryFailed() {
    for (final it in items) {
      if (it.state == ImagePromptState.error) {
        it.state = ImagePromptState.queued;
        it.error = '';
      }
    }
    notifyListeners();
    _pump();
  }

  void remove(ImagePromptItem it) {
    if (it.state == ImagePromptState.running) return;
    items.remove(it);
    notifyListeners();
    _saveItems();
  }

  void clearFinished() {
    items.removeWhere((i) =>
        i.state == ImagePromptState.done || i.state == ImagePromptState.error);
    notifyListeners();
    _saveItems();
  }

  /// Stops after the picture that is currently being analysed; the rest
  /// stay queued and continue with [resume].
  void stop() {
    if (!_working) return;
    _stopRequested = true;
    status = 'Stopping after the current picture...';
    notifyListeners();
  }

  void resume() => _pump();

  void updatePrompt(ImagePromptItem it, String text) {
    it.prompt = text;
    _saveItems();
    notifyListeners();
  }

  void addToList(Iterable<ImagePromptItem> list) {
    final picked = list
        .where((i) => i.state == ImagePromptState.done && i.prompt.isNotEmpty)
        .toList();
    PromptListBridge.instance.add(picked.map((i) => i.prompt));
    for (final i in picked) {
      i.addedToList = true;
    }
    notifyListeners();
    _saveItems();
  }

  Future<GeminiWebClient> _gemini() async {
    // Saved cookie session from Settings.
    Future<GeminiWebClient?> saved() async {
      final raw = await GeminiWebStore.load();
      if (raw.trim().isEmpty) return null;
      if (_clientKey == 'saved:${raw.hashCode}' && _client != null) {
        return _client;
      }
      final c = GeminiWebClient(GeminiWebSession.parse(raw));
      _clientKey = 'saved:${raw.hashCode}';
      geminiNote = 'Saved Gemini web session (Settings)';
      return c;
    }

    // Live cookies of the controlled Chromium profile.
    Future<GeminiWebClient?> chromium() async {
      final b = _browser;
      if (b == null || !b.isConnected) return null;
      final cookies = await b.googleCookies();
      final s = GeminiWebSession.fromCookieList(cookies);
      if (!s.authCookies.contains('__Secure-1PSID')) return null;
      if (_clientKey == 'chromium' && _client != null) return _client;
      _clientKey = 'chromium';
      geminiNote = 'Live Gemini cookies from the Chromium window';
      return GeminiWebClient(s);
    }

    GeminiWebClient? c;
    switch (cookieSource) {
      case GeminiCookieSource.chromium:
        c = await chromium();
        break;
      case GeminiCookieSource.saved:
        c = await saved();
        break;
      case GeminiCookieSource.auto:
        try {
          c = await chromium();
        } catch (_) {}
        c ??= await saved();
        break;
    }
    if (c == null) {
      throw GeminiWebException(
          cookieSource == GeminiCookieSource.saved
              ? 'No Gemini web session saved. Paste it in Settings.'
              : 'No Gemini session: sign in to gemini.google.com in the '
                  'opened Chromium window, or paste a cookie session in '
                  'Settings.',
          expired: true);
    }
    _client = c;
    return c;
  }

  Future<void> _pump() async {
    if (_working) return;
    _working = true;
    _stopRequested = false;
    lastError = '';
    notifyListeners();
    try {
      while (!_stopRequested) {
        ImagePromptItem? next;
        for (final i in items.reversed) {
          // oldest first
          if (i.state == ImagePromptState.queued) {
            next = i;
            break;
          }
        }
        if (next == null) break;
        await _process(next);
        if (lastError.isNotEmpty) break; // session problem: pause queue
        if (queuedCount > 0) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
    } finally {
      _working = false;
      final q = queuedCount;
      status = lastError.isNotEmpty
          ? 'Paused: $lastError'
          : (q > 0 ? 'Stopped. $q still queued.' : 'All done.');
      _stopRequested = false;
      notifyListeners();
      _saveItems();
    }
  }

  Future<void> _process(ImagePromptItem it) async {
    it.state = ImagePromptState.running;
    it.error = '';
    final total = items
        .where((i) =>
            i.state == ImagePromptState.queued ||
            i.state == ImagePromptState.running)
        .length;
    status = 'Analyzing picture... ($total left)';
    notifyListeners();
    _browser?.notifyPage(it.sessionId, it.src, 'running');
    try {
      final client = await _gemini();
      final pic = await _download(it);
      final reply = await client.askWithImage(
        instruction,
        pic.bytes,
        filename: pic.mimeType == 'image/png' ? 'image.png' : 'image.jpg',
        mimeType: pic.mimeType,
        completeWhen: instruction.contains('[/PROMPT]')
            ? RegExp(r'\\?\[/PROMPT\\?\]', caseSensitive: false)
            : null,
      );
      final prompt = extractPrompt(reply);
      if (prompt.isEmpty) throw GeminiWebException('Gemini returned no prompt.');
      it.prompt = prompt;
      it.state = ImagePromptState.done;
      if (autoAddToList) {
        PromptListBridge.instance.add([prompt]);
        it.addedToList = true;
      }
      _browser?.notifyPage(it.sessionId, it.src, 'done', prompt);
    } on GeminiWebException catch (e) {
      it.state = ImagePromptState.error;
      it.error = e.message;
      if (e.expired) {
        lastError = e.message;
        _client = null;
        _clientKey = '';
      }
      _browser?.notifyPage(it.sessionId, it.src, 'error', e.message);
    } catch (e) {
      it.state = ImagePromptState.error;
      it.error = '$e';
      _browser?.notifyPage(it.sessionId, it.src, 'error', '$e');
    }
    notifyListeners();
    _saveItems();
  }

  Future<FetchedImage> _download(ImagePromptItem it) async {
    final b = _browser;
    FetchedImage raw;
    if (b != null && b.isConnected) {
      raw = await b.fetchImage(it.src,
          sessionId: it.sessionId, pageUrl: it.pageUrl);
    } else {
      // Browser gone (e.g. retry after restart): plain download.
      raw = await ChromiumBrowser.fetchDirect(it.src, it.pageUrl);
    }
    final prepared = await _prepareInBackground(raw.bytes, raw.mimeType);
    if (prepared != null) return prepared;
    // Format the image package cannot read (AVIF / SVG / HEIC): let
    // Chromium rasterize it.
    if (b != null && b.isConnected) {
      final png = await b.rasterizeInPage(it.src, it.sessionId);
      if (png != null) return FetchedImage(png, 'image/png');
    }
    throw GeminiWebException(
        'Unsupported picture format (${raw.mimeType}).');
  }

  static Future<FetchedImage?> _prepareInBackground(
          Uint8List bytes, String mime) =>
      Isolate.run(() => _prepare(bytes, mime));

  /// JPEG/PNG/WebP under 2048 px pass through; anything else is decoded,
  /// down-scaled to 2048 px and re-encoded as JPEG. Returns null when the
  /// format cannot be decoded.
  static FetchedImage? _prepare(Uint8List bytes, String mime) {
    const passThrough = {'image/jpeg', 'image/png', 'image/webp'};
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {}
    if (decoded == null) {
      return passThrough.contains(mime) ? FetchedImage(bytes, mime) : null;
    }
    final big = decoded.width > 2048 || decoded.height > 2048;
    if (!big && passThrough.contains(mime) && mime != 'image/webp') {
      return FetchedImage(bytes, mime);
    }
    var out = decoded;
    if (big) {
      out = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: 2048)
          : img.copyResize(decoded, height: 2048);
    }
    if (out.hasAlpha) {
      final bg = img.Image(width: out.width, height: out.height);
      img.fill(bg, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(bg, out);
      out = bg;
    }
    return FetchedImage(
        Uint8List.fromList(img.encodeJpg(out, quality: 92)), 'image/jpeg');
  }

  /// Pulls the prompt out of Gemini's reply ([PROMPT]...[/PROMPT], with or
  /// without markdown escaping); falls back to the cleaned reply.
  static String extractPrompt(String reply) {
    var t = reply.replaceAll(r'\[', '[').replaceAll(r'\]', ']');
    final m = RegExp(r'\[PROMPT\]([\s\S]*?)\[/PROMPT\]', caseSensitive: false)
        .firstMatch(t);
    if (m != null) {
      t = m.group(1)!;
    } else {
      t = t.replaceAll(RegExp(r'\[/?PROMPT\]', caseSensitive: false), '');
    }
    t = t
        .replaceAll(RegExp(r'^```[a-z]*\s*', multiLine: true), '')
        .replaceAll('```', '')
        .replaceAll(RegExp(r'^\s*(\*\*)?prompt(\*\*)?\s*:\s*',
            caseSensitive: false), '')
        .replaceAll('**', '')
        .trim();
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      t = t.substring(1, t.length - 1).trim();
    }
    return t.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
  }
}
