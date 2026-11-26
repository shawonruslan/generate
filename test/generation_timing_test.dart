import 'dart:convert';

import 'package:ai_image_studio/cloudinary_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('async task: adaptive polling + timing split', () async {
    var polls = 0;
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        return http.Response(jsonEncode({'data': {'task_id': 't1'}}), 202);
      }
      polls++;
      final status = polls == 1 ? 'pending' : polls < 4 ? 'processing' : 'completed';
      return http.Response(
          jsonEncode({
            'data': {
              'status': status,
              if (status == 'completed')
                'result': {
                  'assets': [
                    {
                      'storage': {'secure_url': 'https://x/y.png'},
                      'width': 10,
                      'height': 10,
                    }
                  ]
                }
            }
          }),
          200);
    });
    final seen = <String>[];
    final sw = Stopwatch()..start();
    final r = await http.runWithClient(
        () => CloudinaryApi(const CloudinaryCredentials(
                cloudName: 'c', apiKey: 'k', apiSecret: 's'))
            .textToImage(
                prompt: 'p',
                modelId: 'm',
                aspectRatio: '1:1',
                resolution: '1K',
                format: 'png',
                onProgress: (s, t) => seen.add(s)),
        () => client);
    sw.stop();
    expect(r.imageUrl, 'https://x/y.png');
    expect(r.timing, isNotNull);
    expect(seen.first, 'pending');
    // 4 polls: 1.2 + 1.5 * 3 = 5.7 s (the old fixed 3 s step needed 12 s).
    expect(sw.elapsed.inMilliseconds, lessThan(7000));
    expect(r.timing!.queued.inMilliseconds, greaterThan(1000));
    // ignore: avoid_print
    print(r.timing!.summary);
  });
}
