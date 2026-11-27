import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../android_gecko.dart';
import '../browser/cdp.dart';
import '../browser/chromium_browser.dart';
import '../browser/image_prompt_service.dart';
import 'stable_audio.dart';
import 'temp_mail.dart';

/// Cross-platform Stable Audio browser sign-in and account rotation
/// (Windows/Desktop Chrome/Edge via CDP; Android via built-in Chromium WebView).
class StableAudioBrowser {
  StableAudioBrowser._();

  static bool get supported =>
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS ||
      AndroidGecko.supported;

  static final _jwtRe = RegExp(
    r'^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
  );

  /// Opens a browser window for the user to sign in to Stable Audio and
  /// automatically captures `access_token`, `refresh_token`, and `client_id`.
  static Future<StableAudioAccount?> signInInteractive({
    void Function(String line)? onLog,
  }) async {
    if (AndroidGecko.supported) {
      final res = await AndroidGecko.signInStableAudio();
      if (res == null) return null;
      final at = (res['accessToken'] ?? '').toString().trim();
      if (at.isEmpty) return null;
      return StableAudioAccount(
        id: 'acc_${DateTime.now().millisecondsSinceEpoch}',
        label: (res['email'] ?? '').toString().isNotEmpty
            ? res['email'].toString()
            : 'Stable Audio',
        accessToken: at,
        refreshToken: (res['refreshToken'] ?? '').toString().trim(),
        clientId: (res['clientId'] ?? '').toString().trim().isNotEmpty
            ? res['clientId'].toString().trim()
            : StableAudioClient.defaultClientId,
      );
    }

    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return null;
    }

    return _runDesktopCdp(interactive: true, onLog: onLog);
  }

  /// Creates a fresh 50-credit Stable Audio account using Temp-Mail + OTP
  /// and captures `access_token`, `refresh_token`, and `client_id`.
  static Future<StableAudioAccount?> autoCreateAccount({
    void Function(String line)? onLog,
    TempMailClient? tempMail,
  }) async {
    final mail = tempMail ?? TempMailClient();
    if (AndroidGecko.supported) {
      TempMailInbox? inbox;
      onLog?.call('Opening Stable Audio browser on Android...');
      final res = await AndroidGecko.autoCreateStableAudio(
        onPrepareAccount: () async {
          onLog?.call('Preparing account while the web page loads...');
          final created = await mail
              .createInbox(onLog: onLog)
              .timeout(const Duration(seconds: 90));
          inbox = created;
          return {
            'email': created.email,
            'password': mail.generateStrongPassword(),
          };
        },
        onPollOtp: () async {
          final readyInbox = inbox;
          if (readyInbox == null) return null;
          onLog?.call('Polling ${readyInbox.provider} for 6-digit OTP...');
          return await mail.pollForOtp(
            readyInbox,
            timeout: const Duration(seconds: 60),
          );
        },
      );
      if (res == null) return null;
      var at = (res['accessToken'] ?? '').toString().trim();
      var rt = (res['refreshToken'] ?? '').toString().trim();
      final cid = (res['clientId'] ?? '').toString().trim().isNotEmpty
          ? res['clientId'].toString().trim()
          : StableAudioClient.defaultClientId;
      if (at.isEmpty && rt.isNotEmpty) {
        final mem = MemoryStableAudioStore();
        final tmp = StableAudioClient(store: mem);
        await tmp.setTokens(refreshToken: rt, clientId: cid);
        if (await tmp.refreshToken()) {
          at = tmp.accessToken;
          rt = (await mem.load()).refreshToken;
        }
        tmp.dispose();
      }
      if (at.isEmpty) return null;
      return StableAudioAccount(
        id: 'acc_${DateTime.now().millisecondsSinceEpoch}',
        label: inbox?.email ?? 'Stable Audio',
        accessToken: at,
        refreshToken: rt,
        clientId: cid,
      );
    }

    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return null;
    }

    return _runDesktopCdp(interactive: false, tempMail: mail, onLog: onLog);
  }

  static Future<StableAudioAccount?> _runDesktopCdp({
    required bool interactive,
    TempMailClient? tempMail,
    void Function(String line)? onLog,
  }) async {
    final exe =
        ChromiumBrowser.findExecutable(ImagePromptService.instance.browserPath);
    if (exe == null) {
      throw const StableAudioException(
          'No Chrome or Edge browser found on this PC.',
          StableAudioFailure.auth);
    }

    final mail = tempMail ?? TempMailClient();
    final profileDir = await Directory.systemTemp.createTemp('sa_cdp_');
    Process? proc;
    CdpConnection? cdp;

    try {
      onLog?.call(interactive
          ? 'Opening browser for Stable Audio sign-in...'
          : 'Opening browser for Stable Audio account rotation...');
      proc = await Process.start(exe, [
        '--user-data-dir=${profileDir.path}',
        '--remote-debugging-port=0',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-blink-features=AutomationControlled',
        '--window-size=1280,820',
        'https://stableaudio.com',
      ]);
      proc.stdout.drain<void>();
      proc.stderr.drain<void>();

      TempMailInbox? inbox;
      Object? mailErr;
      var password = '';
      Future<void>? mailFuture;
      if (!interactive) {
        password = mail.generateStrongPassword();
        mailFuture = mail.createInbox(onLog: onLog).then((created) {
          inbox = created;
          onLog?.call('Auto-creating Stable Audio account (${created.email})...');
        }, onError: (Object e) {
          mailErr = e;
        });
      }

      final wsUrl = await _waitForWsUrl(profileDir.path);
      if (wsUrl == null) {
        throw const StableAudioException(
            'Could not connect to browser DevTools port.',
            StableAudioFailure.auth);
      }

      for (var i = 0; i < 12 && cdp == null; i++) {
        try {
          cdp = await CdpConnection.connect(wsUrl);
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
      if (cdp == null) {
        throw const StableAudioException(
            'Browser DevTools socket did not respond.',
            StableAudioFailure.auth);
      }

      if (mailFuture != null) await mailFuture;
      if (mailErr != null) throw mailErr!;
      final targets = await cdp.send('Target.getTargets');
      final infos = (targets['targetInfos'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      final pageTarget = infos.firstWhere(
        (t) => t['type'] == 'page',
        orElse: () => <String, dynamic>{},
      );
      final targetId = (pageTarget['targetId'] ?? '').toString();
      if (targetId.isEmpty) {
        throw const StableAudioException(
            'No browser tab available.', StableAudioFailure.auth);
      }

      final attach = await cdp.send('Target.attachToTarget', params: {
        'targetId': targetId,
        'flatten': true,
      });
      final sid = (attach['sessionId'] ?? '').toString();
      await cdp.send('Page.enable', sessionId: sid);
      await cdp.send('Runtime.enable', sessionId: sid);
      await cdp.send('Network.enable', sessionId: sid);

      String? capturedToken;
      String? capturedRefresh;
      String? capturedClientId;
      final tokenReqIds = <String, String>{};

      final sub = cdp.events.listen((ev) async {
        if (ev.sessionId != sid) return;
        if (ev.method == 'Network.requestWillBeSent') {
          final req = ev.params['request'];
          if (req is! Map) return;
          final url = (req['url'] ?? '').toString();
          final headers = req['headers'];
          if (headers is Map) {
            final auth = (headers['authorization'] ??
                    headers['Authorization'] ??
                    '')
                .toString();
            if (auth.startsWith('Bearer ')) {
              final tok = auth.substring(7).trim();
              if (tok.length > 40 && capturedToken == null) {
                capturedToken = tok;
                onLog?.call('Captured Stable Audio access token from request.');
              }
            }
          }
          if (url.contains('api.workos.com/user_management/authenticate')) {
            try {
              final post = jsonDecode((req['postData'] ?? '{}').toString());
              if (post is Map) {
                if (post['client_id'] != null) {
                  capturedClientId = post['client_id'].toString();
                }
                if (post['refresh_token'] != null && capturedRefresh == null) {
                  capturedRefresh = post['refresh_token'].toString();
                }
              }
            } catch (_) {}
          }
        } else if (ev.method == 'Network.responseReceived') {
          final resp = ev.params['response'];
          if (resp is! Map) return;
          final url = (resp['url'] ?? '').toString();
          final status = (resp['status'] as num?)?.toInt() ?? 0;
          final isTokUrl = url.contains('/oauth/token') ||
              url.contains('/token') ||
              url.contains('/authenticate') ||
              url.contains('authkit.app') ||
              url.contains('workos') ||
              url.contains('api.stableaudio.com') ||
              url.contains('sessions-api.stableaudio.com');
          if (isTokUrl && status == 200) {
            final rid = (ev.params['requestId'] ?? '').toString();
            if (rid.isNotEmpty) tokenReqIds[rid] = url;
          }
        } else if (ev.method == 'Network.loadingFinished') {
          final rid = (ev.params['requestId'] ?? '').toString();
          if (!tokenReqIds.containsKey(rid)) return;
          tokenReqIds.remove(rid);
          try {
            final bodyRes = await cdp!.send('Network.getResponseBody',
                params: {'requestId': rid}, sessionId: sid);
            var raw = (bodyRes['body'] ?? '').toString();
            if (bodyRes['base64Encoded'] == true) {
              raw = utf8.decode(base64Decode(raw));
            }
            final json = jsonDecode(raw);
            if (json is Map) {
              final tok = (json['access_token'] ??
                      json['accessToken'] ??
                      json['token'] ??
                      json['id_token'] ??
                      (json['data'] is Map ? json['data']['access_token'] : '') ??
                      '')
                  .toString();
              if (tok.length > 40 && capturedToken == null) {
                capturedToken = tok;
                onLog?.call('Captured Stable Audio access token.');
              }
              final rt = json['refresh_token'];
              if (rt is String && rt.isNotEmpty) {
                capturedRefresh = rt;
                onLog?.call('Captured WorkOS refresh_token.');
              }
            }
          } catch (_) {}
        }
      });

      try {
        if (interactive) {
          final deadline = DateTime.now().add(const Duration(minutes: 4));
          while (capturedToken == null &&
              DateTime.now().isBefore(deadline) &&
              cdp.isOpen) {
            await Future<void>.delayed(const Duration(milliseconds: 900));
            capturedToken ??= await _scanStorageAndCookies(cdp, sid);
          }
        } else {
          await _automateSignup(
            cdp: cdp,
            sid: sid,
            inbox: inbox!,
            password: password,
            mail: mail,
            hasToken: () => capturedToken != null,
            onLog: onLog,
          );
          final deadline = DateTime.now().add(const Duration(seconds: 35));
          while (capturedToken == null &&
              DateTime.now().isBefore(deadline) &&
              cdp.isOpen) {
            capturedToken ??= await _scanStorageAndCookies(cdp, sid);
            if (capturedToken != null) break;
            await Future<void>.delayed(const Duration(milliseconds: 1000));
          }
        }
      } finally {
        await sub.cancel();
      }

      if (capturedToken == null || capturedToken!.isEmpty) {
        return null;
      }

      return StableAudioAccount(
        id: 'acc_${DateTime.now().millisecondsSinceEpoch}',
        label: inbox?.email ?? 'Stable Audio',
        accessToken: capturedToken!,
        refreshToken: capturedRefresh ?? '',
        clientId: capturedClientId ?? StableAudioClient.defaultClientId,
      );
    } finally {
      try {
        await cdp?.send('Browser.close').timeout(const Duration(seconds: 2));
      } catch (_) {}
      try {
        await cdp?.close();
      } catch (_) {}
      try {
        proc?.kill();
      } catch (_) {}
      try {
        if (profileDir.existsSync()) {
          profileDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }

  static Future<String?> _waitForWsUrl(String profileDir) async {
    final f = File('$profileDir${Platform.pathSeparator}DevToolsActivePort');
    for (var i = 0; i < 40; i++) {
      if (f.existsSync()) {
        try {
          final lines = f
              .readAsLinesSync()
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          if (lines.length >= 2) {
            final port = int.tryParse(lines[0]);
            if (port != null && port > 0) {
              return 'ws://127.0.0.1:$port${lines[1]}';
            }
          }
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  static Future<String?> _evalStr(
      CdpConnection cdp, String sid, String expr) async {
    try {
      final res = await cdp.send(
        'Runtime.evaluate',
        params: {
          'expression': expr,
          'returnByValue': true,
          'awaitPromise': true,
        },
        sessionId: sid,
      );
      final val = res['result']?['value'];
      return val?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _evalBool(
      CdpConnection cdp, String sid, String expr) async {
    return (await _evalStr(cdp, sid, expr)) == 'true';
  }

  static Future<String?> _scanStorageAndCookies(
      CdpConnection cdp, String sid) async {
    final url = await _evalStr(cdp, sid, 'location.href') ?? '';
    if (!url.contains('stableaudio.com') ||
        url.contains('login.') ||
        url.contains('authkit.')) {
      return null;
    }
    final tok = await _evalStr(cdp, sid, '''
(() => {
  const scan = (s) => {
    for (let i = 0; i < s.length; i++) {
      const k = s.key(i);
      const v = (s.getItem(k) || '').trim();
      if (/^eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\$/.test(v)) return v;
      try {
        const p = JSON.parse(v);
        const t = p?.body?.access_token || p?.access_token || p?.accessToken || p?.token || p?.id_token;
        if (typeof t === 'string' && t.length > 40) return t;
      } catch {}
    }
    return null;
  };
  return scan(localStorage) || scan(sessionStorage);
})()
''');
    if (tok != null && tok.length > 40) return tok;

    try {
      final ck = await cdp.send('Network.getCookies', sessionId: sid);
      for (final c in (ck['cookies'] as List? ?? const [])) {
        if (c is Map) {
          final v = (c['value'] ?? '').toString();
          if (_jwtRe.hasMatch(v)) return v;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _setInputAndSubmit(
      CdpConnection cdp, String sid, String selectorJson, String valueJson) async {
    await _evalStr(cdp, sid, '''
(() => {
  const el = document.querySelector($selectorJson);
  if (!el) return false;
  el.focus();
  const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
  if (setter) setter.call(el, $valueJson);
  else el.value = $valueJson;
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  return true;
})()
''');
  }

  static Future<void> _automateSignup({
    required CdpConnection cdp,
    required String sid,
    required TempMailInbox inbox,
    required String password,
    required TempMailClient mail,
    required bool Function() hasToken,
    void Function(String line)? onLog,
  }) async {
    // 1. Wait for stableaudio.com and click Start free / Sign Up
    await Future<void>.delayed(const Duration(seconds: 3));
    await _evalStr(cdp, sid, '''
(() => {
  const els = [...document.querySelectorAll('button, a')].filter(el =>
    /^\\s*(start\\s*free|sign\\s*up)\\s*\$/i.test(el.innerText || el.textContent || '')
  );
  const vis = els.find(el => el.offsetParent !== null) || els[0];
  if (vis) vis.click();
})()
''');

    // 2. Wait for email input on AuthKit
    var emailReady = false;
    for (var i = 0; i < 30; i++) {
      emailReady = await _evalBool(cdp, sid,
          "!!document.querySelector('input[name=\"email\"], input[type=\"email\"], input[autocomplete=\"email\"]')");
      if (emailReady) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!emailReady) {
      throw const StableAudioException(
          'Sign-up email form did not appear.', StableAudioFailure.auth);
    }

    await _setInputAndSubmit(cdp, sid,
        "'input[name=\"first_name\"], input[name=\"firstName\"]'", "'Alex'");
    await _setInputAndSubmit(cdp, sid,
        "'input[name=\"last_name\"], input[name=\"lastName\"]'", "'Carter'");
    await _setInputAndSubmit(
        cdp,
        sid,
        "'input[name=\"email\"], input[type=\"email\"], input[autocomplete=\"email\"]'",
        jsonEncode(inbox.email));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final passVisible = await _evalBool(cdp, sid,
        "!!document.querySelector('input[name=\"password\"], input[type=\"password\"]')");
    if (!passVisible) {
      await _evalStr(cdp, sid, '''
(() => {
  const btn = document.querySelector('button.ak-PrimaryButton, button[type="submit"]');
  if (btn) btn.click();
})()
''');
      for (var i = 0; i < 30; i++) {
        if (await _evalBool(cdp, sid,
            "!!document.querySelector('input[name=\"password\"], input[type=\"password\"]')")) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    // 3. Fill password and submit
    await _setInputAndSubmit(
        cdp,
        sid,
        "'input[name=\"password\"], input[type=\"password\"]'",
        jsonEncode(password));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _evalStr(cdp, sid, '''
(() => {
  const btn = document.querySelector('button.ak-PrimaryButton, button[type="submit"]');
  if (btn) btn.click();
})()
''');

    // 4. Wait for OTP screen or redirect
    var onVerify = false;
    for (var i = 0; i < 20; i++) {
      if (hasToken()) return;
      final url = await _evalStr(cdp, sid, 'location.href') ?? '';
      if (url.contains('email-verification') ||
          url.contains('verify') ||
          await _evalBool(cdp, sid,
              "!!document.querySelector('input[name=\"code\"], input[autocomplete=\"one-time-code\"], input[maxlength=\"1\"], input[maxlength=\"6\"]')")) {
        onVerify = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    if (onVerify) {
      onLog?.call('Waiting for 6-digit OTP email at ${inbox.email}...');
      final otp = await mail.pollForOtp(inbox,
          timeout: const Duration(seconds: 60));
      if (otp == null) {
        throw const StableAudioException(
            'Timed out waiting for 6-digit OTP email.',
            StableAudioFailure.auth);
      }
      onLog?.call('Entering 6-digit OTP...');
      await _evalStr(cdp, sid, '''
((code) => {
  const all = [...document.querySelectorAll('input')].filter(el => {
    const t = (el.getAttribute('type') || '').toLowerCase();
    return t !== 'hidden' && t !== 'checkbox' && t !== 'radio';
  });
  const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
  if (all.length === 6) {
    for (let i = 0; i < 6; i++) {
      all[i].focus();
      if (setter) setter.call(all[i], code[i]); else all[i].value = code[i];
      all[i].dispatchEvent(new Event('input', { bubbles: true }));
      all[i].dispatchEvent(new Event('change', { bubbles: true }));
    }
  }
  const single = document.querySelector('input[autocomplete="one-time-code"], input[name="code"], input[data-input-otp], input[inputmode="numeric"]') || (all.length === 1 ? all[0] : null);
  if (single) {
    single.focus();
    if (setter) setter.call(single, code); else single.value = code;
    single.dispatchEvent(new Event('input', { bubbles: true }));
    single.dispatchEvent(new Event('change', { bubbles: true }));
  }
  const target = single || all[0] || document.querySelector('form');
  if (target) {
    const dt = new DataTransfer();
    dt.setData('text/plain', code);
    target.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
  }
  const btn = document.querySelector('button[type="submit"], button.ak-PrimaryButton');
  if (btn) btn.click();
})(${jsonEncode(otp)})
''');
    }

    // 5. Wait for stableaudio.com and accept the terms wherever they
    // appear - the /terms page, onboarding, or a modal/banner with a
    // "Review / accept terms" button on any page (his screenshot,
    // 2026-11-27: the old code only looked on /terms URLs, so that
    // button needed a manual click). Keep looping while clicks are
    // happening; stop at the first stableaudio page with nothing to
    // accept.
    for (var i = 0; i < 45; i++) {
      if (hasToken()) return;
      final url = await _evalStr(cdp, sid, 'location.href') ?? '';
      if (url.contains('stableaudio.com') &&
          !url.contains('login.') &&
          !url.contains('authkit.')) {
        final clicked = await _evalStr(cdp, sid, '''
(() => {
  const onTermsPage = /\\/terms|onboarding/.test(location.href);
  const unchecked = [...document.querySelectorAll('input[type="checkbox"], [role="checkbox"]')]
    .filter(el => !(el.checked === true || el.getAttribute('aria-checked') === 'true'));
  const btn = [...document.querySelectorAll('button, a')]
    .filter(b => b.offsetParent !== null)
    .find(b => {
      const t = b.innerText || '';
      if (!/accept|agree/i.test(t)) return false;
      return onTermsPage || /term|review/i.test(t) || unchecked.length > 0;
    }) || (onTermsPage ? document.querySelector('button[type="submit"]') : null);
  if (!btn) return 'none';
  unchecked.forEach(el => el.click());
  btn.click();
  return 'clicked';
})()
''');
        if (clicked == 'clicked') {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
  }
}
