import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'gemini_api.dart';

/// Distribution: uploads a finished set's files to the user's own
/// storage (Cloudflare R2 via their worker gateway) and pushes the
/// set record (files + metadata) to their own Firebase Realtime
/// Database - the same flow as the Generator Hub workflow
/// (generator__1.yml `distributeItem`):
///   R2 key layout : <folder>/wallpaper/<timestamp>_<name>
///   Firebase      : POST <dbUrl>/<queuePath>.json  -> { name: <key> }
///   Record fields : name, type, size, width, height, isMp3, isImage,
///                   contentType, fileUrl, files (per-slot, multi-frame
///                   sets), setName, status, prompt, imageModel, source,
///                   createdAt + title/tags/category/description +
///                   policyCheck/policyFlag when metadata exists.

const _store = FlutterSecureStorage();

/// One distribution account, mirroring the workflow's FIREBASE_DB_MAP
/// entries (zedge_1..zedge_4): a name plus its own Firebase database
/// URL (and optional secret). The R2 folder is derived from the name,
/// exactly like the workflow (`zedge_1` -> `zedge1`).
class DistAccount {
  final String name;
  final String dbUrl;
  final String secret;

  const DistAccount({
    required this.name,
    required this.dbUrl,
    this.secret = '',
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'dbUrl': dbUrl, 'secret': secret};

  static DistAccount fromJson(Map<String, dynamic> m) => DistAccount(
        name: (m['name'] ?? '').toString(),
        dbUrl: (m['dbUrl'] ?? '').toString(),
        secret: (m['secret'] ?? '').toString(),
      );

  /// R2 folder for this account, like the workflow's
  /// `dbName.replace(/^zedge_?/i, 'zedge')`.
  String get r2Folder {
    var f = name.replaceAll(RegExp(r'^zedge_?', caseSensitive: false), 'zedge');
    f = f.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    return f.isEmpty ? 'studio' : f;
  }
}

/// The whole distribution config. Different users have different
/// account counts, so accounts are a free-form list.
class DistConfig {
  final String r2WorkerUrl;
  final String queuePath;
  final List<DistAccount> accounts;

  /// 'spread' or an account name.
  final String defaultTarget;

  /// Account names participating in spread.
  final List<String> spreadPool;

  const DistConfig({
    this.r2WorkerUrl = '',
    this.queuePath = 'wallpaperQueue',
    this.accounts = const [],
    this.defaultTarget = 'spread',
    this.spreadPool = const [],
  });

  List<DistAccount> get spreadAccounts {
    final pool = spreadPool.isEmpty
        ? accounts.map((a) => a.name).toList()
        : spreadPool;
    return accounts.where((a) => pool.contains(a.name)).toList();
  }

  Map<String, dynamic> toJson() => {
        'r2WorkerUrl': r2WorkerUrl,
        'queuePath': queuePath,
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'defaultTarget': defaultTarget,
        'spreadPool': spreadPool,
      };

  static DistConfig fromJson(Map<String, dynamic> m) => DistConfig(
        r2WorkerUrl: (m['r2WorkerUrl'] ?? '').toString(),
        queuePath: (m['queuePath'] ?? 'wallpaperQueue').toString(),
        accounts: ((m['accounts'] as List?) ?? [])
            .whereType<Map>()
            .map((e) =>
                DistAccount.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        defaultTarget: (m['defaultTarget'] ?? 'spread').toString(),
        spreadPool: ((m['spreadPool'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

/// User's own distribution targets. Kept in secure storage.
class DistributeStore {
  DistributeStore._();

  static const _key = 'dist_config_v2';

  static Future<DistConfig> load() async {
    try {
      final raw = await _store.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        return DistConfig.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw)));
      }
    } catch (_) {}
    // Migrate the very first single-DB settings, if present.
    try {
      final db = (await _store.read(key: 'dist_db_url'))?.trim() ?? '';
      if (db.isNotEmpty) {
        final cfg = DistConfig(
          r2WorkerUrl:
              (await _store.read(key: 'dist_r2_worker_url'))?.trim() ?? '',
          queuePath:
              (await _store.read(key: 'dist_queue_path'))?.trim() ??
                  'wallpaperQueue',
          accounts: [
            DistAccount(
              name: 'main',
              dbUrl: db,
              secret:
                  (await _store.read(key: 'dist_db_secret'))?.trim() ?? '',
            ),
          ],
        );
        await save(cfg);
        return cfg;
      }
    } catch (_) {}
    return const DistConfig();
  }

  static Future<void> save(DistConfig cfg) =>
      _store.write(key: _key, value: jsonEncode(cfg.toJson()));

  /// Round-robin spread cursor, persisted.
  static Future<int> spreadCursor() async {
    final raw = await _store.read(key: 'dist_spread_cursor');
    return int.tryParse(raw ?? '') ?? 0;
  }

  static Future<void> setSpreadCursor(int v) =>
      _store.write(key: 'dist_spread_cursor', value: '$v');

  static Future<bool> isConfigured() async {
    final cfg = await load();
    return cfg.accounts.isNotEmpty &&
        cfg.r2WorkerUrl.trim().isNotEmpty;
  }

  static String normUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  static String _authQuery(String? secret) {
    final s = (secret ?? '').trim();
    return s.isEmpty ? '' : '?auth=${Uri.encodeQueryComponent(s)}';
  }
}

/// Uploads raw file bytes to R2 through the user's worker gateway.
/// Mirrors the workflow's `uploadToR2`: the destination key goes in
/// the X-File-Name header, the MIME type in X-File-Type.
Future<String> uploadFileToR2({
  required Uint8List bytes,
  required String fileName,
  required String mime,
  required String workerUrl,
  required String folder,
}) async {
  final cleaned = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final key =
      '${folder.replaceAll(RegExp(r'^/+|/+$'), '')}/wallpaper/${DateTime.now().millisecondsSinceEpoch}_$cleaned';
  http.Response resp;
  try {
    resp = await http
        .post(
          Uri.parse(DistributeStore.normUrl(workerUrl)),
          headers: {'X-File-Name': key, 'X-File-Type': mime},
          body: bytes,
        )
        .timeout(const Duration(seconds: 120));
  } catch (e) {
    throw Exception('Network error reaching the R2 worker: $e');
  }
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw Exception(
        'R2 upload failed (HTTP ${resp.statusCode}): ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}');
  }
  dynamic data;
  try {
    data = jsonDecode(resp.body);
  } catch (e) {
    throw Exception('R2 worker returned invalid JSON: $e');
  }
  final url = (data is Map ? data['url'] : null)?.toString() ?? '';
  if (url.isEmpty) {
    throw Exception('R2 worker response missing the url field.');
  }
  final folderSeg = '/${folder.replaceAll(RegExp(r'^/+|/+$'), '')}/wallpaper/';
  if (!url.contains(folderSeg)) {
    throw Exception(
        'R2 returned a URL outside the $folder/wallpaper folder ($url) - aborted before writing to the database.');
  }
  return url;
}

/// Pushes one record to the queue path. Returns the Firebase push key.
Future<String> pushToDatabase({
  required String dbUrl,
  required String queuePath,
  required Map<String, dynamic> record,
  String? secret,
}) async {
  final url =
      '${DistributeStore.normUrl(dbUrl)}/${queuePath.trim()}.json${DistributeStore._authQuery(secret)}';
  http.Response resp;
  try {
    resp = await http
        .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(record),
        )
        .timeout(const Duration(seconds: 60));
  } catch (e) {
    throw Exception('Network error reaching the database: $e');
  }
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    final body =
        resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body;
    throw Exception('Database push failed (HTTP ${resp.statusCode}): $body');
  }
  dynamic data;
  try {
    data = jsonDecode(resp.body);
  } catch (e) {
    throw Exception('Database returned invalid JSON: $e');
  }
  final key = (data is Map ? data['name'] : null)?.toString() ?? '';
  if (key.isEmpty) throw Exception('Database push returned no key.');
  return key;
}

/// Read-only connection test: fetches the DB root shallowly. Writes
/// nothing.
Future<void> testDatabaseConnection({
  required String dbUrl,
  String? secret,
}) async {
  final url =
      '${DistributeStore.normUrl(dbUrl)}/.json?shallow=true${secret?.trim().isNotEmpty == true ? '&auth=${Uri.encodeQueryComponent(secret!.trim())}' : ''}';
  final resp = await http
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 30));
  if (resp.statusCode == 401 || resp.statusCode == 403) {
    throw Exception(
        'Database refused access (HTTP ${resp.statusCode}). Check the URL and secret / database rules.');
  }
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw Exception('Database test failed (HTTP ${resp.statusCode}).');
  }
}

/// Builds the Firebase record for one finished set, mirroring the
/// workflow's `distributeItem` base fields.
Map<String, dynamic> buildSetRecord({
  required String firstName,
  required int firstSize,
  required int totalSize,
  required int width,
  required int height,
  required String contentType,
  required String firstFileUrl,
  Map<String, Map<String, dynamic>>? files,
  String? setName,
  required String prompt,
  required String imageModel,
  SetMetadata? metadata,
  String? policyFlag,
  bool single = false,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final record = <String, dynamic>{
    'name': firstName,
    'type': 'image/jpeg',
    'size': single ? firstSize : totalSize,
    'width': width,
    'height': height,
    'isMp3': false,
    'isImage': true,
    'contentType': contentType,
    'fileUrl': firstFileUrl,
    'status': 'queued',
    'prompt': prompt,
    'imageModel': imageModel,
    'source': 'ai-image-studio-flutter',
    'createdAt': now,
  };
  if (!single) {
    if (files != null) record['files'] = files;
    if (setName != null) record['setName'] = setName;
  }
  // Write whatever metadata exists. Previously the whole block was
  // skipped unless BOTH title and tags were present, so a partially
  // generated set reached the database with no metadata at all and the
  // panel/bot reported "missing: title, tags, category".
  if (metadata != null &&
      (metadata.title.isNotEmpty ||
          metadata.tags.isNotEmpty ||
          metadata.category.isNotEmpty ||
          metadata.description.isNotEmpty)) {
    record['title'] = metadata.title;
    // The Hub's Search Tags field is a plain text input: it must receive a
    // clean comma-separated string, never a JSON array (otherwise the
    // brackets and quotes end up inside the tag field).
    record['tags'] = metadata.tags.join(', ');
    record['tagsList'] = metadata.tags;
    record['category'] = metadata.category;
    record['description'] = metadata.description;
    record['metadataGeneratedAt'] = now;
    if (policyFlag != null && policyFlag.isNotEmpty) {
      // Policy-held, like the workflow: visible in Failed, never
      // auto-uploaded by the bot.
      record['status'] = 'failed';
      record['policyCheck'] = 'held';
      record['policyFlag'] = policyFlag;
      record['policyCheckedAt'] = now;
      record['error'] =
          'Zedge policy hold - $policyFlag. Review this item; requeue only if it is your own original, policy-compliant work.';
      record['failedAt'] = now;
    } else {
      record['policyCheck'] = 'passed';
      record['policyCheckedAt'] = now;
    }
  }
  return record;
}
