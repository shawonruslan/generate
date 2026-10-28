// Integration check of the Chromium/CDP controller. Runs only when
// AIS_CHROMIUM points at a Chromium binary and AIS_TEST_URL at a page
// with pictures, e.g.:
//   AIS_CHROMIUM=/usr/bin/chromium AIS_TEST_URL=http://127.0.0.1:8765/ flutter test test/browser_cdp_test.dart
import 'dart:async';
import 'dart:io';

import 'package:ai_image_studio/browser/cdp.dart';
import 'package:ai_image_studio/browser/chromium_browser.dart';
import 'package:ai_image_studio/browser/image_prompt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extractPrompt handles markers and escaping', () {
    expect(
        ImagePromptService.extractPrompt(
            'Sure!\n\\[PROMPT\\]\nA red fox in snow, **cinematic**\n\\[/PROMPT\\]'),
        'A red fox in snow, cinematic');
    expect(ImagePromptService.extractPrompt('Prompt: "Blue sky"'), 'Blue sky');
    expect(
        ImagePromptService.extractPrompt(
            '[PROMPT][cite_start]Red rocks, serene and awe-inspiring [cite: 1].[/PROMPT]'),
        'Red rocks, serene and awe-inspiring.');
  });

  final exe = Platform.environment['AIS_CHROMIUM'];
  final url = Platform.environment['AIS_TEST_URL'];
  test('overlay click reaches the app and the picture downloads', () async {
    final prof = Directory.systemTemp.createTempSync('ais').path;
    final b = await ChromiumBrowser.launch(
      preferredExecutable: exe,
      startUrl: url!,
      profileDir: prof,
      extraArgs: const ['--headless=new', '--no-sandbox'],
    );
    final got = Completer<WebImageRequest>();
    b.requests.listen((r) {
      if (!got.isCompleted) got.complete(r);
    });
    await Future.delayed(const Duration(seconds: 3));
    expect(b.tabCount, greaterThan(0));

    // Second, raw connection plays the user: hover + click "Prompt".
    final lines = File('$prof/DevToolsActivePort').readAsLinesSync();
    final raw =
        await CdpConnection.connect('ws://127.0.0.1:${lines[0]}${lines[1]}');
    final targets = await raw.send('Target.getTargets');
    final page = (targets['targetInfos'] as List)
        .firstWhere((t) => t['type'] == 'page' && '${t['url']}'.startsWith('http'));
    final sid = (await raw.send('Target.attachToTarget',
        params: {'targetId': page['targetId'], 'flatten': true}))['sessionId'];
    final rect = (await raw.send('Runtime.evaluate', params: {
      'expression':
          'JSON.stringify(document.querySelector("img").getBoundingClientRect())',
      'returnByValue': true
    }, sessionId: sid))['result']['value'] as String;
    final m = RegExp(r'"right":([\d.]+).*"top":([\d.]+)').firstMatch(rect) ??
        RegExp(r'"top":([\d.]+).*"right":([\d.]+)').firstMatch(rect);
    final r = RegExp(r'"(\w+)":(-?[\d.]+)')
        .allMatches(rect)
        .fold<Map<String, double>>({}, (a, x) => a..[x[1]!] = double.parse(x[2]!));
    expect(m, isNotNull);
    Future<void> mouse(String type, double x, double y) => raw.send(
        'Input.dispatchMouseEvent',
        params: {'type': type, 'x': x, 'y': y, 'button': 'left', 'clickCount': type == 'mouseMoved' ? 0 : 1},
        sessionId: sid);
    await mouse('mouseMoved', r['left']! + 60, r['top']! + 60);
    await Future.delayed(const Duration(milliseconds: 400));
    final bx = r['right']! - 78, by = r['top']! + 24;
    await mouse('mouseMoved', bx, by);
    await mouse('mousePressed', bx, by);
    await mouse('mouseReleased', bx, by);

    final req = await got.future.timeout(const Duration(seconds: 10));
    expect(req.action, 'single');
    expect(req.images.single.src, contains('.jpg'));
    final pic = await b.fetchImage(req.images.single.src,
        sessionId: req.sessionId, pageUrl: req.pageUrl);
    expect(pic.mimeType, 'image/jpeg');
    expect(pic.bytes.length, greaterThan(1000));
    await b.notifyPage(req.sessionId, req.images.single.src, 'done', 'ok');

    // Basket survives navigation: push it, go to another page, and check
    // the new page reports the same basket version.
    b.setBasket([req.images.single.src], 1);
    await raw.send('Page.navigate',
        params: {'url': '$url#other'.replaceFirst('index.html#other', 'page2.html')},
        sessionId: sid);
    await Future.delayed(const Duration(seconds: 2));
    final take = (await raw.send('Runtime.evaluate', params: {
      'expression': 'window.__aisTake()',
      'returnByValue': true
    }, sessionId: sid))['result']['value'] as String;
    expect(take, contains('"v":1'));
    final cookies = await b.googleCookies();
    expect(cookies, isA<List>());
    await raw.close();
    await b.closeBrowser();
  }, skip: exe == null || url == null, timeout: const Timeout(Duration(minutes: 2)));
}
