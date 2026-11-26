import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_image_studio/distribute.dart';
import 'package:ai_image_studio/ringtone/audio_master.dart';
import 'package:ai_image_studio/ringtone/ringtone_metadata.dart';
import 'package:ai_image_studio/ringtone/ringtone_models.dart';
import 'package:ai_image_studio/ringtone/ringtone_policy.dart';
import 'package:ai_image_studio/ringtone/ringtone_publish.dart';
import 'package:ai_image_studio/ringtone/ringtone_service.dart';
import 'package:ai_image_studio/ringtone/stable_audio.dart';
import 'package:ai_image_studio/ringtone/temp_mail.dart';

const reply =
    '[ENHANCED_PROMPT]Bright gentle piano with soft chimes[/ENHANCED_PROMPT]'
    '[TITLE]Morning Bells[/TITLE][KEYWORDS]bright, piano, chimes, morning[/KEYWORDS]'
    '[CATEGORY]CLASSICAL[/CATEGORY][DESCRIPTION]Gentle morning melody[/DESCRIPTION]';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('policy cleaners and checks', () {
    expect(RingtonePolicy.cleanTitle('Morning Bells - V2'), 'Morning Bells');
    expect(RingtonePolicy.cleanCategory('CLASSICAL'), 'CLASSICAL');
    expect(RingtonePolicy.cleanCategory('nonsense'), 'OTHER');
    expect(
        RingtonePolicy.issues(title: 'visit https://example.com'), isNotEmpty);
    expect(RingtonePolicy.cleanTags('bright bright calm'), ['bright', 'calm']);
  });
  test('metadata parsing, retries, disabled enhancer and unique fallback',
      () async {
    var calls = 0;
    final e = RingtoneMetadataEngine((_) async {
      calls++;
      return calls < 3 ? '[TITLE]Incomplete[/TITLE]' : reply;
    }, random: Random(2));
    expect(RingtoneMetadataEngine.tagValue(reply, 'TITLE'), 'Morning Bells');
    final cfg = RingtoneConfig(useGeminiEnhancer: false);
    final m = await e.generateCompliant('Soft piano', cfg);
    expect(calls, 3);
    expect(m.enhancedPrompt, startsWith('Soft piano'));
    expect(m.title, 'Morning Bells');
    final fallback =
        RingtoneMetadataEngine((_) async => 'invalid', random: Random(3));
    final takes = await fallback.uniqueTakes(m, 4, cfg);
    expect(takes.length, 4);
    expect(takes.map((x) => x.title.toLowerCase()).toSet().length, 4);
    expect(
        RingtoneMetadataEngine.parseTakeItems('[{"title":"Bright"}]')
            .single['title'],
        'Bright');
  });
  test('Stable Audio payload, generation, poll and download', () async {
    final bytes = Uint8List.fromList(List.generate(2000, (i) => i % 256));
    final reqs = <String>[];
    final mock = MockClient((req) async {
      reqs.add(req.url.path);
      if (req.url.path.contains('balance'))
        return http.Response(
            '{"attributes":{"generations_limit":20,"credits_per_period":50}}',
            200);
      if (req.url.path.endsWith('compose-from-plan'))
        return http.Response('{"job_id":"job-1"}', 200);
      if (req.url.path.contains('/status/'))
        return http.Response(
            '{"status":"complete","stems_completed":1,"stems_total":1}', 200);
      if (req.url.path.contains('/result/'))
        return http.Response(
            '{"stems":[{"name":"stem","audio_url":"https://audio.example/file","duration_seconds":3}]}',
            200);
      if (req.url.host == 'audio.example')
        return http.Response.bytes(bytes, 200);
      return http.Response('unknown', 404);
    });
    final c = StableAudioClient(
        httpClient: mock,
        store: MemoryStableAudioStore(),
        pollInterval: Duration.zero);
    await c.setTokens(accessToken: 'abc');
    final cfg = RingtoneConfig(
        takesCount: 1,
        lengthSeconds: 3,
        audioShape: 'oneshot',
        bpm: 120,
        seed: 42);
    final prompt = StableAudioClient.buildPrompt('piano at 80 BPM',
        shape: 'oneshot', bpm: 120);
    expect(prompt, contains('120 BPM'));
    expect(prompt, contains('one-shot'));
    expect(prompt, isNot(contains('80 BPM')));
    expect(c.buildPayload(prompt, cfg, 42)['duration_per_stem'], 3);
    final job = await c.compose('piano', cfg);
    final stems = await c.waitForStems(job.jobId);
    expect(
        (await c.downloadStem(job.jobId, stems.single)).length, bytes.length);
    expect(reqs.any((p) => p.endsWith('compose-from-plan')), true);
  });
  test('token parse and auth refresh retries same seed', () async {
    expect(
        StableAudioClient.parsePasted(
                '{"access_token":"abc","refresh_token":"rr"}')
            .refresh,
        'rr');
    var count = 0;
    final seeds = <int>[];
    final mock = MockClient((r) async {
      if (r.url.host == 'api.workos.com')
        return http.Response(
            '{"access_token":"new","refresh_token":"rotated"}', 200);
      if (r.url.path.contains('balance'))
        return http.Response('{"attributes":{"generations_limit":10}}', 200);
      if (r.url.path.endsWith('compose-from-plan')) {
        count++;
        final obj = jsonDecode(r.body) as Map;
        seeds.add(obj['plan']['tracks'][0]['seed'] as int);
        return count == 1
            ? http.Response('unauthorized', 401)
            : http.Response('{"job_id":"ok"}', 200);
      }
      return http.Response('', 404);
    });
    final c =
        StableAudioClient(httpClient: mock, store: MemoryStableAudioStore());
    await c.setTokens(accessToken: 'old', refreshToken: 'rr');
    await c.compose('bell', RingtoneConfig(takesCount: 1, seed: 23));
    expect(count, 2);
    expect(seeds, [23, 23]);
    expect(c.accessToken, 'new');
  });
  test('WAV mastering and ffmpeg conversion', () async {
    final samples = Float64List(16000);
    for (var i = 2000; i < 14000; i++) {
      samples[i] = 0.2 * sin(i * 0.1);
    }
    final wav = WavAudio.encode16(samples, 1, 8000);
    expect(WavAudio.durationOf(wav), closeTo(2, 0.01));
    final cfg = RingtoneConfig(lengthSeconds: 2, fadeInMs: 30, fadeOutMs: 350);
    expect(MasterParams(cfg).filterChain(-12), contains('alimiter'));
    final result = AudioMaster.masterWav(wav, cfg);
    expect(result.processed, true);
    expect(result.mime, 'audio/wav');
    expect(WavAudio.durationOf(result.bytes)!, lessThan(2));
    if (File('/usr/bin/ffmpeg').existsSync()) {
      final mp3 = await AudioMaster.toMp3(
          wav, const FfmpegInfo('/usr/bin/ffmpeg', 'test'), '192k');
      expect(mp3.length, greaterThan(100));
    }
  });
  test('R2 upload, delete protocol and Firebase queue filtering', () async {
    final requests = <http.Request>[];
    final mock = MockClient((r) async {
      requests.add(r);
      if (r.method == 'DELETE')
        return http.Response('{"ok":true,"absent":true}', 200);
      if (r.url.host == 'worker.example')
        return http.Response('{"url":"https://bucket.r2.dev/tone.mp3"}', 200);
      return http.Response(
          '{"tone":{"isMp3":true,"title":"Bell","fileUrl":"https://bucket.r2.dev/tone.mp3"},"image":{"isImage":true}}',
          200);
    });
    final p = RingtonePublisher(httpClient: mock);
    final url = await p.uploadToR2(
        bytes: Uint8List(8),
        fileName: 'bell.mp3',
        workerUrl: 'https://worker.example',
        folder: 'zedge1');
    expect(requests.first.headers['X-File-Name'], contains('zedge1/ringtone/'));
    expect(await p.deleteFromR2(url, 'https://worker.example'), true);
    expect(requests[1].headers['X-R2-Delete-Protocol'], 'r2-delete-v1');
    final rows = await p.fetchQueue(
        const DistAccount(name: 'zedge_1', dbUrl: 'https://db.example'),
        'wallpaperQueue');
    expect(rows.length, 1);
    expect(rows.single.title, 'Bell');
  });
  test('batch prompt expansion and safe publishing preflight', () {
    expect(
        RingtoneService.promptList('first\n\nsecond', 5), ['first', 'second']);
    expect(RingtoneService.promptList('', 3), ['', '', '']);
    final s = RingtoneService(persist: false);
    expect(s.preflight(['bell']), contains('distribution'));
    s.config.autoPublish = false;
    expect(s.preflight(['bell']), '');
    s.dist = const DistConfig(
        r2WorkerUrl: 'https://worker.example',
        accounts: [DistAccount(name: 'current', dbUrl: 'https://db.example')]);
    s.ffmpeg = const FfmpegInfo('/usr/bin/ffmpeg', 'test');
    s.config.autoPublish = true;
    s.config.targetAccount = 'removed';
    expect(s.preflight(['bell']), contains('no longer configured'));
  });
  test('local batch renders and saves a playable WAV', () async {
    final dir = await Directory.systemTemp.createTemp('rt-e2e-');
    final samples =
        Float64List.fromList(List.generate(8000, (i) => 0.2 * sin(i * 0.1)));
    final wav = WavAudio.encode16(samples, 1, 8000);
    final mock = MockClient((r) async {
      if (r.url.path.contains('balance'))
        return http.Response('{"attributes":{"generations_limit":20}}', 200);
      if (r.url.path.endsWith('compose-from-plan'))
        return http.Response('{"job_id":"job"}', 200);
      if (r.url.path.contains('/status/'))
        return http.Response('{"status":"complete"}', 200);
      if (r.url.path.contains('/result/'))
        return http.Response(
            '{"stems":[{"name":"stem","audio_url":"https://audio.example/tone"}]}',
            200);
      if (r.url.host == 'audio.example') return http.Response.bytes(wav, 200);
      return http.Response('', 404);
    });
    final client = StableAudioClient(
        httpClient: mock,
        store: MemoryStableAudioStore(),
        pollInterval: Duration.zero);
    await client.setTokens(accessToken: 'token');
    final s = RingtoneService(
        persist: false,
        dataDir: () async => dir,
        stableAudio: client,
        asker: (_) async => reply,
        distLoader: () async => const DistConfig(r2WorkerUrl: '', accounts: []),
        ffmpegFinder: (_) async => null);
    await s.init();
    s.config.autoPublish = false;
    s.config.takesCount = 1;
    final result = await s.run(['gentle piano']);
    expect(result.single.ok, true);
    expect(s.library.single.hasLocalFile, true);
    expect(
        WavAudio.durationOf(
            await File(s.library.single.localPath).readAsBytes()),
        greaterThan(0));
    expect(File('${dir.path}/library.json').existsSync(), true);
    await dir.delete(recursive: true);
  });

  test('TempMail OTP extraction strips HTML and finds 6-digit code', () {
    expect(
        TempMailClient.extractSixDigitOtp(
            html: '<style>.x{color:123456}</style><p>Code:&nbsp;<b>482910</b></p>'),
        '482910');
    expect(
        TempMailClient.extractSixDigitOtp(subject: 'Verify code 901234'),
        '901234');
    expect(TempMailClient.extractSixDigitOtp(text: 'no code here'), null);
  });

  test('concurrent refreshToken deduplicates and fetchCredits auto-refreshes',
      () async {
    String fakeJwt(int expSec) {
      final h = base64Url.encode(utf8.encode('{"alg":"none"}')).replaceAll('=', '');
      final p = base64Url.encode(utf8.encode('{"exp":$expSec}')).replaceAll('=', '');
      return '$h.$p.sig';
    }

    final expired = fakeJwt(1000);
    final fresh = fakeJwt(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600);
    var refreshCalls = 0;
    final mock = MockClient((r) async {
      if (r.url.host == 'api.workos.com') {
        refreshCalls++;
        return http.Response(
            '{"access_token":"$fresh","refresh_token":"rt2"}', 200);
      }
      if (r.url.path.contains('balance')) {
        expect(r.headers['Authorization'], 'Bearer $fresh');
        return http.Response(
            '{"attributes":{"generations_limit":44,"credits_per_period":50}}',
            200);
      }
      return http.Response('', 404);
    });

    final c = StableAudioClient(
        httpClient: mock, store: MemoryStableAudioStore());
    await c.setTokens(accessToken: expired, refreshToken: 'rt1');
    final results = await Future.wait([c.refreshToken(), c.refreshToken()]);
    expect(results, [true, true]);
    expect(refreshCalls, 1);

    // Expired again -> fetchCredits auto-refreshes before reading balance.
    await c.setTokens(accessToken: expired, refreshToken: 'rt2');
    final bal = await c.fetchCredits();
    expect(bal?.remaining, 44);
    expect(c.accessToken, fresh);
    c.dispose();
  });

  test('account rotation switches on low credits and falls back to auto-create',
      () async {
    var autoCreated = false;
    final mock = MockClient((r) async {
      final auth = r.headers['Authorization'] ?? '';
      if (r.url.path.contains('balance')) {
        if (auth == 'Bearer tok1') {
          return http.Response(
              '{"attributes":{"generations_limit":2,"credits_per_period":50}}',
              200);
        }
        if (auth == 'Bearer tok2') {
          return http.Response(
              '{"attributes":{"generations_limit":48,"credits_per_period":50}}',
              200);
        }
        if (auth == 'Bearer tok3') {
          return http.Response(
              '{"attributes":{"generations_limit":50,"credits_per_period":50}}',
              200);
        }
      }
      if (r.url.path.endsWith('compose-from-plan')) {
        if (auth == 'Bearer tok2') {
          return http.Response('rate limit exceeded', 429);
        }
        if (auth == 'Bearer tok3') {
          return http.Response('{"job_id":"job-rot"}', 200);
        }
      }
      return http.Response('', 404);
    });

    final c = StableAudioClient(
        httpClient: mock, store: MemoryStableAudioStore());
    c.onAutoCreateAccount = () async {
      autoCreated = true;
      return StableAudioAccount(
          id: 'acc_new', label: 'new@mail.tm', accessToken: 'tok3');
    };
    await c.addAccount(accessToken: 'tok1', label: 'one@mail.tm');
    await c.addAccount(
        accessToken: 'tok2', label: 'two@mail.tm', makeActive: false);

    // tok1 has 2 credits -> ensureReady rotates to tok2 (48 credits);
    // tok2 hits 429 -> compose rotates to auto-created tok3.
    final job = await c.compose('piano', RingtoneConfig(takesCount: 1, seed: 7));
    expect(job.jobId, 'job-rot');
    expect(autoCreated, true);
    expect(c.accessToken, 'tok3');
    expect(c.activeLabel, 'new@mail.tm');
    c.dispose();
  });
}
