import 'dart:convert';

import 'package:ai_image_studio/cloudinary_api.dart';
import 'package:ai_image_studio/compare/target_match.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('always image_to_image with the source picture', () {
    for (final t in [20, 40, 60, 90]) {
      expect(firstMatchStep(t).mode, MatchMode.guided);
      expect(firstMatchStep(t).brief, t);
    }
  });

  test('correction loop', () {
    // Target 90 measured 55 -> ask for more similarity, still guided.
    var s = nextMatchStep(90, const MatchStep(MatchMode.guided, 90), 55);
    expect(s, isNull); // already at the max brief
    s = nextMatchStep(40, const MatchStep(MatchMode.guided, 40), 8)!;
    expect(s.mode, MatchMode.guided);
    expect(s.brief, greaterThan(40));
    final down = nextMatchStep(40, const MatchStep(MatchMode.guided, 40), 80)!;
    expect(down.mode, MatchMode.guided);
    expect(down.brief, lessThan(40));
    expect(nextMatchStep(40, s, 45), isNull);
  });

  test('prompt = source image [1] + generated prompt + percent', () {
    for (final t in [30, 60, 90]) {
      final p = guidedPrompt('moonlit lake, lone boat', t,
          palette: ['#AA3C23'], tone: 'dark low-key exposure');
      expect(p, contains('[1]'));
      expect(p, contains('moonlit lake, lone boat'));
      expect(p, contains('$t%'));
    }
    expect(guidedPrompt('x', 90, palette: ['#AA3C23']), contains('#AA3C23'));
  });

  test('signed reference upload', () async {
    late http.BaseRequest seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(
          jsonEncode({'secure_url': 'https://res.cloudinary.com/x/ref.jpg'}),
          200);
    });
    final url = await http.runWithClient(
        () => CloudinaryApi(const CloudinaryCredentials(
                cloudName: 'demo', apiKey: 'k', apiSecret: 's'))
            .uploadImage([1, 2, 3]),
        () => client);
    expect(url, 'https://res.cloudinary.com/x/ref.jpg');
    expect(seen.url.toString(),
        'https://api.cloudinary.com/v1_1/demo/image/upload');
  });
}
