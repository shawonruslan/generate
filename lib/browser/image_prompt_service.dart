import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../compare/originality.dart';
import '../compare/element_plan.dart';
export '../compare/element_plan.dart' show SceneElement;

import '../gemini_session_manager.dart';
import '../gemini_web.dart';
import '../secure_store.dart';
import '../keep_awake.dart';
import 'chromium_browser.dart';
import 'gecko_prompt_browser.dart';
import 'prompt_browser.dart';

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
    this.hiSrc = '',
    this.preview,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Sharpest version of the picture (largest srcset entry), may be ''.
  final String hiSrc;

  /// Small JPEG thumbnail for captures / snips (they have no URL).
  Uint8List? preview;

  /// Screenshot of a video frame, snipped area or locked picture.
  bool get isCapture => src.startsWith('capture:');

  /// "video", "area", "canvas", "picture" for captures, else "".
  String get captureKind {
    if (!isCapture) return '';
    final p = src.split(':');
    return p.length > 1 ? p[1] : '';
  }

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

  /// Bytes downloaded when the picture was ticked (not persisted), so it
  /// still works after the user navigated away from its page.
  FetchedImage? cached;

  /// One-shot similarity override for a rewrite (not persisted).
  int? forceTarget;

  /// Similarity target (%) the prompt was written for (0 = unknown).
  int target = 0;

  /// Element inventory of the picture with the keep/change plan used
  /// for [prompt] (empty = generic plan).
  List<SceneElement> elements = [];

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
        if (hiSrc.isNotEmpty && hiSrc != src) 'hi': hiSrc,
        if (preview != null) 'pv': base64Encode(preview!),
        if (target > 0) 'tg': target,
        if (elements.isNotEmpty)
          'el': [for (final e in elements) e.toJson()],
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
      hiSrc: (j['hi'] ?? '').toString(),
      preview: _b64(j['pv']),
    )
      ..target = (j['tg'] as num?)?.toInt() ?? 0
      ..elements = [
        if (j['el'] is List)
          for (final e in j['el'] as List)
            if (SceneElement.fromJson(e) case final el?) el
      ];
  }

  static Uint8List? _b64(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    try {
      return base64Decode(v);
    } catch (_) {
      return null;
    }
  }
}

/// Prompts waiting to be dropped into the Batch Sets "Prompts" list. The
/// Batch screen consumes them when it is open (or the next time it opens).
class PromptListBridge {
  PromptListBridge._();
  static final PromptListBridge instance = PromptListBridge._();

  static const _kPending = 'pending_batch_prompts';
  final ValueNotifier<List<String>> pending = ValueNotifier(const []);
  Future<void>? _loading;

  /// Same text = same prompt (case, spacing and trailing dots ignored).
  static String key(String p) => p
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\s.]+$'), '')
      .trim();

  /// Loads prompts left over from the last run (once; every caller waits
  /// for the same load, so nothing is merged twice).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final p = await AppPrefs.prefs();
      final saved = p.getStringList(_kPending) ?? const [];
      if (saved.isNotEmpty) _merge(saved);
    } catch (_) {}
  }

  /// Appends only prompts that are not already waiting.
  bool _merge(Iterable<String> prompts) {
    final seen = pending.value.map(key).toSet();
    final add = <String>[];
    for (final raw in prompts) {
      final t = raw.trim();
      if (t.isEmpty || !seen.add(key(t))) continue;
      add.add(t);
    }
    if (add.isEmpty) return false;
    pending.value = [...pending.value, ...add];
    return true;
  }

  Future<void> _save() async {
    try {
      final p = await AppPrefs.prefs();
      await p.setStringList(_kPending, pending.value);
    } catch (_) {}
  }

  void add(Iterable<String> prompts) {
    if (_merge(prompts)) _save();
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

/// A ticked picture waiting in the cross-page selection.
class BasketItem {
  BasketItem(this.ref, this.pageUrl, this.pageTitle, this.sessionId);
  final WebImageRef ref;
  final String pageUrl;
  final String pageTitle;
  final String sessionId;
  FetchedImage? bytes;
  Future<void>? prefetch;
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
  static const _kInstrRev = 'img_prompt_instruction_rev';
  static const _kCreativity = 'img_prompt_creativity';
  static const _kTarget = 'img_prompt_similarity_target';
  static const _kAntiRepeat = 'img_prompt_anti_repeat';
  static const _kAutoAdd = 'img_prompt_auto_add';
  static const _kExe = 'img_prompt_browser_path';
  static const _kSource = 'img_prompt_cookie_source';
  static const _kHome = 'img_prompt_home_url';

  /// v1.9 default: recreates the picture as closely as possible.
  static const faithfulInstruction =
      'You are a senior prompt engineer and art director for state-of-the-art '
      'text-to-image models (Midjourney v7, FLUX, Imagen 4, GPT-Image, '
      'nano-banana). Analyse the attached image with a professional eye and '
      'write ONE production-ready text-to-image prompt that recreates it as '
      'faithfully as possible.\n\n'
      'Work through these layers in order and fold every one of them into '
      'the prompt:\n'
      '1. Subject - what it is, exact count, pose / action, expression, '
      'clothing, materials and distinctive details.\n'
      '2. Setting - environment, foreground and background elements, time of '
      'day, season, weather.\n'
      '3. Composition - shot type, framing, camera angle, subject placement, '
      'depth layers, orientation (portrait / landscape / square).\n'
      '4. Camera and lens - focal length feel (wide, 35 mm, 85 mm portrait, '
      'macro, aerial), depth of field, bokeh, motion blur or long exposure - '
      'only what is visible.\n'
      '5. Lighting - key light direction and quality, golden hour / studio / '
      'neon / rim light, shadows, reflections, atmosphere (haze, fog, '
      'volumetric rays).\n'
      '6. Colour - dominant palette with precise colour names, contrast, '
      'saturation, colour grading.\n'
      '7. Style and medium - photograph, 3D render, digital painting, anime, '
      'watercolour, vector illustration..., plus the art movement or render '
      'look when evident.\n'
      '8. Texture and detail - surfaces, materials, grain, sharpness.\n'
      '9. Mood - the emotion and story in a few precise adjectives.\n\n'
      'Rules: describe only what is really visible; quote visible text only '
      'when it is clearly part of the design and never add text, logos or '
      'watermarks; do not name real people, brands or copyrighted characters '
      '(describe their look instead); no "this image shows", no lists, no '
      'line breaks, no hashtags, no commentary. Prefer concrete, vivid nouns '
      'and adjectives over vague words. Write one flowing paragraph of '
      '120-200 words, most important elements first, ending with quality '
      'cues (for example "ultra detailed, sharp focus, high dynamic range"). '
      'Return it exactly in this format:\n'
      '[PROMPT]\n<the prompt>\n[/PROMPT]';

  /// v1.9.1 - v1.10 default (fixed "change 4 things"); saved copies are
  /// upgraded to [defaultInstruction].
  static const _creativeInstructionV191 =
      'You are a senior prompt engineer and creative art director for '
      'state-of-the-art text-to-image models (Midjourney v7, FLUX, Imagen 4, '
      'GPT-Image, nano-banana). Study the attached image as a REFERENCE FOR '
      'INSPIRATION ONLY and write ONE production-ready prompt for a NEW, '
      'ORIGINAL image that shares its overall look and feel but is clearly '
      'not a copy of it.\n\n'
      'Step 1 - analyse the reference: subject, setting, composition, '
      'camera and lens, lighting, colour palette, style and medium, texture, '
      'mood.\n'
      'Step 2 - KEEP the transferable qualities: the general genre and theme, '
      'the art style / medium, the lighting approach, the mood and the '
      'overall colour harmony, the level of detail and quality.\n'
      'Step 3 - CHANGE at least four specific elements so the new image is '
      'unmistakably original, for example: a different subject identity '
      '(age, face, hairstyle, outfit, species or object design), a different '
      'pose or action, a new background or location with different props, '
      'a shifted camera angle or framing, a different time of day or '
      'weather, or a re-mixed accent colour. Add one or two fresh creative '
      'touches that are not in the reference (a meaningful prop, an '
      'atmospheric effect, an interesting detail) that fit the theme.\n'
      'Step 4 - write the prompt.\n\n'
      'Rules: the result must NOT reproduce the reference one-to-one; never '
      'copy distinctive, recognisable or trademark designs, characters, '
      'mascots, logos, text, watermarks, signatures or the unique layout of '
      'an artwork; do not name real people, brands, copyrighted characters '
      'or living artists (describe a generic style instead, e.g. "soft '
      'cinematic editorial photography"); never add text or logos. No '
      '"this image shows", no "inspired by the reference", no lists, no line '
      'breaks, no hashtags, no commentary. Prefer concrete, vivid nouns and '
      'adjectives. Write one flowing paragraph of 120-200 words, most '
      'important elements first, covering subject, setting, composition, '
      'camera and lens, lighting, colour, style, texture and mood, ending '
      'with quality cues (for example "ultra detailed, sharp focus, high '
      'dynamic range"). Return it exactly in this format:\n'
      '[PROMPT]\n<the prompt>\n[/PROMPT]';

  /// Default (v1.11+): professional analysis + prompt. How close the new
  /// image stays to the reference is decided ONLY by the similarity
  /// target block appended per picture (see similarityBrief).
  static const defaultInstruction =
      'You are a senior prompt engineer and art director for '
      'state-of-the-art text-to-image models (Midjourney v7, FLUX, Imagen 4, '
      'GPT-Image, nano-banana). Analyse the attached reference image with a '
      'professional eye, then write ONE production-ready text-to-image '
      'prompt for a new image that follows the SIMILARITY TARGET given '
      'below exactly - it decides what stays identical and what changes.\n\n'
      'Analyse these layers and fold every one of them into the prompt (as '
      'kept or as changed, according to the target):\n'
      '1. Subject - what it is, count, variety / identity, pose, expression, '
      'clothing, colours, materials, distinctive details.\n'
      '2. Setting - environment, foreground and background elements, time of '
      'day, season, weather.\n'
      '3. Composition - shot type, framing, camera angle, subject placement, '
      'depth layers, orientation.\n'
      '4. Camera and lens - focal length feel, depth of field, bokeh, motion.\n'
      '5. Lighting - key light direction and quality, shadows, reflections, '
      'atmosphere.\n'
      '6. Colour - dominant palette with precise colour names, contrast, '
      'saturation, grading.\n'
      '7. Style and medium - photograph, 3D render, painting, anime, '
      'illustration..., plus the render look.\n'
      '8. Texture and detail - surfaces, materials, grain, sharpness.\n'
      '9. Mood - the emotion in a few precise adjectives.\n\n'
      'Rules: never copy logos, text, watermarks, signatures or '
      'recognisable trademark characters; do not name real people, brands, '
      'copyrighted characters or living artists (describe a generic look '
      'instead); never add text. No "this image shows", no lists, no line '
      'breaks, no hashtags, no commentary. Prefer concrete, vivid nouns and '
      'adjectives. Write one flowing paragraph of 120-200 words, most '
      'important elements first, ending with quality cues (for example '
      '"ultra detailed, sharp focus, high dynamic range"). Return it exactly '
      'in this format:\n'
      '[PROMPT]\n<the prompt>\n[/PROMPT]';

  /// The short instruction of v1.0-v1.8; saved copies are upgraded.
  static const _legacyInstruction =
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

  /// Test hook: replaces the Gemini call (bytes -> reply).
  @visibleForTesting
  static Future<String> Function(Uint8List bytes)? debugAnswer;

  final List<ImagePromptItem> items = [];

  /// Pictures ticked in the browser, across pages / sites / tabs.
  final List<BasketItem> basket = [];
  PromptBrowser? _browser;
  StreamSubscription? _reqSub;
  StreamSubscription? _chgSub;

  String instruction = defaultInstruction;
  bool autoAddToList = true;

  /// How similar (%) the new image should stay to its reference.
  int similarityTarget = defaultSimilarityTarget;

  /// Rewrite a prompt once when it reads like an earlier one.
  bool antiRepeat = true;

  /// Batch: generate from the reference picture and retry until the
  /// measured similarity is near the target.
  bool matchTarget = true;

  /// Extra images allowed per set anchor while matching (0-3).
  int matchTries = 2;
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

  PromptBrowser? get browser => _browser;

  /// Windows / desktop: Chromium window. Android: built-in Firefox engine.
  static bool get browserSupported =>
      ChromiumBrowser.supported || GeckoPromptBrowser.supported;

  /// True on Android (touch UI, built-in browser).
  static bool get builtInBrowser => GeckoPromptBrowser.supported;
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
      final rev = p.getInt(_kInstrRev) ?? 0;
      if (instruction.trim().isEmpty ||
          instruction == _legacyInstruction ||
          instruction == _creativeInstructionV191 ||
          (instruction == faithfulInstruction && rev < 3)) {
        // Built-in texts move to the target-driven default (closeness is
        // now set with the similarity target, not inside the text).
        instruction = defaultInstruction;
      }
      if (rev < 3) {
        await p.setString(_kInstruction, instruction);
        await p.setInt(_kInstrRev, 3);
      }
      autoAddToList = p.getBool(_kAutoAdd) ?? true;
      final oldLevel = p.getString(_kCreativity);
      similarityTarget = p.getInt(_kTarget) ??
          (oldLevel == null
              ? defaultSimilarityTarget
              : CreativityLevel.values
                  .firstWhere((c) => c.name == oldLevel,
                      orElse: () => CreativityLevel.balanced)
                  .target);
      similarityTarget = similarityTarget
          .clamp(minSimilarityTarget, maxSimilarityTarget);
      antiRepeat = p.getBool(_kAntiRepeat) ?? true;
      matchTarget = p.getBool('img_prompt_match_target') ?? true;
      matchTries = (p.getInt('img_prompt_match_tries') ?? 2).clamp(0, 3);
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
    int? similarityTarget,
    bool? antiRepeat,
    bool? matchTarget,
    int? matchTries,
    String? browserPath,
    String? homeUrl,
    GeminiCookieSource? cookieSource,
  }) async {
    if (instruction != null) {
      this.instruction =
          instruction.trim().isEmpty ? defaultInstruction : instruction;
    }
    if (autoAddToList != null) this.autoAddToList = autoAddToList;
    if (similarityTarget != null) {
      this.similarityTarget =
          similarityTarget.clamp(minSimilarityTarget, maxSimilarityTarget);
    }
    if (antiRepeat != null) this.antiRepeat = antiRepeat;
    if (matchTarget != null) this.matchTarget = matchTarget;
    if (matchTries != null) this.matchTries = matchTries.clamp(0, 3);
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
      await p.setInt(_kTarget, this.similarityTarget);
      await p.setBool(_kAntiRepeat, this.antiRepeat);
      await p.setBool('img_prompt_match_target', this.matchTarget);
      await p.setInt('img_prompt_match_tries', this.matchTries);
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
    status = builtInBrowser ? 'Opening the browser...' : 'Starting Chromium...';
    notifyListeners();
    try {
      final PromptBrowser b;
      if (builtInBrowser) {
        b = GeckoPromptBrowser.instance;
        await b.openTab(target);
      } else {
        b = await ChromiumBrowser.launch(
            preferredExecutable: browserPath, startUrl: target);
      }
      _browser = b;
      _reqSub = b.requests.listen(_onRequest);
      if (basket.isNotEmpty) _basketChanged();
      _chgSub = b.changes.listen((_) {
        if (!b.isConnected) {
          status = 'Browser closed.';
          _dropBrowser();
        }
        notifyListeners();
      });
      status = 'Connected to ${b.displayName}';
    } catch (e) {
      lastError = '$e';
      status = '';
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  @visibleForTesting
  void debugAttach(PromptBrowser b) {
    _browser = b;
    _reqSub = b.requests.listen(_onRequest);
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

  /// Google refuses sign-in in a DevTools-controlled window, so sign-in
  /// runs in the same profile started as a plain browser. When the user
  /// closes that window, the controlled browser reopens already signed in.
  bool signingIn = false;

  /// Closes the controlled window so the profile can start as a plain
  /// browser (Google refuses sign-in in a DevTools-controlled window).
  Future<void> closeBrowserForSignIn() async {
    if (builtInBrowser || !browserConnected) return;
    final b = _browser;
    await _dropBrowser();
    await b?.closeBrowser();
    _client = null;
    _clientKey = '';
    notifyListeners();
    await Future.delayed(const Duration(seconds: 2));
  }

  Future<void> signInToGoogle() async {
    if (signingIn) return;
    signingIn = true;
    lastError = '';
    if (builtInBrowser) {
      // Android: the built-in Firefox engine sign-in screen (same engine
      // profile as the browser, so the browser is signed in too).
      status = 'Sign in to Google in the opened screen...';
      notifyListeners();
      try {
        final s = await GeminiSessionManager.signInWithBrowser();
        _client = null;
        _clientKey = '';
        status = s != null
            ? 'Signed in - Gemini session saved.'
            : 'Not signed in to Google.';
      } catch (e) {
        lastError = '$e';
        status = '';
      } finally {
        signingIn = false;
        notifyListeners();
      }
      return;
    }
    if (browserConnected) {
      final b = _browser;
      await _dropBrowser();
      await b?.closeBrowser();
      await Future.delayed(const Duration(seconds: 2));
    }
    status = 'Sign in to Google in the opened window, then CLOSE that '
        'window to continue.';
    notifyListeners();
    try {
      await ChromiumBrowser.launchPlain(preferredExecutable: browserPath);
      _client = null;
      _clientKey = '';
      status = 'Signed-in window closed. Reopening the browser...';
      signingIn = false;
      notifyListeners();
      await open(homeUrl);
    } catch (e) {
      lastError = '$e';
      status = '';
    } finally {
      signingIn = false;
      notifyListeners();
    }
  }

  /// Android: brings the built-in browser screen back (same page).
  Future<void> showBrowser() async {
    final b = _browser;
    if (b is GeckoPromptBrowser) {
      await b.show();
    } else {
      await open(homeUrl);
    }
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
    switch (r.action) {
      case 'select':
        for (final ref in r.images) {
          if (basket.any((b) => b.ref.src == ref.src)) continue;
          final it = BasketItem(ref, r.pageUrl, r.pageTitle, r.sessionId);
          basket.add(it);
          // Download now, while the picture is still on screen.
          it.prefetch = _fetchBest(ref.src, ref.hi, r.sessionId, r.pageUrl)
              .then<void>((f) {
            it.bytes = f;
          }, onError: (_) {});
        }
        _basketChanged();
        return;
      case 'unselect':
        final drop = r.images.map((i) => i.src).toSet();
        basket.removeWhere((b) => drop.contains(b.ref.src));
        _basketChanged();
        return;
      case 'clear_basket':
        clearBasket();
        return;
      case 'generate_basket':
        generateBasket();
        return;
      case 'capture':
        _capture(r);
        return;
    }
    _enqueue(r);
  }

  /// Video frame / snipped area / locked picture: the browser screenshots
  /// the area and the shot is queued like any other picture.
  Future<void> _capture(WebImageRequest r) async {
    final b = _browser;
    for (final ref in r.images) {
      Uint8List? png;
      try {
        png = await b?.captureRegion(r.sessionId, ref.meta);
      } catch (_) {}
      if (png == null || png.isEmpty) {
        b?.notifyPage(r.sessionId, ref.src, 'error', 'Could not capture that area');
        status = 'Capture failed - scroll it fully into view and try again.';
        notifyListeners();
        continue;
      }
      final it = ImagePromptItem(
        id: '${DateTime.now().microsecondsSinceEpoch}-c',
        src: ref.src,
        pageUrl: r.pageUrl,
        pageTitle: r.pageTitle,
        alt: ref.alt,
        sessionId: r.sessionId,
      )..cached = FetchedImage(png, 'image/png');
      it.preview = await _thumbInBackground(png);
      items.insert(0, it);
      b?.notifyPage(r.sessionId, ref.src, 'queued');
      status = '${_captureLabel(it.captureKind)} captured and queued.';
    }
    notifyListeners();
    _saveItems();
    _pump();
  }

  static String _captureLabel(String kind) => switch (kind) {
        'video' => 'Video frame',
        'area' => 'Snipped area',
        'canvas' => 'Canvas',
        _ => 'Picture',
      };

  static Future<Uint8List?> _thumbInBackground(Uint8List png) =>
      Isolate.run(() {
        try {
          final d = img.decodeImage(png);
          if (d == null) return null;
          final t = d.width >= d.height
              ? img.copyResize(d, width: 240)
              : img.copyResize(d, height: 240);
          return Uint8List.fromList(img.encodeJpg(t, quality: 78));
        } catch (_) {
          return null;
        }
      });

  void _basketChanged() {
    final pages = basket.map((b) => b.pageUrl).toSet().length;
    _browser?.setBasket([for (final b in basket) b.ref.src], pages);
    status = basket.isEmpty
        ? status
        : '${basket.length} picture${basket.length == 1 ? '' : 's'} selected'
            ' from $pages page${pages == 1 ? '' : 's'}.';
    notifyListeners();
  }

  void clearBasket() {
    basket.clear();
    _basketChanged();
  }

  void removeFromBasket(BasketItem b) {
    basket.remove(b);
    _basketChanged();
  }

  /// Queues every ticked picture (all pages) and empties the selection.
  Future<void> generateBasket() async {
    if (basket.isEmpty) return;
    final list = List<BasketItem>.from(basket);
    basket.clear();
    _basketChanged();
    var n = 0;
    for (final b in list) {
      if (_known(b.ref.src)) continue;
      items.insert(
          0,
          ImagePromptItem(
            id: '${DateTime.now().microsecondsSinceEpoch}-b$n',
            src: b.ref.src,
            pageUrl: b.pageUrl,
            pageTitle: b.pageTitle,
            alt: b.ref.alt,
            sessionId: b.sessionId,
            hiSrc: b.ref.hi,
          )..cached = b.bytes);
      n++;
      _browser?.notifyPage(b.sessionId, b.ref.src, 'queued');
    }
    status = '$n picture${n == 1 ? '' : 's'} queued.';
    notifyListeners();
    _saveItems();
    // Late prefetches still fill the cache before their turn comes.
    for (final b in list) {
      b.prefetch?.then((_) {
        for (final i in items) {
          if (i.src == b.ref.src && i.cached == null) i.cached = b.bytes;
        }
      });
    }
    _pump();
  }

  /// Already waiting, running, or finished with a prompt (use "Generate
  /// again" in the app to redo a finished one).
  bool _known(String src) => items.any((i) =>
      i.src == src &&
      (i.state == ImagePromptState.queued ||
          i.state == ImagePromptState.running ||
          i.state == ImagePromptState.done));

  void _enqueue(WebImageRequest r) {
    var added = 0;
    var skipped = 0;
    for (final ref in r.images) {
      if (_known(ref.src)) {
        skipped++;
        final done = items.firstWhere((i) => i.src == ref.src);
        _browser?.notifyPage(r.sessionId, ref.src, done.state.name,
            done.state == ImagePromptState.done ? 'Prompt already generated' : '');
        continue;
      }
      items.insert(
          0,
          ImagePromptItem(
            id: '${DateTime.now().microsecondsSinceEpoch}-$added',
            src: ref.src,
            pageUrl: r.pageUrl,
            pageTitle: r.pageTitle,
            alt: ref.alt,
            sessionId: r.sessionId,
            hiSrc: ref.hi,
          ));
      added++;
      _browser?.notifyPage(r.sessionId, ref.src, 'queued');
    }
    if (added == 0) {
      if (skipped > 0) {
        status = skipped == 1
            ? 'That picture already has a prompt (use Generate again to redo).'
            : '$skipped pictures already have prompts.';
        notifyListeners();
      }
      return;
    }
    status = added == 1 ? 'Picture queued.' : '$added pictures queued.';
    notifyListeners();
    _saveItems();
    _pump();
  }

  void retry(ImagePromptItem it) {
    if (it.state == ImagePromptState.running) return;
    if (it.state == ImagePromptState.done) it.addedToList = false;
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

  /// Sends finished prompts to the Batch Sets list. Prompts that were
  /// already sent are skipped unless [force] (explicit "add again").
  int addToList(Iterable<ImagePromptItem> list, {bool force = false}) {
    final picked = list
        .where((i) =>
            i.state == ImagePromptState.done &&
            i.prompt.isNotEmpty &&
            (force || !i.addedToList))
        .toList();
    if (picked.isEmpty) return 0;
    PromptListBridge.instance.add(picked.map((i) => i.prompt));
    for (final i in picked) {
      i.addedToList = true;
    }
    notifyListeners();
    _saveItems();
    return picked.length;
  }

  Future<GeminiWebClient> _gemini() async {
    // Saved cookie session from Settings.
    Future<GeminiWebClient?> saved() async {
      final raw = await GeminiWebStore.load();
      if (raw.trim().isEmpty) return null;
      if (_clientKey == 'saved:${raw.hashCode}' && _client != null) {
        return _client;
      }
      late final GeminiWebClient c;
      c = GeminiSessionManager.clientFor(GeminiWebSession.parse(raw),
          onSaved: (json) {
        // Renewed cookies were saved: keep using this (warm) client.
        if (identical(_client, c)) _clientKey = 'saved:${json.hashCode}';
      });
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
      // Signed in once in the browser = cookie JSON saved automatically
      // (Settings, Batch Sets, and copy to Android).
      try {
        final only = geminiCookiesOnly(cookies);
        if (only.isNotEmpty) {
          await GeminiWebStore.save(
              GeminiWebSession.fromCookieList(only).toStorageJson());
        }
      } catch (_) {}
      geminiNote = 'Gemini runs inside the signed-in browser window';
      return GeminiWebClient(s,
          onSessionUpdated: (x) {
            GeminiWebStore.save(x.toStorageJson());
          },
          refreshSession: GeminiSessionManager.refreshFromBrowser,
          // Requests run in a gemini.google.com tab of the window itself:
          // the browser keeps and renews its own login.
          transport: b is GeminiPageTransport ? b as GeminiPageTransport : null);
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
    // Android: keep generating with the screen off.
    KeepAwake.start('prompts', 'Image to Prompt',
        text: '$queuedCount queued', total: items.length);
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
        KeepAwake.progress('prompts',
            text: '$queuedCount queued', done: items.length - queuedCount,
            total: items.length);
        await _process(next);
        if (lastError.isNotEmpty) break; // session problem: pause queue
        if (queuedCount > 0) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
    } finally {
      KeepAwake.stop('prompts');
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
      final pic = await _download(it);
      unawaited(_saveReference(it.id, pic.bytes));
      final target = (it.forceTarget ?? similarityTarget)
          .clamp(minSimilarityTarget, maxSimilarityTarget);
      final rewrite = it.forceTarget != null && it.prompt.isNotEmpty;
      it.forceTarget = null;
      // The similarity target is appended to EVERY instruction (built-in
      // or custom) and overrides any closeness rule inside it.
      final seed = it.id.hashCode ^ DateTime.now().microsecondsSinceEpoch;
      // 1) Element inventory of THIS picture (reused on rewrites), then
      //    the keep/change plan for the target.
      var els = it.elements;
      if (els.length < 5 && debugAnswer == null) {
        status = 'Listing the elements of the picture...';
        notifyListeners();
        try {
          final reply = await (await _gemini()).askWithImage(
            elementInventoryInstruction,
            pic.bytes,
            filename: pic.mimeType == 'image/png' ? 'image.png' : 'image.jpg',
            mimeType: pic.mimeType,
            completeWhen:
                RegExp(r'\\?\[/ELEMENTS\\?\]', caseSensitive: false),
          );
          els = parseElements(reply);
        } on GeminiWebException catch (e) {
          if (e.expired) rethrow;
          els = [];
        } catch (_) {
          els = [];
        }
      }
      if (els.length >= 5) planElements(els, target);
      status = 'Writing the prompt...';
      notifyListeners();
      Future<String> ask(String boost) {
        final brief = els.length >= 5
            ? elementBrief(els, target, boost: boost)
            : similarityBrief(target, seed, boost: boost);
        final full = '$instruction$brief';
        final hook = debugAnswer;
        if (hook != null) return hook(pic.bytes);
        return _gemini().then((g) => g.askWithImage(
              full,
              pic.bytes,
              filename:
                  pic.mimeType == 'image/png' ? 'image.png' : 'image.jpg',
              mimeType: pic.mimeType,
              completeWhen: full.contains('[/PROMPT]')
                  ? RegExp(r'\\?\[/PROMPT\\?\]', caseSensitive: false)
                  : null,
            ));
      }

      final previous = it.prompt;
      final remix = rewrite && previous.isNotEmpty;
      var prompt = extractPrompt(await ask(remix
          ? 'This is a rewrite: the previous prompt for this picture was '
              'written for ${it.target > 0 ? '${it.target}%' : 'another'} '
              'similarity; follow the new $target% target strictly.'
          : ''));
      if (prompt.isEmpty) throw GeminiWebException('Gemini returned no prompt.');
      // Anti-repeat: look-alike pictures must not give look-alike prompts.
      // Skipped for close targets (there the prompt SHOULD follow the
      // picture closely).
      if (antiRepeat && target <= 75 && !remix) {
        final others = <String>[
          for (final o in items)
            if (!identical(o, it) &&
                o.state == ImagePromptState.done &&
                o.prompt.isNotEmpty)
              o.prompt,
        ].take(40).toList();
        final sim = maxPromptSimilarity(prompt, others);
        final limit = target >= 60 ? 0.55 : 0.45;
        if (sim > limit) {
          status = 'Prompt read like an earlier one '
              '(${(sim * 100).round()}%), rewriting it...';
          notifyListeners();
          final again = extractPrompt(await ask(
              'Your first answer was ${(sim * 100).round()}% identical in '
              'wording to another prompt of this session. Keep the same '
              '$target% similarity to THIS reference, but vary the wording '
              'and the changed elements so it does not repeat that prompt.'));
          if (again.isNotEmpty && maxPromptSimilarity(again, others) < sim) {
            prompt = again;
          }
        }
      }
      it.target = target;
      it.elements = els.length >= 5 ? els : [];
      if (remix && previous.isNotEmpty) it.addedToList = false;
      it.prompt = prompt;
      it.state = ImagePromptState.done;
      if (!it.isCapture) it.cached = null; // free memory (captures keep theirs)
      if (autoAddToList && !it.addedToList) {
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

  // ------------------------------------------------------ compare support
  static Directory? _refDir;

  static Future<File> _refFile(String id) async {
    final d = _refDir ??= Directory(
        '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}prompt_refs');
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${d.path}${Platform.pathSeparator}$safe.jpg');
  }

  /// Keeps a 768 px JPEG of every analysed picture so the result can be
  /// compared later (also after restarts, and for captures).
  Future<void> _saveReference(String id, Uint8List bytes) async {
    try {
      final jpg = await Isolate.run(() {
        final d = img.decodeImage(bytes);
        if (d == null) return null;
        final t = d.width >= d.height
            ? (d.width > 768 ? img.copyResize(d, width: 768) : d)
            : (d.height > 768 ? img.copyResize(d, height: 768) : d);
        return Uint8List.fromList(img.encodeJpg(t, quality: 88));
      });
      if (jpg == null) return;
      final f = await _refFile(id);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(jpg, flush: true);
    } catch (_) {}
  }

  /// Best available bytes of the reference picture of [it].
  Future<Uint8List?> referenceBytes(ImagePromptItem it) async {
    try {
      final f = await _refFile(it.id);
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    if (it.cached != null) return it.cached!.bytes;
    for (final u in [it.hiSrc, it.src]) {
      if (!u.startsWith('http')) continue;
      try {
        final r = await http.get(Uri.parse(u), headers: {
          'User-Agent': 'Mozilla/5.0',
          if (it.pageUrl.startsWith('http')) 'Referer': it.pageUrl,
        }).timeout(const Duration(seconds: 30));
        if (r.statusCode == 200 && r.bodyBytes.length > 500) {
          return r.bodyBytes;
        }
      } catch (_) {}
    }
    return it.preview;
  }

  /// The Image-to-Prompt item whose prompt produced [generatedPrompt]
  /// (set prompts carry extra suffixes, so containment is enough).
  ImagePromptItem? referenceFor(String generatedPrompt) {
    final g = PromptListBridge.key(generatedPrompt);
    if (g.isEmpty) return null;
    ImagePromptItem? best;
    var bestScore = 0.0;
    for (final it in items) {
      if (it.prompt.isEmpty) continue;
      final k = PromptListBridge.key(it.prompt);
      if (k.length < 20) continue;
      final score = g.contains(k)
          ? 1.0 + k.length / 100000
          : promptSimilarity(it.prompt, generatedPrompt);
      if (score > bestScore) {
        bestScore = score;
        best = it;
      }
    }
    return bestScore >= 0.6 ? best : null;
  }

  /// Re-writes the prompt of [it] for another similarity [target];
  /// the new prompt is added to the batch list again.
  void rewriteWithTarget(ImagePromptItem it, int target) {
    it.forceTarget = target.clamp(minSimilarityTarget, maxSimilarityTarget);
    it.state = ImagePromptState.queued;
    it.error = '';
    status = 'Rewriting the prompt for ${it.forceTarget}% similarity...';
    notifyListeners();
    _saveItems();
    _pump();
  }

  /// "More original": 20 points less similar than before.
  void remixMoreOriginal(ImagePromptItem it) => rewriteWithTarget(
      it, (it.target > 0 ? it.target : similarityTarget) - 20);

  /// Professional visual review by Gemini: both pictures side by side
  /// (A = reference, B = new) with a strict scoring format.
  Future<AiCompareReview> aiReview(Uint8List reference, Uint8List generated) async {
    final sheet = await Isolate.run(() => _compareSheet(reference, generated));
    if (sheet == null) throw GeminiWebException('Could not read the pictures.');
    final reply = await (await _gemini()).askWithImage(
      aiReviewInstruction,
      sheet,
      filename: 'compare.jpg',
      mimeType: 'image/jpeg',
      completeWhen: RegExp(r'\\?\[/REVIEW\\?\]', caseSensitive: false),
    );
    return AiCompareReview.parse(reply);
  }

  static const aiReviewInstruction =
      'You are an art director and copyright-risk reviewer for a wallpaper '
      'store. The attached sheet shows two pictures side by side: A (left) '
      'is the REFERENCE found online, B (right) is the NEW AI-generated '
      'picture made from a prompt inspired by A. Judge only what you see. '
      'Score how similar B is to A as a whole (0 = completely unrelated, '
      '100 = the same picture), weighing: subject identity and design, '
      'pose, composition and framing, background and props, colour palette, '
      'lighting, style/medium, and any distinctive or protectable element '
      '(characters, logos, unique artwork layout). Shared genre or mood '
      'alone is NOT copying. Return exactly this format and nothing else:\n'
      '[REVIEW]\n'
      'similarity: <0-100>\n'
      'risk: <low|medium|high>\n'
      'verdict: <one professional sentence>\n'
      'kept: <3-5 short items separated by ; - what B shares with A>\n'
      'changed: <3-5 short items separated by ; - what B does differently>\n'
      'advice: <one sentence: what to change to make B more original, or "none">\n'
      '[/REVIEW]';

  static Uint8List? _compareSheet(Uint8List a, Uint8List b) {
    final ia = img.decodeImage(a), ib = img.decodeImage(b);
    if (ia == null || ib == null) return null;
    const h = 900, gap = 28, top = 44;
    final ra = img.copyResize(ia, height: h, interpolation: img.Interpolation.average);
    final rb = img.copyResize(ib, height: h, interpolation: img.Interpolation.average);
    final sheet = img.Image(width: ra.width + rb.width + gap * 3, height: h + top + gap);
    img.fill(sheet, color: img.ColorRgb8(24, 24, 28));
    img.compositeImage(sheet, ra, dstX: gap, dstY: top);
    img.compositeImage(sheet, rb, dstX: gap * 2 + ra.width, dstY: top);
    final white = img.ColorRgb8(255, 255, 255);
    img.drawString(sheet, 'A - REFERENCE', font: img.arial24, x: gap, y: 10, color: white);
    img.drawString(sheet, 'B - NEW', font: img.arial24, x: gap * 2 + ra.width, y: 10, color: white);
    return Uint8List.fromList(img.encodeJpg(sheet, quality: 90));
  }

  Future<FetchedImage> _download(ImagePromptItem it) async {
    final b = _browser;
    FetchedImage raw;
    if (it.cached != null) {
      raw = it.cached!;
    } else if (it.isCapture && await _refFile(it.id).then((f) => f.exists())) {
      raw = FetchedImage(await (await _refFile(it.id)).readAsBytes(), 'image/jpeg');
    } else if (it.isCapture) {
      throw GeminiWebException('This capture is no longer in memory '
          '(app was restarted) - capture it again.');
    } else {
      try {
        raw = await _fetchBest(it.src, it.hiSrc, it.sessionId, it.pageUrl);
      } catch (e) {
        // Locked / protected picture: screenshot it in its tab instead.
        final shot = (b != null && b.isConnected)
            ? await b.captureElement(it.src, it.sessionId)
            : null;
        if (shot == null) rethrow;
        raw = FetchedImage(shot, 'image/png');
        it.preview ??= await _thumbInBackground(shot);
      }
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

  /// Sharp srcset version first, then the shown picture.
  Future<FetchedImage> _fetchBest(
      String src, String hi, String sessionId, String pageUrl) async {
    final b = _browser;
    Future<FetchedImage> one(String u) => (b != null && b.isConnected)
        ? b.fetchImage(u, sessionId: sessionId, pageUrl: pageUrl)
        : ChromiumBrowser.fetchDirect(u, pageUrl);
    if (hi.isNotEmpty && hi != src) {
      try {
        final f = await one(hi);
        if (f.bytes.length > 1024) return f;
      } catch (_) {}
    }
    return one(src);
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
    // Gemini web citation markers: [cite: 1], [cite: 1, 2], [cite_start].
    t = t
        .replaceAll(RegExp(r'\[cite(?:_start|_end)?(?::[^\]]*)?\]',
            caseSensitive: false), '')
        .replaceAllMapped(RegExp(r'[ \t]+([.,;:!?])'), (m) => m.group(1)!);
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


/// Parsed Gemini visual review of a reference vs generated picture.
class AiCompareReview {
  AiCompareReview({
    required this.similarity,
    required this.risk,
    required this.verdict,
    required this.kept,
    required this.changed,
    required this.advice,
  });
  final int similarity;
  final String risk;
  final String verdict;
  final List<String> kept;
  final List<String> changed;
  final String advice;

  static AiCompareReview parse(String reply) {
    var t = reply.replaceAll(r'\[', '[').replaceAll(r'\]', ']');
    final m = RegExp(r'\[REVIEW\]([\s\S]*?)(\[/REVIEW\]|$)', caseSensitive: false)
        .firstMatch(t);
    if (m != null) t = m.group(1)!;
    String field(String k) {
      final r = RegExp('^\\s*[*_]*$k[*_]*\\s*[:=-]\\s*(.+)\$',
              caseSensitive: false, multiLine: true)
          .firstMatch(t);
      return (r?.group(1) ?? '').replaceAll('**', '').trim();
    }

    List<String> list(String k) => field(k)
        .split(RegExp(r'\s*;\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final sim = int.tryParse(
            RegExp(r'\d{1,3}').firstMatch(field('similarity'))?.group(0) ?? '') ??
        -1;
    if (sim < 0) {
      throw GeminiWebException('Gemini did not return a similarity score.');
    }
    final risk = field('risk').toLowerCase();
    return AiCompareReview(
      similarity: sim.clamp(0, 100),
      risk: risk.contains('high')
          ? 'high'
          : risk.contains('med')
              ? 'medium'
              : 'low',
      verdict: field('verdict'),
      kept: list('kept'),
      changed: list('changed'),
      advice: field('advice'),
    );
  }
}
