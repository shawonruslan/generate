import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloudinary_api.dart';

/// Credentials live in the OS secure storage (Keychain / Keystore /
/// Windows Credential Manager), never in plain preferences.
class CredentialStore {
  CredentialStore._();

  static const _storage = FlutterSecureStorage();
  static const _kCloud = 'cloud_name';
  static const _kKey = 'api_key';
  static const _kSecret = 'api_secret';

  static Future<CloudinaryCredentials> load() async {
    return CloudinaryCredentials(
      cloudName: await _storage.read(key: _kCloud) ?? '',
      apiKey: await _storage.read(key: _kKey) ?? '',
      apiSecret: await _storage.read(key: _kSecret) ?? '',
    );
  }

  static Future<void> save(CloudinaryCredentials creds) async {
    await _storage.write(key: _kCloud, value: creds.cloudName.trim());
    await _storage.write(key: _kKey, value: creds.apiKey.trim());
    await _storage.write(key: _kSecret, value: creds.apiSecret.trim());
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kCloud);
    await _storage.delete(key: _kKey);
    await _storage.delete(key: _kSecret);
  }
}

/// Gemini API keys + model ids for AI metadata. Keys stay in the OS
/// secure storage, next to the Cloudinary credentials.
class GeminiStore {
  GeminiStore._();

  static const _storage = FlutterSecureStorage();
  static const _kKeys = 'gemini_keys';
  static const _kModels = 'gemini_models';

  static List<String> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return [
          for (final e in list)
            if (e.toString().trim().isNotEmpty) e.toString().trim()
        ];
      }
    } catch (_) {}
    return [];
  }

  static Future<({List<String> keys, List<String> models})> load() async {
    return (
      keys: _parse(await _storage.read(key: _kKeys)),
      models: _parse(await _storage.read(key: _kModels)),
    );
  }

  static Future<void> save(
      List<String> keys, List<String> models) async {
    await _storage.write(key: _kKeys, value: jsonEncode(keys));
    await _storage.write(key: _kModels, value: jsonEncode(models));
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kKeys);
    await _storage.delete(key: _kModels);
  }
}

/// Non-secret app preferences.
class AppPrefs {
  AppPrefs._();

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _p() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Shared instance for other preference holders (e.g. GeminiWebPrefs).
  static Future<SharedPreferences> prefs() => _p();

  static Future<String> themeMode() async =>
      (await _p()).getString('theme_mode') ?? 'system';

  static Future<void> setThemeMode(String v) async =>
      (await _p()).setString('theme_mode', v);

  static Future<String?> lastModel(bool imageMode) async =>
      (await _p()).getString(imageMode ? 'last_model_img' : 'last_model_txt');

  static Future<void> setLastModel(bool imageMode, String v) async =>
      (await _p()).setString(imageMode ? 'last_model_img' : 'last_model_txt', v);

  static Future<String> lastRatio() async =>
      (await _p()).getString('last_ratio') ?? '1:1';

  static Future<void> setLastRatio(String v) async =>
      (await _p()).setString('last_ratio', v);

  static Future<String> lastResolution() async =>
      (await _p()).getString('last_resolution') ?? '1K';

  static Future<void> setLastResolution(String v) async =>
      (await _p()).setString('last_resolution', v);

  static Future<String> lastFormat() async =>
      (await _p()).getString('last_format') ?? 'png';

  static Future<void> setLastFormat(String v) async =>
      (await _p()).setString('last_format', v);

  static Future<List<String>> history() async =>
      (await _p()).getStringList('history') ?? [];

  static Future<void> setHistory(List<String> v) async =>
      (await _p()).setStringList('history', v);

  static Future<int> lastExport() async =>
      (await _p()).getInt('export_preset') ?? 0;

  static Future<void> setExport(int v) async =>
      (await _p()).setInt('export_preset', v);

  static Future<int> gridCols() async =>
      (await _p()).getInt('grid_cols') ?? 3;

  static Future<void> setGridCols(int v) async =>
      (await _p()).setInt('grid_cols', v.clamp(2, 6));
}
