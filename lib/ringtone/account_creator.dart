import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../browser/cdp.dart';
import '../browser/chromium_browser.dart';
import 'account_rotation.dart';

/// Port of the workflow's `createStableAudioAccount()`.
///
/// The cloud job launched an undetected Chromium, signed up on
/// stableaudio.com with a temp-mail inbox, scraped the 6-digit WorkOS
/// OTP out of the inbox and captured the `access_token` /
/// `refresh_token` from the network traffic.
///
/// This does the same with the browser already installed on the PC
/// (driven over the Chrome DevTools Protocol) and the free mail.tm API.
/// Two things are deliberately more forgiving than the workflow:
///
///  * every automation step is best-effort — if a selector changes, the
///    window stays open so the signup can be finished by hand while the
///    network sniffer keeps watching for the token;
///  * the account is only returned once a real bearer token was seen, so
///    a half-finished signup can never poison the rotation pool.
class StableAudioAccountCreator {
  StableAudioAccountCreator._();

  static Future<StableAudioAccount?> create({
    void Function(String line)? onStatus,
    Duration timeout = const Duration(minutes: 8),
  }) async {
    void log(String s) => onStatus?.call(s);

    if (!ChromiumBrowser.supported) {
      log('  ⚠️ Auto account creation needs the desktop build '
          '(Windows/macOS/Linux). Add accounts by pasting a token instead.');
      return null;
    }
    final exe = ChromiumBrowser.findExecutable();
    if (exe == null) {
      log('  ⚠️ No Chrome / Edge / Brave / Chromium found — install one, '
          'or add accounts by pasting a token.');
      return null;
    }

    final inbox = await _TempInbox.open(log);
    final email = inbox?.address ?? '';
    final password =
        'Sa!${newStableAudioId().replaceAll('-', '').substring(0, 12)}9x';

    final profile = await Directory.systemTemp.createTemp('sa_signup_');
    Process? proc;
    CdpConnection? cdpRef;
    StreamSubscription<CdpEvent>? sub;
    String? accessToken;
    String? refreshToken;

    try {
      log('  🌐 Launching a fresh browser profile for the signup…');
      proc = await Process.start(exe, [
        '--remote-debugging-port=0',
        '--user-data-dir=${profile.path}',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-features=Translate,ChromeWhatsNewUI',
        '--window-size=1180,820',
        '--new-window',
        'https://stableaudio.com/sign-up',
      ]);
      proc.stdout.drain<void>();
      proc.stderr.drain<void>();

      final ws = await _waitForDevTools(profile.path);
      if (ws == null) {
        log('  ⚠️ The browser did not open its DevTools port.');
        return null;
      }
      final CdpConnection conn = await CdpConnection.connect(ws);
      cdpRef = conn;

      await conn.send('Target.setDiscoverTargets', params: {'discover': true});
      Map<String, dynamic>? page;
      for (var i = 0; i < 40 && page == null; i++) {
        final res = await conn.send('Target.getTargets');
        for (final t in (res['targetInfos'] as List? ?? const [])) {
          if (t is Map && t['type'] == 'page') {
            page = Map<String, dynamic>.from(t);
            break;
          }
        }
        if (page == null) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
      if (page == null) {
        log('  ⚠️ No browser tab to drive.');
        return null;
      }
      final att = await conn.send('Target.attachToTarget', params: {
        'targetId': page['targetId'].toString(),
        'flatten': true,
      });
      final String? sessionRaw = att['sessionId']?.toString();
      if (sessionRaw == null || sessionRaw.isEmpty) {
        log('  ⚠️ Could not attach to the browser tab.');
        return null;
      }
      final String session = sessionRaw;

      await conn.send('Network.enable', sessionId: session);
      await conn.send('Page.enable', sessionId: session);
      await conn.send('Runtime.enable', sessionId: session);

      // ── network sniffer: access token + refresh token ─────────────
      final bodyIds = <String>{};
      sub = conn.events.listen((e) {
        if (e.sessionId != null && e.sessionId != session) return;
        if (e.method == 'Network.requestWillBeSent') {
          final req = e.params['request'];
          if (req is! Map) return;
          final headers = req['headers'];
          if (headers is! Map) return;
          for (final k in headers.keys) {
            if (k.toString().toLowerCase() != 'authorization') continue;
            final v = headers[k].toString();
            if (!v.toLowerCase().startsWith('bearer ')) continue;
            final tok = v.substring(7).trim();
            if (tok.length > 40 && accessToken == null) {
              accessToken = tok;
              log('  🔑 Token captured from outgoing request.');
            }
          }
        } else if (e.method == 'Network.responseReceived') {
          final resp = e.params['response'];
          if (resp is! Map) return;
          final url = (resp['url'] ?? '').toString().toLowerCase();
          if (url.contains('workos') ||
              url.contains('authenticate') ||
              url.contains('/token') ||
              url.contains('authkit')) {
            final rid = e.params['requestId']?.toString();
            if (rid != null) bodyIds.add(rid);
          }
        } else if (e.method == 'Network.loadingFinished') {
          final rid = e.params['requestId']?.toString();
          if (rid == null || !bodyIds.remove(rid)) return;
          _readAuthBody(conn, session, rid).then((pair) {
            if (pair == null) return;
            if (pair.access.isNotEmpty && accessToken == null) {
              accessToken = pair.access;
              log('  🔑 Token captured from auth response.');
            }
            if (pair.refresh.isNotEmpty) refreshToken = pair.refresh;
          }).catchError((Object _) {});
        }
      });

      // ── best-effort signup automation ──────────────────────────────
      final deadline = DateTime.now().add(timeout);
      var signupClicked = false;
      var emailFilled = false;
      var passwordFilled = false;
      var otpFilled = false;
      var code = '';
      var ticks = 0;

      while (DateTime.now().isBefore(deadline)) {
        final seen = accessToken;
        if (seen != null && seen.isNotEmpty) break;
        ticks++;
        try {
          final state = await _pageState(conn, session);
          if (state != null) {
            if (state.otp) {
              if (!otpFilled) {
                if (code.isEmpty) {
                  final c = await inbox?.nextCode();
                  if (c != null && c.isNotEmpty) {
                    code = c;
                    log('  📨 OTP received from the inbox: $code');
                  }
                }
                if (code.isNotEmpty) {
                  await _fillOtp(conn, session, code);
                  otpFilled = true;
                  await _clickText(conn, session,
                      ['verify', 'continue', 'confirm', 'submit', 'next']);
                  log('  ✅ OTP submitted.');
                }
              }
            } else if (state.password) {
              if (!passwordFilled) {
                await _fillPassword(conn, session, password);
                passwordFilled = true;
                await _clickText(conn, session, [
                  'continue',
                  'create account',
                  'sign up',
                  'submit',
                  'next',
                  'done',
                ]);
                log('  🔑 Password submitted.');
              }
            } else if (state.email && email.isNotEmpty) {
              if (!emailFilled) {
                await _fillEmail(conn, session, email);
                emailFilled = true;
                await _clickText(conn, session,
                    ['continue', 'next', 'sign up', 'create account']);
                log('  📧 Email submitted.');
              }
            } else if (!signupClicked) {
              final clicked = await _clickText(conn, session, [
                'sign up',
                'signup',
                'get started',
                'start free',
                'try free',
                'create account',
                'continue with email',
              ]);
              if (clicked.isNotEmpty) {
                signupClicked = true;
                log('  🖱️ Clicked "$clicked".');
              }
            }
            if (ticks % 15 == 0) {
              log('  ⏳ Waiting for the signup to finish in the browser '
                  'window… (you can complete it by hand)');
            }
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 1600));
      }

      final tok = accessToken;
      if (tok == null || tok.isEmpty) {
        log('  ❌ No Stable Audio token was captured — the signup did not '
            'finish in time.');
        return null;
      }
      final acc = StableAudioAccount(
        email: email.isEmpty ? 'Auto-created account' : email,
        accessToken: tok,
        refreshToken: refreshToken ?? '',
        autoCreated: true,
      );
      log('  ✅ Account captured (${acc.label}).');
      return acc;
    } catch (e) {
      log('  ❌ Signup automation error: $e');
      return null;
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        await cdpRef?.close();
      } catch (_) {}
      try {
        proc?.kill();
      } catch (_) {}
      try {
        if (await profile.exists()) {
          await profile.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  // ── CDP helpers ─────────────────────────────────────────────────
  static Future<String?> _waitForDevTools(String profileDir) async {
    final file =
        File('$profileDir${Platform.pathSeparator}DevToolsActivePort');
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!file.existsSync()) continue;
      try {
        final lines = file
            .readAsLinesSync()
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.length < 2) continue;
        final port = int.tryParse(lines[0]);
        if (port == null || port <= 0) continue;
        return 'ws://127.0.0.1:$port${lines[1]}';
      } catch (_) {}
    }
    return null;
  }

  static Future<dynamic> _eval(
      CdpConnection cdp, String session, String expression) async {
    final res = await cdp.send(
      'Runtime.evaluate',
      params: {
        'expression': expression,
        'returnByValue': true,
        'userGesture': true,
      },
      sessionId: session,
    );
    final result = res['result'];
    if (result is Map) return result['value'];
    return null;
  }

  static String _jsStr(String s) {
    final escaped = s
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\r', '')
        .replaceAll('\n', r'\n');
    return "'$escaped'";
  }

  static Future<({bool email, bool password, bool otp})?> _pageState(
      CdpConnection cdp, String session) async {
    const expr = '''
(function(){
  try {
    var inputs = Array.prototype.slice.call(document.querySelectorAll('input'));
    function meta(i){
      return ((i.name||'')+' '+(i.placeholder||'')+' '+
        (i.getAttribute('aria-label')||'')+' '+(i.type||'')).toLowerCase();
    }
    var email = inputs.some(function(i){
      return (i.type||'').toLowerCase()==='email' || /e-?mail/.test(meta(i));
    });
    var password = inputs.some(function(i){
      return (i.type||'').toLowerCase()==='password';
    });
    var otpInputs = inputs.filter(function(i){
      return (i.getAttribute('inputmode')||'')==='numeric' ||
        (i.getAttribute('maxlength')||'')==='1' ||
        /code|otp|verif/.test(meta(i));
    });
    // A real OTP step is either a row of one-char boxes or a single field
    // that literally talks about a code — never a stray numeric input.
    var otp = otpInputs.length >= 4 ||
      (otpInputs.length === 1 && /code|otp|verif/.test(meta(otpInputs[0])));
    return {email: !!email, password: !!password, otp: !!otp};
  } catch (e) { return null; }
})()
''';
    final v = await _eval(cdp, session, expr);
    if (v is! Map) return null;
    return (
      email: v['email'] == true,
      password: v['password'] == true,
      otp: v['otp'] == true,
    );
  }

  static Future<void> _fillEmail(
      CdpConnection cdp, String session, String email) async {
    final expr = '''
(function(){
  try {
    var val = ${_jsStr(email)};
    var inputs = Array.prototype.slice.call(document.querySelectorAll('input'));
    var el = inputs.filter(function(i){
      return (i.type||'').toLowerCase()==='email';
    })[0];
    if (!el) {
      el = inputs.filter(function(i){
        var m = ((i.name||'')+' '+(i.placeholder||'')+' '+
          (i.getAttribute('aria-label')||'')).toLowerCase();
        return /e-?mail/.test(m);
      })[0];
    }
    if (!el) return false;
    var set = Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype,'value').set;
    set.call(el, val);
    el.dispatchEvent(new Event('input',{bubbles:true}));
    el.dispatchEvent(new Event('change',{bubbles:true}));
    el.focus();
    return true;
  } catch (e) { return false; }
})()
''';
    await _eval(cdp, session, expr);
  }

  static Future<void> _fillPassword(
      CdpConnection cdp, String session, String password) async {
    final expr = '''
(function(){
  try {
    var val = ${_jsStr(password)};
    var inputs = Array.prototype.slice.call(document.querySelectorAll('input'))
      .filter(function(i){ return (i.type||'').toLowerCase()==='password'; });
    if (!inputs.length) return false;
    var set = Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype,'value').set;
    inputs.forEach(function(el){
      set.call(el, val);
      el.dispatchEvent(new Event('input',{bubbles:true}));
      el.dispatchEvent(new Event('change',{bubbles:true}));
    });
    inputs[0].focus();
    return true;
  } catch (e) { return false; }
})()
''';
    await _eval(cdp, session, expr);
  }

  static Future<void> _fillOtp(
      CdpConnection cdp, String session, String code) async {
    final expr = '''
(function(){
  try {
    var digits = ${_jsStr(code)};
    var inputs = Array.prototype.slice.call(document.querySelectorAll('input'))
      .filter(function(i){
        var m = ((i.name||'')+' '+(i.getAttribute('aria-label')||'')).toLowerCase();
        return (i.getAttribute('inputmode')||'')==='numeric' ||
          (i.getAttribute('maxlength')||'')==='1' ||
          /code|otp|verif/.test(m);
      });
    if (!inputs.length) return false;
    var set = Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype,'value').set;
    if (inputs.length === 1) {
      set.call(inputs[0], digits);
      inputs[0].dispatchEvent(new Event('input',{bubbles:true}));
      inputs[0].dispatchEvent(new Event('change',{bubbles:true}));
      return true;
    }
    for (var i=0;i<inputs.length && i<digits.length;i++) {
      set.call(inputs[i], digits.charAt(i));
      inputs[i].dispatchEvent(new Event('input',{bubbles:true}));
      inputs[i].dispatchEvent(new Event('change',{bubbles:true}));
    }
    return true;
  } catch (e) { return false; }
})()
''';
    await _eval(cdp, session, expr);
  }

  /// Clicks the first visible button/link whose label matches one of
  /// [labels]; returns the label that was clicked ('' when none).
  static Future<String> _clickText(
      CdpConnection cdp, String session, List<String> labels) async {
    final list = labels.map(_jsStr).join(',');
    final expr = '''
(function(){
  try {
    var wanted = [$list];
    var els = Array.prototype.slice.call(document.querySelectorAll(
      'button, a, [role=button], input[type=submit], div[tabindex]'));
    for (var i=0;i<els.length;i++) {
      var el = els[i];
      var label = (el.innerText || el.value ||
        el.getAttribute('aria-label') || '').replace(/\\s+/g,' ').trim();
      if (!label) continue;
      var low = label.toLowerCase();
      var hit = false;
      for (var w=0;w<wanted.length;w++) {
        var key = wanted[w];
        if (low === key || (key.length > 4 && low.indexOf(key) >= 0)) {
          hit = true;
          break;
        }
      }
      if (!hit) continue;
      if (el.disabled) continue;
      if (!el.getClientRects().length) continue;
      el.click();
      return label;
    }
    return '';
  } catch (e) { return ''; }
})()
''';
    final v = await _eval(cdp, session, expr);
    return (v ?? '').toString();
  }

  static Future<({String access, String refresh})?> _readAuthBody(
      CdpConnection cdp, String session, String requestId) async {
    try {
      final res = await cdp.send(
        'Network.getResponseBody',
        params: {'requestId': requestId},
        sessionId: session,
      );
      var body = (res['body'] ?? '').toString();
      if (res['base64Encoded'] == true) {
        body = utf8.decode(base64.decode(body));
      }
      if (body.isEmpty || !body.contains('token')) return null;
      final data = jsonDecode(body);
      if (data is! Map) return null;
      final at = (data['access_token'] ?? '').toString();
      final rt = (data['refresh_token'] ?? '').toString();
      return (access: at, refresh: rt);
    } catch (_) {
      return null;
    }
  }
}

/// Minimal mail.tm client: one throwaway inbox, polled for the WorkOS
/// 6-digit verification code.
class _TempInbox {
  _TempInbox(this.address, this._token);

  final String address;
  final String _token;
  final Set<String> _seen = {};

  static Future<_TempInbox?> open(void Function(String) log) async {
    try {
      final domRes = await http
          .get(Uri.parse('https://api.mail.tm/domains'),
              headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (domRes.statusCode != 200) {
        log('  ⚠️ Temp-mail domains unavailable (${domRes.statusCode}) — '
            'sign up with your own email in the browser window.');
        return null;
      }
      final dom = jsonDecode(domRes.body);
      String domain = '';
      final members = (dom is Map ? dom['hydra:member'] : null);
      if (members is List && members.isNotEmpty && members.first is Map) {
        domain = (members.first as Map)['domain']?.toString() ?? '';
      }
      if (domain.isEmpty) return null;

      final local =
          'sa${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
          '${Random().nextInt(999)}';
      final address = '$local@$domain';
      final password =
          'Tmp!${newStableAudioId().replaceAll('-', '').substring(0, 12)}';

      final accRes = await http
          .post(Uri.parse('https://api.mail.tm/accounts'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({'address': address, 'password': password}))
          .timeout(const Duration(seconds: 25));
      if (accRes.statusCode >= 300) {
        log('  ⚠️ Temp-mail inbox could not be created '
            '(${accRes.statusCode}).');
        return null;
      }
      final tokRes = await http
          .post(Uri.parse('https://api.mail.tm/token'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({'address': address, 'password': password}))
          .timeout(const Duration(seconds: 25));
      if (tokRes.statusCode >= 300) return null;
      final t = jsonDecode(tokRes.body);
      final token = (t is Map ? t['token'] : null)?.toString() ?? '';
      if (token.isEmpty) return null;
      log('  📧 Temp inbox ready: $address');
      return _TempInbox(address, token);
    } catch (e) {
      log('  ⚠️ Temp-mail unavailable ($e) — sign up with your own email.');
      return null;
    }
  }

  /// Newest unread verification code, or null.
  Future<String?> nextCode() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.mail.tm/messages'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final list = (data is Map ? data['hydra:member'] : null);
      if (list is! List) return null;
      for (final m in list) {
        if (m is! Map) continue;
        final id = (m['id'] ?? '').toString();
        if (id.isEmpty || _seen.contains(id)) continue;
        final det = await http.get(
          Uri.parse('https://api.mail.tm/messages/$id'),
          headers: {
            'Authorization': 'Bearer $_token',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 20));
        if (det.statusCode != 200) continue;
        _seen.add(id);
        final d = jsonDecode(det.body);
        if (d is! Map) continue;
        final t1 = d['text']?.toString() ?? '';
        final t2 = d['html']?.toString() ?? '';
        final t3 = d['intro']?.toString() ?? '';
        final t4 = d['subject']?.toString() ?? '';
        final text = '$t1\n$t2\n$t3\n$t4';
        final m6 = RegExp(r'(?<!\d)(\d{6})(?!\d)').firstMatch(text);
        if (m6 != null) return m6.group(1);
        final m4 = RegExp(r'(?<!\d)(\d{4})(?!\d)').firstMatch(text);
        if (m4 != null) return m4.group(1);
      }
    } catch (_) {}
    return null;
  }
}
