import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'cdp.dart';
import 'overlay_script.dart';

/// One picture the user asked for from a web page.
class WebImageRef {
  final String src;
  final String alt;
  final int width;
  final int height;
  const WebImageRef(this.src, this.alt, this.width, this.height);
}

/// A request coming from the in-page overlay ("Prompt" button or the
/// "Generate prompts" dock for ticked pictures).
class WebImageRequest {
  final String action; // single | batch
  final List<WebImageRef> images;
  final String pageUrl;
  final String pageTitle;
  final String sessionId; // CDP session of the tab it came from
  const WebImageRequest(
      this.action, this.images, this.pageUrl, this.pageTitle, this.sessionId);
}

/// Raw picture bytes plus their detected MIME type.
class FetchedImage {
  final Uint8List bytes;
  final String mimeType;
  const FetchedImage(this.bytes, this.mimeType);
}

/// Drives a **real, separate Chromium window** (Chrome / Edge / Brave /
/// Chromium already installed on the PC) through the Chrome DevTools
/// Protocol. No WebView is embedded in the app: browsing stays 100 %
/// native Chromium (GPU, extensions, password manager, smooth scrolling),
/// and the app only injects a small overlay into each tab.
///
/// The browser runs with its own profile under the app-support folder, so
/// signing in to gemini.google.com there once is enough for the live
/// cookie path.
class ChromiumBrowser {
  ChromiumBrowser._(this._cdp, this.executable, this.profileDir) {
    _evSub = _cdp.events.listen(_onEvent);
    _cdp.done.then((_) => _handleClosed());
  }

  final CdpConnection _cdp;
  final String executable;
  final String profileDir;
  late final StreamSubscription _evSub;

  final _requests = StreamController<WebImageRequest>.broadcast();
  final _changes = StreamController<void>.broadcast();

  /// targetId -> sessionId of every attached tab.
  final Map<String, String> _sessions = {};
  final Set<String> _attaching = {};
  final Map<String, String> _tabUrls = {};
  bool _closed = false;

  Stream<WebImageRequest> get requests => _requests.stream;
  Stream<void> get changes => _changes.stream;
  bool get isConnected => !_closed && _cdp.isOpen;
  int get tabCount => _sessions.length;

  static bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // ------------------------------------------------------------ discovery
  /// Finds an installed Chromium-based browser. [preferred] (a full path
  /// typed in the app) wins when it exists.
  static String? findExecutable([String? preferred]) {
    if (preferred != null &&
        preferred.trim().isNotEmpty &&
        File(preferred.trim()).existsSync()) {
      return preferred.trim();
    }
    final env = Platform.environment;
    final candidates = <String>[];
    if (Platform.isWindows) {
      final roots = [
        env['ProgramFiles'],
        env['ProgramFiles(x86)'],
        env['LOCALAPPDATA'],
        env['ProgramW6432'],
      ].whereType<String>().where((s) => s.isNotEmpty);
      for (final r in roots) {
        candidates.addAll([
          '$r\\Google\\Chrome\\Application\\chrome.exe',
          '$r\\Chromium\\Application\\chrome.exe',
          '$r\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
          '$r\\Microsoft\\Edge\\Application\\msedge.exe',
        ]);
      }
    } else if (Platform.isMacOS) {
      candidates.addAll([
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        '/Applications/Chromium.app/Contents/MacOS/Chromium',
        '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
        '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
      ]);
    } else {
      final path = (env['PATH'] ?? '/usr/bin:/usr/local/bin').split(':');
      for (final name in const [
        'google-chrome',
        'google-chrome-stable',
        'chromium',
        'chromium-browser',
        'brave-browser',
        'microsoft-edge',
      ]) {
        for (final dir in path) {
          candidates.add('$dir/$name');
        }
      }
    }
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  static Future<String> _profileDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(
        '${base.path}${Platform.pathSeparator}chromium-profile');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// Reads `DevToolsActivePort` (written by Chromium when started with
  /// `--remote-debugging-port=0`) and returns the browser WebSocket URL.
  static String? _readWsUrl(String profileDir) {
    final f = File('$profileDir${Platform.pathSeparator}DevToolsActivePort');
    if (!f.existsSync()) return null;
    try {
      final lines = f
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length < 2) return null;
      final port = int.tryParse(lines[0]);
      if (port == null || port <= 0) return null;
      return 'ws://127.0.0.1:$port${lines[1]}';
    } catch (_) {
      return null;
    }
  }

  /// Opens (or re-attaches to) the controlled Chromium window and loads
  /// [startUrl].
  static Future<ChromiumBrowser> launch({
    String? preferredExecutable,
    String startUrl = 'https://www.google.com/',
    String? profileDir,
    List<String> extraArgs = const [],
  }) async {
    if (!supported) {
      throw CdpException('The Chromium browser feature needs the desktop '
          '(Windows) build of the app.');
    }
    final exe = findExecutable(preferredExecutable);
    if (exe == null) {
      throw CdpException('No Chromium browser found. Install Google Chrome, '
          'Chromium, Brave or Microsoft Edge, or enter the full path to '
          'chrome.exe in "Browser path".');
    }
    final profile = profileDir ?? await _profileDir();

    // 1) A window from an earlier run may still be open: re-attach.
    final existing = _readWsUrl(profile);
    if (existing != null) {
      try {
        final cdp = await CdpConnection.connect(existing,
            timeout: const Duration(seconds: 3));
        final b = ChromiumBrowser._(cdp, exe, profile);
        await b._start();
        await b.openTab(startUrl);
        return b;
      } catch (_) {}
    }

    // 2) Fresh start.
    try {
      final f = File('$profile${Platform.pathSeparator}DevToolsActivePort');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}

    await Process.start(
      exe,
      [
        '--remote-debugging-port=0',
        '--user-data-dir=$profile',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-features=Translate,ChromeWhatsNewUI',
        ...extraArgs,
        '--new-window',
        startUrl,
      ],
      mode: ProcessStartMode.detached,
    );

    String? ws;
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 250));
      ws = _readWsUrl(profile);
      if (ws != null) break;
    }
    if (ws == null) {
      throw CdpException('Chromium started but did not open its DevTools '
          'port. Close every window of that browser profile and try again.');
    }
    CdpConnection? cdp;
    Object? lastErr;
    for (var i = 0; i < 12 && cdp == null; i++) {
      try {
        cdp = await CdpConnection.connect(ws);
      } catch (e) {
        lastErr = e;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    if (cdp == null) {
      throw CdpException('Could not connect to Chromium: $lastErr');
    }
    final b = ChromiumBrowser._(cdp, exe, profile);
    await b._start();
    return b;
  }

  // ------------------------------------------------------------- sessions
  Future<void> _start() async {
    await _cdp.send('Target.setDiscoverTargets', params: {'discover': true});
    final res = await _cdp.send('Target.getTargets');
    for (final t in (res['targetInfos'] as List? ?? const [])) {
      if (t is Map) _maybeAttach(t.cast<String, dynamic>());
    }
  }

  void _maybeAttach(Map<String, dynamic> info) {
    if (info['type'] != 'page') return;
    final id = info['targetId'] as String?;
    if (id == null) return;
    _tabUrls[id] = (info['url'] ?? '').toString();
    if (_sessions.containsKey(id) || _attaching.contains(id)) return;
    _attaching.add(id);
    _attach(id).whenComplete(() => _attaching.remove(id));
  }

  Future<void> _attach(String targetId) async {
    try {
      final r = await _cdp.send('Target.attachToTarget',
          params: {'targetId': targetId, 'flatten': true});
      final sid = r['sessionId'] as String?;
      if (sid == null) return;
      _sessions[targetId] = sid;
      await _cdp.send('Runtime.addBinding',
          params: {'name': overlayBindingName}, sessionId: sid);
      await _cdp.send('Runtime.enable', sessionId: sid);
      await _cdp.send('Page.enable', sessionId: sid);
      await _cdp.send('Page.addScriptToEvaluateOnNewDocument',
          params: {'source': overlayScript}, sessionId: sid);
      // Tab that is already showing a page: inject right away.
      await _cdp.send('Runtime.evaluate',
          params: {'expression': overlayScript}, sessionId: sid);
      _changes.add(null);
    } catch (_) {
      // chrome:// pages, closing tabs, etc. – ignore.
    }
  }

  void _onEvent(CdpEvent e) {
    switch (e.method) {
      case 'Target.targetCreated':
      case 'Target.targetInfoChanged':
        final info = (e.params['targetInfo'] as Map?)?.cast<String, dynamic>();
        if (info != null) _maybeAttach(info);
        break;
      case 'Target.targetDestroyed':
        final id = e.params['targetId'] as String?;
        if (id != null) {
          _sessions.remove(id);
          _tabUrls.remove(id);
          _changes.add(null);
        }
        break;
      case 'Target.detachedFromTarget':
        final sid = e.params['sessionId'] as String?;
        _sessions.removeWhere((_, v) => v == sid);
        _changes.add(null);
        break;
      case 'Runtime.bindingCalled':
        if (e.params['name'] != overlayBindingName) return;
        _handleBinding(e.params['payload']?.toString() ?? '', e.sessionId);
        break;
    }
  }

  void _handleBinding(String payload, String? sessionId) {
    try {
      final m = (jsonDecode(payload) as Map).cast<String, dynamic>();
      final imgs = <WebImageRef>[];
      for (final i in (m['images'] as List? ?? const [])) {
        if (i is! Map) continue;
        final src = (i['src'] ?? '').toString();
        if (src.isEmpty) continue;
        imgs.add(WebImageRef(
          src,
          (i['alt'] ?? '').toString(),
          (i['w'] as num?)?.toInt() ?? 0,
          (i['h'] as num?)?.toInt() ?? 0,
        ));
      }
      if (imgs.isEmpty) return;
      _requests.add(WebImageRequest(
        (m['action'] ?? 'single').toString(),
        imgs,
        (m['page'] ?? '').toString(),
        (m['title'] ?? '').toString(),
        sessionId ?? '',
      ));
    } catch (_) {}
  }

  void _handleClosed() {
    if (_closed) return;
    _closed = true;
    _sessions.clear();
    _changes.add(null);
  }

  // -------------------------------------------------------------- actions
  /// Opens [url] in a new tab of the controlled window.
  Future<void> openTab(String url) async {
    await _cdp.send('Target.createTarget', params: {'url': url});
  }

  /// Pushes a status update to the overlay of the tab that asked.
  Future<void> notifyPage(String sessionId, String src, String state,
      [String message = '']) async {
    if (sessionId.isEmpty || !isConnected) return;
    if (!_sessions.containsValue(sessionId)) return;
    final arg = jsonEncode({'src': src, 'state': state, 'message': message});
    try {
      await _cdp.send('Runtime.evaluate',
          params: {
            'expression': 'window.__aisStatus && window.__aisStatus($arg)'
          },
          sessionId: sessionId,
          timeout: const Duration(seconds: 5));
    } catch (_) {}
  }

  /// Cookies of the controlled profile for google.com (the live Gemini
  /// web session when the user is signed in there).
  Future<List<Map<String, dynamic>>> googleCookies() async {
    final r = await _cdp.send('Storage.getCookies');
    return [
      for (final c in (r['cookies'] as List? ?? const []))
        if (c is Map && (c['domain'] ?? '').toString().contains('google.com'))
          c.cast<String, dynamic>()
    ];
  }

  /// Gets the picture bytes, trying (1) Chromium's own resource cache for
  /// the tab, (2) a direct download with the page as referrer and (3) a
  /// fetch() inside the page (blob: / cookie-protected images).
  Future<FetchedImage> fetchImage(String src,
      {String sessionId = '', String pageUrl = ''}) async {
    if (src.startsWith('data:')) {
      final comma = src.indexOf(',');
      if (comma > 0) {
        final meta = src.substring(5, comma);
        final data = src.substring(comma + 1);
        final bytes = meta.contains(';base64')
            ? base64Decode(data)
            : Uint8List.fromList(utf8.encode(Uri.decodeComponent(data)));
        return FetchedImage(Uint8List.fromList(bytes), meta.split(';').first);
      }
    }
    final live = sessionId.isNotEmpty &&
        isConnected &&
        _sessions.containsValue(sessionId);

    if (live && !src.startsWith('blob:')) {
      try {
        final tree = await _cdp.send('Page.getFrameTree',
            sessionId: sessionId, timeout: const Duration(seconds: 5));
        final ids = <String>[];
        void walk(dynamic node) {
          if (node is! Map) return;
          final f = node['frame'];
          if (f is Map && f['id'] != null) ids.add(f['id'].toString());
          for (final c in (node['childFrames'] as List? ?? const [])) {
            walk(c);
          }
        }

        walk(tree['frameTree']);
        for (final fid in ids) {
          try {
            final r = await _cdp.send('Page.getResourceContent',
                params: {'frameId': fid, 'url': src},
                sessionId: sessionId,
                timeout: const Duration(seconds: 10));
            final content = (r['content'] ?? '').toString();
            if (content.isEmpty) continue;
            final bytes = r['base64Encoded'] == true
                ? base64Decode(content)
                : Uint8List.fromList(utf8.encode(content));
            if (bytes.length > 64) {
              return FetchedImage(bytes, sniffMime(bytes));
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (!src.startsWith('blob:')) {
      try {
        return await fetchDirect(src, pageUrl);
      } catch (_) {}
    }

    if (live) {
      final expr = '(async (u) => { const r = await fetch(u, '
          '{credentials: "include"}); const b = await r.blob(); '
          'return await new Promise((ok, no) => { const fr = new FileReader(); '
          'fr.onload = () => ok(fr.result); fr.onerror = () => no("read"); '
          'fr.readAsDataURL(b); }); })(${jsonEncode(src)})';
      try {
        final r = await _cdp.send('Runtime.evaluate',
            params: {
              'expression': expr,
              'awaitPromise': true,
              'returnByValue': true
            },
            sessionId: sessionId,
            timeout: const Duration(seconds: 40));
        final v = (r['result'] as Map?)?['value']?.toString() ?? '';
        final comma = v.indexOf(',');
        if (v.startsWith('data:') && comma > 0) {
          final bytes = base64Decode(v.substring(comma + 1));
          if (bytes.length > 64) return FetchedImage(bytes, sniffMime(bytes));
        }
      } catch (_) {}
    }
    throw CdpException('Could not download the picture (the site blocks '
        'it or the tab was closed).');
  }

  /// Plain HTTP download with the page as referrer (no browser needed).
  static Future<FetchedImage> fetchDirect(String src, String pageUrl) async {
    final res = await http.get(Uri.parse(src), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 '
          'Safari/537.36',
      'Accept': 'image/avif,image/webp,image/png,image/*,*/*;q=0.8',
      if (pageUrl.isNotEmpty) 'Referer': pageUrl,
    }).timeout(const Duration(seconds: 40));
    if (res.statusCode != 200 || res.bodyBytes.length <= 64) {
      throw CdpException('Picture download failed (HTTP ${res.statusCode}).');
    }
    return FetchedImage(res.bodyBytes, sniffMime(res.bodyBytes));
  }

  static String sniffMime(Uint8List b) {
    bool at(int o, List<int> sig) {
      if (b.length < o + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[o + i] != sig[i]) return false;
      }
      return true;
    }

    if (at(0, [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (at(0, [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (at(0, [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
      return 'image/webp';
    }
    if (at(4, [0x66, 0x74, 0x79, 0x70])) {
      final brand = String.fromCharCodes(b.sublist(8, 12));
      if (brand.startsWith('avi')) return 'image/avif';
      if (brand.startsWith('hei') || brand.startsWith('mif')) {
        return 'image/heic';
      }
    }
    if (at(0, [0x42, 0x4D])) return 'image/bmp';
    final head = String.fromCharCodes(b.take(256)).toLowerCase();
    if (head.contains('<svg')) return 'image/svg+xml';
    return 'application/octet-stream';
  }

  /// Converts a picture that the image package cannot decode (AVIF, SVG,
  /// HEIC...) to PNG using Chromium itself: draws it on a canvas inside a
  /// tab and returns the PNG bytes.
  Future<Uint8List?> rasterizeInPage(String src, String sessionId) async {
    if (sessionId.isEmpty || !_sessions.containsValue(sessionId)) return null;
    final expr = '(async (u) => { const i = new Image(); '
        'i.crossOrigin = "anonymous"; i.src = u; await i.decode(); '
        'const max = 2048; let w = i.naturalWidth || 1024, h = i.naturalHeight || 1024; '
        'const k = Math.min(1, max / Math.max(w, h)); w = Math.round(w * k); h = Math.round(h * k); '
        'const c = document.createElement("canvas"); c.width = w; c.height = h; '
        'c.getContext("2d").drawImage(i, 0, 0, w, h); return c.toDataURL("image/png"); '
        '})(${jsonEncode(src)})';
    try {
      final r = await _cdp.send('Runtime.evaluate',
          params: {'expression': expr, 'awaitPromise': true, 'returnByValue': true},
          sessionId: sessionId,
          timeout: const Duration(seconds: 30));
      final v = (r['result'] as Map?)?['value']?.toString() ?? '';
      final comma = v.indexOf(',');
      if (v.startsWith('data:image/png') && comma > 0) {
        return base64Decode(v.substring(comma + 1));
      }
    } catch (_) {}
    return null;
  }

  /// Disconnects from the window (the browser itself stays open).
  Future<void> disconnect() async {
    await _evSub.cancel();
    await _cdp.close();
    _handleClosed();
  }

  /// Closes the whole Chromium window.
  Future<void> closeBrowser() async {
    try {
      await _cdp.send('Browser.close', timeout: const Duration(seconds: 5));
    } catch (_) {}
    await disconnect();
  }
}
