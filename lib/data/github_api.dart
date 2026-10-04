import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kGhApi = 'https://api.github.com';
const String kGhCfgKey = 'ghCtl_v1';
const String kGhSessionKey = 'ghGeminiSession_v1';
const String kGhCfgTsKey = 'ghCtl_v1_ts';
const String kGhSessionTsKey = 'ghGeminiSession_v1_ts';
const String kGhDbSettingsPath = 'dashboardSettings/ghPanel';

/// GitHub Control connection settings (`ghCtl_v1`).
class GhCfg {
  GhCfg({this.owner = '', this.repo = '', this.branch = 'main', this.token = '', Map<String, String>? workflows})
      : workflows = workflows ?? {};
  String owner, repo, branch, token;
  final Map<String, String> workflows;

  bool get ready => owner.isNotEmpty && repo.isNotEmpty && token.isNotEmpty;

  static GhCfg fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return GhCfg();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return GhCfg();
      final wf = <String, String>{};
      if (m['workflows'] is Map) {
        (m['workflows'] as Map).forEach((k, v) => wf['$k'] = '${v ?? ''}');
      }
      return GhCfg(
        owner: '${m['owner'] ?? ''}',
        repo: '${m['repo'] ?? ''}',
        branch: '${m['branch'] ?? ''}'.isEmpty ? 'main' : '${m['branch']}',
        token: '${m['token'] ?? ''}',
        workflows: wf,
      );
    } catch (_) {
      return GhCfg();
    }
  }

  String toJson() => jsonEncode({
        'owner': owner,
        'repo': repo,
        'branch': branch.isEmpty ? 'main' : branch,
        'token': token,
        'workflows': workflows,
      });
}

class GhApiException implements Exception {
  GhApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `ghApi(path, options)` - authenticated GitHub REST call.
Future<dynamic> ghApiCall({
  required String token,
  required String path,
  String method = 'GET',
  Object? body,
}) async {
  final uri = Uri.parse('$kGhApi$path');
  final headers = <String, String>{
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    if (body != null) 'Content-Type': 'application/json',
  };
  final req = http.Request(method, uri)..headers.addAll(headers);
  if (body != null) req.body = body is String ? body : jsonEncode(body);
  final streamed = await http.Client().send(req).timeout(const Duration(seconds: 60));
  final res = await http.Response.fromStream(streamed);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    var detail = '';
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['message'] != null) detail = '${j['message']}';
    } catch (_) {}
    throw GhApiException('GitHub API ${res.statusCode}: ${detail.isNotEmpty ? detail : res.reasonPhrase ?? ''}');
  }
  if (res.statusCode == 204 || res.body.isEmpty) return null;
  return jsonDecode(res.body);
}

String ghEncodePath(String p) => p.split('/').map(Uri.encodeComponent).join('/');

class GhSessionInfo {
  const GhSessionInfo(this.cookies, this.format);
  final int cookies;
  final String format;
}

/// `ghSessionInfo(raw)` - throws FormatException on invalid JSON.
GhSessionInfo ghSessionInfo(String raw) {
  final parsed = jsonDecode(raw);
  if (parsed is List) return GhSessionInfo(parsed.length, 'cookie array');
  if (parsed is Map && parsed['cookies'] is List) return GhSessionInfo((parsed['cookies'] as List).length, 'storageState');
  return const GhSessionInfo(0, 'unknown object');
}

/// Local persistence of the GitHub panel (mirrors localStorage keys).
class GhLocalStore {
  static Future<SharedPreferences> get _sp => SharedPreferences.getInstance();

  static Future<GhCfg> loadCfg() async => GhCfg.fromJson((await _sp).getString(kGhCfgKey));
  static Future<String> loadCfgRaw() async => (await _sp).getString(kGhCfgKey) ?? '';
  static Future<int> loadCfgTs() async => (await _sp).getInt(kGhCfgTsKey) ?? 0;
  static Future<void> saveCfgRaw(String raw, int ts) async {
    final sp = await _sp;
    await sp.setString(kGhCfgKey, raw);
    await sp.setInt(kGhCfgTsKey, ts);
  }

  static Future<String> loadSession() async => (await _sp).getString(kGhSessionKey) ?? '';
  static Future<int> loadSessionTs() async => (await _sp).getInt(kGhSessionTsKey) ?? 0;
  static Future<void> saveSession(String raw, int ts) async {
    final sp = await _sp;
    if (raw.isEmpty) {
      await sp.remove(kGhSessionKey);
    } else {
      await sp.setString(kGhSessionKey, raw);
    }
    await sp.setInt(kGhSessionTsKey, ts);
  }

  static String vpnGhLocalKey(String acc) => 'vpnGh_v1_$acc';
  static Future<Map<String, dynamic>?> loadVpnGh(String acc) async {
    final raw = (await _sp).getString(vpnGhLocalKey(acc));
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveVpnGh(String acc, Map<String, dynamic> rec) async => (await _sp).setString(vpnGhLocalKey(acc), jsonEncode(rec));
}
