import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_image_studio/ringtone/stable_audio_http_auth.dart';

String _field(http.Request request, String name) {
  final pattern = RegExp(
      'name="${RegExp.escape(name)}"\\r?\\n\\r?\\n(.*?)(?=\\r?\\n--)',
      dotAll: true);
  return pattern.firstMatch(request.body)?.group(1) ?? '';
}

String _records(Map<String, dynamic> data) =>
    data.entries.map((e) => '${e.key}:${jsonEncode(e.value)}\n').join();

// Synthetic fixtures mirror the HAR's field names and React Flight structure.
// No captured passwords, OTPs, cookies, authorization codes or tokens are used.
class _AuthServer {
  final bool wrongState, challenge, absentAction, wrongHost;
  final String deployment;
  String state = '', challengeHash = '';
  int tokenExchanges = 0;
  final requests = <http.Request>[];
  _AuthServer(
      {this.wrongState = false,
      this.challenge = false,
      this.absentAction = false,
      this.wrongHost = false,
      this.deployment = 'one'});

  String action(String stage) => sha256
      .convert(utf8.encode('$deployment-$stage'))
      .toString()
      .substring(0, 42);
  Uri uri(String path) => Uri.https('example.authkit.app', path, {
        'state': state,
        'redirect_uri': 'https://stableaudio.com',
        'authorization_session_id': 'test-session',
      });
  String form(String stage, {bool html = false}) {
    final props = <String, dynamic>{
      'authorizationSessionId': 'test-session',
      'state': state,
      'redirectUri': 'https://stableaudio.com',
      if (!absentAction)
        (stage == 'verify' ? 'verifyAction' : 'action'): r'$h30',
      if (stage == 'verify') 'pendingAuthenticationToken': 'test-pending',
      'extraHiddenFormFields': {'email': 'test@example.invalid'},
    };
    final flight = _records({
      '18': [r'$', 'TestForm', null, props],
      '30': {'id': action(stage), 'bound': null},
    });
    return html
        ? '<html><head></head><body><input type="hidden" name="signals" value="">'
            '<script>self.__next_f.push(${jsonEncode([
                1,
                flight.substring(0, 19)
              ])})</script>'
            '<script>self.__next_f.push(${jsonEncode([
                1,
                flight.substring(19)
              ])})</script></body></html>'
        : flight;
  }

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    final url = request.url;
    expect(request.headers['user-agent'], contains('native HTTP client'));
    if (url.host == 'api.workos.com' && url.path.endsWith('/authorize')) {
      state = url.queryParameters['state']!;
      challengeHash = url.queryParameters['code_challenge']!;
      expect(url.queryParameters['code_challenge_method'], 'S256');
      return http.Response('', 302, headers: {
        'location': wrongHost
            ? 'https://attacker.invalid/sign-up'
            : uri('/sign-up').toString(),
        'set-cookie': 'workos_cookie=test; Path=/; Secure; HttpOnly',
      });
    }
    if (url.host == 'example.authkit.app' &&
        request.method == 'GET' &&
        url.path == '/sign-up') {
      expect(request.headers['cookie'], isNull); // No WorkOS cookie leak.
      if (challenge)
        return http.Response('<title>Just a moment...</title>', 200);
      return http.Response(form('signup', html: true), 200, headers: {
        'set-cookie': 'session=live-test; Path=/; Secure; HttpOnly, '
            'prefs=test; Expires=Wed, 09 Jun 2038 10:18:14 GMT; Path=/; Secure, '
            'bad=discard; Domain=authkit.app; Path=/; Secure',
      });
    }
    if (url.host == 'example.authkit.app' && request.method == 'POST') {
      expect(request.headers['cookie'], contains('session=live-test'));
      expect(request.headers['cookie'], isNot(contains('workos_cookie')));
      expect(request.headers['cookie'], isNot(contains('bad=discard')));
      expect(_field(request, '0'), r'["$K1"]');
      expect(_field(request, '_1_state'), state);
      expect(_field(request, '_1_authorization_session_id'), 'test-session');
      expect(request.headers['origin'], 'https://example.authkit.app');
      if (url.path == '/sign-up') {
        expect(request.headers['next-action'], action('signup'));
        expect(_field(request, '_1_email'), 'test@example.invalid');
        expect(
            _field(request, '_1_signals'), isEmpty); // No spoofed fingerprint.
        return http.Response(form('password'), 200,
            headers: {'x-action-redirect': '${uri('/sign-up/password')};push'});
      }
      if (url.path == '/sign-up/password') {
        expect(request.headers['next-action'], action('password'));
        expect(_field(request, '_1_password'), 'test-only-password');
        return http.Response(form('verify'), 200, headers: {
          'x-action-redirect': '${uri('/email-verification')};push'
        });
      }
      if (url.path == '/email-verification') {
        expect(request.headers['next-action'], action('verify'));
        expect(_field(request, '_1_code'), '123456');
        expect(
            _field(request, '_1_pending_authentication_token'), 'test-pending');
        return http.Response(
            _records({
              '1': {
                'redirectUrl': '/success?client_redirect_key=test-only',
              }
            }),
            200);
      }
    }
    if (url.host == 'example.authkit.app' && url.path == '/success') {
      final callback = Uri.https('stableaudio.com', '/', {
        'code': 'test-authorization-code',
        'state': wrongState ? 'wrong' : state,
      });
      return http.Response(
          _records({
            '18': {'clientRedirect': callback.toString()}
          }),
          200);
    }
    if (url.host == 'api.workos.com' && url.path.endsWith('/authenticate')) {
      tokenExchanges++;
      expect(request.headers['cookie'] ?? '',
          isNot(contains('session=live-test')));
      final body = jsonDecode(request.body) as Map;
      expect(body['grant_type'], 'authorization_code');
      expect(body['code'], 'test-authorization-code');
      final verifier = body['code_verifier'] as String;
      expect(
          base64Url
              .encode(sha256.convert(ascii.encode(verifier)).bytes)
              .replaceAll('=', ''),
          challengeHash);
      return http.Response(
          jsonEncode({
            'access_token': 'test-access',
            'refresh_token': 'test-refresh',
          }),
          200);
    }
    fail('Unexpected HTTP route: ${request.method} ${url.host}${url.path}');
  }
}

void main() {
  test('complete HTTP signup, dynamic actions, cookies, OTP and PKCE exchange',
      () async {
    final server = _AuthServer();
    final logs = <String>[];
    final auth = StableAudioHttpAuth(
        httpClient: MockClient(server.respond), onLog: logs.add);
    addTearDown(auth.close);
    final result = await auth.createAccount(
        email: 'test@example.invalid',
        password: 'test-only-password',
        onOtp: () async => '123456');
    expect(result.accessToken, 'test-access');
    expect(result.refreshToken, 'test-refresh');
    expect(server.tokenExchanges, 1);
    expect(logs.join(), isNot(contains('test-only-password')));
    expect(logs.join(), isNot(contains('test-access')));
    expect(logs.join(), isNot(contains('123456')));
    expect(
        server.requests.any((r) => r.url.host == 'stableaudio.com'), isFalse);
  });

  test('new deployments discover new action IDs, never hard-code HAR IDs',
      () async {
    for (final deployment in ['release-a', 'release-b']) {
      final server = _AuthServer(deployment: deployment);
      final auth = StableAudioHttpAuth(httpClient: MockClient(server.respond));
      await auth.createAccount(
          email: 'test@example.invalid',
          password: 'test-only-password',
          onOtp: () async => '123456');
      auth.close();
      expect(server.tokenExchanges, 1);
    }
  });

  test('rejects mismatched OAuth state before token exchange', () async {
    final server = _AuthServer(wrongState: true);
    final auth = StableAudioHttpAuth(httpClient: MockClient(server.respond));
    addTearDown(auth.close);
    await expectLater(
        auth.createAccount(
            email: 'test@example.invalid',
            password: 'test-only-password',
            onOtp: () async => '123456'),
        throwsA(isA<StableAudioHttpAuthException>()
            .having((e) => e.message, 'message', contains('state'))));
    expect(server.tokenExchanges, 0);
  });

  test('does not send credentials to an unexpected redirect host', () async {
    final server = _AuthServer(wrongHost: true);
    final auth = StableAudioHttpAuth(httpClient: MockClient(server.respond));
    addTearDown(auth.close);
    await expectLater(
        auth.createAccount(
            email: 'test@example.invalid',
            password: 'test-only-password',
            onOtp: () async => '123456'),
        throwsA(isA<StableAudioHttpAuthException>()));
    expect(server.requests.length, 1);
  });

  test('stops on browser verification without fallback or fake signals',
      () async {
    final server = _AuthServer(challenge: true);
    final auth = StableAudioHttpAuth(httpClient: MockClient(server.respond));
    addTearDown(auth.close);
    await expectLater(
        auth.createAccount(
            email: 'test@example.invalid',
            password: 'test-only-password',
            onOtp: () async => '123456'),
        throwsA(isA<StableAudioHttpAuthException>().having(
            (e) => e.message, 'message', contains('security verification'))));
    expect(server.tokenExchanges, 0);
  });

  test('fails clearly if a live action reference cannot be found', () async {
    final server = _AuthServer(absentAction: true);
    final auth = StableAudioHttpAuth(httpClient: MockClient(server.respond));
    addTearDown(auth.close);
    await expectLater(
        auth.createAccount(
            email: 'test@example.invalid',
            password: 'test-only-password',
            onOtp: () async => '123456'),
        throwsA(isA<StableAudioHttpAuthException>()
            .having((e) => e.message, 'message', contains('action'))));
    expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  test('invalid OTP is not submitted', () async {
    final server = _AuthServer();
    final auth = StableAudioHttpAuth(httpClient: MockClient(server.respond));
    addTearDown(auth.close);
    await expectLater(
        auth.createAccount(
            email: 'test@example.invalid',
            password: 'test-only-password',
            onOtp: () async => null),
        throwsA(isA<StableAudioHttpAuthException>()));
    expect(server.requests.where((r) => r.url.path == '/email-verification'),
        isEmpty);
  });

  test('HTML hidden input entities and split Flight chunks are parsed', () {
    final server = _AuthServer()..state = 'test-state';
    final source = server.form('signup', html: true) +
        '<input value="a&amp;b&quot;c" name="hidden_example" type="hidden">';
    final page = AuthKitHttpPage.parse(source, server.uri('/sign-up'));
    expect(page.actionId(), server.action('signup'));
    expect(page.hiddenFields['hidden_example'], 'a&b"c');
  });
}
