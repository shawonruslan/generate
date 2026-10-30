import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_image_studio/gemini_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Browser tab whose StreamGenerate reply has NO image link (the picture
/// is finished later), but whose chat page shows the picture.
class LatePage implements GeminiPageTransport, GeminiChatImageReader {
  String? openedChat;
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
    if (url.endsWith('/app')) {
      return GeminiPageResponse(200, url,
          '<script>{"SNlM0e":"tok","cfb2h":"bl1","qKIAYe":"feeds/x"}</script>');
    }
    final inner = jsonEncode([
      null,
      ['c_1f2c1e0bc23847b5', 'r_8aac47c4ee830d08'],
      null,
      null,
      [
        ['rc_1', ['http://googleusercontent.com/image_generation_content/0']]
      ]
    ]);
    final line = jsonEncode([
      ['wrb.fr', null, inner]
    ]);
    return GeminiPageResponse(200, url, ")]}'\n\n123\n$line\n");
  }

  @override
  Future<Uint8List?> chatImage(String conversationId,
      {Duration timeout = const Duration(seconds: 120)}) async {
    openedChat = conversationId;
    return Uint8List.fromList(List.filled(2000, 7));
  }
}

void main() {
  test('late picture is taken from the chat page', () async {
    final page = LatePage();
    final out = await http.runWithClient(() async {
      final c = GeminiWebClient(
          GeminiWebSession.fromCookieList([
            {'name': '__Secure-1PSID', 'value': 'x', 'domain': '.google.com'}
          ]),
          transport: page);
      return c.generateImages('Generate an image. a bee');
    }, () => MockClient((r) async => fail('Direct HTTP call: ${r.url}')));
    expect(page.openedChat, 'c_1f2c1e0bc23847b5');
    expect(out.bytes!.length, 2000);
  });
}
