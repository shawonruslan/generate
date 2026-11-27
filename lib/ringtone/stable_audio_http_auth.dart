import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Authentication result. Credentials and cookies are never written to logs.
class StableAudioHttpTokens {
  final String accessToken, refreshToken, clientId, email;
  const StableAudioHttpTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.clientId,
    required this.email,
  });
}

class StableAudioHttpAuthException implements Exception {
  final String message;
  const StableAudioHttpAuthException(this.message);
  @override
  String toString() => message;
}

/// Request-only AuthKit flow observed in the supplied HAR:
/// authorize + PKCE -> signup -> password -> OTP -> success -> code exchange.
/// Server-action IDs and hidden state are discovered from each LIVE response.
/// No WebView, CDP, browser fingerprint spoofing, or captured session replay.
class StableAudioHttpAuth {
  static const defaultClientId = 'client_01M5FKRSSZMYNTGJZ7SF9WXKH6';
  static final redirectUri = Uri.parse('https://stableaudio.com');
  final http.Client _http;
  final bool _ownsClient;
  final Random _random;
  final Duration requestTimeout;
  final void Function(String)? onLog;
  final _cookies = _AuthCookieJar();
  String? _authHost;
  bool _closed = false;

  StableAudioHttpAuth({
    http.Client? httpClient,
    Random? random,
    this.requestTimeout = const Duration(seconds: 30),
    this.onLog,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _random = random ?? Random.secure();

  void close() {
    _closed = true;
    _cookies.clear();
    if (_ownsClient) _http.close();
  }

  String _nonce() => base64Url
      .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  Future<StableAudioHttpTokens> createAccount({
    required String email,
    required String password,
    required Future<String?> Function() onOtp,
    String firstName = 'Alex',
    String lastName = 'Carter',
    String clientId = defaultClientId,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const StableAudioHttpAuthException(
        'Email and password are required.',
      );
    }
    // One instance is one isolated authentication session.
    _cookies.clear();
    _authHost = null;
    final verifier = _nonce();
    final state = _nonce();
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    onLog?.call('HTTP auth: starting a fresh PKCE authorization session.');
    final authorize =
        Uri.https('api.workos.com', '/user_management/authorize', {
      'client_id': clientId,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'provider': 'authkit',
      'redirect_uri': redirectUri.toString(),
      'response_type': 'code',
      'screen_hint': 'sign-up',
      'state': state,
    });
    var page = await _getPage(authorize);
    _requireAuthPage(page.uri);
    if (page.uri.path != '/sign-up') {
      throw const StableAudioHttpAuthException(
        'AuthKit did not return the expected signup form. HTTP signup is unavailable.',
      );
    }
    final details = {
      'first_name': firstName,
      'last_name': lastName,
      'email': email.trim(),
      'intent': 'sign-up',
    };
    onLog?.call('HTTP auth: submitting signup details.');
    page = await _submit(
      page,
      details,
      state: state,
      expectedPath: '/sign-up/password',
    );
    onLog?.call('HTTP auth: submitting password.');
    page = await _submit(
      page,
      {...details, 'password': password},
      state: state,
      expectedPath: '/email-verification',
    );
    final verifyProps = page.formProperties(verify: true);
    if ((verifyProps['pendingAuthenticationToken'] ?? '').toString().isEmpty) {
      throw const StableAudioHttpAuthException(
        'AuthKit did not issue a pending verification token. No captured token will be reused.',
      );
    }
    onLog?.call('HTTP auth: waiting for the email verification code.');
    final code = (await onOtp())?.trim() ?? '';
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const StableAudioHttpAuthException(
        'A six-digit email verification code was not received in time.',
      );
    }
    page = await _submit(
      page,
      {'code': code, 'email': email.trim()},
      state: state,
      verify: true,
    );
    final success = page.findString('redirectUrl');
    Uri callback;
    if (success != null && success.isNotEmpty) {
      final next = page.uri.resolve(success);
      if (_isCallback(next)) {
        callback = next;
      } else {
        _requireAuthPage(next);
        if (next.path != '/success') {
          throw const StableAudioHttpAuthException(
            'Unexpected verification redirect.',
          );
        }
        page = await _getPage(next);
        final target = page.findString('clientRedirect');
        if (target == null) {
          throw const StableAudioHttpAuthException(
            'AuthKit success response contained no client callback.',
          );
        }
        callback = page.uri.resolve(target);
      }
    } else if (_isCallback(page.uri)) {
      callback = page.uri;
    } else {
      // Some deployments redirect directly instead of returning /success.
      final target = page.findString('clientRedirect');
      if (target == null) {
        throw const StableAudioHttpAuthException(
          'Email verification was not accepted. Retry with a new code/session.',
        );
      }
      callback = page.uri.resolve(target);
    }
    if (!_isCallback(callback) || callback.queryParameters['state'] != state) {
      throw const StableAudioHttpAuthException(
        'OAuth callback origin or state did not match this authentication session.',
      );
    }
    final authorizationCode = callback.queryParameters['code'] ?? '';
    if (authorizationCode.isEmpty) {
      throw const StableAudioHttpAuthException(
        'OAuth callback contained no authorization code.',
      );
    }
    onLog?.call('HTTP auth: exchanging authorization code for tokens.');
    final response = await _request(
      'POST',
      Uri.https('api.workos.com', '/user_management/authenticate'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Origin': redirectUri.origin,
        'Referer': '${redirectUri.origin}/',
      },
      body: jsonEncode({
        'code': authorizationCode,
        'client_id': clientId,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      }),
    );
    if (response.statusCode != 200) {
      throw StableAudioHttpAuthException(
        'Authorization code exchange failed (HTTP ${response.statusCode}).',
      );
    }
    dynamic data;
    try {
      data = jsonDecode(_body(response));
    } catch (_) {}
    if (data is! Map ||
        data['access_token'] is! String ||
        (data['access_token'] as String).isEmpty ||
        data['refresh_token'] is! String ||
        (data['refresh_token'] as String).isEmpty) {
      throw const StableAudioHttpAuthException(
        'Token exchange returned an invalid token response.',
      );
    }
    onLog?.call('HTTP auth: account connected; no browser was opened.');
    return StableAudioHttpTokens(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      clientId: clientId,
      email: email.trim(),
    );
  }

  bool _isCallback(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == redirectUri.host &&
      uri.port == 443 &&
      (uri.path.isEmpty || uri.path == '/') &&
      uri.queryParameters.containsKey('code');

  void _requireAuthPage(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.port != 443 ||
        !uri.host.endsWith('.authkit.app') ||
        uri.userInfo.isNotEmpty ||
        (_authHost != null && _authHost != uri.host)) {
      throw const StableAudioHttpAuthException(
        'Refused an unexpected authentication host.',
      );
    }
    _authHost ??= uri.host;
  }

  Future<AuthKitHttpPage> _getPage(Uri uri) async {
    for (var redirects = 0; redirects < 10; redirects++) {
      if (_isCallback(uri)) return AuthKitHttpPage.parse('', uri);
      if (uri.host != 'api.workos.com') _requireAuthPage(uri);
      final response = await _request(
        'GET',
        uri,
        headers: {'Accept': 'text/html,application/xhtml+xml'},
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) {
          throw const StableAudioHttpAuthException(
            'Authentication redirect had no Location.',
          );
        }
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) _reject(response.statusCode);
      _checkChallenge(_body(response));
      return AuthKitHttpPage.parse(_body(response), uri);
    }
    throw const StableAudioHttpAuthException(
      'Too many authentication redirects.',
    );
  }

  Future<AuthKitHttpPage> _submit(
    AuthKitHttpPage page,
    Map<String, String> supplied, {
    required String state,
    String? expectedPath,
    bool verify = false,
  }) async {
    _requireAuthPage(page.uri);
    final props = page.formProperties(verify: verify);
    final actionId = page.actionId(verify: verify);
    if (actionId == null) {
      throw const StableAudioHttpAuthException(
        'AuthKit form action could not be discovered. Its web protocol may have changed.',
      );
    }
    final session = (props['authorizationSessionId'] ??
            page.uri.queryParameters['authorization_session_id'] ??
            '')
        .toString();
    final returnedState =
        (props['state'] ?? page.uri.queryParameters['state'] ?? '').toString();
    final target =
        (props['redirectUri'] ?? page.uri.queryParameters['redirect_uri'] ?? '')
            .toString();
    if (session.isEmpty ||
        returnedState != state ||
        target != redirectUri.toString()) {
      throw const StableAudioHttpAuthException(
        'AuthKit form session/state did not match this request.',
      );
    }
    final fields = <String, String>{
      ...page.hiddenFields,
      if (!verify) 'signals': '',
      'redirect_uri': target,
      'authorization_session_id': session,
      'state': state,
    };
    final extra = props['extraHiddenFormFields'];
    if (extra is Map) {
      for (final e in extra.entries) {
        if (e.value is String && (e.value as String).isNotEmpty)
          fields[e.key.toString()] = e.value as String;
      }
    }
    fields.addAll(supplied);
    if (verify) {
      fields['pending_authentication_token'] =
          (props['pendingAuthenticationToken'] ?? '').toString();
    }
    // A native HTTP client has no browser fingerprint. Do not copy HAR signals
    // or invent canvas/WebGL/automation fields. The server may reject this.
    final multipart = http.MultipartRequest('POST', page.uri)
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'text/x-component',
        'Next-Action': actionId,
        'Origin': page.uri.origin,
        'Referer': page.uri.toString(),
      })
      ..fields['0'] = '["\$K1"]';
    for (final e in fields.entries) {
      if (!e.key.startsWith('\$ACTION_'))
        multipart.fields['_1_${e.key}'] = e.value;
    }
    final response = await _send(multipart);
    if (response.statusCode != 200 &&
        ![301, 302, 303, 307, 308].contains(response.statusCode)) {
      _reject(response.statusCode);
    }
    _checkChallenge(_body(response));
    final redirect = response.headers['x-action-redirect']?.split(';').first ??
        response.headers['location'];
    final nextUri = redirect == null ? page.uri : page.uri.resolve(redirect);
    final parsed = AuthKitHttpPage.parse(_body(response), nextUri);
    if (expectedPath != null) {
      // Next.js may return the next form inline with x-action-redirect.
      final correctAction = parsed.actionId(
        verify: expectedPath == '/email-verification',
      );
      if (nextUri.path != expectedPath || correctAction == null) {
        if (redirect != null && nextUri.path == expectedPath) {
          return _getPage(nextUri);
        }
        // Surface the server's own rejection reason when the response carries
        // one (validation errors live in the returned Flight records); the old
        // build discarded the body and reported only a generic guess.
        final serverSays = parsed.serverMessages();
        onLog?.call(
          'HTTP auth: AuthKit stayed on ${page.uri.path} '
          '(expected $expectedPath).'
          '${serverSays.isEmpty ? '' : ' Server: $serverSays'}',
        );
        throw StableAudioHttpAuthException(
          'AuthKit did not advance to the next form.'
          '${serverSays.isEmpty ? '' : ' Server said: $serverSays'} '
          'Account creation now runs in the built-in browser, whose page '
          'collects the verification signals AuthKit requires.',
        );
      }
    } else if (redirect != null && parsed.findString('redirectUrl') == null) {
      return _getPage(nextUri);
    }
    return parsed;
  }

  String _body(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  Never _reject(int status) => throw StableAudioHttpAuthException(
        status == 429
            ? 'AuthKit rate limited this request. Wait before retrying.'
            : 'AuthKit request failed (HTTP $status). Browser/security verification may be required.',
      );

  void _checkChallenge(String body) {
    // Do not confuse references to optional CAPTCHA components with a challenge.
    if (body.contains('<title>Just a moment') ||
        body.contains('cf-chl-widget') ||
        body.contains('cf-chl-running')) {
      throw const StableAudioHttpAuthException(
        'The server requires browser security verification. Request-only authentication stopped.',
      );
    }
  }

  Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll(headers);
    if (body != null) request.body = body;
    return _send(request);
  }

  Future<http.Response> _send(http.BaseRequest request) async {
    if (_closed) {
      throw const StableAudioHttpAuthException(
          'HTTP authentication session is closed.');
    }
    if (request.url.scheme != 'https' ||
        request.url.port != 443 ||
        request.url.userInfo.isNotEmpty) {
      throw const StableAudioHttpAuthException(
        'Authentication requires a trusted HTTPS endpoint.',
      );
    }
    final cookie = _cookies.header(request.url);
    if (cookie.isNotEmpty) request.headers['Cookie'] = cookie;
    request.headers['User-Agent'] = 'RingtoneStudio/1.18 (native HTTP client)';
    try {
      final streamed = await _http.send(request).timeout(requestTimeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(requestTimeout);
      if (_closed) {
        throw const StableAudioHttpAuthException(
            'HTTP authentication session was cancelled.');
      }
      _cookies.update(request.url, response.headers['set-cookie']);
      return response;
    } on TimeoutException {
      throw const StableAudioHttpAuthException(
        'Authentication request timed out. Check the connection and retry.',
      );
    } on http.ClientException {
      throw const StableAudioHttpAuthException(
        'Authentication network request failed. Check the connection and retry.',
      );
    } on SocketException {
      throw const StableAudioHttpAuthException(
        'Could not connect to the authentication service.',
      );
    }
  }
}

/// Minimal reader for JSON records embedded in React Flight/Next.js HTML.
/// Only reads data; never executes downloaded JavaScript or captured actions.
class AuthKitHttpPage {
  final Uri uri;
  final Map<String, dynamic> records;
  final Map<String, String> hiddenFields;
  AuthKitHttpPage._(this.uri, this.records, this.hiddenFields);

  factory AuthKitHttpPage.parse(String source, Uri uri) {
    final fragments = <String>[];
    final hidden = <String, String>{};
    for (final tag in RegExp(
      r'<input\b[^>]*>',
      caseSensitive: false,
    ).allMatches(source)) {
      final attrs = <String, String>{};
      final attr = RegExp(
        r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
      );
      for (final a in attr.allMatches(tag.group(0)!)) {
        attrs[a.group(1)!.toLowerCase()] = _html(
          a.group(2) ?? a.group(3) ?? a.group(4) ?? '',
        );
      }
      if (attrs['type']?.toLowerCase() == 'hidden' &&
          attrs['name'] != null &&
          !attrs['name']!.startsWith('\$ACTION_')) {
        hidden[attrs['name']!] = attrs['value'] ?? '';
      }
    }
    for (final script in RegExp(
      r'<script\b[^>]*>([\s\S]*?)</script\s*>',
      caseSensitive: false,
    ).allMatches(source)) {
      final body = script.group(1)!;
      var offset = 0;
      while ((offset = body.indexOf('self.__next_f.push(', offset)) >= 0) {
        final start = body.indexOf('[', offset);
        if (start < 0) break;
        final end = _arrayEnd(body, start);
        if (end < 0) break;
        try {
          final chunk = jsonDecode(body.substring(start, end + 1));
          if (chunk is List && chunk.length > 1 && chunk[1] is String) {
            fragments.add(chunk[1] as String);
          }
        } catch (_) {}
        offset = end + 1;
      }
    }
    final flight = fragments.isEmpty ? source : fragments.join();
    final records = <String, dynamic>{};
    for (final line in const LineSplitter().convert(flight)) {
      final match = RegExp(r'^([a-fA-F0-9]+):(.*)$').firstMatch(line);
      if (match == null) continue;
      final value = match.group(2)!;
      try {
        records[match.group(1)!] = jsonDecode(value);
      } catch (_) {
        // Module imports, stylesheets and raw text records are not form data.
      }
    }
    return AuthKitHttpPage._(uri, records, hidden);
  }

  static String _html(String s) => s.replaceAllMapped(
        RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|quot|apos|lt|gt);'),
        (m) {
          final entity = m.group(1)!;
          if (entity.startsWith('#')) {
            final code = entity.startsWith('#x')
                ? int.tryParse(entity.substring(2), radix: 16)
                : int.tryParse(entity.substring(1));
            if (code != null && code <= 0x10ffff)
              return String.fromCharCode(code);
          }
          return {
                'amp': '&',
                'quot': '"',
                'apos': "'",
                'lt': '<',
                'gt': '>',
              }[entity] ??
              m.group(0)!;
        },
      );

  static int _arrayEnd(String s, int start) {
    var depth = 0, quoted = false, escaped = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == '[') {
        depth++;
      } else if (c == ']' && --depth == 0) {
        return i;
      }
    }
    return -1;
  }

  Iterable<Map> _maps(dynamic value) sync* {
    if (value is Map) {
      yield value;
      for (final child in value.values) {
        yield* _maps(child);
      }
    } else if (value is List) {
      for (final child in value) {
        yield* _maps(child);
      }
    }
  }

  dynamic _resolve(dynamic value, [int depth = 0]) {
    if (depth > 12 || value is! String) return value;
    final match = RegExp(r'^\$(?:h|F|@)?([a-fA-F0-9]+)$').firstMatch(value);
    if (match == null || !records.containsKey(match.group(1))) return value;
    return _resolve(records[match.group(1)], depth + 1);
  }

  Map formProperties({bool verify = false}) {
    final key = verify ? 'verifyAction' : 'action';
    for (final record in records.values) {
      for (final props in _maps(record)) {
        if (props.containsKey(key) &&
            props.containsKey('authorizationSessionId')) return props;
      }
    }
    return const {};
  }

  String? actionId({bool verify = false}) {
    final action = _resolve(
      formProperties(verify: verify)[verify ? 'verifyAction' : 'action'],
    );
    if (action is Map &&
        action['bound'] == null &&
        action['id'] is String &&
        RegExp(r'^[a-fA-F0-9]{40,64}$').hasMatch(action['id'] as String)) {
      return action['id'] as String;
    }
    // Bound actions need proper React serialization; never reuse a stale ID.
    return null;
  }

  String? findString(String key) {
    for (final record in records.values) {
      for (final map in _maps(record)) {
        final value = _resolve(map[key]);
        if (value is String && value.isNotEmpty && !value.startsWith('\$'))
          return value;
      }
    }
    return null;
  }

  /// Human-readable validation/error strings embedded in a rejected form
  /// response (AuthKit returns field errors inside the Flight records, e.g.
  /// under `errors`, `error`, or `message`). Returns '' when none are found.
  String serverMessages() {
    final found = <String>[];
    void add(dynamic v) {
      if (v is String) {
        final t = v.trim();
        if (t.length >= 3 &&
            t.length <= 240 &&
            !t.startsWith('\$') &&
            !t.contains('http') &&
            !found.contains(t)) {
          found.add(t);
        }
      } else if (v is List) {
        for (final e in v) {
          add(e);
        }
      } else if (v is Map) {
        for (final e in v.values) {
          add(e);
        }
      }
    }

    for (final record in records.values) {
      for (final map in _maps(record)) {
        for (final key in const ['errors', 'error', 'message', 'detail']) {
          if (map.containsKey(key)) add(_resolve(map[key]));
        }
      }
    }
    return found.take(3).join(' | ');
  }
}

class _StoredAuthCookie {
  final Cookie cookie;
  final String domain, path;
  final bool hostOnly;
  final DateTime? expires;
  _StoredAuthCookie(
    this.cookie,
    this.domain,
    this.path,
    this.hostOnly,
    this.expires,
  );
  bool matches(Uri u, DateTime now) =>
      (expires == null || expires!.isAfter(now)) &&
      (!cookie.secure || u.scheme == 'https') &&
      (u.host == domain || (!hostOnly && u.host.endsWith('.$domain'))) &&
      (u.path == path ||
          (u.path.startsWith(path) &&
              (path.endsWith('/') ||
                  (u.path.length > path.length &&
                      u.path[path.length] == '/'))));
}

class _AuthCookieJar {
  final _items = <_StoredAuthCookie>[];
  void clear() => _items.clear();
  void update(Uri uri, String? combined) {
    if (combined == null) return;
    for (final header in combined.split(RegExp(r',(?=\s*[^\s;,=]+\s*=)'))) {
      Cookie cookie;
      try {
        cookie = Cookie.fromSetCookieValue(header.trim());
      } catch (_) {
        continue;
      }
      final domain = (cookie.domain ?? uri.host)
          .replaceFirst(RegExp(r'^\.'), '')
          .toLowerCase();
      if (uri.host != domain && !uri.host.endsWith('.$domain')) continue;
      // Do not accept a parent-domain cookie spanning unrelated services.
      if (domain == 'app' || domain == 'authkit.app' || !domain.contains('.'))
        continue;
      final path = cookie.path?.startsWith('/') == true
          ? cookie.path!
          : (uri.path.contains('/')
              ? (uri.path.lastIndexOf('/') <= 0
                  ? '/'
                  : uri.path.substring(0, uri.path.lastIndexOf('/')))
              : '/');
      final expires = cookie.maxAge != null
          ? DateTime.now().toUtc().add(Duration(seconds: cookie.maxAge!))
          : cookie.expires;
      _items.removeWhere(
        (c) =>
            c.domain == domain &&
            c.path == path &&
            c.cookie.name == cookie.name,
      );
      if (expires == null || expires.isAfter(DateTime.now().toUtc())) {
        _items.add(
          _StoredAuthCookie(
            cookie,
            domain,
            path,
            cookie.domain == null,
            expires,
          ),
        );
      }
    }
  }

  String header(Uri uri) {
    final now = DateTime.now().toUtc();
    _items.removeWhere((c) => c.expires != null && !c.expires!.isAfter(now));
    final matches = _items.where((c) => c.matches(uri, now)).toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    return matches.map((c) => '${c.cookie.name}=${c.cookie.value}').join('; ');
  }
}
