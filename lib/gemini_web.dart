import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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

  bool get isGoogle => domain.contains('google.com');

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
  String get cookieHeader {
    final seen = <String>{};
    final parts = <String>[];
    for (final c in cookies) {
      if (!c.isGoogle) continue;
      if (c.name.isEmpty || c.value.isEmpty) continue;
      if (!seen.add(c.name)) continue;
      parts.add('${c.name}=${c.value}');
    }
    return parts.join('; ');
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
          if (v is Map && v['cookies'] is List && (v['cookies'] as List).isNotEmpty) {
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
  const GeminiPageResponse(this.status, this.url, this.body);
  final int status;
  final String url;
  final String body;
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
      {this.onSessionUpdated, this.refreshSession, this.transport});

  /// When set and available, every request runs inside the browser.
  final GeminiPageTransport? transport;

  bool get _viaPage => transport?.isAvailable ?? false;

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
  /// signed-in desktop browser profile (Windows). Null on Android.
  final Future<GeminiWebSession?> Function()? refreshSession;

  /// Last RotateCookies call per __Secure-1PSID (Google answers 429 when
  /// rotating more than about once a minute).
  static final Map<String, DateTime> _rotatedAt = {};

  /// Default boq build id; replaced with the live one from the app HTML.
  static const _fallbackBl =
      'boq_assistant-bard-web-server_20240625.13_p0';

  String? _at; // SNlM0e token
  String _pushId = 'feeds/mcudyrk2a4khkz'; // upload Push-ID (qKIAYe)
  String _bl = _fallbackBl;
  String? _cid; // conversation id
  String? _rid; // response id
  String? _rcid; // chosen candidate id
  int _reqid = 100000 + Random().nextInt(800000);

  bool get ready => _at != null && _at!.isNotEmpty;

  /// Always identify as **desktop Chrome on Windows**, on every platform
  /// (including Android). There is no WebView and no DOM here, but Google
  /// still serves a different mobile variant of the app/endpoint when the
  /// client looks like a phone, so the client hints are pinned to desktop
  /// so Android behaves byte-for-byte like the Windows build.
  Map<String, String> _headers({bool form = false}) => {
        'User-Agent': geminiWebUserAgent,
        'Cookie': session.cookieHeader,
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
    return head.contains('ServiceLogin') &&
        !head.contains('SNlM0e');
  }

  /// Renews the short-lived `__Secure-1PSIDTS` cookie exactly like the
  /// Gemini web app does in the background (accounts.google.com
  /// RotateCookies). As long as the long-lived `__Secure-1PSID` is still
  /// valid this keeps a pasted / saved session alive for months without
  /// signing in again - on Android and Windows alike.
  Future<bool> rotateCookies({bool force = false}) async {
    if (!allowAppRotation || _viaPage) return false;
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
    await rotateCookies(); // keep fresh (at most every 10 min)
    try {
      await _handshake(timeout);
      return;
    } on GeminiWebException catch (e) {
      if (!e.expired) rethrow;
    }
    if (await rotateCookies(force: true)) {
      try {
        await _handshake(timeout);
        return;
      } on GeminiWebException catch (e) {
        if (!e.expired) rethrow;
      }
    }
    final hook = refreshSession;
    if (hook != null) {
      GeminiWebSession? fresh;
      try {
        fresh = await hook();
      } catch (_) {}
      if (fresh != null) {
        session = fresh;
        await _handshake(timeout);
        return;
      }
    }
    throw GeminiWebException(
        'The Gemini session expired and could not be renewed automatically. '
        '${refreshSession != null ? 'Use "Sign in with Google" in Settings (one time).' : 'Refresh the cookies in the Windows app (Settings > Copy session) or paste a new export.'}',
        expired: true);
  }

  Future<void> _handshake(Duration timeout) async {
    if (_viaPage) {
      final r = await _pageRequest('GET', 'https://gemini.google.com/app',
          timeout: timeout);
      _readAppPage(r.status, r.url, r.body);
      return;
    }
    http.Response res;
    try {
      res = await http
          .get(Uri.parse('https://gemini.google.com/app'), headers: _headers())
          .timeout(timeout);
    } on TimeoutException {
      throw GeminiWebException(
          'gemini.google.com did not respond within ${timeout.inSeconds}s.');
    } catch (e) {
      throw GeminiWebException('Could not reach gemini.google.com: $e');
    }

    _readAppPage(
        res.statusCode, res.request?.url.toString() ?? '', res.body);
  }

  Future<GeminiPageResponse> _pageRequest(String method, String url,
      {Map<String, String> headers = const {},
      String? body,
      Uint8List? file,
      String fileName = 'image.jpg',
      String fileMime = 'image/jpeg',
      required Duration timeout}) async {
    try {
      return await transport!
          .request(method, url,
              headers: headers,
              body: body,
              file: file,
              fileName: fileName,
              fileMime: fileMime,
              timeout: timeout)
          .timeout(timeout + const Duration(seconds: 10));
    } on TimeoutException {
      throw GeminiWebException(
          'Gemini (in the browser) did not respond within ${timeout.inSeconds}s.');
    } on GeminiWebException {
      rethrow;
    } catch (e) {
      throw GeminiWebException('Gemini request in the browser failed: $e');
    }
  }

  void _readAppPage(int statusCode, String finalUrl, String body) {
    final res = (statusCode: statusCode, body: body);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw GeminiWebException(
          'Gemini rejected the session (HTTP ${res.statusCode}). '
          'Re-export fresh cookies.',
          expired: true);
    }
    if (res.statusCode >= 400) {
      throw GeminiWebException(
          'gemini.google.com returned HTTP ${res.statusCode}.');
    }
    if (_looksLoggedOut(finalUrl, res.body)) {
      throw GeminiWebException(
          'The Gemini session is signed out (redirected to the Google login '
          'page). Re-export fresh cookies while gemini.google.com is open.',
          expired: true);
    }

    final at = RegExp(r'"SNlM0e":"(.*?)"').firstMatch(res.body)?.group(1);
    if (at == null || at.isEmpty) {
      throw GeminiWebException(
          'The Gemini session is expired or invalid (no auth token in the '
          'page). Re-export fresh cookies.',
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
          // One re-handshake: the token can rotate mid-run.
          _at = null;
          if (i == attempts - 1) rethrow;
          try {
            await init();
          } on GeminiWebException {
            rethrow;
          }
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
    Uint8List bytes, {
    String filename = 'image.jpg',
    String mimeType = 'image/jpeg',
    Duration timeout = const Duration(seconds: 90),
  }) async {
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
            'Image upload to Gemini failed (HTTP ${r.status}).');
      }
      return GeminiWebUpload(b, filename);
    }
    final req = http.MultipartRequest(
        'POST', Uri.parse('https://content-push.googleapis.com/upload'));
    req.headers.addAll({
      'Push-ID': _pushId,
      'X-Tenant-Id': 'bard-storage',
      'User-Agent': geminiWebUserAgent,
      'Cookie': session.cookieHeader,
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
          'Image upload to Gemini failed (HTTP ${res.statusCode}).');
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
      List<GeminiWebUpload> files = const []}) async {
    final at = _at;
    if (at == null || at.isEmpty) {
      throw GeminiWebException('Gemini web session is not initialized.',
          expired: true);
    }
    final url = Uri.parse(
        'https://gemini.google.com/_/BardChatUi/data/assistant.lamda.'
        'BardFrontendService/StreamGenerate'
        '?bl=${Uri.encodeQueryComponent(_bl)}&_reqid=$_reqid&rt=c');
    final inner = jsonEncode([
      files.isEmpty
          ? [prompt]
          : [
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
      final h = await http
          .post(url,
              headers: _headers(form: true),
              body: {'f.req': freq, 'at': at})
          .timeout(timeout);
      res = (
        statusCode: h.statusCode,
        text: utf8.decode(h.bodyBytes, allowMalformed: true)
      );
    }
    _reqid += 100000;

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw GeminiWebException(
          'Gemini rejected the session (HTTP ${res.statusCode}). '
          'Re-export fresh cookies.',
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
    return _parseStream(res.text);
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
      if (raw.contains('accounts.google.com') ||
          raw.contains('ServiceLogin')) {
        throw GeminiWebException(
            'The Gemini session expired mid-run. Re-export fresh cookies.',
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
