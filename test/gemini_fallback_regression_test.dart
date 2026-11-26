import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_image_studio/gemini_web.dart';

class Browser implements GeminiPageTransport {
  @override
  bool get isAvailable => true;
  @override
  Future<GeminiPageResponse> request(String method, String url,
          {Map<String, String> headers = const {},
          String? body,
          Uint8List? file,
          String fileName = 'image.jpg',
          String fileMime = 'image/jpeg',
          Duration timeout = const Duration(seconds: 120)}) async =>
      GeminiPageResponse(200, url, '{"SNlM0e":"fresh-token"}');
}

GeminiWebCookie cookie(String domain, String value) => GeminiWebCookie(
    name: '__Secure-1PSID',
    value: value,
    domain: domain,
    path: '/',
    expires: 0,
    httpOnly: true,
    secure: true,
    sameSite: 'None');
void main() {
  test('401 after refresh switches to signed-in browser', () async {
    final session = GeminiWebSession([
      cookie('.google.com.bd', 'wrong'),
      cookie('gemini.google.com', 'host'),
      cookie('.google.com', 'root')
    ], 'test');
    expect(session.cookieHeader, contains('root'));
    expect(session.cookieHeader, isNot(contains('wrong')));
    expect(session.cookieHeader, isNot(contains('host')));
    GeminiWebClient.preferBrowser = false;
    var requests = 0;
    var refreshed = 0;
    await http.runWithClient(() async {
      final c = GeminiWebClient(session,
          refreshSession: () async {
            refreshed++;
            return session;
          },
          browserFallback: () async => Browser());
      await c.init();
      expect(c.ready, true);
      expect(c.usingBrowser, true);
      expect(refreshed, 1);
      expect(requests, greaterThanOrEqualTo(2));
    },
        () => MockClient((_) async {
              requests++;
              return http.Response('unauthorized', 401);
            }));
    GeminiWebClient.preferBrowser = false;
  });
  test('failed browser fallback gives actionable error not raw 401', () async {
    final session = GeminiWebSession([cookie('.google.com', 'root')], 'test');
    await http.runWithClient(() async {
      final c = GeminiWebClient(session,
          refreshSession: () async => session,
          browserFallback: () async => null);
      await expectLater(
          c.init(),
          throwsA(predicate((e) =>
              e.toString().contains('app\'s own browser') &&
              !e.toString().contains('HTTP 401'))));
    }, () => MockClient((_) async => http.Response('unauthorized', 401)));
  });
}
