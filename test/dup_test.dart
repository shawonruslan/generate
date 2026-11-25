import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:ai_image_studio/browser/cdp.dart';
import 'package:ai_image_studio/browser/chromium_browser.dart';
import 'package:ai_image_studio/browser/image_prompt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('one click -> prompt added once', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    ImagePromptService.debugAnswer = (_) async {
      calls++;
      return '[PROMPT]\nA red fox ${DateTime.now().microsecondsSinceEpoch % 1}\n[/PROMPT]';
    };
    final svc = ImagePromptService.instance;
    await svc.load();
    final prof = Directory.systemTemp.createTempSync('ais').path;
    final b = await ChromiumBrowser.launch(
        preferredExecutable: Platform.environment['AIS_CHROMIUM'],
        startUrl: Platform.environment['AIS_TEST_URL']!,
        profileDir: prof,
        extraArgs: const ['--headless=new', '--no-sandbox']);
    svc.debugAttach(b);
    await Future.delayed(const Duration(seconds: 3));
    final lines = File('$prof/DevToolsActivePort').readAsLinesSync();
    final raw = await CdpConnection.connect('ws://127.0.0.1:${lines[0]}${lines[1]}');
    final t = await raw.send('Target.getTargets');
    final page = (t['targetInfos'] as List).firstWhere((x) => x['type'] == 'page' && '${x['url']}'.startsWith('http'));
    final sid = (await raw.send('Target.attachToTarget', params: {'targetId': page['targetId'], 'flatten': true}))['sessionId'];
    Future<void> mouse(String type, double x, double y) => raw.send('Input.dispatchMouseEvent',
        params: {'type': type, 'x': x, 'y': y, 'button': 'left', 'clickCount': type == 'mouseMoved' ? 0 : 1}, sessionId: sid);
    // img 1 at (20,100)-(420,400) approx
    final rr = (await raw.send('Runtime.evaluate', params: {'expression': 'JSON.stringify(document.images[0].getBoundingClientRect())', 'returnByValue': true}, sessionId: sid))['result']['value'];
    final rc = jsonDecode(rr as String) as Map;
    final bx = (rc['left'] as num).toDouble() + 40, by = (rc['top'] as num).toDouble() + 24;
    await mouse('mouseMoved', 100, 200);
    await Future.delayed(const Duration(milliseconds: 400));
    await mouse('mouseMoved', bx, by);
    await mouse('mousePressed', bx, by);
    await mouse('mouseReleased', bx, by);
    await Future.delayed(const Duration(seconds: 5));
    // Click "Prompt" on the same picture two more times.
    for (var k = 0; k < 2; k++) {
      await mouse('mouseMoved', 100, 200);
      await Future.delayed(const Duration(milliseconds: 300));
      await mouse('mouseMoved', bx, by);
      await mouse('mousePressed', bx, by);
      await mouse('mouseReleased', bx, by);
      await Future.delayed(const Duration(seconds: 2));
    }
    expect(svc.items.length, 1);
    expect(calls, 1);
    print('items=${svc.items.length} geminiCalls=$calls pending=${PromptListBridge.instance.pending.value}');
    expect(PromptListBridge.instance.pending.value.length, 1);
    await raw.close();
    await b.closeBrowser();
  },
      skip: Platform.environment['AIS_CHROMIUM'] == null ||
          Platform.environment['AIS_TEST_URL'] == null,
      timeout: const Timeout(Duration(minutes: 2)));
}
