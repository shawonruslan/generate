import 'dart:async';

import 'package:http/http.dart' as http;

import 'stable_audio.dart';
import 'stable_audio_http_auth.dart';
import 'temp_mail.dart';

/// Browser-free account creation. FALLBACK ONLY: AuthKit's signup form
/// requires the browser "signals" payload its own JS collects, so a plain
/// HTTP client is normally rejected at the first form (see
/// BROWSER_SIGNUP_FIX.md). Ringtone Studio uses the browser flow
/// (StableAudioBrowser) wherever a browser engine exists and only reaches
/// this path on platforms without one.
class StableAudioHttpAccounts {
  StableAudioHttpAccounts._();
  static const supported = true;

  static Future<StableAudioAccount?> autoCreateAccount({
    void Function(String)? onLog,
    http.Client? httpClient,
    TempMailClient? tempMail,
  }) async {
    final mail = tempMail ?? TempMailClient(httpClient: httpClient);
    final auth = StableAudioHttpAuth(httpClient: httpClient, onLog: onLog);
    try {
      onLog?.call('Preparing email inbox for request-only signup...');
      final inbox = await mail
          .createInbox(onLog: onLog)
          .timeout(const Duration(seconds: 90));
      final tokens = await auth
          .createAccount(
            email: inbox.email,
            password: mail.generateStrongPassword(),
            onOtp: () =>
                mail.pollForOtp(inbox, timeout: const Duration(seconds: 90)),
          )
          .timeout(const Duration(minutes: 4));
      return StableAudioAccount(
        id: 'acc_${DateTime.now().microsecondsSinceEpoch}',
        label: tokens.email,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        clientId: tokens.clientId,
      );
    } on TimeoutException {
      throw const StableAudioHttpAuthException(
          'HTTP account creation timed out. Please retry.');
    } finally {
      auth.close();
      if (tempMail == null) mail.close();
    }
  }
}
