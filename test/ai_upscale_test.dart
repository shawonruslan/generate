import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_image_studio/ai_upscale.dart';

void main() {
  const original = 'https://res.cloudinary.com/demo/image/upload/v1/sample.png';
  test('applies AI before the export transformation', () {
    expect(AiUpscale.url(original, after: 'w_1620,h_2880,c_fill/f_jpg,q_100'),
        'https://res.cloudinary.com/demo/image/upload/e_upscale/w_1620,h_2880,c_fill/f_jpg,q_100/v1/sample.png');
  });
  test('rejects non Cloudinary or fetched URLs', () {
    expect(() => AiUpscale.url('https://example.com/image/upload/a.png'), throwsArgumentError);
    expect(() => AiUpscale.url('https://res.cloudinary.com/demo/image/fetch/a.png'), throwsArgumentError);
  });
  test('accepts an image response', () async {
    final client = MockClient((request) async => http.Response.bytes(
        [1, 2, 3], 200, headers: {'content-type': 'image/png'}));
    await AiUpscale.prepare(original, client: client);
    client.close();
  });
  test('surfaces server failure instead of reporting success', () async {
    final client = MockClient((request) async => http.Response('failed', 403));
    await expectLater(AiUpscale.prepare(original, client: client), throwsStateError);
    client.close();
  });
  test('rejects a non-image response', () async {
    final client = MockClient((request) async => http.Response('not an image', 200));
    await expectLater(AiUpscale.prepare(original, client: client), throwsStateError);
    client.close();
  });
}
