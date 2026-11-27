import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_image_studio/android_gecko.dart';
import 'package:ai_image_studio/platform_ui.dart';
import 'package:ai_image_studio/ringtone/stable_audio_browser.dart';
import 'package:ai_image_studio/ringtone/temp_mail.dart';

const _codec = StandardMethodCodec();
const _gecko = MethodChannel('ais/gecko');
const _audio = MethodChannel('ais/stable_audio');
const _inbox = TempMailInbox(
  provider: 'test',
  email: 'test@example.invalid',
  mailToken: 'test-only',
);

// Simulate an Android -> Dart MethodChannel request without a device.
Future<dynamic> _fromAndroid(String method) {
  final reply = Completer<dynamic>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'ais/stable_audio',
        _codec.encodeMethodCall(MethodCall(method)),
        (data) {
          try {
            reply.complete(data == null ? null : _codec.decodeEnvelope(data));
          } catch (e, stack) {
            reply.completeError(e, stack);
          }
        },
      );
  return reply.future;
}

class _DelayedMail extends TempMailClient {
  final ready = Completer<TempMailInbox>();
  bool requested = false;

  @override
  Future<TempMailInbox> createInbox({void Function(String)? onLog}) {
    requested = true;
    return ready.future;
  }

  @override
  String generateStrongPassword() => 'Test-only-password-123!';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugForceAndroid = true;
  });
  tearDown(() {
    debugForceAndroid = null;
    messenger.setMockMethodCallHandler(_gecko, null);
    _audio.setMethodCallHandler(null);
  });

  test('rotation opens Android browser before waiting for mailbox', () async {
    final mail = _DelayedMail();
    final launched = Completer<void>();
    messenger.setMockMethodCallHandler(_gecko, (call) async {
      expect(call.method, 'stableAudioAutoCreate');
      expect(mail.requested, isFalse);
      expect(call.arguments['email'], isEmpty);
      launched.complete();
      final details = await _fromAndroid('prepareStableAudioAccount') as Map;
      expect(details['email'], _inbox.email);
      expect(details['password'], isNotEmpty);
      return jsonEncode({'accessToken': 'test-access-token'});
    });

    final rotation = StableAudioBrowser.autoCreateAccount(tempMail: mail);
    await launched.future;
    // The browser launch is already requested, even with an unresolved inbox.
    expect(mail.ready.isCompleted, isFalse);
    mail.ready.complete(_inbox);
    final account = await rotation;
    expect(account?.label, _inbox.email);
    expect(account?.accessToken, 'test-access-token');
  });

  test(
    'closing browser before preparation returns without creating inbox',
    () async {
      final mail = _DelayedMail();
      messenger.setMockMethodCallHandler(_gecko, (_) async => null);
      expect(
        await StableAudioBrowser.autoCreateAccount(tempMail: mail),
        isNull,
      );
      expect(mail.requested, isFalse);
      expect(await _fromAndroid('prepareStableAudioAccount'), isNull);
    },
  );

  test('existing prepared account and OTP bridge remain compatible', () async {
    var polls = 0;
    messenger.setMockMethodCallHandler(_gecko, (call) async {
      expect(call.arguments['email'], 'test@example.invalid');
      final details = await _fromAndroid('prepareStableAudioAccount') as Map;
      expect(details['password'], 'test-only');
      expect(await _fromAndroid('pollStableAudioOtp'), '123456');
      return jsonEncode({'accessToken': 'test-access-token'});
    });
    final result = await AndroidGecko.autoCreateStableAudio(
      email: 'test@example.invalid',
      password: 'test-only',
      onPollOtp: () async {
        polls++;
        return '123456';
      },
    );
    expect(result?['accessToken'], 'test-access-token');
    expect(polls, 1);
    expect(await _fromAndroid('pollStableAudioOtp'), isNull);
  });

  test('repeated rotate click does not replace active callback handler', () async {
    final launched = Completer<void>();
    final close = Completer<String?>();
    messenger.setMockMethodCallHandler(_gecko, (_) async {
      launched.complete();
      return await close.future;
    });
    final first = AndroidGecko.autoCreateStableAudio(
      email: 'test@example.invalid', password: 'test-only',
      onPollOtp: () async => '123456',
    );
    await launched.future;
    await expectLater(
      AndroidGecko.autoCreateStableAudio(onPollOtp: () async => null),
      throwsA(isA<PlatformException>().having(
        (e) => e.code, 'code', 'stable_audio_busy')),
    );
    expect(await _fromAndroid('pollStableAudioOtp'), '123456');
    close.complete(null);
    expect(await first, isNull);
  });

  test(
    'preparation failure reaches caller and removes callback handler',
    () async {
      messenger.setMockMethodCallHandler(_gecko, (_) async {
        try {
          await _fromAndroid('prepareStableAudioAccount');
        } on PlatformException {
          throw PlatformException(
            code: 'stable_audio',
            message: 'Could not prepare account',
          );
        }
        return null;
      });
      await expectLater(
        AndroidGecko.autoCreateStableAudio(
          onPrepareAccount: () async => throw Exception('Mailbox unavailable'),
          onPollOtp: () async => null,
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(await _fromAndroid('prepareStableAudioAccount'), isNull);
    },
  );
}
