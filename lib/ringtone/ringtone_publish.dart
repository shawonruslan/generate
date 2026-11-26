import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../distribute.dart';
import 'ringtone_models.dart';

/// R2 + Firebase queue calls for tones, mirroring generator.yml
/// (uploadToR2, deleteFromR2, firebasePushToUrl, firebasePatchToUrl,
/// firebaseDeleteFromUrl, syncFirebaseRingtones, generateFilename,
/// resolveTargetDbs). Accounts and the worker URL are the ones already
/// set up under Settings > Distribution.
class RingtonePublisher {
  final http.Client _http;
  final Random _rnd;
  RingtonePublisher({http.Client? httpClient, Random? random})
      : _http = httpClient ?? http.Client(),
        _rnd = random ?? Random();

  static const allAccounts = 'all_accounts';

  /// Accounts a run publishes to. [target]: an account name,
  /// [allAccounts], or '' (the first account).
  static List<DistAccount> resolveTargets(DistConfig cfg, String target) {
    final usable = [
      for (final a in cfg.accounts)
        if (a.name.trim().isNotEmpty && a.dbUrl.trim().isNotEmpty) a
    ];
    if (usable.isEmpty) return const [];
    final t = target.trim().toLowerCase();
    if (t == allAccounts || t == 'all') return usable;
    for (final a in usable) {
      if (a.name.toLowerCase() == t) return [a];
    }
    return [usable.first];
  }

  static String _auth(String secret) {
    final s = secret.trim();
    return s.isEmpty ? '' : '?auth=${Uri.encodeQueryComponent(s)}';
  }

  static String _queueUrl(DistAccount a, String queuePath, [String key = '']) {
    final q = queuePath.trim().isEmpty ? 'wallpaperQueue' : queuePath.trim();
    final k = key.isEmpty ? '' : '/${Uri.encodeComponent(key)}';
    return '${DistributeStore.normUrl(a.dbUrl)}/$q$k.json${_auth(a.secret)}';
  }

  static String _cut(String s, [int n = 200]) =>
      s.length > n ? s.substring(0, n) : s;

  T _pick<T>(List<T> l) => l[_rnd.nextInt(l.length)];

  /// File name stored with the upload. Each of the four stock accounts
  /// has its own naming habit in the workflow; any other account gets
  /// `tone_<timestamp>.mp3`.
  String generateFilename(String accountName) {
    switch (accountName) {
      case 'zedge_1':
        const smashes = [
          'asdf', 'asdfg', 'qwerty', 'hjkl', 'lkjh', 'qwer', 'zxcv', 'test',
          'new', 'audio', 'untitled', 'file', 'rec', 'my',
        ];
        return '${_pick(smashes)}${_rnd.nextInt(999)}.mp3';
      case 'zedge_2':
        const prefixes = [
          'my', 'cool', 'new', 'best', 'fav', 'top', 'great', 'nice', 'saved',
          'ringtone', 'tone', 'sound', 'audio',
        ];
        const mid = [
          'ring', 'tone', 'beat', 'track', 'song', 'clip', 'tune', 'sound',
          'mix', 'edit',
        ];
        const suffixes = [
          'v1', 'v2', 'final', 'new', 'copy', 'edit', '2', '3', '1', 'hd',
        ];
        return '${_pick(prefixes)}_${_pick(mid)}_${_pick(suffixes)}.mp3';
      case 'zedge_3':
        return 'audio_${_rnd.nextInt(90000) + 10000}.mp3';
      case 'zedge_4':
        const words = [
          'Ringtone', 'Tone', 'Sound', 'Alarm', 'Notification', 'Melody',
          'Beat', 'Loop', 'Alert', 'Chime',
        ];
        const tags = ['HD', 'New', 'Best', 'Original', 'Clean'];
        return '${_pick(words)}-${_pick(tags)}-${_rnd.nextInt(99) + 1}.mp3';
    }
    return 'tone_${DateTime.now().millisecondsSinceEpoch}.mp3';
  }

  /// Uploads an MP3 to `<folder>/ringtone/<timestamp>_<name>`; returns
  /// the public URL.
  Future<String> uploadToR2({
    required Uint8List bytes,
    required String fileName,
    required String workerUrl,
    required String folder,
  }) async {
    final cleaned = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final f = folder.replaceAll(RegExp(r'^/+|/+$'), '');
    final key = '$f/ringtone/${DateTime.now().millisecondsSinceEpoch}_$cleaned';
    http.Response resp;
    try {
      resp = await _http
          .post(Uri.parse(DistributeStore.normUrl(workerUrl)),
              headers: {'X-File-Name': key, 'X-File-Type': 'audio/mpeg'},
              body: bytes)
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      throw Exception('Network error reaching the R2 worker: $e');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          'R2 upload failed (HTTP ${resp.statusCode}): ${_cut(resp.body)}');
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
    return url;
  }

  /// Removes the file behind [fileUrl] from R2. Returns false when the
  /// URL is not an R2 one (nothing to delete); throws when the worker
  /// does not confirm the file is gone.
  Future<bool> deleteFromR2(String fileUrl, String workerUrl) async {
    final url = fileUrl.trim();
    final worker = DistributeStore.normUrl(workerUrl);
    if (url.isEmpty || worker.isEmpty) return false;
    if (!(url.contains('.r2.dev/') || url.startsWith(worker))) return false;
    http.Response resp;
    try {
      final req = http.Request('DELETE', Uri.parse(worker))
        ..headers['Content-Type'] = 'application/json'
        ..headers['X-R2-Delete-Protocol'] = 'r2-delete-v1'
        ..body = jsonEncode({'url': url});
      resp = await http.Response.fromStream(
          await _http.send(req).timeout(const Duration(seconds: 15)));
    } catch (e) {
      throw Exception('Network error reaching the R2 worker: $e');
    }
    dynamic body;
    try {
      body = jsonDecode(resp.body);
    } catch (_) {}
    final ok = resp.statusCode >= 200 &&
        resp.statusCode < 300 &&
        body is Map &&
        body['ok'] == true &&
        body['absent'] == true;
    if (!ok) {
      final err = body is Map ? body['error'] : null;
      throw Exception(err?.toString() ??
          'R2 delete failed (HTTP ${resp.statusCode}). The worker must support the r2-delete-v1 protocol.');
    }
    return true;
  }

  /// Appends [record] to the queue; returns the Firebase push key.
  Future<String> pushRecord(
      DistAccount a, String queuePath, Map<String, dynamic> record) async {
    http.Response resp;
    try {
      resp = await _http
          .post(Uri.parse(_queueUrl(a, queuePath)),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(record))
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw Exception('Network error reaching the database: $e');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          'Database push failed (HTTP ${resp.statusCode}): ${_cut(resp.body)}');
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

  Future<void> patchRecord(DistAccount a, String queuePath, String key,
      Map<String, dynamic> patch) async {
    http.Response resp;
    try {
      resp = await _http
          .patch(Uri.parse(_queueUrl(a, queuePath, key)),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(patch))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception('Network error reaching the database: $e');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          'Database update failed (HTTP ${resp.statusCode}): ${_cut(resp.body)}');
    }
  }

  Future<void> deleteRecord(DistAccount a, String queuePath, String key) async {
    http.Response resp;
    try {
      resp = await _http
          .delete(Uri.parse(_queueUrl(a, queuePath, key)))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception('Network error reaching the database: $e');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          'Database delete failed (HTTP ${resp.statusCode}): ${_cut(resp.body)}');
    }
  }

  static bool isRingtoneRecord(Map rec) =>
      rec['isMp3'] == true ||
      (rec['contentType'] ?? '').toString().toUpperCase() == 'RINGTONE' ||
      (rec['type'] ?? '').toString().startsWith('audio/');

  /// Every tone waiting in the queue of [a].
  Future<List<RingtoneItem>> fetchQueue(DistAccount a, String queuePath) async {
    http.Response resp;
    try {
      resp = await _http
          .get(Uri.parse(_queueUrl(a, queuePath)))
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      throw Exception('Network error reaching the database: $e');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          'Database read failed (HTTP ${resp.statusCode}): ${_cut(resp.body)}');
    }
    dynamic data;
    try {
      data = jsonDecode(resp.body);
    } catch (_) {}
    final out = <RingtoneItem>[];
    if (data is! Map) return out;
    data.forEach((key, rec) {
      if (rec is! Map || !isRingtoneRecord(rec)) return;
      String s(String k) => (rec[k] ?? '').toString();
      num? n(String k) => rec[k] is num ? rec[k] as num : null;
      final title = s('title').isNotEmpty ? s('title') : s('name');
      out.add(RingtoneItem(
        id: '${a.name}_$key',
        dbName: a.name,
        firebaseKey: key.toString(),
        fileUrl: s('fileUrl'),
        title: title.isNotEmpty ? title : 'Ringtone',
        tags: s('tags'),
        category: s('category').isNotEmpty ? s('category') : 'OTHER',
        description: s('description'),
        prompt: s('prompt'),
        enhancedPrompt:
            s('enhancedPrompt').isNotEmpty ? s('enhancedPrompt') : s('prompt'),
        negativePrompt: s('negativePrompt'),
        fileName: s('name'),
        mimeType: s('type').isNotEmpty ? s('type') : 'audio/mpeg',
        sizeBytes: n('size')?.toInt() ?? 0,
        lengthSeconds: n('lengthSeconds')?.toDouble() ?? 0,
        audioSeed: n('audioSeed')?.toInt(),
        audioShape: s('audioShape').isNotEmpty ? s('audioShape') : 'track',
        musicalKey: s('musicalKey').isNotEmpty ? s('musicalKey') : 'Auto',
        timeSignature:
            s('timeSignature').isNotEmpty ? s('timeSignature') : '4/4',
        takeIndex: n('takeIndex')?.toInt() ?? 1,
        takesTotal: n('takesTotal')?.toInt() ?? 1,
        wizardJobId: s('wizardJobId'),
        processed: rec['processed'] == true,
        processing: rec['processing'] is Map
            ? Map<String, dynamic>.from(rec['processing'] as Map)
            : null,
        processError: s('processError'),
        createdAt: n('createdAt')?.toInt() ?? 0,
      ));
    });
    return out;
  }

  /// The queue record of one take - field for field the workflow's.
  static Map<String, dynamic> buildRecord({
    required RingtoneItem item,
    required String fileName,
    required String fileUrl,
    required int size,
    required bool autoProcess,
    required int createdAt,
  }) =>
      {
        'name': fileName,
        'type': 'audio/mpeg',
        'size': size,
        'width': null,
        'height': null,
        'isMp3': true,
        'contentType': 'RINGTONE',
        'fileUrl': fileUrl,
        'title': item.title,
        'tags': item.tags,
        'category': item.category,
        'description': item.description,
        'policyCheck': 'passed',
        'policyCheckedAt': createdAt,
        'status': 'queued',
        'prompt': item.prompt,
        'enhancedPrompt': item.enhancedPrompt,
        'negativePrompt': item.negativePrompt,
        'audioSeed': item.audioSeed,
        'audioModel': 'stable-audio-wizard',
        'audioShape': item.audioShape,
        'musicalKey': item.musicalKey,
        'timeSignature': item.timeSignature,
        'lengthSeconds': item.lengthSeconds,
        'takeIndex': item.takeIndex,
        'takesTotal': item.takesTotal,
        'wizardJobId': item.wizardJobId,
        'autoProcess': autoProcess,
        'processed': item.processed,
        'processing': item.processing,
        'processError': item.processError.isEmpty ? null : item.processError,
        'createdAt': createdAt,
      };
}
