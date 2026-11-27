import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_image_studio/ringtone/ringtone_models.dart';
import 'package:ai_image_studio/ringtone/stable_audio.dart';

void main() {
  test('HAR terms flag blocks generation until explicit acceptance', () async {
    var accepted = false, patches = 0, creations = 0;
    final client = StableAudioClient(
        store: MemoryStableAudioStore(),
        httpClient: MockClient((r) async {
          if (r.method == 'PATCH' && r.url.path == '/v1alpha/user') {
            patches++;
            expect(r.headers['authorization'], 'Bearer test-access');
            expect(jsonDecode(r.body), {
              'terms_of_service_accepted': true,
              'marketing_opt_in': false,
            });
            accepted = true;
            return http.Response('{}', 200);
          }
          if (r.url.path.endsWith('/balance')) {
            return http.Response(
                jsonEncode({
                  'attributes': {
                    'generations_limit': 50,
                    'credits_per_period': 50,
                    'is_terms_of_service_accepted': accepted,
                    'force_tos_acceptance': !accepted,
                  }
                }),
                200);
          }
          return http.Response('Unexpected request', 400);
        }));
    addTearDown(client.dispose);
    client.onAutoCreateAccount = () async {
      creations++;
      return null;
    };
    await client.setTokens(accessToken: 'test-access');
    await expectLater(
        client.ensureReady(1),
        throwsA(isA<StableAudioException>()
            .having((e) => e.message, 'message', contains('terms'))));
    expect(patches, 0); // Never accept legal terms implicitly.
    expect(creations, 0); // Never rotate around a terms requirement.
    expect(await client.acceptTerms(), isTrue);
    expect(patches, 1);
    expect(client.termsRequired, isFalse);
    await client.ensureReady(1);
  });

  test(
      'HTTP generation, status, result and authenticated relative WAV download',
      () async {
    var polls = 0, downloads = 0;
    final bytes = Uint8List.fromList(List.generate(2048, (i) => i % 256));
    final client = StableAudioClient(
        store: MemoryStableAudioStore(),
        pollInterval: Duration.zero,
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/balance')) {
            return http.Response(
                '{"attributes":{"generations_limit":50,"credits_per_period":50,"is_terms_of_service_accepted":true}}',
                200);
          }
          if (r.url.path.endsWith('/compose-from-plan')) {
            final body = jsonDecode(r.body) as Map;
            expect(body['plan']['source'], 'generate');
            expect(body['plan']['tracks'], hasLength(1));
            expect(body['plan']['tracks'][0]['seed'], 123);
            expect(body['duration_per_stem'], 24);
            expect(body['output_format'], 'wav');
            expect(body['quality_preset'], 'standard');
            expect(body['apply_mix'], isFalse);
            expect(body['generation_strategy'], 'parallel_t2a');
            expect(r.headers['idempotency-key'], isNotEmpty);
            return http.Response('{"job_id":"test-job"}', 200);
          }
          if (r.url.path.endsWith('/status/test-job')) {
            polls++;
            return http.Response(
                jsonEncode({
                  'status': polls == 1 ? 'generating' : 'complete',
                  'stems_completed': polls == 1 ? 0 : 1,
                  'stems_total': 1
                }),
                200);
          }
          if (r.url.path.endsWith('/result/test-job')) {
            return http.Response(
                jsonEncode({
                  'stems': [
                    {
                      'name': 'Descriptive track name',
                      'duration_seconds': 24,
                      'audio_url': '/agents/wizard/stems/test-job/item-0',
                    }
                  ]
                }),
                200);
          }
          if (r.url.path == '/agents/wizard/stems/test-job/item-0') {
            downloads++;
            expect(r.headers['authorization'], 'Bearer test-access');
            return http.Response.bytes(bytes, 200,
                headers: {'content-type': 'audio/wav'});
          }
          fail('Unexpected route: ${r.method} ${r.url.path}');
        }));
    addTearDown(client.dispose);
    await client.setTokens(accessToken: 'test-access');
    final config = RingtoneConfig(
        takesCount: 1, lengthSeconds: 24, audioShape: 'oneshot', seed: 123);
    final job = await client.compose('Soft bell', config);
    final stems = await client.waitForStems(job.jobId);
    expect(await client.downloadStem(job.jobId, stems.single), bytes);
    expect(polls, 2);
    expect(downloads, 1);
  });

  test(
      'refresh request matches HAR and stores rotated single-use refresh token',
      () async {
    var refreshes = 0;
    final store = MemoryStableAudioStore();
    final client = StableAudioClient(
        store: store,
        httpClient: MockClient((r) async {
          refreshes++;
          expect(r.url.toString(),
              'https://api.workos.com/user_management/authenticate');
          expect(jsonDecode(r.body), {
            'client_id': StableAudioClient.defaultClientId,
            'grant_type': 'refresh_token',
            'refresh_token': 'old-test-refresh',
          });
          await Future<void>.delayed(Duration.zero);
          return http.Response(
              '{"access_token":"new-test-access","refresh_token":"new-test-refresh"}',
              200);
        }));
    addTearDown(client.dispose);
    await client.setTokens(refreshToken: 'old-test-refresh');
    final results =
        await Future.wait([client.refreshToken(), client.refreshToken()]);
    expect(results, [true, true]);
    expect(refreshes, 1);
    expect((await store.load()).refreshToken, 'new-test-refresh');
  });
  test('failed HTTP account creation restores the original saved account',
      () async {
    final client = StableAudioClient(
        store: MemoryStableAudioStore(),
        httpClient: MockClient((_) async => http.Response(
            '{"attributes":{"generations_limit":0,"credits_per_period":50}}',
            200)));
    addTearDown(client.dispose);
    await client.addAccount(accessToken: 'first-access', label: 'First');
    final original = client.activeAccountId;
    await client.addAccount(
        accessToken: 'second-access', label: 'Second', makeActive: false);
    client.onAutoCreateAccount =
        () async => throw const StableAudioException('HTTP signup rejected');
    await expectLater(
        client.rotateToNextAccount(), throwsA(isA<StableAudioException>()));
    expect(client.activeAccountId, original);
    expect(client.accessToken, 'first-access');
  });
}
