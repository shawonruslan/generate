import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/models.dart';
import '../utils/config.dart';
import 'cronet_adapter.dart';

/// Thrown for any worker-side error. [status] is the HTTP status code.
class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'ApiException($status): $message';
}

/// Thrown on HTTP 401 — the app treats this as "session dead, log out".
class UnauthorizedException extends ApiException {
  UnauthorizedException() : super(401, 'Session expired — please log in again.');
}

typedef ProgressCallback = void Function(int sent, int total);

/// Full client for the Team Drive Cloudflare Worker API (v7.6).
/// Mirrors the web app's request shapes exactly:
/// - JSON calls: `Authorization: Bearer <token>` + `Content-Type: application/json`
/// - Binary uploads: raw bytes (NOT multipart), explicit Content-Length,
///   X-File-Type / X-File-Name / X-Version-Note headers.
class ApiClient {
  final Dio _dio;
  String _baseUrl;
  String? _token;
  void Function()? onUnauthorized;

  ApiClient({String? baseUrl, String? token})
      : _baseUrl = (baseUrl ?? AppConfig.workerBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 30),
          responseType: ResponseType.json,
          validateStatus: (_) => true, // we map statuses ourselves
        )) {
    _token = token;
    // Android: route through Cronet (Chromium's network stack, same as Chrome)
    // instead of Dart's own DNS resolver — fixes "Failed host lookup" on
    // devices where dart:io DNS doesn't respect the system configuration.
    if (Platform.isAndroid) {
      try {
        _dio.httpClientAdapter = CronetDioAdapter();
      } catch (_) {
        // Fall back to the default adapter if Cronet isn't available.
      }
    }
  }

  String get baseUrl => _baseUrl;
  set baseUrl(String v) => _baseUrl = v.replaceAll(RegExp(r'/+$'), '');
  String? get token => _token;
  set token(String? v) => _token = v;

  Map<String, String> get _authHeaders =>
      _token == null ? {} : {'Authorization': 'Bearer $_token'};

  Never _throwFor(Response r) {
    final body = r.data;
    final msg = body is Map && body['error'] != null
        ? body['error'].toString()
        : 'Request failed (HTTP ${r.statusCode})';
    if (r.statusCode == 401) _unauth();
    throw ApiException(r.statusCode ?? 0, msg);
  }

  /// 401: session is dead server-side — notify the app so it logs out.
  Never _unauth() {
    try {
      onUnauthorized?.call();
    } catch (_) {}
    throw UnauthorizedException();
  }

  T _ok<T>(Response r, T Function(dynamic) parse) {
    final s = r.statusCode ?? 0;
    if (s >= 200 && s < 300) return parse(r.data);
    _throwFor(r);
  }

  Map<String, dynamic> _map(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  // ---------------- misc ----------------

  /// GET / — no auth. Returns the worker version string.
  Future<String> getWorkerVersion() async {
    final r = await _dio.get('$_baseUrl/');
    return _ok(r, (d) => _map(d)['version']?.toString() ?? '?');
  }

  // ---------------- auth ----------------

  Future<SessionUser> login({
    required String role,
    String? username,
    required String password,
  }) async {
    final r = await _dio.post('$_baseUrl/api/login',
        data: jsonEncode({
          'role': role,
          if (username != null) 'username': username,
          'password': password,
        }),
        options: Options(headers: {'Content-Type': 'application/json'}));
    return _ok(r, (d) {
      final m = _map(d);
      final t = m['token'].toString();
      _token = t;
      return SessionUser(
          username: m['username'].toString(), role: m['role'].toString(), token: t);
    });
  }

  Future<SessionUser> me() async {
    final r = await _dio.get('$_baseUrl/api/me',
        options: Options(headers: _authHeaders));
    return _ok(r, (d) {
      final m = _map(d);
      return SessionUser(
          username: m['username'].toString(),
          role: m['role'].toString(),
          token: _token ?? '');
    });
  }

  /// Members only — admins get a 400.
  Future<void> changePassword({required String current, required String next}) async {
    final r = await _dio.post('$_baseUrl/api/password',
        data: jsonEncode({'current': current, 'next': next}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  // ---------------- drive ----------------

  Future<DriveData> getData() async {
    final r = await _dio.get('$_baseUrl/api/data',
        options: Options(headers: _authHeaders));
    return _ok(r, (d) => DriveData.fromJson(_map(d)));
  }

  Future<String> createFolder({required String name, String parent = 'root'}) async {
    final r = await _dio.post('$_baseUrl/api/folder',
        data: jsonEncode({'name': name, 'parent': parent}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => _map(d)['id'].toString());
  }

  Future<void> patchItem(
      {required String id, required String kind, String? name, String? parent}) async {
    final r = await _dio.patch('$_baseUrl/api/item',
        data: jsonEncode({
          'id': id,
          'kind': kind,
          if (name != null) 'name': name,
          if (parent != null) 'parent': parent,
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  Future<int> deleteItems(
      {required List<String> folders, required List<String> files}) async {
    final r = await _dio.delete('$_baseUrl/api/item',
        data: jsonEncode({'folders': folders, 'files': files}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => (_map(d)['deleted'] ?? 0) as int);
  }

  /// Uploads a file, choosing single-shot (<=95MiB) or multipart like the web app.
  Future<void> uploadFile({
    required String localPath,
    required String folderId,
    required String displayName,
    String? mime,
    String? versionNote,
    ProgressCallback? onProgress,
  }) async {
    final file = File(localPath);
    final size = await file.length();
    if (size <= AppConfig.multipartThresholdBytes) {
      await _uploadSingle(
          file: file, size: size, folderId: folderId, displayName: displayName,
          mime: mime, versionNote: versionNote, onProgress: onProgress);
    } else {
      await _uploadMultipart(
          file: file, size: size, folderId: folderId, displayName: displayName,
          mime: mime, versionNote: versionNote, onProgress: onProgress);
    }
  }

  Future<void> _uploadSingle({
    required File file,
    required int size,
    required String folderId,
    required String displayName,
    String? mime,
    String? versionNote,
    ProgressCallback? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    final r = await _dio.post(
      '$_baseUrl/api/upload',
      queryParameters: {'folder': folderId, 'path': displayName},
      data: bytes,
      options: Options(headers: {
        ..._authHeaders,
        'Content-Type': 'application/octet-stream',
        'Content-Length': '$size',
        'X-File-Type': mime ?? 'application/octet-stream',
        if (versionNote != null && versionNote.isNotEmpty)
          'X-Version-Note': Uri.encodeComponent(versionNote),
      }),
      onSendProgress: onProgress,
    );
    _ok(r, (_) {});
  }

  /// Multipart upload: create -> 3-parallel 25MiB parts w/ retry -> complete.
  /// Mirrors the web app's enqueue() MPU parameters.
  Future<void> _uploadMultipart({
    required File file,
    required int size,
    required String folderId,
    required String displayName,
    String? mime,
    String? versionNote,
    ProgressCallback? onProgress,
  }) async {
    const partSize = AppConfig.multipartChunkBytes; // 25 MiB, like the web app
    const parallel = 3;
    const maxAttempts = 4;

    final mimeType = mime ?? 'application/octet-stream';
    // 1. create
    final cr = await _dio.post('$_baseUrl/api/mpu/create',
        data: jsonEncode({
          'path': displayName,
          'type': mimeType,
          'size': size,
          'folder': folderId,
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    final cm = _ok(cr, _map);
    final String key = cm['key'].toString();
    final String uploadId = cm['uploadId'].toString();

    final partCount = (size / partSize).ceil();
    final etags = List<String?>.filled(partCount, null);
    int sentTotal = 0;
    void report() => onProgress?.call(sentTotal, size);

    Future<void> abort() async {
      try {
        await _dio.delete('$_baseUrl/api/mpu/abort',
            queryParameters: {'key': key, 'uploadId': uploadId},
            options: Options(headers: _authHeaders));
      } catch (_) {}
    }

    Future<void> putPart(int partNumber /* 1-based */) async {
      final start = (partNumber - 1) * partSize;
      final end = min(start + partSize, size);
      final slice = await file.openRead(start, end).fold<BytesBuilder>(
          BytesBuilder(), (b, d) => b..add(d)).then((b) => b.takeBytes());
      Object? lastErr;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final pr = await _dio.put(
            '$_baseUrl/api/mpu/part',
            queryParameters: {'key': key, 'uploadId': uploadId, 'part': partNumber},
            data: slice,
            options: Options(headers: {
              ..._authHeaders,
              'Content-Type': 'application/octet-stream',
              'Content-Length': '${slice.length}',
            }),
          );
          final pm = _ok(pr, _map);
          final etag = (pm['etag'] ?? pm['ETag'] ?? '').toString();
          if (etag.isEmpty) throw ApiException(pr.statusCode ?? 0, 'Part upload returned no etag');
          etags[partNumber - 1] = etag;
          sentTotal += slice.length;
          report();
          return;
        } catch (e) {
          lastErr = e;
          if (attempt < maxAttempts) {
            await Future.delayed(Duration(milliseconds: 1500 * attempt));
          }
        }
      }
      throw lastErr is Exception ? lastErr : Exception('Part $partNumber failed: $lastErr');
    }

    try {
      // 2. parts, 3 at a time
      for (var i = 0; i < partCount; i += parallel) {
        final batch = <Future>[];
        for (var p = i + 1; p <= min(i + parallel, partCount); p++) {
          batch.add(putPart(p));
        }
        await Future.wait(batch);
      }
      // 3. complete
      final parts = List.generate(
          partCount, (i) => {'partNumber': i + 1, 'etag': etags[i]});
      final fr = await _dio.post('$_baseUrl/api/mpu/complete',
          data: jsonEncode({
            'key': key,
            'uploadId': uploadId,
            'parts': parts,
            'folder': folderId,
            'path': displayName,
            'type': mimeType,
            if (versionNote != null && versionNote.isNotEmpty) 'note': versionNote,
          }),
          options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
      _ok(fr, (_) {});
      onProgress?.call(size, size);
    } catch (e) {
      await abort();
      rethrow;
    }
  }

  /// Downloads a signed /dl/ URL (no auth header — the URL itself is signed).
  Future<void> downloadFile({
    required String url,
    required String savePath,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final r = await _dio.download(url, savePath,
        onReceiveProgress: onProgress, cancelToken: cancelToken,
        options: Options(responseType: ResponseType.bytes, validateStatus: (_) => true));
    final s = r.statusCode ?? 0;
    if (s < 200 || s >= 300) {
      try {
        await File(savePath).delete();
      } catch (_) {}
      if (s == 401) _unauth();
      throw ApiException(s, 'Download failed (HTTP $s)');
    }
  }

  /// Preview variant of a signed URL (inline instead of attachment).
  String previewUrl(String signedUrl) =>
      signedUrl.contains('?') ? '$signedUrl&pv=1' : '$signedUrl?pv=1';

  Future<List<FileVersion>> getVersions(String fileId) async {
    final r = await _dio.get('$_baseUrl/api/versions',
        queryParameters: {'id': fileId},
        options: Options(headers: _authHeaders));
    return _ok(r, (d) {
      final m = _map(d);
      return ((m['versions'] as List?) ?? [])
          .map((e) => FileVersion.fromJson(_map(e)))
          .toList();
    });
  }

  Future<int> restoreVersion({required String id, required int ver}) async {
    final r = await _dio.post('$_baseUrl/api/versions',
        data: jsonEncode({'id': id, 'ver': ver}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => (_map(d)['ver'] ?? ver) as int);
  }

  Future<void> deleteVersion({required String id, required int ver}) async {
    final r = await _dio.delete('$_baseUrl/api/versions',
        queryParameters: {'id': id, 'ver': ver},
        options: Options(headers: _authHeaders));
    _ok(r, (_) {});
  }

  /// Admin only.
  Future<bool> setFileLock({required String id, required bool locked, String? reason}) async {
    final r = await _dio.patch('$_baseUrl/api/lock',
        data: jsonEncode({
          'id': id,
          'locked': locked,
          if (reason != null) 'reason': reason,
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => (_map(d)['locked'] ?? locked) as bool);
  }

  // ---------------- group feed ----------------

  /// GET marks the caller as seen on all posts (server side effect).
  Future<GroupFeed> getGroup() async {
    final r = await _dio.get('$_baseUrl/api/group',
        options: Options(headers: _authHeaders));
    return _ok(r, (d) => GroupFeed.fromJson(_map(d)));
  }

  Future<GroupUploadDescriptor> uploadGroupFile({
    required String localPath,
    required String fileName,
    String? mime,
    ProgressCallback? onProgress,
  }) async {
    final file = File(localPath);
    final size = await file.length();
    if (size > AppConfig.groupPostMaxBytes) {
      throw ApiException(413, 'File exceeds the 512 MB group post limit.');
    }
    final bytes = await file.readAsBytes();
    final r = await _dio.post(
      '$_baseUrl/api/group/upload',
      queryParameters: {'name': fileName},
      data: bytes,
      options: Options(headers: {
        ..._authHeaders,
        'Content-Type': 'application/octet-stream',
        'Content-Length': '$size',
        'X-File-Name': Uri.encodeComponent(fileName),
        'X-File-Type': (mime ?? 'application/octet-stream').substring(
            0, min(120, (mime ?? 'application/octet-stream').length)),
      }),
      onSendProgress: onProgress,
    );
    return _ok(r, (d) => GroupUploadDescriptor.fromJson(_map(d)));
  }

  Future<GroupPost> createPost({String? caption, GroupFile? file}) async {
    final r = await _dio.post('$_baseUrl/api/group',
        data: jsonEncode({
          if (caption != null) 'caption': caption,
          if (file != null) 'file': file.toJson(),
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => GroupPost.fromJson(_map(_map(d)['post'])));
  }

  Future<void> deletePost(String id) async {
    final r = await _dio.delete('$_baseUrl/api/group',
        queryParameters: {'id': id},
        options: Options(headers: _authHeaders));
    _ok(r, (_) {});
  }

  /// Admin only.
  Future<void> pinPost({required String id, required bool pinned}) async {
    final r = await _dio.patch('$_baseUrl/api/group/pin',
        data: jsonEncode({'id': id, 'pinned': pinned}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  // ---------------- notes ----------------

  Future<List<Note>> getNotes() async {
    final r = await _dio.get('$_baseUrl/api/notes',
        options: Options(headers: _authHeaders));
    return _ok(r, (d) {
      final m = _map(d);
      return ((m['notes'] as List?) ?? [])
          .map((e) => Note.fromJson(_map(e)))
          .toList();
    });
  }

  Future<String> saveNote(Note note) async {
    final r = await _dio.put('$_baseUrl/api/notes',
        data: jsonEncode(note.toJson()),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => _map(d)['id'].toString());
  }

  Future<void> deleteNote(String id) async {
    final r = await _dio.delete('$_baseUrl/api/notes',
        queryParameters: {'id': id},
        options: Options(headers: _authHeaders));
    _ok(r, (_) {});
  }

  // ---------------- avatar ----------------

  Future<String> uploadAvatar({required String localPath, String? user}) async {
    final file = File(localPath);
    final size = await file.length();
    if (size > 500 * 1024) {
      throw ApiException(413, 'Avatar must be 500 KB or smaller.');
    }
    final bytes = await file.readAsBytes();
    final r = await _dio.put(
      '$_baseUrl/api/avatar',
      queryParameters: {if (user != null) 'user': user},
      data: bytes,
      options: Options(headers: {
        ..._authHeaders,
        'Content-Type': 'application/octet-stream',
        'Content-Length': '$size',
      }),
    );
    return _ok(r, (d) => _map(d)['url']?.toString() ?? '');
  }

  Future<void> deleteAvatar({String? user}) async {
    final r = await _dio.delete('$_baseUrl/api/avatar',
        queryParameters: {if (user != null) 'user': user},
        options: Options(headers: _authHeaders));
    _ok(r, (_) {});
  }

  // ---------------- tickets ----------------

  /// GET /api/tickets returns a top-level JSON array.
  Future<List<Ticket>> getTickets() async {
    final r = await _dio.get('$_baseUrl/api/tickets',
        options: Options(headers: _authHeaders));
    return _ok(r, (d) {
      final arr = d is List ? d : ((_map(d)['tickets'] as List?) ?? []);
      return arr.map((e) => Ticket.fromJson(_map(e))).toList();
    });
  }

  /// Members only.
  Future<String> createTicket(
      {required String subject, required String text, String? cat, String? pri}) async {
    final r = await _dio.post('$_baseUrl/api/tickets',
        data: jsonEncode({
          'subject': subject,
          'text': text,
          if (cat != null) 'cat': cat,
          if (pri != null) 'pri': pri,
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => _map(d)['id'].toString());
  }

  Future<void> setTicketStatus({required String id, required String status}) async {
    final r = await _dio.patch('$_baseUrl/api/tickets',
        data: jsonEncode({'id': id, 'status': status}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  Future<void> replyTicket({required String id, required String text}) async {
    final r = await _dio.post('$_baseUrl/api/tickets/reply',
        data: jsonEncode({'id': id, 'text': text}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  Future<void> markTicketRead(String id) async {
    final r = await _dio.post('$_baseUrl/api/tickets/read',
        data: jsonEncode({'id': id}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  /// Admin only.
  Future<void> deleteTicket(String id) async {
    final r = await _dio.delete('$_baseUrl/api/tickets',
        data: jsonEncode({'id': id}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  // ---------------- database / records ----------------

  /// GET /api/records returns a top-level JSON array.
  Future<List<RecordList>> getRecordLists() async {
    final r = await _dio.get('$_baseUrl/api/records',
        options: Options(headers: _authHeaders));
    return _ok(r, (d) {
      final arr = d is List ? d : ((_map(d)['lists'] as List?) ?? []);
      return arr.map((e) => RecordList.fromJson(_map(e))).toList();
    });
  }

  /// GET /api/records/rows returns {list, rows: [...], mine}; rows is a list
  /// with `id` inside each object — normalized here to a rid-keyed map.
  Future<Map<String, RecordRow>> getRecordRows(String listId) async {
    final r = await _dio.get('$_baseUrl/api/records/rows',
        queryParameters: {'id': listId},
        options: Options(headers: _authHeaders));
    return _ok(r, (d) {
      final m = _map(d);
      final out = <String, RecordRow>{};
      for (final e in ((m['rows'] as List?) ?? [])) {
        final row = RecordRow.fromJsonMap(_map(e));
        out[row.rid] = row;
      }
      return out;
    });
  }

  Future<String> addRecordRow(
      {required String listId, required Map<String, dynamic> cells, String? owner}) async {
    final r = await _dio.post('$_baseUrl/api/records/row',
        data: jsonEncode({
          'id': listId,
          'cells': cells,
          if (owner != null) 'owner': owner,
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => _map(d)['id'].toString());
  }

  Future<void> updateRecordRow(
      {required String listId, required String rid, required Map<String, dynamic> cells}) async {
    final r = await _dio.patch('$_baseUrl/api/records/row',
        data: jsonEncode({'id': listId, 'rid': rid, 'cells': cells}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  /// DELETE /api/records/row?id=<listId>&rid=<rid1,rid2,...> (query params).
  Future<void> deleteRecordRows({required String listId, required List<String> rids}) async {
    final r = await _dio.delete('$_baseUrl/api/records/row',
        queryParameters: {'id': listId, 'rid': rids.join(',')},
        options: Options(headers: _authHeaders));
    _ok(r, (_) {});
  }

  Future<RecordCheckResult> checkRecord({String? listId, required String value}) async {
    final r = await _dio.post('$_baseUrl/api/records/check',
        data: jsonEncode({
          if (listId != null) 'id': listId,
          'value': value,
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => RecordCheckResult.fromJson(_map(d)));
  }

  /// Admin: create a record list. [spec] e.g. {name, cols:[{k,name,match}], memberAdd}
  Future<String> createRecordList(Map<String, dynamic> spec) async {
    final r = await _dio.post('$_baseUrl/api/records',
        data: jsonEncode(spec),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => _map(d)['id'].toString());
  }

  /// Admin: update a record list.
  Future<void> updateRecordList(String id, Map<String, dynamic> spec) async {
    final r = await _dio.patch('$_baseUrl/api/records',
        data: jsonEncode({'id': id, ...spec}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  /// Admin: delete a record list. DELETE /api/records?id=<id> (query param).
  Future<void> deleteRecordList(String id) async {
    final r = await _dio.delete('$_baseUrl/api/records',
        queryParameters: {'id': id},
        options: Options(headers: _authHeaders));
    _ok(r, (_) {});
  }

  /// Admin: bulk import rows.
  Future<void> importRecordList(String id, List<Map<String, dynamic>> rows) async {
    final r = await _dio.post('$_baseUrl/api/records/import',
        data: jsonEncode({'id': id, 'rows': rows}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  // ---------------- announcements (admin) ----------------

  /// GET /api/announcements returns a top-level JSON array.
  Future<List<Announcement>> getAnnouncements() async {
    final r = await _dio.get('$_baseUrl/api/announcements',
        options: Options(headers: _authHeaders));
    return _ok(r, (d) {
      final arr = d is List ? d : ((_map(d)['announcements'] as List?) ?? []);
      return arr.map((e) => Announcement.fromJson(_map(e))).toList();
    });
  }

  Future<String> createAnnouncement(
      {required String text, required String type, int? expiresHours}) async {
    final r = await _dio.post('$_baseUrl/api/announcements',
        data: jsonEncode({
          'text': text,
          'type': type,
          if (expiresHours != null) 'expiresHours': expiresHours,
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) => _map(d)['id'].toString());
  }

  Future<void> setAnnouncementActive({required String id, required bool active}) async {
    final r = await _dio.patch('$_baseUrl/api/announcements',
        data: jsonEncode({'id': id, 'active': active}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  Future<void> deleteAnnouncement(String id) async {
    final r = await _dio.delete('$_baseUrl/api/announcements',
        queryParameters: {'id': id},
        options: Options(headers: _authHeaders));
    _ok(r, (_) {});
  }

  // ---------------- members (admin) ----------------

  /// GET /api/members returns a top-level JSON array.
  Future<List<TeamMember>> getMembers() async {
    final r = await _dio.get('$_baseUrl/api/members',
        options: Options(headers: _authHeaders));
    return _ok(r, (d) {
      final arr = d is List ? d : ((_map(d)['members'] as List?) ?? []);
      return arr.map((e) => TeamMember.fromJson(_map(e))).toList();
    });
  }

  Future<void> createOrResetMember(
      {required String username, required String password, bool reset = false}) async {
    final r = await _dio.post('$_baseUrl/api/members',
        data: jsonEncode({
          'username': username,
          'password': password,
          if (reset) 'reset': true,
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  Future<void> setMemberDisabled({required String username, required bool disabled}) async {
    final r = await _dio.patch('$_baseUrl/api/members',
        data: jsonEncode({'username': username, 'disabled': disabled}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  Future<void> deleteMember(String username) async {
    final r = await _dio.delete('$_baseUrl/api/members',
        queryParameters: {'username': username},
        options: Options(headers: _authHeaders));
    _ok(r, (_) {});
  }

  /// Set a member's quota and/or storage pool. [pool] assigns an extra-R2
  /// pool id; [clearPool] explicitly resets the member to auto-assign
  /// (sends 'pool': '', which the worker treats as auto). When neither is
  /// given, the member's current pool assignment is left untouched.
  Future<void> setMemberQuota(
      {required String username,
      double? quotaGB,
      String? pool,
      bool clearPool = false}) async {
    final r = await _dio.patch('$_baseUrl/api/members/quota',
        data: jsonEncode({
          'username': username,
          if (quotaGB != null) 'quotaGB': quotaGB,
          if (clearPool) 'pool': '',
          if (!clearPool && pool != null) 'pool': pool,
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  // ---------------- storage / settings (admin) ----------------

  Future<List<StoragePool>> getStorage() async {
    final r = await _dio.get('$_baseUrl/api/storage',
        options: Options(headers: _authHeaders));
    return _ok(r, (d) {
      final m = _map(d);
      return ((m['pools'] as List?) ?? [])
          .map((e) => StoragePool.fromJson(_map(e)))
          .toList();
    });
  }

  Future<Map<String, dynamic>> getSettings() async {
    final r = await _dio.get('$_baseUrl/api/settings',
        options: Options(headers: _authHeaders));
    return _ok(r, _map);
  }

  Future<void> updateSettings(Map<String, dynamic> fields) async {
    final r = await _dio.patch('$_baseUrl/api/settings',
        data: jsonEncode(fields),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  // ---------------- shares (admin) ----------------

  Future<ShareLink> createShare({
    required String fileId,
    String? password,
    int? expiresHours,
    int? maxDownloads,
  }) async {
    final r = await _dio.post('$_baseUrl/api/shares',
        data: jsonEncode({
          'fileId': fileId,
          if (password != null && password.isNotEmpty) 'password': password,
          if (expiresHours != null) 'expiresHours': expiresHours,
          if (maxDownloads != null) 'maxDownloads': maxDownloads,
        }),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    return _ok(r, (d) {
      final m = _map(d);
      // create returns {id, url}; normalize into a ShareLink
      return ShareLink(
        id: m['id'].toString(),
        fileId: fileId,
        fileName: m['fileName']?.toString() ?? '',
        dl: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        hasPw: password != null && password.isNotEmpty,
        url: m['url']?.toString() ?? shareUrl(m['id'].toString()),
      );
    });
  }

  /// Returns the public URL for a just-created share id.
  String shareUrl(String id) => '$_baseUrl/s/$id';

  /// GET /api/shares returns a top-level JSON array.
  Future<List<ShareLink>> getShares() async {
    final r = await _dio.get('$_baseUrl/api/shares',
        options: Options(headers: _authHeaders));
    return _ok(r, (d) {
      final arr = d is List ? d : ((_map(d)['shares'] as List?) ?? []);
      return arr.map((e) => ShareLink.fromJson(_map(e))).toList();
    });
  }

  Future<void> patchShare(String id, Map<String, dynamic> fields) async {
    final r = await _dio.patch('$_baseUrl/api/shares',
        data: jsonEncode({'id': id, ...fields}),
        options: Options(headers: {..._authHeaders, 'Content-Type': 'application/json'}));
    _ok(r, (_) {});
  }

  Future<void> deleteShare(String id) async {
    final r = await _dio.delete('$_baseUrl/api/shares',
        queryParameters: {'id': id},
        options: Options(headers: _authHeaders));
    _ok(r, (_) {});
  }
}
