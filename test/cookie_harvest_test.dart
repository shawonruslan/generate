// Checks that cookies of a signed-in browser profile are read back without
// a window (headless). Runs only when AIS_CHROMIUM is set.
import 'dart:io';

import 'package:ai_image_studio/browser/cdp.dart';
import 'package:ai_image_studio/browser/chromium_browser.dart';
import 'package:ai_image_studio/gemini_session_manager.dart';
import 'package:ai_image_studio/gemini_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session merge replaces rotated cookies', () {
    final s = GeminiWebSession.fromCookieList([
      {'name': '__Secure-1PSID', 'value': 'a', 'domain': '.google.com'},
      {'name': '__Secure-1PSIDTS', 'value': 'old', 'domain': '.google.com'},
    ]);
    final m = s.merged([
      const GeminiWebCookie(
          name: '__Secure-1PSIDTS',
          value: 'new',
          domain: '.google.com',
          path: '/',
          expires: -1,
          httpOnly: true,
          secure: true,
          sameSite: 'None'),
    ]);
    expect(m.value('__Secure-1PSIDTS'), 'new');
    expect(m.value('__Secure-1PSID'), 'a');
    expect(GeminiWebSession.parse(m.toStorageJson()).value('__Secure-1PSIDTS'),
        'new');
  });

  test('only Gemini session cookies are kept', () {
    final kept = geminiCookiesOnly([
      {'name': '__Secure-1PSID', 'value': 'a', 'domain': '.google.com'},
      {'name': 'SAPISID', 'value': 'b', 'domain': 'gemini.google.com'},
      {'name': 'GMAIL_AT', 'value': 'x', 'domain': 'mail.google.com'},
      {'name': 'SID', 'value': 'y', 'domain': '.youtube.com'},
      {'name': 'OTHER', 'value': 'z', 'domain': '.google.com'},
    ]);
    expect(kept.map((c) => c['name']), ['__Secure-1PSID', 'SAPISID']);
  });

  final exe = Platform.environment['AIS_CHROMIUM'];
  test('harvestGoogleCookies reads the profile headless', () async {
    final prof = Directory.systemTemp.createTempSync('aish').path;
    const args = ['--headless=new', '--no-sandbox', '--password-store=basic'];
    final b = await ChromiumBrowser.launch(
        preferredExecutable: exe,
        startUrl: 'about:blank',
        profileDir: prof,
        extraArgs: args);
    final lines = File('$prof/DevToolsActivePort').readAsLinesSync();
    final raw =
        await CdpConnection.connect('ws://127.0.0.1:${lines[0]}${lines[1]}');
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400 * 30;
    await raw.send('Storage.setCookies', params: {
      'cookies': [
        {
          'name': '__Secure-1PSID',
          'value': 'psid-test',
          'domain': '.google.com',
          'path': '/',
          'secure': true,
          'httpOnly': true,
          'expires': exp,
        }
      ]
    });
    await raw.close();
    await b.closeBrowser();
    await Future.delayed(const Duration(seconds: 3));

    final sw = Stopwatch()..start();
    final got = await ChromiumBrowser.harvestGoogleCookies(
        preferredExecutable: exe,
        profileDir: prof,
        extraArgs: const ['--no-sandbox', '--password-store=basic']);
    final s = GeminiWebSession.fromCookieList(got);
    expect(s.value('__Secure-1PSID'), 'psid-test');
    // ignore: avoid_print
    print('harvested ${got.length} cookies in ${sw.elapsedMilliseconds}ms');
    expect(File('$prof/DevToolsActivePort').existsSync(), isFalse,
        reason: 'headless browser must be closed again');
  }, skip: exe == null, timeout: const Timeout(Duration(minutes: 2)));
}
