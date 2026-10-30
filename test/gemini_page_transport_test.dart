import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_image_studio/gemini_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakePage implements GeminiPageTransport {
  final calls = <String>[];
  @override
  bool get isAvailable => true;
  @override
  Future<GeminiPageResponse> request(String method, String url,
      {Map<String, String> headers = const {},
      String? body,
      Uint8List? file,
      String fileName = 'image.jpg',
      String fileMime = 'image/jpeg',
      Duration timeout = const Duration(seconds: 120)}) async {
    calls.add('$method $url${file != null ? ' +file' : ''}');
    if (url.endsWith('/app')) {
      return GeminiPageResponse(200, url,
          '<script>{"SNlM0e":"tok","cfb2h":"bl1","qKIAYe":"feeds/x"}</script>');
    }
    if (url.contains('content-push')) {
      expect(headers['Push-ID'], 'feeds/x');
      return GeminiPageResponse(200, url, '/contrib_service/ref1');
    }
    expect(body, contains('at=tok'));
    final inner = jsonEncode([
      null,
      ['c1', 'r1'],
      null,
      null,
      [
        ['rc1', ['Hello from the browser tab, this is the answer.']]
      ]
    ]);
    final line = jsonEncode([
      ['wrb.fr', null, inner]
    ]);
    return GeminiPageResponse(200, url, ")]}'\n\n123\n$line\n");
  }
}

void main() {
  test('requests run in the browser tab, no cookies leave it', () async {
    final page = FakePage();
    final noNetwork = MockClient((r) async {
      fail('Direct HTTP call: ${r.url}');
    });
    final reply = await http.runWithClient(() async {
      final c = GeminiWebClient(
          GeminiWebSession.fromCookieList([
            {'name': '__Secure-1PSID', 'value': 'x', 'domain': '.google.com'}
          ]),
          transport: page);
      return c.askWithImage('Describe', Uint8List.fromList([1, 2, 3]));
    }, () => noNetwork);
    expect(reply, contains('Hello from the browser tab'));
    expect(page.calls.first, 'GET https://gemini.google.com/app');
    expect(page.calls[1], contains('content-push'));
    expect(page.calls[1], endsWith('+file'));
    expect(page.calls.last, contains('StreamGenerate'));
  });

  test('app-side cookie renewal is off by default', () async {
    expect(GeminiWebClient.allowAppRotation, isFalse);
    final c = GeminiWebClient(GeminiWebSession.fromCookieList([
      {'name': '__Secure-1PSID', 'value': 'x', 'domain': '.google.com'}
    ]));
    expect(await c.rotateCookies(force: true), isFalse);
  });
}
