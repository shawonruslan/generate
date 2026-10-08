import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart';

import 'gemini_api.dart';
import 'secure_store.dart';

/// Gemini Web provider: drives gemini.google.com inside an embedded
/// browser using the user's own Google session - no Gemini API key,
/// no API rate limits.
///
///  - Windows: Edge WebView2 (webview_windows), session cookies persist
///    in a private WebView2 profile folder.
///  - Android: system WebView (webview_flutter) in desktop user-agent
///    mode, session cookies persist via the platform cookie manager.
///
/// How it works (mirrors the proven CI workflow in generator__1.yml):
///  1. The user connects once by signing into Google inside the embedded
///     browser (Settings -> Gemini Web -> Connect).
///  2. Each task opens a fresh chat, uploads the image via JavaScript
///     drag-and-drop simulation, types the prompt via JS, clicks send,
///     then polls the response DOM until it stabilises - exactly like
///     the Playwright workflow, but inside the app.
///
/// Windows + Android: every entry point throws [UnsupportedError]
/// elsewhere, and callers must gate UI with [GeminiWeb.isSupported].
class GeminiWeb {
  GeminiWeb._();

  static bool get isSupported => Platform.isWindows || Platform.isAndroid;

  static void requireSupported() {
    if (!isSupported) {
      throw UnsupportedError(
          'Gemini Web needs the Windows or Android app.');
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

/// One-shot WebView2 environment init (Windows). The environment (and
/// its user-data folder, where the Google session cookies live) is
/// shared process-wide and can only be initialised once.
/// On Android there is nothing to initialise - the system WebView and
/// its cookie manager are always available.
///
/// IMPORTANT: the WebView2 environment is released when its LAST
/// controller is disposed. Every page that creates a Gemini controller
/// must call [controllerCreated] after creating it and
/// [controllerReleased] when disposing it; otherwise the next page
/// silently gets a fresh default profile and the Google session
/// "disappears" even though the cookies are safe on disk.
class GeminiWebEnv {
  GeminiWebEnv._();
  static bool _done = false;
  static int _aliveControllers = 0;

  static Future<void> ensure() async {
    GeminiWeb.requireSupported();
    if (_done) return;
    if (Platform.isAndroid) {
      _done = true;
      return;
    }
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

  /// Call right after a Gemini WebView controller is created.
  static void controllerCreated() => _aliveControllers++;

  /// Call when a Gemini WebView controller is disposed. Drops the
  /// init flag once no controller is alive, so the next [ensure]
  /// re-attaches the SAME user-data folder instead of falling back
  /// to an empty default profile.
  static void controllerReleased() {
    if (_aliveControllers > 0) _aliveControllers--;
    if (_aliveControllers == 0) _done = false;
  }

  /// Full disconnect: wipes the session.
  ///  - Windows: deletes the WebView2 profile folder (call after
  ///    [WebviewController.clearCookies] for certainty).
  ///  - Android: clears the WebView cookie store.
  static Future<void> wipeProfile() async {
    if (Platform.isAndroid) {
      try {
        await wf.WebViewCookieManager().clearCookies();
      } catch (_) {}
      return;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final profile =
          Directory('${dir.path}${Platform.pathSeparator}gemini_web_profile');
      if (await profile.exists()) await profile.delete(recursive: true);
    } catch (_) {}
    _done = false;
  }
}

/// Platform-agnostic handle over an embedded browser tab: execute a
/// JavaScript snippet and get its decoded result, or navigate.
abstract class GeminiWebDriver {
  Future<dynamic> js(String script);
  Future<void> loadUrl(String url);
}

/// [GeminiWebDriver] over a webview_windows [WebviewController].
/// NOTE: the plugin's executeScript already JSON-decodes the WebView2
/// result into Dart values - do NOT decode again here (a second
/// jsonDecode throws on bools and breaks every check).
class WindowsGeminiWebDriver implements GeminiWebDriver {
  final WebviewController controller;
  WindowsGeminiWebDriver(this.controller);

  @override
  Future<dynamic> js(String script) async {
    final result = await controller.executeScript(script);
    if (result == null) throw Exception('No response from the browser.');
    return result;
  }

  @override
  Future<void> loadUrl(String url) => controller.loadUrl(url);
}

/// JavaScript snippets driving gemini.google.com. Ported from the
/// proven Playwright workflow (generator__1.yml); the plugin's WebView
/// forwards mouse but not keyboard, so everything - login fill, image
/// upload, prompt typing, send - happens through the DOM.
class GeminiWebJs {
  GeminiWebJs._();

  /// True when the Gemini page shows the signed-in Google profile
  /// avatar (sidenav-mavatar-footer). That element only renders for a
  /// logged-in session, so it is the most direct signal - simpler and
  /// sturdier than editor-DOM selectors.
  static const loggedIn = '''
(() => !!document.querySelector(
    'sidenav-mavatar-footer img.mavatar-image, a[aria-label^="Google Account:"]'))()
''';




  /// True when the chat editor is present and ready for typing.
  static const editorPresent = '''
(() => !!document.querySelector('div.ql-editor[contenteditable="true"], rich-textarea [contenteditable="true"]'))()
''';

  /// Upload an image, strategies aligned with the workflow
  /// (generator__1.yml `uploadImageToGemini`):
  ///  A. Click the "Open upload file menu" button, then assign the File
  ///     to the revealed input[type=file] via DataTransfer (the
  ///     workflow's primary setInputFiles strategy, adapted - there is
  ///     no Playwright here) and dispatch change.
  ///  C1. Clipboard paste into the editor.
  ///  C2. Drag-and-drop broadcast (dragenter/dragover/drop).
  ///  C3. File-input override on any existing hidden inputs.
  /// Returns the winning strategy name or '' when nothing attached.
  /// Upload an image, strategies aligned with the workflow
  /// (generator__1.yml `uploadImageToGemini`):
  ///  A. Click the "Open upload file menu" button, then assign the File
  ///     to the revealed input[type=file] via DataTransfer (the
  ///     workflow's primary setInputFiles strategy, adapted - there is
  ///     no Playwright here) and dispatch change.
  ///  C1. Clipboard paste into the editor.
  ///  C2. Drag-and-drop broadcast (dragenter/dragover/drop).
  ///  C3. File-input override on any existing hidden inputs.
  /// A strategy only wins when a NEW attachment chip appears in the DOM
  /// AND its upload finishes. Inline editor images ('rich-textarea img')
  /// are deliberately NOT counted: a clipboard paste can drop the image
  /// inline into the editor, which looks like success but sends the
  /// prompt with no image attached ("No image was attached to your
  /// request").
  /// Returns the winning strategy name or '' when nothing attached.
  /// Upload an image, strategies aligned with the workflow
  /// (generator__1.yml `uploadImageToGemini`):
  ///  A. Click the "Open upload file menu" button, then assign the File
  ///     to the revealed input[type=file] via DataTransfer (the
  ///     workflow's primary setInputFiles strategy, adapted - there is
  ///     no Playwright here) and dispatch change.
  ///  C1. Clipboard paste into the editor.
  ///  C2. Drag-and-drop broadcast (dragenter/dragover/drop).
  ///  C3. File-input override on any existing hidden inputs.
  ///
  /// Protocol (background-tab safe): [uploadInit] installs helpers on
  /// the page; [uploadAttempt] performs ONE step's DOM actions
  /// synchronously and returns immediately - no page-side waiting.
  /// All waiting happens on the Dart side ([GeminiWebClient._uploadImage]
  /// polls [uploadState]), because Chromium throttles page timers when
  /// the window loses focus, which used to stall the automation until
  /// focus returned.
  ///
  /// A strategy only wins when a NEW attachment chip appears in the DOM
  /// AND its upload finishes. Inline editor images ('rich-textarea img')
  /// are deliberately NOT counted: a clipboard paste can drop the image
  /// inline into the editor, which looks like success but sends the
  /// prompt with no image attached ("No image was attached to your
  /// request").
  static const uploadInit = '''
(() => {
  const toFile = (du, name, type) => {
    const arr = du.split(',');
    const bstr = atob(arr[1]);
    let n = bstr.length;
    const u8 = new Uint8Array(n);
    while (n--) u8[n] = bstr.charCodeAt(n);
    return new File([u8], name, {type});
  };
  const chipSels = [
    'ms-file-attachment', 'upload-progress-thumbnail',
    '[class*="upload-thumbnail"]', '[class*="file-chip"]',
    '[class*="attachment"]', '[class*="FileChip"]',
    '[jsname][class*="chip"]',
    '[data-test-id*="attachment"]', '[data-test-id*="upload"]',
    '.attachment-chip', '.upload-thumbnail',
  ];
  const allFileInputs = () => {
    const out = [...document.querySelectorAll('input[type="file"]')];
    const walk = (root) => {
      try {
        root.querySelectorAll('*').forEach(el => {
          if (el.shadowRoot) {
            out.push(...el.shadowRoot.querySelectorAll('input[type="file"]'));
            walk(el.shadowRoot);
          }
        });
      } catch (e) {}
    };
    walk(document);
    return [...new Set(out)];
  };
  const setFiles = (inp, file) => {
    const dt = new DataTransfer();
    dt.items.add(file);
    try { inp.files = dt.files; }
    catch (e) { Object.defineProperty(inp, 'files', {value: dt.files, configurable: true}); }
    inp.dispatchEvent(new Event('change', {bubbles: true}));
    inp.dispatchEvent(new Event('input', {bubbles: true}));
  };
  const findUploadBtn = () => {
    const btnSels = [
      'button[aria-label="Open upload file menu"]',
      'button[aria-label="Upload file"]',
      'button[aria-label="Add image"]',
      'button[aria-label="Attach files"]',
      '[aria-label="Open upload file menu"]',
      '[data-test-id="upload-button"]',
    ];
    for (const s of btnSels) {
      const b = document.querySelector(s);
      if (b) return b;
    }
    return [...document.querySelectorAll('button, [role="button"]')].find(el => {
      const label = (el.getAttribute('aria-label') || '').toLowerCase();
      return label.includes('upload') || label.includes('attach')
        || label.includes('add file') || label.includes('add image');
    }) || null;
  };
  const findEditor = () =>
    document.querySelector('rich-textarea [contenteditable="true"]')
      || document.querySelector('.ql-editor')
      || document.querySelector('[contenteditable="true"]');
  const chipState = () => {
    let chips = 0;
    for (const s of chipSels) {
      try { chips += document.querySelectorAll(s).length; } catch (e) {}
    }
    let uploading = false;
    try {
      uploading = !!document.querySelector(
        'upload-progress-thumbnail, [class*="upload-progress"], [class*="uploading"]');
    } catch (e) {}
    // Backgrounded pages get their timers throttled by Chromium, so
    // Gemini's own file-processing stalls while hidden. The Dart side
    // does not count hidden time against the upload timeout.
    const hidden = document.visibilityState === 'hidden' ? '1' : '0';
    return chips + '|' + (uploading ? '1' : '0') + '|' + hidden;
  };
  window.__up = {toFile, allFileInputs, setFiles, findUploadBtn, findEditor, chipState};
  return 'ok';
})()
''';

  /// Performs one upload step's DOM actions and returns immediately.
  /// Returns the step name when its preconditions held, else ''.
  static const uploadAttempt = '''
((dataUrl, filename, mime, step) => {
  const up = window.__up;
  if (!up) return '';
  const file = up.toFile(dataUrl, filename, mime);
  if (step === 'upload-button-click') {
    const btn = up.findUploadBtn();
    if (!btn) return '';
    btn.click();
    return step;
  }
  if (step === 'upload-button-assign' || step === 'file-input-override') {
    const inputs = up.allFileInputs();
    if (!inputs.length) return '';
    inputs.forEach(inp => { try { up.setFiles(inp, file); } catch (e) {} });
    return step;
  }
  if (step === 'clipboard-paste') {
    const editor = up.findEditor();
    if (!editor) return '';
    editor.focus();
    const dt = new DataTransfer();
    dt.items.add(file);
    editor.dispatchEvent(new ClipboardEvent('paste', {bubbles: true, cancelable: true, clipboardData: dt}));
    return step;
  }
  if (step === 'drag-enter') {
    const dt = new DataTransfer();
    dt.items.add(file);
    window.__upDt = dt;
    const opts = {bubbles: true, cancelable: true, dataTransfer: dt};
    const targets = [
      document.querySelector('[data-filedrop-id="chat-window-input-container"]'),
      document.querySelector('file-drop-indicator'),
      document.querySelector('.input-area-container'),
      document.querySelector('.input-area'),
      document.querySelector('rich-textarea'),
      document.querySelector('[contenteditable="true"]'),
      document.querySelector('fieldset'),
      document.body,
    ].filter(Boolean);
    for (const el of targets) {
      try { el.dispatchEvent(new DragEvent('dragenter', opts)); } catch (e) {}
      try { el.dispatchEvent(new DragEvent('dragover', opts)); } catch (e) {}
    }
    try { document.dispatchEvent(new DragEvent('dragenter', opts)); } catch (e) {}
    try { window.dispatchEvent(new DragEvent('dragover', opts)); } catch (e) {}
    return step;
  }
  if (step === 'drag-drop') {
    const dt = window.__upDt;
    if (!dt) return '';
    const opts = {bubbles: true, cancelable: true, dataTransfer: dt};
    const targets = [
      document.querySelector('[data-filedrop-id="chat-window-input-container"]'),
      document.querySelector('file-drop-indicator'),
      document.querySelector('.input-area-container'),
      document.querySelector('.input-area'),
      document.querySelector('rich-textarea'),
      document.querySelector('[contenteditable="true"]'),
      document.querySelector('fieldset'),
      document.body,
    ].filter(Boolean);
    for (const el of targets) {
      try { el.dispatchEvent(new DragEvent('drop', opts)); } catch (e) {}
    }
    try { document.dispatchEvent(new DragEvent('drop', opts)); } catch (e) {}
    try { window.dispatchEvent(new DragEvent('drop', opts)); } catch (e) {}
    window.__upDt = null;
    return step;
  }
  return '';
})
''';

  /// Sync attachment read for Dart-side polling:
  /// 'chips|uploading|hidden'.
  static const uploadState = '''
(() => {
  const up = window.__up;
  if (!up) return '0|0|0';
  return up.chipState();
})()
''';

  /// True when the page is hidden (background tab - Chromium throttles
  /// its timers, so Gemini's streaming can stall until visible again).
  static const pageHidden = '''
(document.visibilityState === 'hidden')
''';

  /// True when a real attachment chip is present in the composer
  /// (same selectors as the upload verifier - inline editor images
  /// are not attachments).
  static const attachmentPresent = '''
(() => [
  'ms-file-attachment', 'upload-progress-thumbnail',
  '[class*="upload-thumbnail"]', '[class*="file-chip"]',
  '[class*="attachment"]', '[class*="FileChip"]',
  '[jsname][class*="chip"]',
  '[data-test-id*="attachment"]', '[data-test-id*="upload"]',
  '.attachment-chip', '.upload-thumbnail',
].some(s => { try { return !!document.querySelector(s); } catch (e) { return false; } }))()
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

/// Drives one logged-in Gemini web tab through a [GeminiWebDriver]:
/// fresh chat per task, optional image upload, prompt send, response
/// polling. Platform-agnostic - the driver wraps WebView2 on Windows
/// and the system WebView (desktop user-agent mode) on Android.
class GeminiWebClient {
  final GeminiWebDriver _driver;
  GeminiWebClient(this._driver);

  Future<bool> get isLoggedIn async {
    try {
      return await _driver.js(GeminiWebJs.loggedIn) == true;
    } catch (_) {
      return false;
    }
  }

  Future<int> _responseCount() async {
    try {
      final raw = await _driver.js(GeminiWebJs.responseState);
      final m = raw is String ? jsonDecode(raw) : raw;
      return (m['count'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Opens a fresh chat and waits for the input to be ready.
  Future<void> gotoFreshChat({void Function(String)? onStatus}) async {
    onStatus?.call('Opening a fresh chat...');
    await _driver.loadUrl('https://gemini.google.com/app/new');
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      if (await isLoggedIn) return;
      await Future.delayed(const Duration(seconds: 1));
    }
    throw Exception('Gemini chat did not load - is the session still valid?');
  }

  /// Shrinks an image for upload: the vision model only needs ~1K, and
  /// a small payload keeps the JS bridge fast (and under Android's
  /// Binder transaction limits).
  static Uint8List _shrinkForUpload(Uint8List bytes) {
    try {
      final im = img.decodeImage(bytes);
      if (im == null) return bytes;
      const maxDim = 1024;
      if (im.width <= maxDim && im.height <= maxDim) return bytes;
      final r = img.copyResize(im,
          width: im.width >= im.height ? maxDim : null,
          height: im.height > im.width ? maxDim : null);
      return Uint8List.fromList(img.encodeJpg(r, quality: 85));
    } catch (_) {
      return bytes;
    }
  }

  /// Waits for the chat editor to be present, like the workflow's
  /// waitForSelector(inputSel) - the editor renders after the page
  /// chrome, so typing immediately after load fails with 'no-editor'.
  Future<void> _waitForEditor() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await _driver.js(GeminiWebJs.editorPresent) == true) return;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 700));
    }
    throw Exception('Gemini chat input did not appear.');
  }

  /// Uploads the image, returning the winning strategy name or ''.
  /// The page only performs each step's DOM actions; every wait happens
  /// here on the Dart side, so a backgrounded page (Chromium throttles
  /// its timers when the window loses focus) can't stall the upload.
  /// Hidden time does not count against the per-strategy timeout:
  /// Gemini's own file processing pauses while hidden and resumes when
  /// the page is visible again, so we wait it out instead of failing.
  Future<String> _uploadImage(
    Uint8List bytes,
    String filename, {
    void Function(String stage)? onStatus,
  }) async {
    final small = _shrinkForUpload(bytes);
    const mime = 'image/jpeg';
    final name = filename.isEmpty ? 'wallpaper.jpg' : filename;
    final dataUrl = 'data:$mime;base64,${base64Encode(small)}';
    const strategies = <String, List<String>>{
      'upload-button': ['upload-button-click', 'upload-button-assign'],
      'clipboard-paste': ['clipboard-paste'],
      'drag-broadcast': ['drag-enter', 'drag-drop'],
      'file-input-override': ['file-input-override'],
    };
    const strategyLabels = <String, String>{
      'upload-button': 'file picker',
      'clipboard-paste': 'clipboard paste',
      'drag-broadcast': 'drag and drop',
      'file-input-override': 'hidden file input',
    };
    try {
      // NOTE: uploadInit is already an IIFE - call it directly, do NOT
      // wrap it in another (...)() or the returned 'ok' string gets
      // invoked as a function and the whole upload fails instantly.
      final initResult = await _driver.js(GeminiWebJs.uploadInit);
      if (initResult?.toString() != 'ok') return '';
    } catch (_) {
      return '';
    }
    final base = await _uploadChips();
    for (final entry in strategies.entries) {
      onStatus?.call(
          'Uploading image via ${strategyLabels[entry.key]}...');
      var attempted = true;
      for (final step in entry.value) {
        dynamic r;
        try {
          r = await _driver.js('(${GeminiWebJs.uploadAttempt})('
              '${jsonEncode(dataUrl)},'
              ' ${jsonEncode(name)},'
              ' ${jsonEncode(mime)},'
              ' ${jsonEncode(step)})');
        } catch (_) {
          r = '';
        }
        if (r?.toString() != step) {
          attempted = false;
          break;
        }
        // Let the page react. Dart-side wait: immune to background
        // timer throttling.
        await Future.delayed(const Duration(milliseconds: 700));
      }
      if (!attempted) continue;
      // 45s of VISIBLE time per strategy; hidden time is free (the
      // page will process the file once visible again). Hard stop at
      // 6 minutes so a truly stuck upload can't hang forever.
      var deadline =
          DateTime.now().add(const Duration(seconds: 45));
      final hardStop =
          DateTime.now().add(const Duration(minutes: 6));
      var wasHidden = false;
      while (DateTime.now().isBefore(deadline) &&
          DateTime.now().isBefore(hardStop)) {
        await Future.delayed(const Duration(seconds: 1));
        final st = await _uploadState();
        if (st == null) continue;
        if (st.hidden) {
          deadline = deadline.add(const Duration(seconds: 1));
          if (!wasHidden) {
            wasHidden = true;
            onStatus?.call('Upload sent - waiting for the page '
                '(bring this window forward to speed it up)...');
          }
          continue;
        }
        wasHidden = false;
        if (st.chips > base && !st.uploading) {
          await Future.delayed(const Duration(milliseconds: 900));
          final st2 = await _uploadState();
          if (st2 != null &&
              st2.chips > base &&
              !st2.uploading) {
            return entry.key;
          }
        }
      }
    }
    return '';
  }

  /// Attachment chip count on the page (for the upload baseline).
  Future<int> _uploadChips() async =>
      (await _uploadState())?.chips ?? 0;

  /// Sync attachment read: chip count, whether an upload is still in
  /// progress, and whether the page is hidden (throttled). Null when
  /// the read itself fails.
  Future<({int chips, bool uploading, bool hidden})?>
      _uploadState() async {
    try {
      final r = await _driver.js(GeminiWebJs.uploadState);
      final parts = r.toString().split('|');
      if (parts.length != 3) return null;
      return (
        chips: int.tryParse(parts[0]) ?? 0,
        uploading: parts[1] == '1',
        hidden: parts[2] == '1',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _typePrompt(String prompt) async {
    final r = await _driver
        .js('(${GeminiWebJs.typePrompt})(${jsonEncode(prompt)})');
    if (r != 'typed') throw Exception('Could not type into the Gemini chat.');
  }

  Future<void> _waitSendReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await _driver.js(GeminiWebJs.sendReady) == true) return;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<Map<String, dynamic>> _responseState() async {
    final raw = await _driver.js(GeminiWebJs.responseState);
    final m = raw is String ? jsonDecode(raw) : raw;
    return {
      'count': (m['count'] as int?) ?? 0,
      'text': (m['text'] as String?) ?? ''
    };
  }

  /// Polls until the newest response stabilises (or [completeWhen]
  /// matches), mirroring the workflow's stability logic.
  Future<String> _pollResponse(int initialCount, {RegExp? completeWhen}) async {
    // Hidden time doesn't count: backgrounded pages stall Gemini's
    // streaming until visible again.
    var deadline = DateTime.now().add(const Duration(seconds: 150));
    final hardStop = DateTime.now().add(const Duration(minutes: 10));
    var lastSeen = '';
    var stable = 0;
    while (DateTime.now().isBefore(deadline) &&
        DateTime.now().isBefore(hardStop)) {
      await Future.delayed(const Duration(milliseconds: 1500));
      var hidden = false;
      try {
        final h = await _driver.js(GeminiWebJs.pageHidden);
        hidden = h == true || h == 'true';
      } catch (_) {}
      if (hidden) {
        deadline = deadline.add(const Duration(milliseconds: 1500));
        continue;
      }
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
    onStatus?.call('Waiting for the chat input...');
    await _waitForEditor();
    final initialCount = await _responseCount();
    if (imageBytes != null) {
      onStatus?.call('Uploading image to Gemini...');
      final strat = await _uploadImage(imageBytes, imageName,
          onStatus: onStatus);
      if (strat.isEmpty) {
        throw Exception('Could not attach the image to Gemini.');
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    onStatus?.call('Asking Gemini...');
    await _typePrompt(prompt);
    await _waitSendReady();
    final sent = await _driver.js(GeminiWebJs.clickSend);
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
  // Backstop: descriptions stay short even if the model ignores the
  // 5-word instruction.
  return t.length > 80 ? t.substring(0, 80).trim() : t;
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
      '4. A SHORT DESCRIPTION (maximum 5 words, no punctuation, no full sentences, no hashtags, no emoji). Never mention file names.\n'
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
