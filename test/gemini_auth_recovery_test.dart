import 'dart:convert';
import 'dart:typed_data';
import 'package:ai_image_studio/gemini_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

GeminiWebSession session(String value) => GeminiWebSession.fromCookieList([
  {'name': '__Secure-1PSID', 'value': value, 'domain': '.google.com'}
]);
const appPage = '<script>{"SNlM0e":"token","cfb2h":"build"}</script>';
String stream(String text) {
  final inner = jsonEncode([null, ['c_id', 'r_id'], null, null,
    [['rc_id', [text]]]]);
  return ")]}'\n\n123\n${jsonEncode([['wrb.fr', null, inner]])}\n";
}

void main() {
  test('401 refreshes browser cookies and retries director with attempts=1', () async {
    var refreshes = 0, sends = 0, handshakes = 0;
    final h = MockClient((r) async {
      if (r.url.path == '/app') { handshakes++; return http.Response(appPage, 200); }
      sends++;
      if (sends == 1) {
        expect(r.headers['Cookie'], contains('old'));
        return http.Response('', 401);
      }
      expect(r.headers['Cookie'], contains('fresh'));
      return http.Response(stream('A fresh and successful answer from Gemini.'), 200);
    });
    final answer = await http.runWithClient(() => GeminiWebClient(session('old'),
        refreshSession: () async { refreshes++; return session('fresh'); })
        .ask('director', attempts: 1), () => h);
    expect(answer, contains('successful answer'));
    expect((refreshes, sends, handshakes), (1, 2, 2));
  });

  test('persistent 401 stops after one recovery', () async {
    var refreshes = 0, sends = 0;
    final h = MockClient((r) async {
      if (r.url.path == '/app') return http.Response(appPage, 200);
      sends++; return http.Response('', 401);
    });
    await expectLater(http.runWithClient(() => GeminiWebClient(session('old'),
        refreshSession: () async { refreshes++; return session('fresh'); })
        .ask('director', attempts: 1), () => h),
        throwsA(isA<GeminiWebException>()
            .having((e) => e.expired, 'expired', true)
            .having((e) => e.message, 'message', contains('after automatic session refresh'))));
    expect((refreshes, sends), (1, 2));
  });

  test('image generation recovers on 401 with one normal attempt', () async {
    var refreshes = 0, sends = 0;
    const url = 'https://lh3.googleusercontent.com/gg-dl/abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG=s1024';
    final h = MockClient((r) async {
      if (r.url.path == '/app') return http.Response(appPage, 200);
      sends++; return sends == 1 ? http.Response('', 401) : http.Response(stream(url), 200);
    });
    final out = await http.runWithClient(() => GeminiWebClient(session('old'),
        refreshSession: () async { refreshes++; return session('fresh'); })
        .generateImages('draw', attempts: 1), () => h);
    expect(out.urls, isNotEmpty);
    expect((refreshes, sends), (1, 2));
  });

  test('image upload refreshes once on rejected session', () async {
    var refreshes = 0, uploads = 0;
    final h = MockClient((r) async {
      if (r.url.path == '/app') return http.Response(appPage, 200);
      uploads++;
      if (uploads == 1) return http.Response('', 401);
      expect(r.headers['Cookie'], contains('fresh'));
      return http.Response('/contrib_service/ref', 200);
    });
    final out = await http.runWithClient(() => GeminiWebClient(session('old'),
        refreshSession: () async { refreshes++; return session('fresh'); })
        .uploadImage(Uint8List.fromList([1, 2])), () => h);
    expect(out.ref, '/contrib_service/ref');
    expect((refreshes, uploads), (1, 2));
  });
}
