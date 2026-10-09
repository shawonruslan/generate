import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

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

/// Talks to gemini.google.com with a cookie session.
class GeminiWebClient {
  GeminiWebClient(this.session);

  final GeminiWebSession session;

  /// Default boq build id; replaced with the live one from the app HTML.
  static const _fallbackBl =
      'boq_assistant-bard-web-server_20240625.13_p0';

  String? _at; // SNlM0e token
  String _bl = _fallbackBl;
  String? _cid; // conversation id
  String? _rid; // response id
  String? _rcid; // chosen candidate id
  int _reqid = 100000 + Random().nextInt(800000);

  bool get ready => _at != null && _at!.isNotEmpty;

  Map<String, String> _headers({bool form = false}) => {
        'User-Agent': geminiWebUserAgent,
        'Cookie': session.cookieHeader,
        'Origin': 'https://gemini.google.com',
        'Referer': 'https://gemini.google.com/',
        'X-Same-Domain': '1',
        'Accept-Language': 'en-US,en;q=0.9',
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

  /// Loads gemini.google.com/app, verifies the session is alive and picks
  /// up the `SNlM0e` token + boq build id (the workflow's session
  /// verification step).
  Future<void> init({Duration timeout = const Duration(seconds: 45)}) async {
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

    final finalUrl = res.request?.url.toString() ?? '';
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
  }) async {
    if (!ready) await init();
    Object? lastErr;
    for (var i = 0; i < attempts; i++) {
      if (freshChat) newChat();
      try {
        final text = await _send(prompt, timeout: timeout);
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

  Future<String> _send(String prompt, {required Duration timeout}) async {
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
      [prompt],
      null,
      [_cid, _rid, _rcid],
    ]);
    final freq = jsonEncode([null, inner]);

    final res = await http
        .post(url,
            headers: _headers(form: true),
            body: {'f.req': freq, 'at': at})
        .timeout(timeout);
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
    return _parseStream(utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  /// Parses the `)]}'`-prefixed chunked batchexecute stream and returns the
  /// answer text, capturing the conversation ids on the way.
  String _parseStream(String raw) {
    final payloads = <String>[];
    for (final line in const LineSplitter().split(raw)) {
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
