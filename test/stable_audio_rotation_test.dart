import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/ringtone/stable_audio.dart';
import 'package:ai_image_studio/ringtone/stable_audio_rotator.dart';

void main() {
  test('generateStrongPassword builds complex password', () {
    final p1 = generateStrongPassword(Random(1));
    final p2 = generateStrongPassword(Random(2));
    expect(p1.length, greaterThanOrEqualTo(18));
    expect(p1, contains('#'));
    expect(p1, contains('!'));
    expect(p1, endsWith('Q9'));
    expect(p1, isNot(equals(p2)));
  });

  test('extractSixDigitOtp extracts 6-digit code from subject, text, and HTML', () {
    expect(
      extractSixDigitOtp(subject: 'Your verification code is 482910'),
      '482910',
    );
    expect(
      extractSixDigitOtp(
        html: '<head><style>.x{color:#123456}</style></head>'
            '<body><p>Enter code <b>739201</b> to continue.</p></body>',
      ),
      '739201',
    );
    expect(extractSixDigitOtp(text: 'No code here 12345 or 1234567'), isNull);
  });

  test('getJwtExpSeconds decodes exp claim from JWT', () {
    final header = base64Url.encode(utf8.encode('{"alg":"RS256"}')).replaceAll('=', '');
    final payload = base64Url.encode(utf8.encode('{"exp":1800000000}')).replaceAll('=', '');
    final jwt = '$header.$payload.sig';
    expect(getJwtExpSeconds(jwt), 1800000000);
    expect(getJwtExpSeconds('not-a-jwt'), isNull);
  });
}

