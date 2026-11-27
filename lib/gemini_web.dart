import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;

/// Gemini Web (cookie session) client — the desktop port of the
/// `callGeminiWeb()` path in the Generator Hub workflow (generator.yml).
///
/// The workflow drives gemini.google.com with Playwright + a storageState
/// cookie export. A Flutter desktop app cannot ship a browser, so this
/// client talks to the exact same endpoint the web app itself calls
/// (`BardFrontendService/StreamGenerate`) using the same cookies, the same
/// `SNlM0e` (`at`) token and the same conversation ids. Behaviour kept 1:1
/// with the workflow:
///
///  * the session JSON is accepted in all three formats the workflow
///    normalizes (Playwright storageState, raw browser-extension cookie
///    array, nested/alternate key) with the same field mapping
///    (expirationDate -> expires, sameSite casing, -1 session cookies);
///  * the key auth cookies are reported exactly like the workflow logs
///    them (SID, SSID, APISID, SAPISID, __Secure-1PSID, __Secure-3PSID);
///  * an expired/invalid session is detected (login redirect, missing
///    `SNlM0e`, 401/403) and surfaced as "re-export your session",
///    instead of silently falling back;
///  * every prompt starts a **fresh chat** (the workflow navigates to
///    `/app/new` before each metadata prompt), so no answer is polluted
///    by the previous one;
///  * a reply is only accepted once it is non-empty and — when a
///    `completeWhen` pattern is given — actually contains the closing
///    marker, mirroring the workflow's streaming-completion guard; a
///    partial reply is retried instead of being parsed.
const String geminiWebUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Label stored as the "model" of anything produced through the cookie
/// session, so the UI can tell API-key results from web-session results.
const String geminiWebModelLabel = 'gemini-web (cookie)';

/// The auth cookies the workflow checks for after loading a session.
const List<String> geminiWebKeyCookies = [
  'SID',
  'SSID',
  'APISID',
  'SAPISID',
  '__Secure-1PSID',
  '__Secure-3PSID',
];

/// Thrown for every Gemini-web problem. [expired] is true when the fix is
/// "re-export the cookies" rather than "retry".
class GeminiWebException implements Exception {
  final String message;
  final bool expired;
  GeminiWebException(this.message, {this.expired = false});

  @override
  String toString() => message;
}

/// One normalized cookie (Playwright storageState shape).
class GeminiWebCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final int expires;
  final bool httpOnly;
  final bool secure;
  final String sameSite;

  const GeminiWebCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.expires,
    required this.httpOnly,
    required this.secure,
    required this.sameSite,
  });

  /// google.com itself or one of its hosts - not look-alikes such as the
  /// country domains (`.google.com.bd`), whose SID cookies carry other
  /// values and make gemini.google.com answer 401 when sent instead.
  bool get isGoogle {
    final d = (domain.startsWith('.') ? domain.substring(1) : domain)
        .toLowerCase();
    return d == 'google.com' || d.endsWith('.google.com');
  }

  /// True when a browser would send this cookie to gemini.google.com.
  bool get forGemini {
    final d = (domain.startsWith('.') ? domain.substring(1) : domain)
        .toLowerCase();
    return d == 'google.com' || d == 'gemini.google.com';
  }

  /// True when the cookie carries an absolute expiry that already passed.
  bool get isExpired =>
      expires > 0 && expires * 1000 < DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'expires': expires,
        'httpOnly': httpOnly,
        'secure': secure,
        'sameSite': sameSite,
      };
}

/// A parsed + normalized Gemini web session.
class GeminiWebSession {
  final List<GeminiWebCookie> cookies;

  /// Which of the workflow's three input formats was detected.
  final String format;

  const GeminiWebSession(this.cookies, this.format);

  /// Playwright storageState JSON (what Settings stores).
  String toStorageJson() => jsonEncode({
        'cookies': [for (final c in cookies) c.toJson()],
        'origins': const [],
      });

  String? value(String name) {
    for (final c in cookies) {
      if (c.name == name && c.isGoogle && c.value.isNotEmpty) return c.value;
    }
    return null;
  }

  /// Returns a copy where [fresh] replace cookies of the same name on the
  /// same (google.com) domain, the way a browser jar would.
  GeminiWebSession merged(List<GeminiWebCookie> fresh) {
    String bare(String d) => d.startsWith('.') ? d.substring(1) : d;
    final out = <GeminiWebCookie>[];
    for (final c in cookies) {
      final replaced = fresh.any((f) =>
          f.name == c.name &&
          (bare(f.domain) == bare(c.domain) ||
              (f.isGoogle && c.isGoogle && bare(c.domain) == 'google.com')));
      if (!replaced) out.add(c);
    }
    out.addAll(fresh);
    return GeminiWebSession(out, format);
  }

  List<GeminiWebCookie> get googleCookies =>
      cookies.where((c) => c.isGoogle).toList();

  /// Key auth cookie names present in this session.
  List<String> get authCookies => [
        for (final n in geminiWebKeyCookies)
          if (cookies.any((c) => c.name == n && c.value.trim().isNotEmpty)) n
      ];

  /// Cookie header for gemini.google.com (google.com cookies only, exactly
  /// what the browser would send).
  String get cookieHeader => _header(null);

  /// Only the cookies the Google sign-in itself consists of - the
  /// workflow's fallback when the full jar is refused.
  String get minimalCookieHeader => _header(_essentialCookies);

  static const _skippedCookies = {'COMPASS', 'S', 'SEARCH_SAMESITE'};
  static const _essentialCookies = {
    'SID', 'HSID', 'SSID', 'APISID', 'SAPISID', 'SIDCC', 'NID',
    '__Secure-1PSID', '__Secure-3PSID',
    '__Secure-1PAPISID', '__Secure-3PAPISID',
    '__Secure-1PSIDTS', '__Secure-3PSIDTS',
  };

  /// Same rules as the workflow's `buildCookieHeader`: one value per
  /// name, the `.google.com` cookie wins over a host cookie of the same
  /// name, and cookies of other hosts (accounts.google.com, country
  /// domains...) are never sent to gemini.google.com.
  String _header(Set<String>? only) {
    final byName = <String, String>{};
    final fromRoot = <String>{};
    bool root(GeminiWebCookie c) =>
        (c.domain.startsWith('.') ? c.domain.substring(1) : c.domain)
            .toLowerCase() ==
        'google.com';
    final usable = cookies.any((c) => c.forGemini)
        ? cookies.where((c) => c.forGemini)
        : cookies.where((c) => c.isGoogle);
    for (final c in usable) {
      if (c.name.isEmpty || c.value.isEmpty) continue;
      if (_skippedCookies.contains(c.name)) continue;
      if (only != null && !only.contains(c.name)) continue;
      if (c.isExpired) continue;
      final r = root(c);
      if (byName.containsKey(c.name) && !(r && !fromRoot.contains(c.name))) {
        continue;
      }
      byName[c.name] = c.value;
      if (r) fromRoot.add(c.name);
    }
    return [for (final e in byName.entries) '${e.key}=${e.value}'].join('; ');
  }

  /// One-line human summary, the desktop version of the workflow's
  /// "Gemini Web Session loaded: N cookies ..." log lines.
  String get summary {
    final auth = authCookies;
    return '${cookies.length} cookies · ${googleCookies.length} google.com · '
        'auth: ${auth.isEmpty ? 'NONE — session will fail' : auth.join(', ')}';
  }

  /// `expirationDate` (float) -> `expires` (int seconds, -1 = session),
  /// sameSite casing, hostOnly/storeId/session stripped. Identical to the
  /// workflow's `normalizeCookies()`.
  static List<GeminiWebCookie> _normalize(List<dynamic> raw) {
    final out = <GeminiWebCookie>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final value = (item['value'] ?? '').toString();

      var sameSite = 'None';
      final rawSame = item['sameSite'];
      if (rawSame != null && rawSame.toString().trim().isNotEmpty) {
        final ss = rawSame.toString().toLowerCase();
        if (ss == 'lax') {
          sameSite = 'Lax';
        } else if (ss == 'strict') {
          sameSite = 'Strict';
        } else if (ss == 'none' || ss == 'no_restriction') {
          sameSite = 'None';
        }
      }

      int expires = -1;
      final e = item['expires'] ?? item['expirationDate'];
      if (e is num) {
        expires = e.floor();
      } else if (e != null) {
        final parsed = double.tryParse(e.toString());
        if (parsed != null) expires = parsed.floor();
      }

      var domain = (item['domain'] ?? '').toString().trim();
      if (domain.isEmpty) domain = '.google.com';

      out.add(GeminiWebCookie(
        name: name,
        value: value,
        domain: domain,
        path: (item['path'] ?? '/').toString().isEmpty
            ? '/'
            : (item['path'] ?? '/').toString(),
        expires: expires,
        httpOnly: item['httpOnly'] == true,
        secure: item['secure'] == true,
        sameSite: sameSite,
      ));
    }
    // Last occurrence of a name/domain/path wins (same as a real jar).
    final byKey = <String, GeminiWebCookie>{};
    for (final c in out) {
      byKey['${c.name}|${c.domain}|${c.path}'] = c;
    }
    return byKey.values.toList();
  }

  /// Builds a session straight from a raw cookie list, e.g. the result of
  /// the Chrome DevTools Protocol `Storage.getCookies` call on the user's
  /// own Chromium profile (the *live* gemini.google.com cookies).
  static GeminiWebSession fromCookieList(List<dynamic> raw,
      {String format = 'Chromium profile'}) {
    final cookies = _normalize(raw).where((c) => c.isGoogle).toList();
    if (cookies.isEmpty) {
      throw GeminiWebException(
          'The Chromium profile has no google.com cookies. Sign in to '
          'gemini.google.com in the opened browser window first.',
          expired: true);
    }
    return GeminiWebSession(cookies, format);
  }

  /// Accepts the same formats as the workflow:
  ///   1. Playwright storageState  `{"cookies":[...],"origins":[...]}`
  ///   2. Raw browser-extension array `[{"name":...,"value":...}]`
  ///   3. Object with the cookies under an alternate / nested key
  static GeminiWebSession parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw GeminiWebException('Paste your Gemini web session JSON first.');
    }
    dynamic parsed;
    try {
      parsed = jsonDecode(text);
    } catch (_) {
      throw GeminiWebException(
          'Gemini session is not valid JSON. Expected either a Playwright '
          'storageState {"cookies":[...]} or a browser-extension cookie '
          'array [{"name":"...","value":"...","domain":"..."}].');
    }

    List<dynamic>? found;
    var format = '';

    if (parsed is Map && parsed['cookies'] is List) {
      found = parsed['cookies'] as List;
      format = 'Playwright storageState';
    } else if (parsed is List &&
        parsed.isNotEmpty &&
        parsed.first is Map &&
        (parsed.first as Map)['name'] != null) {
      found = parsed;
      format = 'browser-extension cookie array';
    } else if (parsed is Map) {
      for (final k in const [
        'cookie',
        'Cookie',
        'cookieList',
        'cookieJar',
        'session'
      ]) {
        final v = parsed[k];
        if (v is List && v.isNotEmpty) {
          found = v;
          format = 'nested key "$k"';
          break;
        }
      }
      if (found == null) {
        for (final v in parsed.values) {
          if (v is Map &&
              v['cookies'] is List &&
              (v['cookies'] as List).isNotEmpty) {
            found = v['cookies'] as List;
            format = 'nested storageState';
            break;
          }
          if (v is List &&
              v.isNotEmpty &&
              v.first is Map &&
              (v.first as Map)['name'] != null) {
            found = v;
            format = 'nested cookie array';
            break;
          }
        }
      }
    }

    final cookies = found == null ? <GeminiWebCookie>[] : _normalize(found);
    if (cookies.isEmpty) {
      throw GeminiWebException(
          'No cookies found in the Gemini session JSON. Re-export it from '
          'your browser (Playwright storageState or a cookie-editor export).');
    }
    if (cookies.every((c) => !c.isGoogle)) {
      throw GeminiWebException(
          'The session has no google.com cookies, so gemini.google.com '
          'cannot be restored. Export the cookies while gemini.google.com '
          'is open.');
    }
    return GeminiWebSession(cookies, format);
  }
}

/// A file already pushed to content-push.googleapis.com.
class GeminiWebUpload {
  final String ref;
  final String filename;
  const GeminiWebUpload(this.ref, this.filename);
}

/// Normalizes an image for attachment to Gemini: ALWAYS JPEG out,
/// whatever came in (his rule, 2026-11-27). JPEG input passes
/// through untouched (magic-byte check, not the caller's label);
/// anything else is decoded, flattened onto white when it has
/// alpha, and re-encoded as JPEG q90 with a .jpg filename. When
/// the bytes cannot be decoded at all, the input is returned
/// unchanged (the upload then speaks for itself).
({Uint8List bytes, String filename, String mimeType}) ensureJpegForGemini(
  Uint8List bytes, {
  required String filename,
  required String mimeType,
}) {
  final isJpeg = bytes.length > 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
  if (isJpeg) {
    return (bytes: bytes, filename: filename, mimeType: 'image/jpeg');
  }
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return (bytes: bytes, filename: filename, mimeType: mimeType);
    }
    var out = decoded;
    if (out.hasAlpha) {
      final bg = img.Image(width: out.width, height: out.height);
      img.fill(bg, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(bg, out);
      out = bg;
    }
    final base = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;
    return (
      bytes: Uint8List.fromList(img.encodeJpg(out, quality: 90)),
      filename: '$base.jpg',
      mimeType: 'image/jpeg',
    );
  } catch (_) {
    return (bytes: bytes, filename: filename, mimeType: mimeType);
  }
}

/// Result of a session self-test (Settings -> Test session).
class GeminiWebTestResult {
  final bool ok;
  final int ms;
  final String message;
  final String summary;
  final bool expired;
  const GeminiWebTestResult({
    required this.ok,
    required this.ms,
    required this.message,
    required this.summary,
    this.expired = false,
  });
}

/// Response of a request made inside the signed-in browser.
class GeminiPageResponse {
  const GeminiPageResponse(this.status, this.url, this.body,
      {this.bytes, this.contentType = ''});
  final int status;
  final String url;
  final String body;

  /// Raw body when the response was an image (else null).
  final Uint8List? bytes;
  final String contentType;
}

/// Image(s) Gemini web drew for one prompt.
/// Browser that can open a Gemini chat and hand over the picture the
/// page shows (`generated-image img.image`, a blob: URL).
abstract class GeminiChatImageReader {
  Future<Uint8List?> chatImage(String conversationId, {Duration timeout});
}

class GeminiGeneratedImages {
  const GeminiGeneratedImages(this.urls, this.text, {this.bytes});

  /// The picture itself when it was taken from the page (no download).
  final Uint8List? bytes;

  /// lh3.googleusercontent.com/gg-dl/... download links, in order.
  final List<String> urls;

  /// Text Gemini wrote next to the image (may be empty).
  final String text;
}

/// Runs Gemini web requests INSIDE the signed-in browser (a
/// gemini.google.com tab), exactly like the Gemini page itself: the
/// browser sends and renews its own cookies, nothing is copied out.
abstract class GeminiPageTransport {
  bool get isAvailable;
  Future<GeminiPageResponse> request(
    String method,
    String url, {
    Map<String, String> headers = const {},
    String? body,
    Uint8List? file,
    String fileName = 'image.jpg',
    String fileMime = 'image/jpeg',
    Duration timeout = const Duration(seconds: 120),
  });
}

/// Talks to gemini.google.com with a cookie session (or through the
/// signed-in browser when [transport] is set).
class GeminiWebClient {
  GeminiWebClient(this.session,
      {this.onSessionUpdated,
      this.refreshSession,
      this.transport,
      this.browserFallback});

  /// When set and available, every request runs inside the browser.
  final GeminiPageTransport? transport;

  /// Last line of defence, the desktop version of the workflow's "Live
  /// Browser Gmail Login": when Google refuses the copied cookies (HTTP
  /// 401/403) although the app's browser profile IS signed in, this
  /// returns a hidden instance of that profile and every request runs
  /// inside a real gemini.google.com tab, where Chrome authenticates
  /// itself (device-bound sessions, rotated cookies, anything Google adds
  /// later). Null on platforms without a desktop browser.
  final Future<GeminiPageTransport?> Function()? browserFallback;
  GeminiPageTransport? _fallback;

  /// Set once the copied cookies were refused while the browser profile
  /// worked: later clients go to the browser first instead of failing
  /// (and re-reading cookies) on every single request.
  static bool preferBrowser = false;

  /// The transport in use: the controlled window, else the hidden profile.
  GeminiPageTransport? get _tx {
    final t = transport;
    if (t != null && t.isAvailable) return t;
    final f = _fallback;
    if (f != null && f.isAvailable) return f;
    return null;
  }

  bool get _viaPage => !_pageBroken && _tx != null;

  /// True while requests run inside the signed-in browser.
  bool get usingBrowser => _viaPage;

  /// Workflow fallback: essential cookies only (see [_handshake]).
  bool _minimalCookies = false;

  String get _cookie => _minimalCookies
      ? session.minimalCookieHeader
      : session.cookieHeader;

  Future<bool> _engageBrowser() async {
    final hook = browserFallback;
    if (hook == null) return false;
    try {
      final t = await hook();
      if (t == null || !t.isAvailable) return false;
      _fallback = t;
      _pageBroken = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  static const _signInHint =
      'Open Settings > Gemini web session > "Sign in with Google" once, '
      'wait until Gemini opens, then retry.';

  /// Set when a request inside the browser tab timed out or failed: the
  /// rest of this session uses the direct cookie path instead.
  bool _pageBroken = false;

  /// App-side cookie renewal (RotateCookies). OFF by default: renewing a
  /// session that is also open in a browser (the app's sign-in browser or
  /// your own Chrome) makes Google end it there -> "logged out after a
  /// few minutes". The browser renews its own cookies; the app only reads
  /// them again when they expire. Turn on only for a dedicated account
  /// whose cookies were pasted and are not used in any browser.
  static bool allowAppRotation = false;

  /// Current cookies; replaced when Google rotates them.
  GeminiWebSession session;

  /// Called whenever the cookies were renewed (persist them!).
  final void Function(GeminiWebSession session)? onSessionUpdated;

  /// Last resort when the session is dead: fetch fresh cookies from the
  /// signed-in browser profile (desktop Chrome/Edge, or the built-in
  /// GeckoView browser on Android).
  final Future<GeminiWebSession?> Function()? refreshSession;

  /// Last RotateCookies call per __Secure-1PSID (Google answers 429 when
  /// rotating more than about once a minute).
  static final Map<String, DateTime> _rotatedAt = {};

  /// Default boq build id; replaced with the live one from the app HTML.
  static const _fallbackBl = 'boq_assistant-bard-web-server_20240625.13_p0';

  String? _at; // SNlM0e token
  String _pushId = 'feeds/mcudyrk2a4khkz'; // upload Push-ID (qKIAYe)
  String _bl = _fallbackBl;
  String? _cid; // conversation id
  String? _rid; // response id
  String? _rcid; // chosen candidate id
  int _reqid = 100000 + Random().nextInt(800000);

  bool get ready => _at != null && _at!.isNotEmpty;

  /// Independent chat state for a concurrent task using the same session.
  GeminiWebClient fork() => GeminiWebClient(session,
      onSessionUpdated: onSessionUpdated,
      refreshSession: refreshSession,
      transport: transport,
      browserFallback: browserFallback)
    .._fallback = _fallback
    .._minimalCookies = _minimalCookies
    .._at = _at
    .._bl = _bl
    .._pushId = _pushId
    .._pageBroken = _pageBroken;

  /// Always identify as **desktop Chrome on Windows**, on every platform
  /// (including Android). There is no WebView and no DOM here, but Google
  /// still serves a different mobile variant of the app/endpoint when the
  /// client looks like a phone, so the client hints are pinned to desktop
  /// so Android behaves byte-for-byte like the Windows build.
  Map<String, String> _headers({bool form = false}) => {
        'User-Agent': geminiWebUserAgent,
        'Cookie': _cookie,
        'Origin': 'https://gemini.google.com',
        'Referer': 'https://gemini.google.com/',
        'X-Same-Domain': '1',
        'Accept-Language': 'en-US,en;q=0.9',
        'sec-ch-ua':
            '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'Sec-Fetch-Site': 'same-origin',
        if (form)
          'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
      };

  static bool _looksLoggedOut(String url, String body) {
    final u = url.toLowerCase();
    if (u.contains('accounts.google.com') ||
        u.contains('servicelogin') ||
        u.contains('/signin') ||
        u.contains('/login')) {
      return true;
    }
    final head = body.length > 4000 ? body.substring(0, 4000) : body;
    return head.contains('ServiceLogin') && !head.contains('SNlM0e');
  }

  /// Renews the short-lived `__Secure-1PSIDTS` cookie exactly like the
  /// Gemini web app does in the background (accounts.google.com
  /// RotateCookies). As long as the long-lived `__Secure-1PSID` is still
  /// valid this keeps a pasted / saved session alive for months without
  /// signing in again - on Android and Windows alike.
  Future<bool> rotateCookies({bool force = false}) async {
    if (!allowAppRotation || _viaPage) return false;
    // A session that came out of a browser (the app's built-in browser
    // on Android, the Chrome/Edge profile on Windows) is renewed BY
    // that browser. Rotating its PSIDTS from the app invalidates the
    // browser's copy and Google ends the session in both places - the
    // "signed in, then everything fails" trap when the Settings toggle
    // "Renew cookies from the app" is ON for a browser account. App
    // rotation is only for pasted sessions used nowhere else.
    if (session.format == 'Built-in browser' ||
        session.format == 'Browser profile' ||
        session.format == 'Chromium profile') {
      return false;
    }
    final psid = session.value('__Secure-1PSID');
    if (psid == null) return false;
    final last = _rotatedAt[psid];
    final now = DateTime.now();
    if (last != null &&
        now.difference(last) < Duration(seconds: force ? 20 : 600)) {
      return false;
    }
    _rotatedAt[psid] = now;
    final hc = HttpClient()..userAgent = geminiWebUserAgent;
    try {
      final req = await hc
          .postUrl(Uri.parse('https://accounts.google.com/RotateCookies'))
          .timeout(const Duration(seconds: 20));
      req.followRedirects = false;
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Origin', 'https://accounts.google.com');
      req.headers.set('Cookie', session.cookieHeader);
      req.write('[000,"-0000000000000000000"]');
      final res = await req.close().timeout(const Duration(seconds: 20));
      await res.drain<void>();
      if (res.statusCode >= 400) return false;
      final fresh = <GeminiWebCookie>[];
      for (final h in res.headers[HttpHeaders.setCookieHeader] ?? const []) {
        final c = _parseSetCookie(h);
        if (c != null) fresh.add(c);
      }
      if (fresh.isEmpty) return false;
      session = session.merged(fresh);
      _rotatedAt[session.value('__Secure-1PSID') ?? psid] = now;
      onSessionUpdated?.call(session);
      return fresh.any((c) => c.name == '__Secure-1PSIDTS');
    } catch (_) {
      return false;
    } finally {
      hc.close(force: true);
    }
  }

  static GeminiWebCookie? _parseSetCookie(String header) {
    final parts = header.split(';');
    final first = parts.first;
    final eq = first.indexOf('=');
    if (eq <= 0) return null;
    final name = first.substring(0, eq).trim();
    final value = first.substring(eq + 1).trim();
    var domain = '.google.com', path = '/', sameSite = 'None';
    var expires = -1;
    var secure = false, httpOnly = false;
    for (final a in parts.skip(1)) {
      final i = a.indexOf('=');
      final k = (i < 0 ? a : a.substring(0, i)).trim().toLowerCase();
      final v = i < 0 ? '' : a.substring(i + 1).trim();
      switch (k) {
        case 'domain':
          domain = v.startsWith('.') ? v : '.$v';
          break;
        case 'path':
          path = v.isEmpty ? '/' : v;
          break;
        case 'max-age':
          final n = int.tryParse(v);
          if (n != null) {
            expires = DateTime.now().millisecondsSinceEpoch ~/ 1000 + n;
          }
          break;
        case 'expires':
          if (expires == -1) {
            try {
              expires = HttpDate.parse(v).millisecondsSinceEpoch ~/ 1000;
            } catch (_) {}
          }
          break;
        case 'secure':
          secure = true;
          break;
        case 'httponly':
          httpOnly = true;
          break;
        case 'samesite':
          final l = v.toLowerCase();
          sameSite = l == 'lax' ? 'Lax' : (l == 'strict' ? 'Strict' : 'None');
          break;
      }
    }
    return GeminiWebCookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expires: expires,
      httpOnly: httpOnly,
      secure: secure,
      sameSite: sameSite,
    );
  }

  /// Verifies the session (handshake). When Google says it expired it
  /// first renews the cookies itself, then (Windows) pulls fresh cookies
  /// from the signed-in browser profile, and only then gives up.
  Future<void> init({Duration timeout = const Duration(seconds: 45)}) async {
    // Copied cookies were already refused in this run while the browser
    // worked: go straight to the browser.
    if (preferBrowser && !_viaPage && await _engageBrowser()) {
      try {
        await _handshake(timeout);
        return;
      } on GeminiWebException {
        _fallback = null; // fall through to the cookie path below
      }
    }
    await rotateCookies(); // keep fresh (at most every 10 min)
    String? detail;
    try {
      await _handshake(timeout);
      return;
    } on GeminiWebException catch (e) {
      if (!e.expired) rethrow;
      detail = e.message;
    }
    if (await rotateCookies(force: true)) {
      try {
        await _handshake(timeout);
        return;
      } on GeminiWebException catch (e) {
        if (!e.expired) rethrow;
        detail = e.message;
      }
    }
    final hook = refreshSession;
    if (hook != null && !_viaPage) {
      GeminiWebSession? fresh;
      try {
        fresh = await hook();
      } catch (_) {}
      if (fresh != null) {
        session = fresh;
        _minimalCookies = false;
        try {
          await _handshake(timeout);
          return;
        } on GeminiWebException catch (e) {
          if (!e.expired) rethrow;
          detail = e.message;
        }
      }
    }
    // Google refuses the cookies outside the browser: run inside it.
    if (await _handshakeInBrowser(timeout)) return;
    // Say what actually failed. The old message always blamed the
    // browser profile ("not signed in") even when the real failure was
    // Google refusing the copied cookies - which sent users re-signing
    // in to Gmail in Chrome, something that can never fix this.
    throw GeminiWebException(
        browserFallback != null || refreshSession != null
            ? 'Gemini refused the saved session when it was used outside '
                'the browser${detail == null ? '' : ' ($detail)'}, and the '
                'request inside the app\'s own browser did not succeed '
                'either - that browser profile may be signed out (signing '
                'in to Gmail in your normal Chrome or the Gmail app does '
                'not count). $_signInHint'
            : 'The Gemini session expired and could not be renewed '
                'automatically. Refresh the cookies in the Windows app '
                '(Settings > Copy session) or paste a new export.',
        expired: true);
  }

  /// Switches to the hidden signed-in browser profile and gets the page
  /// token there. False when there is no such browser or it is signed out.
  Future<bool> _handshakeInBrowser(Duration timeout) async {
    if (!await _engageBrowser()) return false;
    try {
      await _handshake(timeout);
      preferBrowser = true;
      return true;
    } on GeminiWebException {
      _fallback = null;
      return false;
    }
  }

  /// After an authenticated request is rejected, first reacquire the
  /// browser's current cookies (when available), then get a new token.
  /// Page transports already use the browser's live cookie jar. When the
  /// cookies stay refused, the request moves into the signed-in browser.
  Future<void> _recoverRejectedSession() async {
    _at = null;
    const t = Duration(seconds: 45);
    if (_viaPage) {
      try {
        await _handshake(t);
        return;
      } on GeminiWebException catch (e) {
        if (!e.expired && !_pageBroken) rethrow;
      }
    } else {
      if (refreshSession != null) {
        try {
          final fresh = await refreshSession!();
          if (fresh != null) {
            session = fresh;
            _minimalCookies = false;
            onSessionUpdated?.call(fresh);
          }
        } catch (_) {
          // A fresh token with the current cookies may still be enough.
        }
      }
      try {
        await _handshake(t);
        return;
      } on GeminiWebException catch (e) {
        if (!e.expired) rethrow;
      }
    }
    if (await _handshakeInBrowser(t)) return;
    throw GeminiWebException(
        'Gemini could not refresh the signed-in session automatically. '
        'Check that Gemini is signed in inside the app browser. $_signInHint',
        expired: true);
  }

  GeminiWebException _rejectedAfterRefresh() => GeminiWebException(
      'Gemini rejected the request even after automatic session refresh. '
      'Check that Gemini is signed in inside the app browser. $_signInHint',
      expired: true);

  /// One more way out after a second rejection: when the request was
  /// still using copied cookies, move it into the signed-in browser.
  Future<bool> _escalateToBrowser() async {
    if (_viaPage) return false;
    _at = null;
    return _handshakeInBrowser(const Duration(seconds: 45));
  }

  Future<void> _handshake(Duration timeout) async {
    if (_viaPage) {
      final r = await _pageRequest('GET', 'https://gemini.google.com/app',
          timeout: timeout);
      _readAppPage(r.status, r.url, r.body);
      return;
    }
    // Same order as the workflow's `getGeminiSession`: the full cookie
    // jar first, then only the essential sign-in cookies.
    GeminiWebException? firstErr;
    for (final minimal in _minimalCookies ? const [true] : const [false, true]) {
      if (minimal && session.minimalCookieHeader == session.cookieHeader) {
        break; // nothing different to try
      }
      _minimalCookies = minimal;
      http.Response res;
      try {
        res = await http.get(Uri.parse('https://gemini.google.com/app'),
            headers: {
              'Accept': 'text/html,application/xhtml+xml,application/xml;'
                  'q=0.9,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9',
              'Cookie': _cookie,
              'User-Agent': geminiWebUserAgent,
            }).timeout(timeout);
      } on TimeoutException {
        throw GeminiWebException(
            'gemini.google.com did not respond within ${timeout.inSeconds}s.');
      } catch (e) {
        throw GeminiWebException('Could not reach gemini.google.com: $e');
      }
      try {
        _readAppPage(
            res.statusCode, res.request?.url.toString() ?? '', res.body);
        return;
      } on GeminiWebException catch (e) {
        if (!e.expired) rethrow;
        firstErr ??= e;
      }
    }
    _minimalCookies = false;
    throw firstErr!;
  }

  Future<GeminiPageResponse> _pageRequest(String method, String url,
      {Map<String, String> headers = const {},
      String? body,
      Uint8List? file,
      String fileName = 'image.jpg',
      String fileMime = 'image/jpeg',
      required Duration timeout}) async {
    try {
      return await _tx!
          .request(method, url,
              headers: headers,
              body: body,
              file: file,
              fileName: fileName,
              fileMime: fileMime,
              timeout: timeout)
          .timeout(timeout + const Duration(seconds: 10));
    } on TimeoutException {
      _pageBroken = true;
      throw GeminiWebException(
          'Gemini (in the browser) did not respond within ${timeout.inSeconds}s.');
    } on GeminiWebException {
      rethrow;
    } catch (e) {
      _pageBroken = true;
      throw GeminiWebException('Gemini request in the browser failed: $e');
    }
  }

  void _readAppPage(int statusCode, String finalUrl, String body) {
    final res = (statusCode: statusCode, body: body);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw GeminiWebException(
          'Gemini rejected the session (HTTP ${res.statusCode}).',
          expired: true);
    }
    if (res.statusCode >= 400) {
      throw GeminiWebException(
          'gemini.google.com returned HTTP ${res.statusCode}.');
    }
    if (_looksLoggedOut(finalUrl, res.body)) {
      throw GeminiWebException(
          'The Gemini session is signed out (redirected to the Google login '
          'page).',
          expired: true);
    }

    final at = RegExp(r'"SNlM0e":"(.*?)"').firstMatch(res.body)?.group(1);
    if (at == null || at.isEmpty) {
      throw GeminiWebException(
          'The Gemini session is expired or invalid (no auth token in the '
          'page: HTTP ${res.statusCode}, ${res.body.length} bytes, '
          'final URL ${finalUrl.isEmpty ? '?' : finalUrl}).',
          expired: true);
    }
    _at = at;
    final bl = RegExp(r'"cfb2h":"(.*?)"').firstMatch(res.body)?.group(1);
    if (bl != null && bl.isNotEmpty) _bl = bl;
    final push = RegExp(r'"qKIAYe":\s*"(.*?)"').firstMatch(res.body)?.group(1);
    if (push != null && push.isNotEmpty) _pushId = push;
    newChat();
  }

  /// Forget the conversation — the equivalent of the workflow's
  /// `goto('/app/new')` before every prompt.
  void newChat() {
    _cid = null;
    _rid = null;
    _rcid = null;
  }

  /// Sends [prompt] and returns Gemini's answer text.
  ///
  /// [completeWhen] mirrors the workflow's streaming guard: the reply is
  /// only accepted once it matches (e.g. the closing `[/DESCRIPTION]` tag),
  /// otherwise it is treated as a partial answer and retried.
  Future<String> ask(
    String prompt, {
    RegExp? completeWhen,
    Duration timeout = const Duration(seconds: 120),
    int attempts = 3,
    bool freshChat = true,
    List<GeminiWebUpload> files = const [],
  }) async {
    if (!ready) await init();
    Object? lastErr;
    var recoveredAuth = false;
    var escalated = false;
    for (var i = 0; i < attempts; i++) {
      if (freshChat) newChat();
      try {
        final text = await _send(prompt, timeout: timeout, files: files);
        if (text.trim().isEmpty) {
          lastErr = 'Gemini web returned an empty reply.';
        } else if (completeWhen != null && !completeWhen.hasMatch(text)) {
          lastErr = 'Gemini web reply was cut off before the closing marker.';
        } else {
          return text.trim();
        }
      } on GeminiWebException catch (e) {
        lastErr = e.message;
        if (e.expired) {
          if (recoveredAuth) {
            if (escalated || !await _escalateToBrowser()) {
              throw _rejectedAfterRefresh();
            }
            escalated = true;
          } else {
            recoveredAuth = true;
            await _recoverRejectedSession();
          }
          i--; // one extra authentication retry, even when attempts == 1
          continue;
        }
      } on TimeoutException {
        lastErr = 'Gemini web timed out after ${timeout.inSeconds}s.';
      } catch (e) {
        lastErr = e.toString();
      }
      if (i < attempts - 1) {
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
    throw GeminiWebException('Gemini web failed after $attempts attempts. '
        'Last: $lastErr');
  }

  /// Uploads one image to Google's push service (the same endpoint the
  /// Gemini web app uses when you attach a picture) and returns the
  /// upload reference that StreamGenerate expects.
  Future<GeminiWebUpload> uploadImage(
    Uint8List inputBytes, {
    String filename = 'image.jpg',
    String mimeType = 'image/jpeg',
    Duration timeout = const Duration(seconds: 90),
  }) async {
    // His rule (2026-11-27): EVERY image attached to Gemini goes as
    // JPG, whatever its source format is. This is the single choke
    // point all attachments pass through (image-to-prompt, image
    // generation references, review asks), so the conversion lives
    // here: non-JPEG bytes are decoded and re-encoded as JPEG and
    // the filename/mime are forced to .jpg / image/jpeg - a PNG or
    // WebP can no longer leak through with a wrong label.
    final norm = ensureJpegForGemini(inputBytes,
        filename: filename, mimeType: mimeType);
    final bytes = norm.bytes;
    filename = norm.filename;
    mimeType = norm.mimeType;
    if (!ready) await init();
    try {
      return await _uploadAndProcess(bytes, filename: filename,
          mimeType: mimeType, timeout: timeout);
    } on GeminiWebException catch (e) {
      if (!e.expired) rethrow;
      await _recoverRejectedSession();
      try {
        return await _uploadAndProcess(bytes, filename: filename,
            mimeType: mimeType, timeout: timeout);
      } on GeminiWebException catch (retryError) {
        if (!retryError.expired) rethrow;
        if (!await _escalateToBrowser()) throw _rejectedAfterRefresh();
        try {
          return await _uploadAndProcess(bytes, filename: filename,
              mimeType: mimeType, timeout: timeout);
        } on GeminiWebException catch (last) {
          if (last.expired) throw _rejectedAfterRefresh();
          rethrow;
        }
      }
    }
  }

  /// Upload + the ProcessFile registration the current Gemini web
  /// UI performs right after every upload (HAR-verified 2026-11-27:
  /// push upload -> ProcessFile with the attachment entry). Without
  /// ProcessFile the backend never links the uploaded file to the
  /// session, so the model answers as if no picture was attached.
  /// ProcessFile is best-effort: its reply is an acknowledgement,
  /// the send still carries the attachment entry itself.
  Future<GeminiWebUpload> _uploadAndProcess(
    Uint8List bytes, {
    required String filename,
    required String mimeType,
    required Duration timeout,
  }) async {
    final up = await _uploadImageOnce(bytes,
        filename: filename, mimeType: mimeType, timeout: timeout);
    await _processFile(up, mimeType, timeout);
    return up;
  }

  Future<void> _processFile(
      GeminiWebUpload up, String mimeType, Duration timeout) async {
    try {
      final at = _at;
      if (at == null || at.isEmpty) return;
      final entry = [
        [up.ref, null, 1, mimeType],
        up.filename,
        null,
        null,
        null,
        null,
        null,
        null,
        [0]
      ];
      final inner = jsonEncode([
        [entry],
        null,
        1,
        ['en']
      ]);
      final freq = jsonEncode([null, inner]);
      final url =
          'https://gemini.google.com/_/BardChatUi/data/assistant.lamda.'
          'BardFrontendService/ProcessFile'
          '?bl=${Uri.encodeQueryComponent(_bl)}&_reqid=$_reqid&rt=c';
      if (_viaPage) {
        final form = 'f.req=${Uri.encodeQueryComponent(freq)}'
            '&at=${Uri.encodeQueryComponent(at)}';
        await _pageRequest('POST', url,
            headers: {
              'Content-Type':
                  'application/x-www-form-urlencoded;charset=UTF-8',
              'X-Same-Domain': '1',
            },
            body: form,
            timeout: timeout);
      } else {
        await http
            .post(Uri.parse(url),
                headers: _headers(form: true),
                body: {'f.req': freq, 'at': at})
            .timeout(timeout);
      }
      _reqid += 100000;
    } catch (_) {
      // Best-effort registration; the send proceeds either way.
    }
  }

  /// The current web UI's upload: resumable protocol on
  /// push.clients6.google.com (HAR-verified 2026-11-27). Step 1
  /// "start" returns an upload session URL in a response header;
  /// step 2 "upload, finalize" posts the raw bytes and the
  /// response body IS the file reference
  /// (/contrib_service/ttl_1d/...). Null on any mismatch so the
  /// caller can fall back to the legacy content-push upload.
  Future<GeminiWebUpload?> _uploadResumablePush(
    Uint8List bytes, {
    required String filename,
    required String mimeType,
    required Duration timeout,
  }) async {
    try {
      final base = {
        'Push-ID': _pushId,
        'X-Tenant-Id': 'bard-storage',
        'User-Agent': geminiWebUserAgent,
        'Cookie': _cookie,
        'Origin': 'https://gemini.google.com',
        'Referer': 'https://gemini.google.com/',
      };
      final start = await http
          .post(Uri.parse('https://push.clients6.google.com/upload/'),
              headers: {
                ...base,
                'Content-Type':
                    'application/x-www-form-urlencoded;charset=UTF-8',
                'X-Goog-Upload-Protocol': 'resumable',
                'X-Goog-Upload-Command': 'start',
                'X-Goog-Upload-Header-Content-Length': '${bytes.length}',
                'X-Goog-Upload-Header-Content-Type': mimeType,
              },
              body: 'File name: $filename')
          .timeout(timeout);
      final sessionUrl = start.headers['x-goog-upload-url'];
      if (start.statusCode != 200 || sessionUrl == null || sessionUrl.isEmpty) {
        return null;
      }
      final req = http.Request('POST', Uri.parse(sessionUrl));
      req.headers.addAll({
        ...base,
        'X-Goog-Upload-Command': 'upload, finalize',
        'X-Goog-Upload-Offset': '0',
      });
      req.bodyBytes = bytes;
      final streamed = await req.send().timeout(timeout);
      final body = (await streamed.stream.bytesToString()).trim();
      if (streamed.statusCode != 200 || !body.startsWith('/contrib_service/')) {
        return null;
      }
      return GeminiWebUpload(body, filename);
    } catch (_) {
      return null;
    }
  }

  Future<GeminiWebUpload> _uploadImageOnce(
    Uint8List bytes, {
    required String filename,
    required String mimeType,
    required Duration timeout,
  }) async {
    // HTTP path first tries the current resumable push upload; the
    // legacy content-push endpoint below stays as the fallback.
    if (!_viaPage) {
      final up = await _uploadResumablePush(bytes,
          filename: filename, mimeType: mimeType, timeout: timeout);
      if (up != null) return up;
    }
    if (_viaPage) {
      final r = await _pageRequest(
          'POST', 'https://content-push.googleapis.com/upload',
          headers: {'Push-ID': _pushId, 'X-Tenant-Id': 'bard-storage'},
          file: bytes,
          fileName: filename,
          fileMime: mimeType,
          timeout: timeout);
      final b = r.body.trim();
      if (r.status != 200 || b.isEmpty) {
        throw GeminiWebException(
            'Image upload to Gemini failed (HTTP ${r.status}).',
            expired: r.status == 401 || r.status == 403);
      }
      return GeminiWebUpload(b, filename);
    }
    final req = http.MultipartRequest(
        'POST', Uri.parse('https://content-push.googleapis.com/upload'));
    req.headers.addAll({
      'Push-ID': _pushId,
      'X-Tenant-Id': 'bard-storage',
      'User-Agent': geminiWebUserAgent,
      'Cookie': _cookie,
      'Origin': 'https://gemini.google.com',
      'Referer': 'https://gemini.google.com/',
    });
    req.files.add(http.MultipartFile.fromBytes('file', bytes,
        filename: filename, contentType: MediaType.parse(mimeType)));
    http.StreamedResponse res;
    try {
      res = await req.send().timeout(timeout);
    } on TimeoutException {
      throw GeminiWebException(
          'Image upload to Gemini timed out after ${timeout.inSeconds}s.');
    } catch (e) {
      throw GeminiWebException('Image upload to Gemini failed: $e');
    }
    final body = (await res.stream.bytesToString()).trim();
    if (res.statusCode != 200 || body.isEmpty) {
      throw GeminiWebException(
          'Image upload to Gemini failed (HTTP ${res.statusCode}).',
          expired: res.statusCode == 401 || res.statusCode == 403);
    }
    return GeminiWebUpload(body, filename);
  }

  /// Uploads [bytes] once and asks [prompt] about the picture (image to
  /// text). Retries reuse the same upload reference.
  Future<String> askWithImage(
    String prompt,
    Uint8List bytes, {
    String filename = 'image.jpg',
    String mimeType = 'image/jpeg',
    RegExp? completeWhen,
    Duration timeout = const Duration(seconds: 150),
    int attempts = 3,
  }) async {
    if (!ready) await init();
    GeminiWebUpload? up;
    Object? lastErr;
    for (var i = 0; i < 2 && up == null; i++) {
      try {
        up = await uploadImage(bytes, filename: filename, mimeType: mimeType);
      } on GeminiWebException catch (e) {
        if (e.expired) rethrow;
        lastErr = e.message;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    if (up == null) throw GeminiWebException('$lastErr');
    return ask(prompt,
        completeWhen: completeWhen,
        timeout: timeout,
        attempts: attempts,
        files: [up]);
  }

  Future<String> _send(String prompt,
          {required Duration timeout,
          List<GeminiWebUpload> files = const []}) async =>
      _parseStream(await _sendRaw(prompt, timeout: timeout, files: files));

  Future<String> _sendRaw(String prompt,
      {required Duration timeout,
      List<GeminiWebUpload> files = const [],
      int imageVariant = 0,
      String? aspectRatio}) async {
    final at = _at;
    if (at == null || at.isEmpty) {
      throw GeminiWebException('Gemini web session is not initialized.',
          expired: true);
    }
    final url =
        Uri.parse('https://gemini.google.com/_/BardChatUi/data/assistant.lamda.'
            'BardFrontendService/StreamGenerate'
            '?bl=${Uri.encodeQueryComponent(_bl)}'
            '${imageVariant > 0 ? '&hl=en' : ''}&_reqid=$_reqid&rt=c');
    final inner = imageVariant > 0
        ? jsonEncode(imageRequestPayload(prompt, files,
            variant: imageVariant, aspectRatio: aspectRatio))
        : jsonEncode([
            files.isEmpty
                ? [prompt]
                : [
                    prompt,
                    0,
                    null,
                    [
                      // Full attachment entry - the same shape the
                      // image-generation payload (variant 1) and the
                      // current Gemini web UI use. The old minimal
                      // [[ref], filename] entry is silently ignored
                      // by Gemini now: the model never sees the
                      // picture, answers without it, and the reply
                      // lacks the closing marker the caller waits
                      // for ("cut off before the closing marker").
                      for (final f in files)
                        [
                          [f.ref, null, 1, _mimeOf(f.filename)],
                          f.filename,
                          null,
                          null,
                          null,
                          null,
                          null,
                          null,
                          [0]
                        ]
                    ],
                    null,
                    null,
                    0,
                  ],
            null,
            [_cid, _rid, _rcid],
          ]);
    final freq = jsonEncode([null, inner]);

    final ({int statusCode, String text}) res;
    if (_viaPage) {
      final form = 'f.req=${Uri.encodeQueryComponent(freq)}'
          '&at=${Uri.encodeQueryComponent(at)}';
      final r = await _pageRequest('POST', url.toString(),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
            'X-Same-Domain': '1',
          },
          body: form,
          timeout: timeout);
      res = (statusCode: r.status, text: r.body);
    } else {
      final h = await http.post(url,
          headers: _headers(form: true),
          body: {'f.req': freq, 'at': at}).timeout(timeout);
      res = (
        statusCode: h.statusCode,
        text: utf8.decode(h.bodyBytes, allowMalformed: true)
      );
    }
    _reqid += 100000;

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw GeminiWebException(
          'Gemini rejected the session (HTTP ${res.statusCode}).',
          expired: true);
    }
    if (res.statusCode == 429) {
      throw GeminiWebException(
          'Gemini web is rate limiting this account (HTTP 429). '
          'Wait a moment and retry.');
    }
    if (res.statusCode != 200) {
      throw GeminiWebException('Gemini web HTTP ${res.statusCode}.');
    }
    return res.text;
  }

  /// StreamGenerate body for an image request, in the shape the Gemini
  /// page (and the Gemini HD Studio extension) sends. With this shape the
  /// finished image links come back inside the same stream, so no chat
  /// read-back is needed. [variant] 1 is the full attachment shape, 2 and
  /// 3 are the older attachment shapes used as fallbacks.
  static List<dynamic> imageRequestPayload(
      String prompt, List<GeminiWebUpload> files,
      {int variant = 1, String? aspectRatio}) {
    List<dynamic> tail(List<dynamic> first) => [
          first,
          ['en'],
          ['', '', ''],
          null,
          null,
          null,
          [1],
          1,
          null,
          null,
          1,
          0,
        ];
    if (files.isEmpty) {
      return tail([prompt, 0, null, null, null, null, 0]);
    }
    final ar = (aspectRatio ?? '').trim();
    if (variant == 1) {
      final atts = [
        for (final f in files)
          [
            [f.ref, null, 1, _mimeOf(f.filename)],
            f.filename,
            null,
            null,
            null,
            null,
            null,
            null,
            [0]
          ]
      ];
      final first = <dynamic>[prompt, 0, null, atts, null, null, 0];
      if (ar.isNotEmpty && ar != 'auto') {
        first.addAll([
          null,
          null,
          [
            null,
            null,
            null,
            null,
            null,
            null,
            [
              null,
              [null, ar]
            ]
          ]
        ]);
      }
      final inner = tail(first);
      while (inner.length < 41) {
        inner.add(null);
      }
      inner.add([1]); // index 41
      return inner;
    }
    if (variant == 2) {
      return tail([
        prompt,
        0,
        null,
        [
          for (final f in files)
            [
              [f.ref, null, 1, _mimeOf(f.filename)],
              f.filename,
              null,
              null,
              null,
              null,
              null,
              null,
              [0]
            ]
        ],
        null,
        null,
        0
      ]);
    }
    return tail([
      prompt,
      0,
      null,
      [
        for (final f in files)
          [
            [f.ref],
            f.filename
          ]
      ],
      null,
      null,
      0
    ]);
  }

  static String _mimeOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Asks Gemini web to DRAW [prompt] (the same request the Gemini page
  /// sends; image generation is chosen by Gemini from the wording).
  /// [files] are uploaded reference pictures (image editing / remix).
  ///
  /// Fast path: the page's image request shape, which returns the image
  /// links in the stream itself. Only when no link comes back does it
  /// fall back to reading the chat (slower).
  Future<GeminiGeneratedImages> generateImages(
    String prompt, {
    List<GeminiWebUpload> files = const [],
    String? aspectRatio,
    Duration timeout = const Duration(seconds: 180),
    int attempts = 2,
    Duration chatPollTimeout = const Duration(seconds: 30),
  }) async {
    if (!ready) await init();
    Object? lastErr;
    var recoveredAuth = false;
    var escalated = false;
    final variants = files.isEmpty ? const [1] : const [1, 2, 3];
    for (var i = 0; i < attempts; i++) {
      try {
        String raw = '';
        String? rawCid;
        Object? variantErr;
        for (final v in variants) {
          newChat();
          try {
            raw = await _sendRaw(prompt,
                timeout: timeout,
                files: files,
                imageVariant: v,
                aspectRatio: aspectRatio);
          } on GeminiWebException catch (e) {
            if (e.expired) rethrow;
            variantErr = e.message;
            continue; // e.g. HTTP 400 -> try the next attachment shape
          }
          final urls = generatedImageUrls(raw);
          var text = '';
          try {
            text = _parseStream(raw);
          } catch (_) {}
          if (urls.isNotEmpty) return GeminiGeneratedImages(urls, text);
          rawCid = conversationIdFrom(raw) ?? _cid;
          if (_noImageAnswer(text)) break; // a real text refusal
          if (rawCid != null && rawCid.isNotEmpty) break;
        }
        if (raw.isEmpty) throw GeminiWebException('$variantErr');
        var text = '';
        try {
          text = _parseStream(raw);
        } catch (_) {}
        // Slow fallback: the picture finished after the stream closed.
        final cid = rawCid;
        var urls = <String>[];
        String chat = '';
        if (cid != null && cid.isNotEmpty) {
          final until = DateTime.now().add(chatPollTimeout);
          while (urls.isEmpty && DateTime.now().isBefore(until)) {
            await Future.delayed(const Duration(seconds: 3));
            try {
              chat = await _readChat(cid);
              urls = generatedImageUrls(chat);
            } catch (_) {}
          }
          if (urls.isNotEmpty) return GeminiGeneratedImages(urls, text);
          final reader = _tx;
          if (reader is GeminiChatImageReader) {
            try {
              final b = await (reader as GeminiChatImageReader)
                  .chatImage(cid, timeout: const Duration(seconds: 45));
              if (b != null && b.isNotEmpty) {
                return GeminiGeneratedImages(const [], text, bytes: b);
              }
            } catch (_) {}
          }
        }
        lastReplyFile = await _dumpReply(
            'prompt-stream:\n$raw\n\nread-chat ($cid):\n$chat');
        if (raw.contains('accounts.google.com/ServiceLogin') ||
            raw.contains('ServiceLogin')) {
          throw GeminiWebException('The Gemini session expired. Sign in again.',
              expired: true);
        }
        final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final where =
            lastReplyFile == null ? '' : ' (reply saved to $lastReplyFile)';
        lastErr = t.isEmpty
            ? 'Gemini made no readable image link$where.'
            : 'Gemini replied without an image: '
                '"${t.substring(0, t.length.clamp(0, 160))}"$where';
      } on GeminiWebException catch (e) {
        lastErr = e.message;
        if (e.expired) {
          if (recoveredAuth) {
            if (escalated || !await _escalateToBrowser()) {
              throw _rejectedAfterRefresh();
            }
            escalated = true;
          } else {
            recoveredAuth = true;
            await _recoverRejectedSession();
          }
          i--;
          continue;
        }
      } on TimeoutException {
        lastErr = 'Gemini image generation timed out after '
            '${timeout.inSeconds}s.';
      } catch (e) {
        lastErr = e.toString();
      }
      if (i < attempts - 1) await Future.delayed(const Duration(seconds: 2));
    }
    throw GeminiWebException('$lastErr');
  }

  /// Gemini answered in words that it will not / cannot draw.
  static bool _noImageAnswer(String text) => RegExp(
          r"(can't|cannot|unable to|not able to) (create|generate|make|draw)"
          r'|limit|quota|try again later',
          caseSensitive: false)
      .hasMatch(text);

  /// Where the last reply without an image was saved (for support).
  static String? lastReplyFile;

  static Future<String?> _dumpReply(String text) async {
    try {
      final f = File('${Directory.systemTemp.path}'
          '${Platform.pathSeparator}ais_gemini_last_reply.txt');
      await f.writeAsString(text);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  /// Conversation id (c_...) of a StreamGenerate reply.
  static String? conversationIdFrom(String raw) {
    String? found;
    void walk(dynamic n, int depth) {
      if (found != null || depth > 6) return;
      if (n is String) {
        if (RegExp(r'^c_[0-9a-f]{8,}$').hasMatch(n)) found = n;
      } else if (n is List) {
        for (final e in n) {
          walk(e, depth + 1);
        }
      }
    }

    for (final line in LineSplitter.split(raw)) {
      final t = line.trim();
      if (!t.startsWith('[')) continue;
      try {
        final chunk = jsonDecode(t);
        if (chunk is! List) continue;
        for (final e in chunk) {
          if (e is List && e.length > 2 && e[0] == 'wrb.fr' && e[2] is String) {
            walk(jsonDecode(e[2] as String), 0);
            if (found != null) return found;
          }
        }
      } catch (_) {}
    }
    return found;
  }

  /// Reads a conversation back (batchexecute hNvQHb, what the page calls
  /// when you open a chat). Returns the raw reply.
  Future<String> _readChat(String cid) async {
    final at = _at ?? '';
    final path = '/app/${cid.startsWith('c_') ? cid.substring(2) : cid}';
    final url = 'https://gemini.google.com/_/BardChatUi/data/batchexecute'
        '?rpcids=hNvQHb&source-path=${Uri.encodeQueryComponent(path)}'
        '&bl=${Uri.encodeQueryComponent(_bl)}&_reqid=$_reqid&rt=c';
    _reqid += 100000;
    final freq = jsonEncode([
      [
        [
          'hNvQHb',
          jsonEncode([
            cid,
            10,
            null,
            1,
            [1],
            [4],
            null,
            1
          ]),
          null,
          'generic'
        ]
      ]
    ]);
    if (_viaPage) {
      final r = await _pageRequest('POST', url,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
            'X-Same-Domain': '1',
          },
          body: 'f.req=${Uri.encodeQueryComponent(freq)}'
              '&at=${Uri.encodeQueryComponent(at)}',
          timeout: const Duration(seconds: 30));
      return r.body;
    }
    final h = await http.post(Uri.parse(url),
        headers: _headers(form: true),
        body: {'f.req': freq, 'at': at}).timeout(const Duration(seconds: 30));
    return utf8.decode(h.bodyBytes, allowMalformed: true);
  }

  static final RegExp _genUrl = RegExp(
      r'^https://[a-z0-9.-]*(googleusercontent\.com|usercontent\.google\.com)'
      r'/(rd-)?gg(-dl)?/',
      caseSensitive: false);

  /// Generated-image links inside a StreamGenerate reply (any depth).
  static List<String> generatedImageUrls(String raw) {
    final out = <String>[];
    void walk(dynamic n) {
      if (n is String) {
        if (_genUrl.hasMatch(n) && !out.contains(n)) {
          out.add(n);
        } else if (n.length > 40 &&
            n.startsWith('[') &&
            n.contains('googleusercontent')) {
          try {
            walk(jsonDecode(n)); // JSON inside a string
          } catch (_) {}
        }
      } else if (n is List) {
        for (final e in n) {
          walk(e);
        }
      } else if (n is Map) {
        for (final e in n.values) {
          walk(e);
        }
      }
    }

    // Image candidates live under inner[4]; any Google image link there
    // (not an avatar) is the drawn picture.
    final cands = <String>[];
    void walkCand(dynamic n) {
      if (n is String) {
        for (final m in _anyImg.allMatches(n)) {
          final u = m.group(0)!;
          if (u.length > 48 &&
              !u.contains('/a/') &&
              !u.contains('/a-/') &&
              !cands.contains(u)) {
            cands.add(u);
          }
        }
      } else if (n is List) {
        for (final e in n) {
          walkCand(e);
        }
      }
    }

    for (final line in LineSplitter.split(raw)) {
      final t = line.trim();
      if (!t.startsWith('[')) continue;
      dynamic chunk;
      try {
        chunk = jsonDecode(t);
      } catch (_) {
        continue;
      }
      if (chunk is! List) continue;
      for (final entry in chunk) {
        if (entry is List &&
            entry.length > 2 &&
            entry[0] == 'wrb.fr' &&
            entry[2] is String) {
          try {
            final inner = jsonDecode(entry[2] as String);
            walk(inner);
            if (inner is List && inner.length > 4 && inner[4] is List) {
              walkCand(inner[4]);
            }
          } catch (_) {}
        }
      }
    }
    if (out.isEmpty) out.addAll(cands);
    if (out.isEmpty) {
      // Last resort: links written straight into the escaped stream text.
      final un = raw
          .replaceAll(r'\u003d', '=')
          .replaceAll(r'\u0026', '&')
          .replaceAll(r'\/', '/');
      for (final m in _rawGen.allMatches(un)) {
        final u = m.group(0)!;
        if (!out.contains(u)) out.add(u);
      }
    }
    // One link per picture (the same image can appear in several sizes).
    final seen = <String>{};
    return [
      for (final u in out)
        if (seen.add(_imageBase(u))) u
    ];
  }

  static final RegExp _anyImg =
      RegExp(r'https://(?:lh3\.googleusercontent\.com|[a-zA-Z0-9-]+\.fife\.'
          r'usercontent\.google\.com)/[a-zA-Z0-9_\-/=+%]+');
  static final RegExp _rawGen = RegExp(
      r'https://(?:lh3\.googleusercontent\.com|[a-zA-Z0-9-]+\.fife\.'
      r'usercontent\.google\.com)/(?:gg-dl|rd-gg-dl|gg)/[a-zA-Z0-9_\-/=+%]+');

  static String _imageBase(String url) {
    var u = url.split('?').first.replaceAll(RegExp(r'["\x27\\]+$'), '');
    final slash = u.lastIndexOf('/');
    final eq = u.indexOf('=', slash < 0 ? 0 : slash);
    if (eq > 0) u = u.substring(0, eq);
    return u;
  }

  /// Original full-size link (`=s0`), what the extension downloads.
  static String hdImageUrl(String url) => '${_imageBase(url)}=s0';

  /// Download link for [url] at [size] px (long side), as the Gemini page
  /// asks for it: `=s<size>-rj?alr=yes`.
  static String sizedImageUrl(String url, int size) {
    var base = url.split('?').first;
    final slash = base.lastIndexOf('/');
    final eq = base.indexOf('=', slash < 0 ? 0 : slash);
    if (eq > 0) base = base.substring(0, eq);
    return '$base=s$size-rj?alr=yes';
  }

  /// Downloads a generated image. The link answers with the next link
  /// as text (gg-dl -> usercontent -> rd-gg-dl) until the JPEG/PNG
  /// itself; every hop needs the signed-in Google session.
  Future<Uint8List> downloadGeneratedImage(String url,
      {int size = 2048, Duration timeout = const Duration(seconds: 90)}) async {
    // Original size first (=s0, one quick hop chain), then the sized
    // link the page uses.
    Object? err;
    for (final first in [hdImageUrl(url), sizedImageUrl(url, size)]) {
      if (_viaPage) {
        try {
          return await _hops(first, timeout, page: true);
        } catch (e) {
          err = e; // fall through to the direct cookie path
        }
      }
      try {
        return await _hops(first, timeout, page: false);
      } catch (e) {
        err = e;
      }
    }
    if (err is GeminiWebException) throw err;
    throw GeminiWebException('Image download from Gemini failed: $err');
  }

  Future<Uint8List> _hops(String url, Duration timeout,
      {required bool page}) async {
    var u = url;
    final hd = url.endsWith('=s0');
    for (var hop = 0; hop < 6; hop++) {
      if (page) {
        final r = await _tx!.request('GET', u, timeout: timeout);
        final b = r.bytes;
        if (b != null && b.isNotEmpty) return b;
        final next = r.body.trim();
        if (r.status == 200 && next.startsWith('http')) {
          u = hd ? hdImageUrl(next) : next;
          continue;
        }
        throw GeminiWebException('Image download from Gemini failed at '
            'step ${hop + 1} (HTTP ${r.status}, ${r.contentType}).');
      }
      final res = await http.get(Uri.parse(u), headers: {
        'Cookie': _cookie,
        'User-Agent': geminiWebUserAgent,
        'Origin': 'https://gemini.google.com',
        'Referer': 'https://gemini.google.com/',
      }).timeout(timeout);
      final ct = res.headers['content-type'] ?? '';
      if (res.statusCode == 200 && ct.startsWith('image/')) {
        return res.bodyBytes;
      }
      final next = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
      if (res.statusCode == 200 && next.startsWith('http')) {
        u = hd ? hdImageUrl(next) : next;
        continue;
      }
      throw GeminiWebException('Image download from Gemini failed at step '
          '${hop + 1} (HTTP ${res.statusCode}, $ct).');
    }
    throw GeminiWebException('Image download from Gemini: too many hops.');
  }

  /// Parses the `)]}'`-prefixed chunked batchexecute stream and returns the
  /// answer text, capturing the conversation ids on the way.
  String _parseStream(String raw) {
    final payloads = <String>[];
    for (final line in LineSplitter.split(raw)) {
      final t = line.trim();
      if (!t.startsWith('[')) continue;
      dynamic chunk;
      try {
        chunk = jsonDecode(t);
      } catch (_) {
        continue;
      }
      if (chunk is! List) continue;
      for (final entry in chunk) {
        if (entry is List &&
            entry.length > 2 &&
            entry[0] == 'wrb.fr' &&
            entry[2] is String) {
          payloads.add(entry[2] as String);
        }
      }
    }

    var best = '';
    for (final payload in payloads) {
      dynamic body;
      try {
        body = jsonDecode(payload);
      } catch (_) {
        continue;
      }
      final text = _extractAnswer(body);
      if (text != null && text.trim().length > best.trim().length) {
        best = text;
        _captureIds(body);
      }
    }

    if (best.trim().isEmpty) {
      if (raw.contains('accounts.google.com') || raw.contains('ServiceLogin')) {
        throw GeminiWebException(
            'The Gemini session expired mid-run.',
            expired: true);
      }
      throw GeminiWebException(
          'Gemini web returned no readable answer (the page layout or the '
          'session may have changed).');
    }
    return best;
  }

  static String? _extractAnswer(dynamic body) {
    // Canonical shape: body[4][0][1][0]
    try {
      final cands = body[4];
      if (cands is List && cands.isNotEmpty) {
        final first = cands[0];
        if (first is List && first.length > 1) {
          final texts = first[1];
          if (texts is List && texts.isNotEmpty) {
            final t = texts[0];
            if (t is String && t.trim().isNotEmpty) return t;
          }
        }
      }
    } catch (_) {}
    // Tolerant fallback: the longest substantial string in the payload.
    var longest = '';
    void walk(dynamic n) {
      if (n is String) {
        if (n.length > longest.length) longest = n;
      } else if (n is List) {
        for (final e in n) {
          walk(e);
        }
      } else if (n is Map) {
        for (final e in n.values) {
          walk(e);
        }
      }
    }

    walk(body);
    return longest.trim().length >= 20 ? longest : null;
  }

  void _captureIds(dynamic body) {
    try {
      final meta = body[1];
      if (meta is List && meta.length > 1) {
        _cid = meta[0]?.toString();
        _rid = meta[1]?.toString();
      }
      final cands = body[4];
      if (cands is List && cands.isNotEmpty && cands[0] is List) {
        _rcid = (cands[0] as List)[0]?.toString();
      }
    } catch (_) {}
  }

  /// Handshake + one tiny prompt, for the Settings test button.
  Future<GeminiWebTestResult> test() async {
    final sw = Stopwatch()..start();
    try {
      await init();
      final reply = await ask('Reply with the single word OK.',
          attempts: 2, timeout: const Duration(seconds: 90));
      sw.stop();
      final snippet = reply.replaceAll(RegExp(r'\s+'), ' ').trim();
      return GeminiWebTestResult(
        ok: true,
        ms: sw.elapsedMilliseconds,
        message: 'Session alive — Gemini replied '
            '"${snippet.substring(0, snippet.length.clamp(0, 60))}"',
        summary: session.summary,
      );
    } on GeminiWebException catch (e) {
      sw.stop();
      return GeminiWebTestResult(
        ok: false,
        ms: sw.elapsedMilliseconds,
        message: e.message,
        summary: session.summary,
        expired: e.expired,
      );
    } catch (e) {
      sw.stop();
      return GeminiWebTestResult(
        ok: false,
        ms: sw.elapsedMilliseconds,
        message: 'Test failed: $e',
        summary: session.summary,
      );
    }
  }
}
