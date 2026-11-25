import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../platform_ui.dart';

import '../android_gecko.dart';
import 'chromium_browser.dart';
import 'prompt_browser.dart';

/// Android: the Image to Prompt browser is the built-in Firefox engine
/// (GeckoView, see android_native/). The page overlay is the same script
/// as on Windows, injected by a built-in extension; requests and status
/// travel over the `ais/gecko` channel.
class GeckoPromptBrowser implements PromptBrowser {
  GeckoPromptBrowser._() {
    _ch.setMethodCallHandler(_onCall);
  }

  static GeckoPromptBrowser? _instance;
  static GeckoPromptBrowser get instance =>
      _instance ??= GeckoPromptBrowser._();

  static bool get supported => isAndroidUi;

  static const _ch = MethodChannel('ais/gecko');
  final _requests = StreamController<WebImageRequest>.broadcast();
  final _changes = StreamController<void>.broadcast();
  bool _open = false;
  bool visible = false;
  int _basketVersion = 0;

  @override
  String get displayName => 'Built-in browser';
  @override
  bool get isConnected => _open;
  @override
  int get tabCount => _open ? 1 : 0;
  @override
  Stream<WebImageRequest> get requests => _requests.stream;
  @override
  Stream<void> get changes => _changes.stream;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'browserRequest':
        _onRequest(call.arguments as String);
        return null;
      case 'browserState':
        try {
          final o = jsonDecode(call.arguments as String) as Map;
          _open = o['open'] == true;
          visible = o['visible'] == true;
        } catch (_) {}
        _changes.add(null);
        return null;
    }
    return null;
  }

  void _onRequest(String json) {
    Map m;
    try {
      m = jsonDecode(json) as Map;
    } catch (_) {
      return;
    }
    for (final raw in (m['q'] as List? ?? const [])) {
      try {
        final r = jsonDecode(raw.toString()) as Map;
        final imgs = <WebImageRef>[
          for (final i in (r['images'] as List? ?? const []))
            if (WebImageRef.fromJson(i) case final ref?) ref
        ];
        _requests.add(WebImageRequest(
          (r['action'] ?? 'single').toString(),
          imgs,
          (r['page'] ?? m['page'] ?? '').toString(),
          (r['title'] ?? m['title'] ?? '').toString(),
          'gecko',
        ));
      } catch (_) {}
    }
  }

  @override
  Future<void> openTab(String url) async {
    await _ch.invokeMethod('browserOpen', {'url': url});
    _open = true;
    _changes.add(null);
  }

  /// Shows the browser screen again without loading anything.
  Future<void> show() async {
    await _ch.invokeMethod('browserOpen', {'url': null});
  }

  @override
  void setBasket(List<String> srcs, int pages) {
    _basketVersion++;
    _ch
        .invokeMethod('browserBasket',
            jsonEncode({'srcs': srcs, 'v': _basketVersion, 'pages': pages}))
        .catchError((_) => null);
  }

  @override
  Future<void> notifyPage(String sessionId, String src, String state,
      [String message = '']) async {
    try {
      await _ch.invokeMethod('browserStatus',
          jsonEncode({'src': src, 'state': state, 'message': message}));
    } catch (_) {}
  }

  @override
  Future<FetchedImage> fetchImage(String src,
      {String sessionId = '', String pageUrl = ''}) async {
    if (src.startsWith('data:')) return _fromDataUrl(src);
    Object? first;
    try {
      return await ChromiumBrowser.fetchDirect(src, pageUrl);
    } catch (e) {
      first = e;
    }
    // CORS / hot-link protected: download inside the engine.
    final data = await _ch.invokeMethod<String>('browserFetch', src);
    if (data == null) {
      throw Exception('Could not download the picture ($first)');
    }
    return _fromDataUrl(data);
  }

  static FetchedImage _fromDataUrl(String src) {
    final comma = src.indexOf(',');
    final head = src.substring(0, comma < 0 ? 0 : comma);
    final body = comma < 0 ? '' : src.substring(comma + 1);
    final Uint8List bytes = head.contains(';base64')
        ? base64Decode(body)
        : Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));
    var mime = head.startsWith('data:') ? head.substring(5).split(';').first : '';
    if (mime.isEmpty || mime == 'application/octet-stream') {
      mime = ChromiumBrowser.sniffMime(bytes);
    }
    return FetchedImage(bytes, mime);
  }

  /// Android: GeckoView renders the visible page to a bitmap and the area
  /// (share of the viewport) is cut out natively.
  @override
  Future<Uint8List?> captureRegion(
      String sessionId, Map<String, dynamic> meta) async {
    final f = meta['frac'];
    if (f is! Map) return null;
    try {
      final b64 = await _ch.invokeMethod<String>('browserCapture', jsonEncode(f));
      if (b64 == null || b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> captureElement(String src, String sessionId) async => null;

  @override
  Future<Uint8List?> rasterizeInPage(String src, String sessionId) async =>
      null;

  @override
  Future<List<Map<String, dynamic>>> googleCookies() async {
    final json = await _ch.invokeMethod<String>('cookies');
    if (json == null) return const [];
    final v = jsonDecode(json);
    return [
      for (final c in (v is List ? v : const []))
        if (c is Map) c.cast<String, dynamic>()
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> refreshGoogleCookies() =>
      AndroidGecko.refresh();

  Future<void> toast(String msg) async {
    try {
      await _ch.invokeMethod('browserToast', msg);
    } catch (_) {}
  }

  @override
  Future<void> closeBrowser() async {
    try {
      await _ch.invokeMethod('browserClose');
    } catch (_) {}
    _open = false;
    _changes.add(null);
  }
}
