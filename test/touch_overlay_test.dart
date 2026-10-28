// Touch UI of the overlay (Android built-in browser): "Select pictures"
// button, then a tap on a picture ticks it without following links.
// Runs only when AIS_CHROMIUM and AIS_TEST_URL are set.
import 'dart:convert';
import 'dart:io';

import 'package:ai_image_studio/browser/cdp.dart';
import 'package:ai_image_studio/browser/overlay_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final exe = Platform.environment['AIS_CHROMIUM'];
  final url = Platform.environment['AIS_TEST_URL'];
  test('tap selects a picture in touch mode', () async {
    final prof = Directory.systemTemp.createTempSync('aist').path;
    final p = await Process.start(exe!, [
      '--headless=new', '--no-sandbox', '--disable-gpu', '--remote-debugging-port=0',
      '--user-data-dir=$prof', '--window-size=400,800', 'about:blank'
    ]);
    String? ws;
    for (var i = 0; i < 80 && ws == null; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      final f = File('$prof/DevToolsActivePort');
      if (f.existsSync()) {
        final l = f.readAsLinesSync();
        if (l.length >= 2) ws = 'ws://127.0.0.1:${l[0]}${l[1]}';
      }
    }
    addTearDown(() => p.kill(ProcessSignal.sigkill));
    final cdp = await CdpConnection.connect(ws!);
    final t = await cdp.send('Target.getTargets');
    final page = (t['targetInfos'] as List)
        .firstWhere((x) => x['type'] == 'page')['targetId'];
    final a = await cdp.send('Target.attachToTarget',
        params: {'targetId': page, 'flatten': true});
    final sid = a['sessionId'] as String;
    Future<dynamic> ev(String e) async => (await cdp.send('Runtime.evaluate',
        params: {'expression': e, 'returnByValue': true},
        sessionId: sid))['result']?['value'];
    Future<void> tap(num x, num y) async {
      for (final type in ['mousePressed', 'mouseReleased']) {
        await cdp.send('Input.dispatchMouseEvent',
            params: {'type': type, 'x': x, 'y': y, 'button': 'left', 'clickCount': 1},
            sessionId: sid);
      }
    }

    await cdp.send('Emulation.setDeviceMetricsOverride',
        params: {'width': 400, 'height': 800, 'deviceScaleFactor': 1, 'mobile': false},
        sessionId: sid);
    await cdp.send('Page.navigate', params: {'url': url}, sessionId: sid);
    await Future.delayed(const Duration(seconds: 2));
    await cdp.send('Runtime.evaluate',
        params: {'expression': 'window.__aisTouchUI = true;\n$overlayScript'},
        sessionId: sid);
    await ev('window.__aisTake()');
    final before = await ev('location.href');

    await Future.delayed(const Duration(milliseconds: 500));
    final vw = await ev('innerWidth'), vh = await ev('innerHeight');
    await tap(vw - 60, vh - 39); // "Select pictures"
    await Future.delayed(const Duration(milliseconds: 300));
    final pos = await ev('''(() => { const i = [...document.images].find(x =>
        x.getBoundingClientRect().width >= 72); const b = i.getBoundingClientRect();
        return {x: b.left + b.width / 2, y: b.top + b.height / 2, src: i.currentSrc || i.src}; })()''');
    await ev('window.__aisTake()');
    await tap(pos['x'], pos['y']);
    await Future.delayed(const Duration(milliseconds: 400));
    final q = jsonDecode(await ev('window.__aisTake()') as String)['q'] as List;
    expect(q, isNotEmpty);
    final r = jsonDecode(q.first as String);
    expect(r['action'], 'select');
    expect(r['images'][0]['src'], pos['src']);
    expect(await ev('location.href'), before);

    // App pushes the basket back -> dock with "Generate prompts".
    await ev('window.__aisBasket(${jsonEncode([pos['src']])}, 1, 1)');
    await Future.delayed(const Duration(milliseconds: 500));
    final shot = await cdp.send('Page.captureScreenshot', sessionId: sid);
    File('${Directory.systemTemp.path}/ais_touch.png')
        .writeAsBytesSync(base64Decode(shot['data'] as String));
    await cdp.close();
    p.kill();
  }, skip: exe == null || url == null, timeout: const Timeout(Duration(seconds: 90)));
}
