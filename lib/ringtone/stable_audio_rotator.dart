import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../browser/cdp.dart';
import '../browser/chromium_browser.dart';
import 'stable_audio.dart';

/// Temporary email inbox used during WorkOS AuthKit email verification.
class TempMailInbox {
  final String provider; // 'mailtm' | 'guerrilla'
  final String apiBase;
  final String email;
  final String mailToken;

  const TempMailInbox({
    required this.provider,
    required this.apiBase,
    required this.email,
    required this.mailToken,
  });
}

/// Credentials and tokens captured from a newly created Stable Audio account.
class RotatedStableAudioAccount {
  final String token;
  final String refreshToken;
  final String workosClientId;
  final String email;
  final String password;

  const RotatedStableAudioAccount({
    required this.token,
    required this.refreshToken,
    required this.workosClientId,
    required this.email,
    required this.password,
  });
}

/// Generates a strong random password matching the workflow's generator.
String generateStrongPassword([Random? rng]) {
  final r = rng ?? Random.secure();
  const words1 = [
    'Velvet', 'Cobalt', 'Zephyr', 'Quartz',
    'Falcon', 'Breeze', 'Cipher', 'Tundra',
  ];
  const words2 = [
    'Meadow', 'Harbor', 'Summit', 'Galaxy',
    'Canyon', 'Orbit', 'Prism', 'Voyage',
  ];
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final w1 = words1[r.nextInt(words1.length)];
  final w2 = words2[r.nextInt(words2.length)];
  final num = r.nextInt(900) + 100;
  final rnd = List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
  return '$w1#$num!$w2\$$rnd' 'Q9';
}

/// Creates a disposable inbox using mail.tm, mail.gw, or GuerrillaMail.
Future<TempMailInbox> createTempMailAccount({
  void Function(String status)? onStatus,
}) async {
  final r = Random.secure();
  const firsts = [
    'alex', 'jordan', 'taylor', 'morgan',
    'casey', 'riley', 'quinn', 'avery',
  ];
  const lasts = [
    'carter', 'bennett', 'hayes', 'parker',
    'collins', 'reid', 'foster', 'brooks',
  ];
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final f = firsts[r.nextInt(firsts.length)];
  final l = lasts[r.nextInt(lasts.length)];

  for (final apiBase in const ['https://api.mail.tm', 'https://api.mail.gw']) {
    try {
      final domRes = await http
          .get(Uri.parse('$apiBase/domains'))
          .timeout(const Duration(seconds: 15));
      if (domRes.statusCode < 200 || domRes.statusCode >= 300) {
        throw Exception('domains HTTP ${domRes.statusCode}');
      }
      final domData = jsonDecode(domRes.body);
      final members = (domData is Map ? domData['hydra:member'] : null) as List? ?? const [];
      final domains = members
          .whereType<Map>()
          .where((d) => d['isActive'] != false && d['domain'] != null)
          .map((d) => d['domain'].toString())
          .toList();
      if (domains.isEmpty) throw Exception('No active domains');

      final domain = domains[r.nextInt(domains.length)];
      final rnd = List.generate(5, (_) => chars[r.nextInt(chars.length)]).join();
      final tsStr = DateTime.now().millisecondsSinceEpoch.toString();
      final ts = tsStr.substring(max(0, tsStr.length - 4));
      final rawAddress = '$f$l$rnd$ts@$domain'.toLowerCase();
      final mailPw = 'MailPass$rnd${ts}A1';

      final accRes = await http
          .post(
            Uri.parse('$apiBase/accounts'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'address': rawAddress, 'password': mailPw}),
          )
          .timeout(const Duration(seconds: 15));
      if (accRes.statusCode < 200 || accRes.statusCode >= 300) {
        throw Exception('accounts HTTP ${accRes.statusCode}');
      }
      final accData = jsonDecode(accRes.body);
      final canonicalAddress = ((accData is Map ? accData['address'] : null) ?? rawAddress)
          .toString()
          .toLowerCase()
          .trim();

      await Future.delayed(const Duration(seconds: 1));

      String? token;
      for (var tTry = 0; tTry < 2; tTry++) {
        final tokRes = await http
            .post(
              Uri.parse('$apiBase/token'),
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({'address': canonicalAddress, 'password': mailPw}),
            )
            .timeout(const Duration(seconds: 15));
        if (tokRes.statusCode >= 200 && tokRes.statusCode < 300) {
          final tokData = jsonDecode(tokRes.body);
          token = (tokData is Map ? tokData['token'] : null)?.toString();
          if (token != null && token.isNotEmpty) break;
        }
        await Future.delayed(const Duration(milliseconds: 1200));
      }
      if (token == null || token.isEmpty) {
        throw Exception('token endpoint did not return token');
      }

      onStatus?.call('Temp-mail ready: $canonicalAddress');
      return TempMailInbox(
        provider: 'mailtm',
        apiBase: apiBase,
        email: canonicalAddress,
        mailToken: token,
      );
    } catch (_) {
      // Try next temp-mail provider.
    }
  }

  try {
    final gmRes = await http
        .get(Uri.parse(
            'https://api.guerrillamail.com/ajax.php?f=get_email_address&lang=en'))
        .timeout(const Duration(seconds: 15));
    if (gmRes.statusCode >= 200 && gmRes.statusCode < 300) {
      final gmData = jsonDecode(gmRes.body);
      final email = (gmData is Map ? gmData['email_addr'] : null)?.toString() ?? '';
      final sid = (gmData is Map ? gmData['sid_token'] : null)?.toString() ?? '';
      if (email.isNotEmpty && sid.isNotEmpty) {
        onStatus?.call('Temp-mail ready: $email');
        return TempMailInbox(
          provider: 'guerrilla',
          apiBase: 'https://api.guerrillamail.com',
          email: email,
          mailToken: sid,
        );
      }
    }
  } catch (_) {}

  throw StableAudioException('All temp-mail providers failed to create an inbox.');
}

/// Extracts a 6-digit verification code from email fields/HTML.
String? extractSixDigitOtp({
  String subject = '',
  String intro = '',
  String text = '',
  String html = '',
}) {
  final cleanHtml = html
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<head[\s\S]*?</head>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  for (final src in [subject, intro, text, cleanHtml]) {
    if (src.isEmpty) continue;
    final m = RegExp(r'\b(\d{6})\b').firstMatch(src);
    if (m != null) return m.group(1);
  }
  return null;
}

/// Polls the disposable inbox until a 6-digit OTP email arrives or [timeout] elapses.
Future<String?> pollTempMailForOtp(
  TempMailInbox inbox, {
  Duration timeout = const Duration(seconds: 60),
  void Function(String status)? onStatus,
}) async {
  if (inbox.mailToken.isEmpty) return null;
  final deadline = DateTime.now().add(timeout);
  onStatus?.call('Waiting for 6-digit OTP email (${inbox.email})…');

  while (DateTime.now().isBefore(deadline)) {
    try {
      if (inbox.provider == 'mailtm') {
        final res = await http
            .get(
              Uri.parse('${inbox.apiBase}/messages'),
              headers: {
                'Authorization': 'Bearer ${inbox.mailToken}',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body);
          final msgs = data is List
              ? data
              : ((data is Map ? data['hydra:member'] : null) as List? ?? const []);
          for (final msg in msgs.whereType<Map>()) {
            final quick = extractSixDigitOtp(
              subject: (msg['subject'] ?? '').toString(),
              intro: (msg['intro'] ?? '').toString(),
            );
            if (quick != null) return quick;

            final id = msg['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            final detailRes = await http
                .get(
                  Uri.parse('${inbox.apiBase}/messages/$id'),
                  headers: {
                    'Authorization': 'Bearer ${inbox.mailToken}',
                    'Accept': 'application/json',
                  },
                )
                .timeout(const Duration(seconds: 15));
            if (detailRes.statusCode >= 200 && detailRes.statusCode < 300) {
              final detail = jsonDecode(detailRes.body);
              if (detail is Map) {
                final rawHtml = detail['html'];
                final htmlStr = rawHtml is List
                    ? rawHtml.join(' ')
                    : (rawHtml ?? '').toString();
                final code = extractSixDigitOtp(
                  subject: (detail['subject'] ?? '').toString(),
                  intro: (detail['intro'] ?? '').toString(),
                  text: (detail['text'] ?? '').toString(),
                  html: htmlStr,
                );
                if (code != null) return code;
              }
            }
          }
        }
      } else if (inbox.provider == 'guerrilla') {
        final res = await http
            .get(Uri.parse(
                'https://api.guerrillamail.com/ajax.php?f=get_email_list&offset=0&sid_token=${Uri.encodeQueryComponent(inbox.mailToken)}'))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body);
          final list = (data is Map ? data['list'] : null) as List? ?? const [];
          for (final msg in list.whereType<Map>()) {
            if (RegExp(r'guerrillamail', caseSensitive: false)
                .hasMatch((msg['mail_from'] ?? '').toString())) {
              continue;
            }
            final quick = extractSixDigitOtp(
              subject: (msg['mail_subject'] ?? '').toString(),
              intro: (msg['mail_excerpt'] ?? '').toString(),
            );
            if (quick != null) return quick;

            final mailId = msg['mail_id']?.toString() ?? '';
            if (mailId.isEmpty) continue;
            final detailRes = await http
                .get(Uri.parse(
                    'https://api.guerrillamail.com/ajax.php?f=fetch_email&email_id=$mailId&sid_token=${Uri.encodeQueryComponent(inbox.mailToken)}'))
                .timeout(const Duration(seconds: 15));
            if (detailRes.statusCode >= 200 && detailRes.statusCode < 300) {
              final detail = jsonDecode(detailRes.body);
              if (detail is Map) {
                final code = extractSixDigitOtp(
                  subject: (detail['mail_subject'] ?? '').toString(),
                  intro: (detail['mail_excerpt'] ?? '').toString(),
                  html: (detail['mail_body'] ?? '').toString(),
                );
                if (code != null) return code;
              }
            }
          }
        }
      }
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 3));
  }
  return null;
}

bool _isStableAudioHost(String urlStr) {
  final u = Uri.tryParse(urlStr);
  if (u == null) return false;
  final h = u.host.toLowerCase();
  return (h == 'stableaudio.com' || h == 'www.stableaudio.com') &&
      !h.contains('login.') &&
      !h.contains('authkit.');
}

String? _readDevToolsWsUrl(String profileDir) {
  final f = File('$profileDir${Platform.pathSeparator}DevToolsActivePort');
  if (!f.existsSync()) return null;
  try {
    final lines = f
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    final port = int.tryParse(lines[0]);
    if (port == null || port <= 0) return null;
    return 'ws://127.0.0.1:$port${lines[1]}';
  } catch (_) {
    return null;
  }
}

/// Auto-creates a fresh 50-credit Stable Audio account using a temporary
/// desktop Chromium profile + Temp-Mail OTP verification, and returns its
/// captured bearer token and WorkOS refresh token.
Future<RotatedStableAudioAccount> createStableAudioAccount({
  String? preferredBrowser,
  void Function(String status)? onStatus,
}) async {
  if (!ChromiumBrowser.supported) {
    throw StableAudioException(
      'Auto account rotation requires a desktop Chromium browser (Windows/macOS/Linux). '
      'On Android, paste a Stable Audio token manually.',
      auth: true,
    );
  }
  final exe = ChromiumBrowser.findExecutable(preferredBrowser);
  if (exe == null) {
    throw StableAudioException(
      'No Chromium browser found (Chrome, Edge, Brave, or Chromium) for auto account rotation.',
      auth: true,
    );
  }

  for (var attempt = 1; attempt <= 2; attempt++) {
    final password = generateStrongPassword();
    final inbox = await createTempMailAccount(onStatus: onStatus);
    final email = inbox.email;

    onStatus?.call('Auto-creating Stable Audio account (attempt $attempt/2: $email)…');

    final tempProfile =
        Directory.systemTemp.createTempSync('sa_rotate_${DateTime.now().millisecondsSinceEpoch}_');
    Process? proc;
    CdpConnection? cdp;

    try {
      proc = await Process.start(
        exe,
        [
          '--headless=new',
          '--remote-debugging-port=0',
          '--user-data-dir=${tempProfile.path}',
          '--no-first-run',
          '--no-default-browser-check',
          '--disable-features=Translate,ChromeWhatsNewUI',
          '--mute-audio',
          '--window-size=1280,800',
          'https://stableaudio.com',
        ],
        mode: ProcessStartMode.detached,
      );

      String? ws;
      final wsDeadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(wsDeadline)) {
        await Future.delayed(const Duration(milliseconds: 250));
        ws = _readDevToolsWsUrl(tempProfile.path);
        if (ws != null) break;
      }
      if (ws == null) {
        throw StableAudioException('Chromium did not open DevTools port for account rotation.');
      }

      for (var i = 0; i < 12 && cdp == null; i++) {
        try {
          cdp = await CdpConnection.connect(ws);
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      if (cdp == null) {
        throw StableAudioException('Could not connect to Chromium DevTools for account rotation.');
      }

      // Attach to the main page target
      String? sessionId;
      for (var i = 0; i < 15 && sessionId == null; i++) {
        final targets = await cdp.send('Target.getTargets');
        final infos = (targets['targetInfos'] as List? ?? const []).whereType<Map>();
        for (final t in infos) {
          if (t['type'] == 'page') {
            final res = await cdp.send('Target.attachToTarget', params: {
              'targetId': t['targetId'],
              'flatten': true,
            });
            sessionId = res['sessionId']?.toString();
            break;
          }
        }
        if (sessionId == null) await Future.delayed(const Duration(milliseconds: 250));
      }
      if (sessionId == null) {
        throw StableAudioException('No Chromium page target found.');
      }

      await cdp.send('Network.enable', sessionId: sessionId);
      await cdp.send('Page.enable', sessionId: sessionId);
      await cdp.send('Runtime.enable', sessionId: sessionId);

      String? capturedToken;
      String? capturedRefreshToken;
      String capturedClientId = 'client_01M5FKRSSZMYNTGJZ7SF9WXKH6';

      final pendingTokenRespIds = <String, String>{};
      final evSub = cdp.events.listen((ev) async {
        if (ev.sessionId != sessionId) return;
        if (ev.method == 'Network.requestWillBeSent') {
          final req = ev.params['request'] as Map?;
          if (req == null) return;
          final url = (req['url'] ?? '').toString();
          final headers = req['headers'] as Map?;
          final auth = (headers?['authorization'] ?? headers?['Authorization'] ?? '').toString();
          if (auth.startsWith('Bearer ')) {
            final tok = auth.substring(7).trim();
            if (tok.length > 40 && capturedToken == null) {
              capturedToken = tok;
            }
          }
          if (url.contains('api.workos.com/user_management/authenticate')) {
            try {
              final body = jsonDecode((req['postData'] ?? '{}').toString());
              if (body is Map) {
                if (body['client_id'] != null) {
                  capturedClientId = body['client_id'].toString();
                }
                if (body['refresh_token'] != null && capturedRefreshToken == null) {
                  capturedRefreshToken = body['refresh_token'].toString();
                }
              }
            } catch (_) {}
          }
        } else if (ev.method == 'Network.responseReceived') {
          final resp = ev.params['response'] as Map?;
          if (resp == null) return;
          final url = (resp['url'] ?? '').toString();
          final status = (resp['status'] as num?)?.toInt() ?? 0;
          final isTokenEndpoint = url.contains('/oauth/token') ||
              url.contains('/token') ||
              url.contains('/authenticate') ||
              url.contains('authkit.app') ||
              url.contains('workos') ||
              url.contains('auth0') ||
              url.contains('login.stableaudio') ||
              url.contains('api.stableaudio.com') ||
              url.contains('sessions-api.stableaudio.com');
          if (isTokenEndpoint && status == 200) {
            final reqId = ev.params['requestId']?.toString();
            if (reqId != null) pendingTokenRespIds[reqId] = url;
          }
        } else if (ev.method == 'Network.loadingFinished') {
          final reqId = ev.params['requestId']?.toString();
          if (reqId != null && pendingTokenRespIds.remove(reqId) != null) {
            try {
              final bodyRes = await cdp!.send(
                'Network.getResponseBody',
                params: {'requestId': reqId},
                sessionId: sessionId,
              );
              final raw = (bodyRes['body'] ?? '').toString();
              final decoded = jsonDecode(raw);
              if (decoded is Map) {
                final tok = (decoded['access_token'] ??
                        decoded['accessToken'] ??
                        decoded['token'] ??
                        decoded['id_token'] ??
                        (decoded['data'] is Map ? decoded['data']['access_token'] : null))
                    ?.toString();
                if (tok != null && tok.length > 40 && capturedToken == null) {
                  capturedToken = tok;
                }
                final rt = decoded['refresh_token']?.toString();
                if (rt != null && rt.isNotEmpty) {
                  capturedRefreshToken = rt;
                }
              }
            } catch (_) {}
          }
        }
      });

      Future<dynamic> evalJs(String expr) async {
        final res = await cdp!.send(
          'Runtime.evaluate',
          params: {
            'expression': expr,
            'returnByValue': true,
            'awaitPromise': true,
          },
          sessionId: sessionId,
        );
        return (res['result'] as Map?)?['value'];
      }

      Future<String> currentUrl() async =>
          (await evalJs('location.href'))?.toString() ?? '';

      Future<void> clickPoint(double x, double y) async {
        await cdp!.send('Input.dispatchMouseEvent',
            params: {'type': 'mouseMoved', 'x': x, 'y': y},
            sessionId: sessionId);
        await Future.delayed(const Duration(milliseconds: 90));
        await cdp.send('Input.dispatchMouseEvent',
            params: {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1},
            sessionId: sessionId);
        await Future.delayed(const Duration(milliseconds: 70));
        await cdp.send('Input.dispatchMouseEvent',
            params: {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1},
            sessionId: sessionId);
      }

      Future<bool> clickSelector(String jsFindRect) async {
        final rect = await evalJs('''(() => {
          const el = $jsFindRect;
          if (!el) return null;
          el.scrollIntoView({block: 'center'});
          const r = el.getBoundingClientRect();
          if (r.width <= 0 || r.height <= 0) return null;
          return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
        })()''');
        if (rect is Map && rect['x'] != null && rect['y'] != null) {
          await clickPoint(
              (rect['x'] as num).toDouble(), (rect['y'] as num).toDouble());
          return true;
        }
        return false;
      }

      Future<bool> typeIntoSelector(String selector, String text) async {
        final clicked = await clickSelector(
            'document.querySelector(${jsonEncode(selector)})');
        if (!clicked) return false;
        await Future.delayed(const Duration(milliseconds: 180));
        await evalJs('''(() => {
          const el = document.querySelector(${jsonEncode(selector)});
          if (!el) return;
          el.focus();
          const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
          if (setter) setter.call(el, ''); else el.value = '';
          el.dispatchEvent(new Event('input', { bubbles: true }));
        })()''');
        await cdp!.send('Input.insertText',
            params: {'text': text}, sessionId: sessionId);
        await Future.delayed(const Duration(milliseconds: 200));
        return true;
      }

      try {
        // Step 1: Wait for stableaudio.com to load
        onStatus?.call('Loading stableaudio.com…');
        await Future.delayed(const Duration(seconds: 3));

        // Step 2: Click Sign up button
        onStatus?.call('Clicking Sign up…');
        final clickedSignup = await clickSelector('''
          [...document.querySelectorAll('button, a')].find(el =>
            el.offsetParent !== null && /^\\s*sign\\s*up\\s*\$/i.test(el.innerText || el.textContent || '')
          )
        ''');
        if (!clickedSignup) {
          await evalJs('''(() => {
            const el = [...document.querySelectorAll('button, a')].find(e =>
              /sign\\s*up/i.test(e.innerText || e.textContent || '')
            );
            if (el) el.click();
          })()''');
        }

        // Step 3: Wait for email input on AuthKit /sign-up
        onStatus?.call('Waiting for AuthKit sign-up form…');
        var emailReady = false;
        for (var i = 0; i < 40; i++) {
          final found = await evalJs(
              '!!document.querySelector(\'input[name="email"], input[type="email"], input[autocomplete="email"]\')');
          if (found == true) {
            emailReady = true;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
        if (!emailReady) {
          throw StableAudioException('AuthKit email field did not appear.');
        }

        await Future.delayed(const Duration(milliseconds: 800));
        await typeIntoSelector('input[name="first_name"], input[name="firstName"]', 'Alex');
        await typeIntoSelector('input[name="last_name"], input[name="lastName"]', 'Carter');

        onStatus?.call('Entering disposable email…');
        await typeIntoSelector(
            'input[name="email"], input[type="email"], input[autocomplete="email"]',
            email);
        await Future.delayed(const Duration(milliseconds: 500));

        // Check if password is already visible on step 1
        var passVisible = await evalJs(
            '!!document.querySelector(\'input[name="password"], input[type="password"]\')');
        if (passVisible != true) {
          await clickSelector(
              'document.querySelector(\'button.ak-PrimaryButton, button[type="submit"], form button\')');
          onStatus?.call('Waiting for password step…');
          for (var i = 0; i < 40; i++) {
            passVisible = await evalJs(
                '!!document.querySelector(\'input[name="password"], input[type="password"]\')');
            if (passVisible == true) break;
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        if (passVisible != true) {
          throw StableAudioException('AuthKit password field did not appear.');
        }

        await Future.delayed(const Duration(milliseconds: 800));
        onStatus?.call('Entering password & submitting…');
        await typeIntoSelector(
            'input[name="password"], input[type="password"]', password);
        await Future.delayed(const Duration(milliseconds: 600));
        await clickSelector(
            'document.querySelector(\'button.ak-PrimaryButton, button[type="submit"]\')');

        // Wait for transition away from /sign-up/password
        for (var w = 0; w < 16; w++) {
          await Future.delayed(const Duration(milliseconds: 500));
          final u = await currentUrl();
          if (_isStableAudioHost(u) || capturedToken != null) break;
          if (!u.contains('/sign-up/password')) break;
        }

        // Check for AuthKit error alerts vs Verify Email screen
        final alertText = (await evalJs('''(() => {
          const el = document.querySelector('[role="alert"], .ak-Error, [data-accent-color="red"]');
          return el ? (el.innerText || '').trim() : '';
        })()''') ?? '')
            .toString();
        final isVerifyAlert = RegExp(
                r'verify your email|verification code|check your email|enter the.*code|sent.*code',
                caseSensitive: false)
            .hasMatch(alertText);
        if (alertText.isNotEmpty &&
            !isVerifyAlert &&
            RegExp(r'blocked|contact support|invalid|disposable|not allowed|already|error|weak',
                    caseSensitive: false)
                .hasMatch(alertText)) {
          throw StableAudioException('AuthKit rejected signup: $alertText');
        }

        // Step 7b: Handle Email Verification (6-digit OTP)
        final curUrl = await currentUrl();
        final hasOtpInput = await evalJs(
            '!!document.querySelector(\'input[name="code"], input[autocomplete="one-time-code"], input[inputmode="numeric"], input[maxlength="1"], input[maxlength="6"]\')');
        if (!_isStableAudioHost(curUrl) &&
            (isVerifyAlert ||
                curUrl.contains('email-verification') ||
                curUrl.contains('verify') ||
                hasOtpInput == true)) {
          final otp = await pollTempMailForOtp(inbox, onStatus: onStatus);
          if (otp == null) {
            throw StableAudioException(
                'Timed out waiting for 6-digit OTP email from AuthKit.');
          }
          onStatus?.call('Entering 6-digit OTP ($otp)…');
          await evalJs('''((code) => {
            const allInputs = Array.from(document.querySelectorAll('input')).filter(el => {
              const t = (el.getAttribute('type') || '').toLowerCase();
              return t !== 'hidden' && t !== 'checkbox' && t !== 'radio';
            });
            if (allInputs.length === 6) {
              for (let i = 0; i < 6; i++) {
                const inp = allInputs[i];
                inp.focus();
                const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
                if (setter) setter.call(inp, code[i]); else inp.value = code[i];
                inp.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
                inp.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
              }
            } else {
              const target = document.querySelector('input[autocomplete="one-time-code"], input[name="code"], input[data-input-otp], input[inputmode="numeric"]') || allInputs[0];
              if (target) {
                target.focus();
                const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
                if (setter) setter.call(target, code); else target.value = code;
                target.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
                target.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
              }
            }
          })(${jsonEncode(otp)})''');

          await Future.delayed(const Duration(milliseconds: 1200));
          if (!_isStableAudioHost(await currentUrl())) {
            final submitted = await clickSelector(
                'document.querySelector(\'button[type="submit"], button.ak-PrimaryButton, .ak-Button--primary\')');
            if (!submitted) {
              await evalJs('''(() => {
                const form = document.querySelector('form');
                if (form) {
                  if (typeof form.requestSubmit === 'function') form.requestSubmit();
                  else form.submit();
                }
              })()''');
            }
          }
          await Future.delayed(const Duration(seconds: 3));
        }

        // Step 8: Wait for redirect to stableaudio.com
        onStatus?.call('Waiting for redirect to stableaudio.com…');
        final redirectDeadline = DateTime.now().add(const Duration(seconds: 40));
        while (DateTime.now().isBefore(redirectDeadline)) {
          if (_isStableAudioHost(await currentUrl())) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }

        // Wait briefly for OAuth ?code= exchange
        for (var w = 0; w < 12; w++) {
          final u = await currentUrl();
          if (!_isStableAudioHost(u) || !u.contains('code=') || capturedToken != null) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }

        // Accept onboarding terms if redirected to /terms
        final termsUrl = await currentUrl();
        if (_isStableAudioHost(termsUrl) &&
            (termsUrl.contains('/terms') || termsUrl.contains('onboarding'))) {
          onStatus?.call('Accepting Stable Audio terms…');
          await evalJs('''(() => {
            document.querySelectorAll('input[type="checkbox"], button[role="checkbox"], [role="checkbox"]').forEach(el => {
              const checked = el.checked === true || el.getAttribute('aria-checked') === 'true' || el.getAttribute('data-state') === 'checked';
              if (!checked) el.click();
            });
            const btn = [...document.querySelectorAll('button')].find(b =>
              /accept|agree|continue|get started/i.test(b.innerText || b.textContent || '')
            ) || document.querySelector('button[type="submit"]');
            if (btn) btn.click();
          })()''');
          await Future.delayed(const Duration(seconds: 2));
        }

        // Poll for token in storage, cookies, or network
        onStatus?.call('Capturing Stable Audio bearer token…');
        final tokDeadline = DateTime.now().add(const Duration(seconds: 45));
        var navigatedToGen = false;
        while (capturedToken == null && DateTime.now().isBefore(tokDeadline)) {
          if (_isStableAudioHost(await currentUrl())) {
            final storageTok = await evalJs('''(() => {
              const scan = (store) => {
                for (let i = 0; i < store.length; i++) {
                  const k = store.key(i);
                  if (!k) continue;
                  const raw = store.getItem(k) || '';
                  if (/^eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\$/.test(raw.trim())) {
                    return raw.trim();
                  }
                  try {
                    const p = JSON.parse(raw);
                    const tok = p?.body?.access_token || p?.access_token || p?.accessToken ||
                                p?.token || p?.idToken || p?.id_token || p?.state?.token ||
                                p?.state?.accessToken;
                    if (tok && typeof tok === 'string' && tok.length > 40) return tok;
                  } catch {}
                }
                return null;
              };
              return scan(localStorage) || scan(sessionStorage);
            })()''');
            if (storageTok is String && storageTok.length > 40) {
              capturedToken = storageTok;
              break;
            }
          }

          final ckRes = await cdp.send('Network.getCookies', sessionId: sessionId);
          final cookies = (ckRes['cookies'] as List? ?? const []).whereType<Map>();
          for (final c in cookies) {
            final v = (c['value'] ?? '').toString();
            if (RegExp(r'^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$')
                .hasMatch(v)) {
              capturedToken = v;
              break;
            }
          }
          if (capturedToken != null) break;

          if (!navigatedToGen &&
              _isStableAudioHost(await currentUrl()) &&
              DateTime.now().isAfter(tokDeadline.subtract(const Duration(seconds: 35)))) {
            navigatedToGen = true;
            await cdp.send('Page.navigate',
                params: {'url': 'https://stableaudio.com/generate'},
                sessionId: sessionId);
          }
          await Future.delayed(const Duration(milliseconds: 1500));
        }

        if (capturedToken != null && capturedToken!.isNotEmpty) {
          onStatus?.call('New 50-credit Stable Audio account ready ($email)!');
          return RotatedStableAudioAccount(
            token: capturedToken!,
            refreshToken: capturedRefreshToken ?? '',
            workosClientId: capturedClientId,
            email: email,
            password: password,
          );
        }
      } finally {
        await evSub.cancel();
      }
    } catch (e) {
      if (attempt == 2) {
        if (e is StableAudioException) rethrow;
        throw StableAudioException('Auto account creation failed: $e', auth: true);
      }
    } finally {
      try {
        await cdp
            ?.send('Browser.close')
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      try {
        await cdp?.close();
      } catch (_) {}
      try {
        if (proc != null) {
          if (Platform.isWindows) {
            await Process.run('taskkill', ['/F', '/T', '/PID', '${proc.pid}'])
                .timeout(const Duration(seconds: 3));
          } else {
            proc.kill();
          }
        }
      } catch (_) {}
      try {
        if (tempProfile.existsSync()) tempProfile.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  throw StableAudioException('Could not capture Stable Audio token after rotation.', auth: true);
}

