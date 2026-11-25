import 'dart:convert';

import 'gemini_image.dart';
import 'gemini_web.dart';
import 'secure_store.dart';

/// Saved Gemini account list + selection, mirroring Gemini HD Studio's
/// discoveredGeminiAccounts / geminiAccountMode / auto-switch on limit.
class GeminiAccounts {
  GeminiAccounts._();

  static const _kList = 'gemini_accounts';
  static const _kMode = 'gemini_account_mode'; // 'auto' or '0'..'5'
  static const _kAuto = 'gemini_auto_switch';

  static Future<List<GeminiAccount>> load() async {
    final p = await AppPrefs.prefs();
    try {
      final raw = p.getString(_kList);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => GeminiAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<GeminiAccount> list) async =>
      (await AppPrefs.prefs())
          .setString(_kList, jsonEncode([for (final a in list) a.toJson()]));

  static Future<String> mode() async =>
      (await AppPrefs.prefs()).getString(_kMode) ?? 'auto';
  static Future<void> setMode(String v) async =>
      (await AppPrefs.prefs()).setString(_kMode, v);

  static Future<bool> autoSwitch() async =>
      (await AppPrefs.prefs()).getBool(_kAuto) ?? true;
  static Future<void> setAutoSwitch(bool v) async =>
      (await AppPrefs.prefs()).setBool(_kAuto, v);

  /// Scans u/0..u/5 with the saved session and stores the result.
  static Future<List<GeminiAccount>> scan() async {
    final raw = await GeminiWebStore.load();
    if (raw.trim().isEmpty) {
      throw GeminiWebException('Sign in with Google first.');
    }
    final list = await GeminiWebClient.scanAccounts(GeminiWebSession.parse(raw));
    await save(list);
    return list;
  }

  /// Ready-to-use image client for the selected account, with failover
  /// to the other signed-in accounts. Throws when no session is saved.
  static Future<GeminiImageClient> client() async {
    final raw = await GeminiWebStore.load();
    if (raw.trim().isEmpty) {
      throw GeminiWebException(
          'Sign in with Google in Settings (or paste a cookie session).');
    }
    final session = GeminiWebSession.parse(raw);
    final m = await mode();
    final u = int.tryParse(m) ?? 0;
    final c = GeminiImageClient(GeminiWebClient(session, authUser: u));
    c.accounts = await load();
    c.autoSwitch = await autoSwitch();
    return c;
  }
}
