import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

import 'gemini_api.dart';
import 'secure_store.dart';

/// Gemini Web provider: drives gemini.google.com inside an embedded
/// Edge WebView2 (Windows desktop only) using the user's own Google
/// session - no Gemini API key, no API rate limits.
///
/// How it works (mirrors the proven CI workflow in generator__1.yml):
///  1. The user connects once by signing into Google inside the embedded
///     browser (Settings -> Gemini Web -> Connect). Cookies persist in
///     the WebView2 profile folder, so the session survives restarts.
///  2. Each task opens a fresh chat, uploads the image via JavaScript
///     drag-and-drop simulation, types the prompt via JS, clicks send,
///     then polls the response DOM until it stabilises - exactly like
///     the Playwright workflow, but inside the desktop app.
///
/// Windows-only: every entry point throws [UnsupportedError] elsewhere,
/// and callers must gate UI with [GeminiWeb.isSupported].
class GeminiWeb {
  GeminiWeb._();

  static bool get isSupported => Platform.isWindows;

  static void requireSupported() {
    if (!isSupported) {
      throw UnsupportedError('Gemini Web needs the Windows desktop app.');
    }
  }
}

/// Non-secret Gemini Web preferences (the session cookies themselves
/// live in the WebView2 profile folder, never in prefs).
class GeminiWebPrefs {
  GeminiWebPrefs._();

  /// 'api' (default) or 'web'.
  static Future<String> provider() async =>
      (await _prefs()).getString('meta_provider') ?? 'api';

  static Future<void> setProvider(String v) async =>
      (await _prefs()).setString('meta_provider', v);

  static Future<bool> connected() async =>
      (await _prefs()).getBool('gemini_web_connected') ?? false;

  static Future<void> setConnected(bool v) async =>
      (await _prefs()).setBool('gemini_web_connected', v);

  static Future<SharedPreferences> _prefs() => AppPrefs.prefs();
}

/// One-shot WebView2 environment init. The environment (and its
/// user-data folder, where the Google session cookies live) is shared
/// process-wide and can only be initialised once.
class GeminiWebEnv {
  GeminiWebEnv._();
  static bool _done = false;

  static Future<void> ensure() async {
    GeminiWeb.requireSupported();
    if (_done) return;
    final dir = await getApplicationSupportDirectory();
    final profile =
        Directory('${dir.path}${Platform.pathSeparator}gemini_web_profile');
    await profile.create(recursive: true);
    try {
      await WebviewController.initializeEnvironment(
          userDataPath: profile.path);
    } on PlatformException catch (e) {
      // Already initialised in this process - safe to continue.
      if (!(e.message ?? '').contains('initialized')) rethrow;
    }
    _done = true;
  }

  /// Wipes the profile folder (full disconnect). Call after
  /// [WebviewController.clearCookies] for certainty.
  static Future<void> wipeProfile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final profile =
          Directory('${dir.path}${Platform.pathSeparator}gemini_web_profile');
      if (await profile.exists()) await profile.delete(recursive: true);
    } catch (_) {}
    _done = false;
  }
}

/// JavaScript snippets driving gemini.google.com. Ported from the
/// proven Playwright workflow (generator__1.yml); the plugin's WebView
/// forwards mouse but not keyboard, so everything - login fill, image
/// upload, prompt typing, send - happens through the DOM.
class GeminiWebJs {
  GeminiWebJs._();

  /// True when the Gemini chat input is present (logged in).
  static const loggedIn = '''
(() => !!document.querySelector('div.ql-editor[contenteditable="true"], rich-textarea [contenteditable="true"]'))()
''';

  /// Fill a Google login field the way a password manager would, so the
  /// framework notices the change. Returns 'ok' or 'no-field'.
  static const fillField = '''
((selector, value) => {
  const el = document.querySelector(selector);
  if (!el) return 'no-field';
  el.focus();
  const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  const desc = Object.getOwnPropertyDescriptor(proto, 'value');
  if (desc && desc.set) desc.set.call(el, value); else el.value = value;
  el.dispatchEvent(new Event('input', {bubbles: true}));
  el.dispatchEvent(new Event('change', {bubbles: true}));
  return 'ok';
})
''';

  /// Click the first button whose visible text matches [pattern].
  static const clickButton = '''
((pattern) => {
  const re = new RegExp(pattern, 'i');
  const btn = [...document.querySelectorAll('button')].find(b => re.test((b.textContent || '').trim()));
  if (!btn) return 'no-button';
  btn.click();
  return 'clicked';
})
''';

  static String fill(String selector, String value) =>
      '(${GeminiWebJs.fillField})(${jsonEncode(selector)}, ${jsonEncode(value)})';

  static String click(String pattern) =>
      '(${GeminiWebJs.clickButton})(${jsonEncode(pattern)})';

  /// Google login page detectors.
  static const hasEmailField =
      '''(() => !!document.querySelector('input[type="email"]'))()''';
  static const hasPasswordField =
      '''(() => !!document.querySelector('input[type="password"]'))()''';
  static const hasTotpField = '''(() => !!document.querySelector(
      'input[type="tel"], #totpPin, input[aria-label*="verification" i]'))()''';

  /// Upload an image by simulating a drag-and-drop of a File built from
  /// a data URL (the workflow's strategy C2), falling back to a
  /// clipboard paste (strategy C1). Returns the winning strategy name
  /// or '' when nothing attached.
  static const uploadImage = '''
((dataUrl, filename, mime) => (async () => {
  const toFile = (du, name, type) => {
    const arr = du.split(',');
    const bstr = atob(arr[1]);
    let n = bstr.length;
    const u8 = new Uint8Array(n);
    while (n--) u8[n] = bstr.charCodeAt(n);
    return new File([u8], name, {type});
  };
  const hasAttachment = () => [
    'ms-file-attachment', 'upload-progress-thumbnail',
    '[class*="upload-thumbnail"]', '[class*="file-chip"]',
    '[class*="attachment"]', '[class*="FileChip"]',
    'rich-textarea img', '[data-test-id*="attachment"]',
    '[data-test-id*="upload"]', '.attachment-chip', '.upload-thumbnail',
  ].some(s => document.querySelector(s));
  const delay = ms => new Promise(r => setTimeout(r, ms));
  const file = toFile(dataUrl, filename, mime);
  // C1: clipboard paste into the editor.
  try {
    const editor = document.querySelector('rich-textarea [contenteditable="true"]')
      || document.querySelector('.ql-editor')
      || document.querySelector('[contenteditable="true"]');
    if (editor) {
      editor.focus();
      const dt = new DataTransfer();
      dt.items.add(file);
      editor.dispatchEvent(new ClipboardEvent('paste', {bubbles: true, cancelable: true, clipboardData: dt}));
      await delay(1500);
      if (hasAttachment()) return 'clipboard-paste';
    }
  } catch (e) {}
  // C2: drag-and-drop broadcast onto likely drop targets.
  try {
    const dt = new DataTransfer();
    dt.items.add(file);
    const opts = {bubbles: true, cancelable: true, dataTransfer: dt};
    const targets = [
      document.querySelector('[data-filedrop-id="chat-window-input-container"]'),
      document.querySelector('rich-textarea'),
      document.querySelector('[contenteditable="true"]'),
      document.body,
    ].filter(Boolean);
    for (const el of targets) { el.dispatchEvent(new DragEvent('drop', opts)); await delay(150); }
    await delay(2000);
    if (hasAttachment()) return 'drag-drop';
  } catch (e) {}
  return '';
})())
''';

  /// Type [prompt] into the chat editor like a user paste.
  static const typePrompt = '''
((prompt) => {
  const editor = document.querySelector('div.ql-editor[contenteditable="true"]')
    || document.querySelector('rich-textarea [contenteditable="true"]');
  if (!editor) return 'no-editor';
  editor.focus();
  document.execCommand('selectAll', false, null);
  const ok = document.execCommand('insertText', false, prompt);
  return ok ? 'typed' : 'insert-failed';
})
''';

  /// True when the send button exists and is enabled.
  static const sendReady = '''
(() => {
  const b = [...document.querySelectorAll('button[aria-label]')]
    .find(x => /send message/i.test(x.getAttribute('aria-label') || ''));
  return !!b && !b.disabled && b.getAttribute('aria-disabled') !== 'true';
})()
''';

  /// Click the send button; falls back to dispatching Enter.
  static const clickSend = '''
(() => {
  const b = [...document.querySelectorAll('button[aria-label]')]
    .find(x => /send message/i.test(x.getAttribute('aria-label') || ''));
  if (b && !b.disabled) { b.click(); return 'sent'; }
  const editor = document.querySelector('div.ql-editor[contenteditable="true"]')
    || document.querySelector('rich-textarea [contenteditable="true"]');
  if (editor) {
    editor.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true}));
    return 'enter-dispatched';
  }
  return 'no-send';
})()
''';

  /// {count, text} of the response blocks, newest last.
  static const responseState = '''
(() => {
  const sels = ['div[id^="model-response-message-content"]',
    'div[id^="response-message-content"]', '.response-content-container',
    'message-content', 'div.message-content'];
  const seen = new Set();
  for (const s of sels) document.querySelectorAll(s).forEach(el => seen.add(el));
  const arr = [...seen];
  arr.sort((a, b) => (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) ? -1 : 1);
  const last = arr[arr.length - 1];
  return JSON.stringify({count: seen.size, text: last ? (last.innerText || last.textContent || '').trim() : ''});
})()
''';
}

/// Drives one logged-in Gemini web tab: fresh chat per task, optional
/// image upload, prompt send, response polling.
class GeminiWebClient {
  final WebviewController controller;
  GeminiWebClient(this.controller);

  Future<bool> get isLoggedIn async {
    try {
      return await controller.executeScript(GeminiWebJs.loggedIn) == true;
    } catch (_) {
      return false;
    }
  }

  Future<int> _responseCount() async {
    try {
      final raw = await controller.executeScript(GeminiWebJs.responseState);
      final m = raw is String ? jsonDecode(raw) : raw;
      return (m['count'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Opens a fresh chat and waits for the input to be ready.
  Future<void> gotoFreshChat({void Function(String)? onStatus}) async {
    onStatus?.call('Opening a fresh chat...');
    await controller.loadUrl('https://gemini.google.com/app/new');
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      if (await isLoggedIn) return;
      await Future.delayed(const Duration(seconds: 1));
    }
    throw Exception('Gemini chat did not load - is the session still valid?');
  }

  Future<String> _uploadImage(Uint8List bytes, String filename) async {
    final mime = filename.endsWith('.png') ? 'image/png' : 'image/jpeg';
    final dataUrl =
        'data:$mime;base64,${base64Encode(bytes)}';
    final r = await controller.executeScript(
        '(${GeminiWebJs.uploadImage})(${jsonEncode(dataUrl)}, ${jsonEncode(filename)}, ${jsonEncode(mime)})');
    return (r ?? '').toString();
  }

  Future<void> _typePrompt(String prompt) async {
    final r = await controller.executeScript(
        '(${GeminiWebJs.typePrompt})(${jsonEncode(prompt)})');
    if (r != 'typed') throw Exception('Could not type into the Gemini chat.');
  }

  Future<void> _waitSendReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await controller.executeScript(GeminiWebJs.sendReady) == true) return;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<Map<String, dynamic>> _responseState() async {
    final raw = await controller.executeScript(GeminiWebJs.responseState);
    final m = raw is String ? jsonDecode(raw) : raw;
    return {
      'count': (m['count'] as int?) ?? 0,
      'text': (m['text'] as String?) ?? ''
    };
  }

  /// Polls until the newest response stabilises (or [completeWhen]
  /// matches), mirroring the workflow's stability logic.
  Future<String> _pollResponse(int initialCount, {RegExp? completeWhen}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 150));
    var lastSeen = '';
    var stable = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 1500));
      Map<String, dynamic> st;
      try {
        st = await _responseState();
      } catch (_) {
        continue;
      }
      if ((st['count'] as int) <= initialCount) continue;
      final text = (st['text'] as String).trim();
      if (text.isEmpty) continue;
      if (text == lastSeen) {
        stable++;
        if (stable >= 2 &&
            (completeWhen == null || completeWhen.hasMatch(text))) {
          return text;
        }
      } else {
        lastSeen = text;
        stable = 0;
      }
    }
    throw Exception('Gemini web took too long to answer.');
  }

  /// Runs one full task: fresh chat -> optional image -> prompt -> reply.
  Future<String> runPrompt(
    String prompt, {
    Uint8List? imageBytes,
    String imageName = 'wallpaper.jpg',
    RegExp? completeWhen,
    void Function(String stage)? onStatus,
  }) async {
    await gotoFreshChat(onStatus: onStatus);
    final initialCount = await _responseCount();
    if (imageBytes != null) {
      onStatus?.call('Uploading image to Gemini...');
      final strat = await _uploadImage(imageBytes, imageName);
      if (strat.isEmpty) {
        throw Exception('Could not attach the image to Gemini.');
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    onStatus?.call('Asking Gemini...');
    await _typePrompt(prompt);
    await _waitSendReady();
    final sent = await controller.executeScript(GeminiWebJs.clickSend);
    if (sent != 'sent' && sent != 'enter-dispatched') {
      throw Exception('Could not send the prompt to Gemini.');
    }
    onStatus?.call('Waiting for the answer...');
    return _pollResponse(initialCount, completeWhen: completeWhen);
  }
}

/// Tolerant `[TAG]...[/TAG]` parser, ported from the workflow: Gemini
/// web renders markdown, so tags can arrive as `**[TITLE]**`,
/// `[TITLE]:`, or with a missing closing tag.
String _tagValue(String text, String tag) {
  final t = tag.replaceAll('_', r'[_ \-]?');
  final open =
      RegExp('\\[\\s*$t\\s*\\]\\s*:?', caseSensitive: false);
  final m = open.firstMatch(text);
  if (m == null) return '';
  var rest = text.substring(m.end);
  final close = RegExp('\\[\\s*/\\s*$t\\s*\\]', caseSensitive: false)
      .firstMatch(rest);
  if (close != null) {
    rest = rest.substring(0, close.start);
  } else {
    final nx = RegExp(
            r'\[\s*/?\s*(TITLE|KEYWORDS|CATEGORY|DESCRIPTION|POLICY)\s*\]',
            caseSensitive: false)
        .firstMatch(rest);
    if (nx != null) rest = rest.substring(0, nx.start);
  }
  rest = rest.replaceAll('**', '').trim();
  rest = rest
      .replaceAll(RegExp(r'^`+|`+$'), '')
      .replaceAll(RegExp(r'^\s*:\s*'), '')
      .trim();
  if (rest == '...' || rest == '\u2026') return '';
  return rest;
}

String _cleanTitle(String raw) {
  var t = raw
      .replaceAll(
          RegExp(r'^(here is a title:|title:|the title is:|suggested title:)',
              caseSensitive: false),
          '')
      .trim();
  final q = RegExp(r'"([^"\r\n]{3,60})"').firstMatch(t);
  if (q != null) return q.group(1)!.trim();
  final b = RegExp(r'\*\*([^\*\r\n]{3,60})\*\*').firstMatch(t);
  if (b != null) return b.group(1)!.trim();
  final line = t.split('\n').map((l) => l.trim()).firstWhere((l) {
    final lower = l.toLowerCase();
    return l.isNotEmpty &&
        !lower.startsWith('here') &&
        !lower.startsWith('sure') &&
        !lower.startsWith('based') &&
        !lower.startsWith('suggest') &&
        !lower.startsWith('the') &&
        !lower.startsWith('this');
  }, orElse: () => '');
  t = (line.isNotEmpty ? line : t)
      .replaceAll(RegExp('^["\'*\\s]+|["\'*\\s]+\$'), '')
      .trim();
  return t.length > 30 ? t.substring(0, 30).trim() : t;
}

List<String> _cleanKeywords(String raw) {
  final words = RegExp(r'[a-zA-Z0-9]{2,20}')
      .allMatches(raw)
      .map((m) => m.group(0)!)
      .toList();
  const stop = {
    'here', 'are', 'the', 'keywords', 'based', 'on', 'this', 'image',
    'and', 'for', 'with', 'your', 'wallpaper', 'title', 'tags',
    'single', 'word'
  };
  final out = <String>[];
  for (final w in words) {
    final l = w.toLowerCase();
    if (l.length > 1 && !stop.contains(l) && !out.contains(l)) out.add(l);
    if (out.length == 12) break;
  }
  return out;
}

/// Alias map: words Gemini might reply with -> exact Zedge category.
const _catAliases = <String, List<String>>{
  'ANIMALS': ['ANIMAL', 'ANIMALS', 'WILDLIFE', 'PET', 'PETS', 'BIRD', 'BIRDS', 'CAT', 'DOG'],
  'ANIME': ['ANIME', 'MANGA', 'ANIMATION', 'ANIMATED'],
  'CARS_N_VEHICLES': ['CAR', 'CARS', 'VEHICLE', 'VEHICLES', 'AUTOMOTIVE', 'AUTO', 'TRUCK', 'MOTORCYCLE', 'BIKE', 'TRANSPORT', 'CARS N VEHICLES', 'CARS AND VEHICLES'],
  'COMICS': ['COMIC', 'COMICS', 'SUPERHERO', 'CARTOON', 'CARTOONS', 'ILLUSTRATION'],
  'DESIGNS': ['DESIGN', 'DESIGNS', 'GRAPHIC', 'ABSTRACT', 'ART', 'ARTISTIC', 'GEOMETRIC'],
  'DRAWINGS': ['DRAWING', 'DRAWINGS', 'SKETCH', 'SKETCHES', 'HAND DRAWN', 'PENCIL', 'INK'],
  'ENTERTAINMENT': ['ENTERTAINMENT', 'MOVIE', 'MOVIES', 'FILM', 'TV', 'CELEBRITY', 'CELEBRITIES', 'ACTOR', 'SHOW'],
  'FUNNY': ['FUNNY', 'HUMOR', 'HUMOUR', 'MEME', 'MEMES', 'COMEDY', 'JOKE', 'JOKES'],
  'GAMES': ['GAME', 'GAMES', 'GAMING', 'VIDEO GAME', 'VIDEOGAME', 'ESPORTS', 'GAMER'],
  'HOLIDAYS': ['HOLIDAY', 'HOLIDAYS', 'CHRISTMAS', 'HALLOWEEN', 'EASTER', 'NEW YEAR', 'FESTIVAL', 'CELEBRATION'],
  'LOVE': ['LOVE', 'ROMANCE', 'ROMANTIC', 'HEART', 'HEARTS', 'VALENTINES', 'COUPLE', 'WEDDING'],
  'MUSIC': ['MUSIC', 'MUSICAL', 'SONG', 'SONGS', 'BAND', 'CONCERT', 'INSTRUMENT', 'DJ'],
  'NATURE': ['NATURE', 'NATURAL', 'LANDSCAPE', 'FOREST', 'MOUNTAIN', 'OCEAN', 'FLOWER', 'FLORAL', 'PLANT', 'TREE', 'BEACH', 'SUNSET', 'SKY', 'FOOD', 'TRAVEL', 'CITY', 'ARCHITECTURE'],
  'PATTERNS': ['PATTERN', 'PATTERNS', 'TEXTURE', 'TEXTURES', 'MINIMALIST', 'MINIMAL', 'RETRO', 'VINTAGE'],
  'PEOPLE': ['PEOPLE', 'PERSON', 'PORTRAIT', 'FACE', 'HUMAN', 'MAN', 'WOMAN', 'GIRL', 'BOY'],
  'SAYINGS': ['SAYING', 'SAYINGS', 'QUOTE', 'QUOTES', 'MOTIVATIONAL', 'INSPIRATIONAL', 'TEXT', 'TYPOGRAPHY', 'WORDS'],
  'SPACE': ['SPACE', 'GALAXY', 'UNIVERSE', 'COSMOS', 'STAR', 'STARS', 'PLANET', 'NEBULA', 'ASTRONAUT', 'SCI FI', 'SCIFI', 'SCIENCE FICTION'],
  'SPIRITUAL': ['SPIRITUAL', 'RELIGION', 'RELIGIOUS', 'FAITH', 'GOD', 'MANDALA', 'MEDITATION', 'ZEN', 'BUDDHIST', 'ISLAMIC', 'CHRISTIAN'],
  'SPORTS': ['SPORT', 'SPORTS', 'FOOTBALL', 'BASKETBALL', 'SOCCER', 'TENNIS', 'BASEBALL', 'ATHLETICS', 'FITNESS', 'GYM'],
  'TECHNOLOGY': ['TECHNOLOGY', 'TECH', 'DIGITAL', 'CYBER', 'NEON', 'FUTURISTIC', 'COMPUTER', 'ROBOT', 'CIRCUIT', 'DARK'],
};

String _cleanCategory(String raw) {
  if (raw.isEmpty) return 'DESIGNS';
  final upper = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_\s]'), ' ');
  for (final e in _catAliases.entries) {
    if (e.value.any((a) => upper.contains(a))) return e.key;
  }
  return 'DESIGNS';
}

String _cleanDescription(String raw) {
  var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final q = RegExp(r'^"(.+)"$').firstMatch(t);
  if (q != null) t = q.group(1)!;
  return t.length > 200 ? t.substring(0, 200).trim() : t;
}

/// Vision metadata prompt: Gemini looks at the attached image.
/// [kindContext] describes what the image belongs to (single wallpaper,
/// 24H set, dual set, battery set).
String webMetadataPrompt(String kindContext) {
  final cats = zedgeCategories.join(', ');
  return 'You are an expert image curator and Zedge marketplace compliance reviewer.\n\n'
      'ZEDGE POLICY (a single violation can suspend the seller account):\n'
      '- 100% original work only. Never name or hint at any real artist, brand, franchise, character, logo, celebrity or public figure.\n'
      '- No sexual or suggestive content, hate, violence, weapons, drugs, or anything involving minors.\n'
      '- Metadata must describe ONLY this image. No promo words (free, download, follow...), no URLs, hashtags, emojis or brand names.\n\n'
      '$kindContext\n'
      'Look at the attached image carefully and generate:\n'
      '1. A creative and UNIQUE TITLE (max 30 characters, Title Case, no emoji, no quotes). Avoid generic filler like "beautiful", "amazing", "stunning".\n'
      '2. 8 to 12 relevant single-word KEYWORDS (comma-separated, lowercase, no spaces, no duplicates) covering subject, colors, mood and style. NEVER use the category name (or any word of it, singular or plural) as a keyword.\n'
      '3. The most appropriate CATEGORY, chosen ONLY from this list: $cats.\n'
      '4. A natural DESCRIPTION (1-2 sentences, max 200 characters, no hashtags, no emoji).\n'
      '5. POLICY verdict: write OK if this image is clearly safe and original. Otherwise write FLAG: <short reason> - flag recognizable copyrighted characters, brands/logos, celebrities or real identifiable people, watermarks, sexual/suggestive content, hate symbols, violence, weapons, drugs, apparent minors, or a stretched/blurry/badly-cropped low-quality image.\n\n'
      'CRITICAL: Format your ENTIRE response EXACTLY like this - no other text outside these tags:\n'
      '[TITLE]...[/TITLE]\n'
      '[KEYWORDS]...[/KEYWORDS]\n'
      '[CATEGORY]...[/CATEGORY]\n'
      '[DESCRIPTION]...[/DESCRIPTION]\n'
      '[POLICY]OK or FLAG: reason[/POLICY]';
}

/// Set-kind context lines, mirroring the workflow's KIND_PROMPT_CONTEXT.
String webKindContext(String setType) => switch (setType) {
      '24-HOUR' =>
        'I have attached ONE image from a 24H WALLPAPER SET - 4 wallpapers of the same scene that automatically change through the day (morning, afternoon, evening, night). Write metadata for the WHOLE day-cycle set, not just this single frame.',
      'DUAL' =>
        'I have attached ONE image from a DUAL WALLPAPER SET - a matching lock screen + home screen wallpaper pair. Write metadata that fits the matching pair.',
      'BATTERY' =>
        'I have attached ONE image from a BATTERY WALLPAPER SET - artwork that changes with the phone battery level. Write metadata that fits the whole battery pack.',
      _ => 'I have attached a phone wallpaper image.',
    };

/// Metadata result from Gemini web vision, plus an optional policy
/// flag (null when the verdict was OK).
class WebMetadataResult {
  final SetMetadata meta;
  final String? policyFlag;
  WebMetadataResult(this.meta, this.policyFlag);
}

/// Parse a Gemini web vision reply into metadata + policy flag.
WebMetadataResult parseWebMetadata(String text, {required String file}) {
  final title = _cleanTitle(_tagValue(text, 'TITLE'));
  final tags = _cleanKeywords(_tagValue(text, 'KEYWORDS'));
  final category = _cleanCategory(_tagValue(text, 'CATEGORY'));
  final description = _cleanDescription(_tagValue(text, 'DESCRIPTION'));
  if (title.isEmpty || tags.isEmpty) {
    final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final head = trimmed.substring(0, 120.clamp(0, trimmed.length));
    throw Exception('Gemini web reply was incomplete. Got: $head');
  }
  final policyRaw = _tagValue(text, 'POLICY').trim();
  final flag = policyRaw.toUpperCase().startsWith('OK')
      ? null
      : (policyRaw.isEmpty
          ? null
          : policyRaw
              .replaceAll(
                  RegExp(r'^FLAG:\s*', caseSensitive: false), '')
              .trim());
  final meta = SetMetadata(
    file: file,
    title: title,
    tags: tags,
    category: category,
    description: description,
  );
  return WebMetadataResult(meta, flag?.isEmpty == true ? null : flag);
}

/// Generate vision metadata for one set's representative image.
Future<WebMetadataResult> webMetadataForImage(
  GeminiWebClient client, {
  required Uint8List imageBytes,
  required String file,
  required String setType,
  void Function(String stage)? onStatus,
}) async {
  final text = await client.runPrompt(
    webMetadataPrompt(webKindContext(setType)),
    imageBytes: imageBytes,
    imageName: '$file.jpg',
    completeWhen:
        RegExp(r'\[\s*/\s*POLICY\s*\]', caseSensitive: false),
    onStatus: onStatus,
  );
  return parseWebMetadata(text, file: file);
}

/// Prompt text for the AI Set Director over Gemini web.
String webDirectorPrompt(
    String type, List<String> variantLabels, String prompt) {
  final labels = variantLabels.map((l) => '"$l"').join(', ');
  return 'You are an art director for mobile wallpaper sets. Reply with ONE JSON object only, no markdown, no commentary.\n'
      'Schema: {"arc": string (short evocative arc name), '
      '"anchor": string (one neutral base-scene description fragment, no strong time-of-day or energy bias - it is the chaining reference every variant derives from), '
      '"palette": array of 1-3 lowercase color words actually present in the concept, '
      '"stages": array with one object per variant label in the given order, each {"label": string (the exact label), "direction": string (1-2 sentence visual direction fragment describing ONLY what changes in that stage: light, state, mood, movement - the subject itself stays identical)}}.\n'
      'Rules: never describe text, letters, numbers, symbols, icons, logos or watermarks anywhere. '
      'Each stage MUST be dramatically, unmistakably different from the others: transform ONLY the light and atmosphere boldly '
      '- light direction, color temperature, glow, mist and mood - while keeping the exact same scene, objects, background and composition; '
      'never add, remove or rearrange anything, never near-duplicate moods.\n'
      'Set type: $type. Variant labels in order: $labels.\n\n'
      'User prompt: $prompt\n\n'
      'Return the JSON object now.';
}

/// AI Set Director via Gemini web (text-only task, no image).
Future<SetDirection> webDirectSet(
  GeminiWebClient client, {
  required String type,
  required List<String> variantLabels,
  required String prompt,
  void Function(String stage)? onStatus,
}) async {
  final text = await client.runPrompt(
      webDirectorPrompt(type, variantLabels, prompt),
      onStatus: onStatus);
  return GeminiApi.parseDirection(text, variantLabels);
}
