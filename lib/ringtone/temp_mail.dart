import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// A disposable email inbox used for automated Stable Audio account rotation.
class TempMailInbox {
  final String provider; // mailtm | guerrilla
  final String apiBase;
  final String email;
  final String mailToken;

  const TempMailInbox({
    required this.provider,
    this.apiBase = '',
    required this.email,
    required this.mailToken,
  });
}

/// Pure-Dart temp-mail client (Mail.tm -> Mail.gw -> GuerrillaMail),
/// matching `generator.yml`'s `createTempMailAccount` & `pollTempMailForOtp`.
class TempMailClient {
  TempMailClient({http.Client? httpClient, Random? random})
      : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _rnd = random ?? Random();

  final http.Client _http;
  final bool _ownsClient;
  final Random _rnd;

  void close() {
    if (_ownsClient) _http.close();
  }

  static const _firsts = [
    'alex',
    'jordan',
    'taylor',
    'morgan',
    'casey',
    'riley',
    'quinn',
    'avery',
  ];
  static const _lasts = [
    'carter',
    'bennett',
    'hayes',
    'parker',
    'collins',
    'reid',
    'foster',
    'brooks',
  ];

  String generateStrongPassword() {
    const lower = 'abcdefghjkmnpqrstuvwxyz';
    const upper = 'ABCDEFGHJKMNPQRSTUVWXYZ';
    const digits = '23456789';
    const symbols = '!@#\$%';
    String pick(String pool) => pool[_rnd.nextInt(pool.length)];
    final chars = <String>[
      pick(upper),
      pick(upper),
      pick(lower),
      pick(lower),
      pick(lower),
      pick(digits),
      pick(digits),
      pick(symbols),
      for (var i = 0; i < 6; i++) pick(lower + upper + digits),
    ]..shuffle(_rnd);
    return chars.join();
  }

  Future<TempMailInbox> createInbox({void Function(String)? onLog}) async {
    final f = _firsts[_rnd.nextInt(_firsts.length)];
    final l = _lasts[_rnd.nextInt(_lasts.length)];

    for (final apiBase in const [
      'https://api.mail.tm',
      'https://api.mail.gw'
    ]) {
      try {
        final domRes = await _http
            .get(Uri.parse('$apiBase/domains'))
            .timeout(const Duration(seconds: 15));
        if (domRes.statusCode < 200 || domRes.statusCode >= 300) {
          throw Exception('domains HTTP ${domRes.statusCode}');
        }
        final domData = jsonDecode(domRes.body);
        final members = domData is Map
            ? (domData['hydra:member'] as List? ?? [])
            : const [];
        final domains = <String>[
          for (final d in members)
            if (d is Map && d['isActive'] != false && d['domain'] != null)
              d['domain'].toString(),
        ];
        if (domains.isEmpty) throw Exception('No active domains');

        final domain = domains[_rnd.nextInt(domains.length)];
        const alpha = 'abcdefghijklmnopqrstuvwxyz0123456789';
        final rndStr =
            List.generate(5, (_) => alpha[_rnd.nextInt(alpha.length)]).join();
        final ts = DateTime.now().millisecondsSinceEpoch.toString();
        final tsTail = ts.substring(max(0, ts.length - 4));
        final rawAddress = '$f$l$rndStr$tsTail@$domain'.toLowerCase();
        final mailPw = 'MailPass$rndStr${tsTail}A1';

        final accRes = await _http
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
        final canonical = (accData is Map && accData['address'] != null)
            ? accData['address'].toString().toLowerCase().trim()
            : rawAddress;

        await Future<void>.delayed(const Duration(seconds: 1));

        String? tok;
        for (var tTry = 0; tTry < 2; tTry++) {
          final tokRes = await _http
              .post(
                Uri.parse('$apiBase/token'),
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
                body: jsonEncode({'address': canonical, 'password': mailPw}),
              )
              .timeout(const Duration(seconds: 15));
          if (tokRes.statusCode >= 200 && tokRes.statusCode < 300) {
            final tokData = jsonDecode(tokRes.body);
            if (tokData is Map && tokData['token'] != null) {
              tok = tokData['token'].toString();
              break;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
        if (tok == null || tok.isEmpty) {
          throw Exception('token endpoint did not return token');
        }
        onLog?.call('Created temp-mail inbox ($apiBase): $canonical');
        return TempMailInbox(
          provider: 'mailtm',
          apiBase: apiBase,
          email: canonical,
          mailToken: tok,
        );
      } catch (e) {
        onLog?.call('$apiBase failed ($e) — trying next temp-mail provider...');
      }
    }

    try {
      final gmRes = await _http
          .get(Uri.parse(
              'https://api.guerrillamail.com/ajax.php?f=get_email_address&lang=en'))
          .timeout(const Duration(seconds: 15));
      if (gmRes.statusCode >= 200 && gmRes.statusCode < 300) {
        final gmData = jsonDecode(gmRes.body);
        if (gmData is Map &&
            gmData['email_addr'] != null &&
            gmData['sid_token'] != null) {
          final email = gmData['email_addr'].toString();
          onLog?.call('Created GuerrillaMail inbox: $email');
          return TempMailInbox(
            provider: 'guerrilla',
            email: email,
            mailToken: gmData['sid_token'].toString(),
          );
        }
      }
    } catch (e) {
      onLog?.call('GuerrillaMail failed ($e)');
    }

    throw Exception('All temp-mail providers failed to create an inbox.');
  }

  static String? extractSixDigitOtp({
    String subject = '',
    String intro = '',
    String text = '',
    String html = '',
  }) {
    final cleanHtml = html
        .replaceAll(
            RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<head[\s\S]*?</head>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    final otpRe = RegExp(r'\b(\d{6})\b');
    for (final src in [subject, intro, text, cleanHtml]) {
      if (src.isEmpty) continue;
      final m = otpRe.firstMatch(src);
      if (m != null) return m.group(1);
    }
    return null;
  }

  Future<String?> pollForOtp(
    TempMailInbox inbox, {
    Duration timeout = const Duration(seconds: 60),
    Duration interval = const Duration(seconds: 3),
    bool Function()? cancelled,
  }) async {
    if (inbox.mailToken.isEmpty) return null;
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      if (cancelled?.call() ?? false) return null;
      try {
        if (inbox.provider == 'mailtm') {
          final res = await _http.get(
            Uri.parse('${inbox.apiBase}/messages'),
            headers: {
              'Authorization': 'Bearer ${inbox.mailToken}',
              'Accept': 'application/json',
            },
          ).timeout(const Duration(seconds: 15));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final data = jsonDecode(res.body);
            final msgs = data is List
                ? data
                : (data is Map
                    ? (data['hydra:member'] as List? ?? [])
                    : const []);
            for (final msg in msgs) {
              if (msg is! Map) continue;
              final quick = extractSixDigitOtp(
                subject: (msg['subject'] ?? '').toString(),
                intro: (msg['intro'] ?? '').toString(),
              );
              if (quick != null) return quick;

              final id = msg['id']?.toString() ?? '';
              if (id.isEmpty) continue;
              final detailRes = await _http.get(
                Uri.parse('${inbox.apiBase}/messages/$id'),
                headers: {
                  'Authorization': 'Bearer ${inbox.mailToken}',
                  'Accept': 'application/json',
                },
              ).timeout(const Duration(seconds: 15));
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
          final res = await _http
              .get(Uri.parse(
                  'https://api.guerrillamail.com/ajax.php?f=get_email_list&offset=0&sid_token=${Uri.encodeComponent(inbox.mailToken)}'))
              .timeout(const Duration(seconds: 15));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            final data = jsonDecode(res.body);
            final list = data is Map ? (data['list'] as List? ?? []) : const [];
            for (final msg in list) {
              if (msg is! Map) continue;
              final from = (msg['mail_from'] ?? '').toString();
              if (RegExp(r'guerrillamail', caseSensitive: false)
                  .hasMatch(from)) {
                continue;
              }
              final quick = extractSixDigitOtp(
                subject: (msg['mail_subject'] ?? '').toString(),
                intro: (msg['mail_excerpt'] ?? '').toString(),
              );
              if (quick != null) return quick;

              final mailId = msg['mail_id']?.toString() ?? '';
              if (mailId.isEmpty) continue;
              final detailRes = await _http
                  .get(Uri.parse(
                      'https://api.guerrillamail.com/ajax.php?f=fetch_email&email_id=$mailId&sid_token=${Uri.encodeComponent(inbox.mailToken)}'))
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
      await Future<void>.delayed(interval);
    }
    return null;
  }
}
