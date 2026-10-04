import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/constants.dart';
import '../core/dhaka_time.dart';
import '../domain/archive_classifier.dart';
import 'archive_reader.dart';
import 'firebase_rtdb.dart';
import 'media.dart';
import 'meta_book.dart';
import 'models.dart';
import 'r2_client.dart';

typedef ConfirmFn = Future<bool> Function(String message);
typedef StatusFn = void Function(String text);
typedef ToastFn = void Function(String text, String kind);
typedef AlertFn = Future<void> Function(String message);

class UploadBusyException implements Exception {
  @override
  String toString() => 'Another upload is already in progress. Please wait for it to finish before adding more files.';
}

/// `new Date().toLocaleDateString("en-GB") + " " + toLocaleTimeString("en-GB", {hour:"2-digit", minute:"2-digit"})`
String _stampNow() {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// All Firebase / R2 mutations of the panel (requeue, verified purge, uploads,
/// sets, videos, pins, copy, metadata save, schedule / mix mode save).
class QueueRepository {
  QueueRepository({required this.dbs, required this.r2, required this.metaBook});

  final Map<String, FirebaseRtdb> dbs;
  final R2Client r2;
  final MetaBook metaBook;

  bool uploadBusy = false;
  bool purgeBusy = false;
  final Set<String> distPushedNames = {};
  int distPointer = 0;

  List<String> get distOrder => dbs.keys.toList();

  FirebaseRtdb db(String key) => dbs[key] ?? dbs.values.first;

  bool acquireUploadLock() {
    if (uploadBusy) return false;
    uploadBusy = true;
    return true;
  }

  void releaseUploadLock() => uploadBusy = false;

  // ---------------------------------------------------------------- requeue
  Future<void> requeueItemsById(String account, List<String> ids) async {
    final d = db(account);
    final freshRaw = await d.get('wallpaperQueue');
    final fresh = freshRaw is Map ? freshRaw : const {};
    if (ids.any((id) {
      final row = fresh[id];
      return row is Map && row['deleteState'] != null && '${row['deleteState']}'.isNotEmpty;
    })) {
      throw Exception('Deletion pending/incomplete. Retry Delete, not Requeue.');
    }
    final patch = <String, dynamic>{};
    for (final id in ids) {
      patch['wallpaperQueue/$id/status'] = 'queued';
      patch['wallpaperQueue/$id/error'] = null;
      patch['wallpaperQueue/$id/failedAt'] = null;
      patch['wallpaperQueue/$id/processingAt'] = null;
      patch['wallpaperQueue/$id/requeuedAt'] = FirebaseRtdb.serverTimestamp;
    }
    await d.update('', patch);
  }

  Future<void> requeueSingle(String account, String id) async {
    await db(account).update('wallpaperQueue/$id', {
      'status': 'queued',
      'error': null,
      'failedAt': null,
      'processingAt': null,
      'requeuedAt': FirebaseRtdb.serverTimestamp,
    });
  }

  // ---------------------------------------------------------------- purge (v19 verified delete)
  static const Set<String> _r2UrlKeys = {'fileUrl', 'thumbUrl', 'fileUrls', 'files'};

  static Set<String> collectR2Urls(dynamic node, Set<String> out, [bool underKey = false]) {
    if (node == null) return out;
    if (node is String) {
      if (underKey && RegExp(r'^https?://', caseSensitive: false).hasMatch(node)) out.add(node);
      return out;
    }
    if (node is List) {
      for (final n in node) {
        collectR2Urls(n, out, underKey);
      }
      return out;
    }
    if (node is Map) {
      node.forEach((k, v) => collectR2Urls(v, out, underKey || _r2UrlKeys.contains('$k')));
    }
    return out;
  }

  Future<PurgeResult> deleteItemsById(String account, List<String> ids, {void Function(PurgePhase)? onPhase}) =>
      purgeItems(account, ids, onPhase: onPhase);

  Future<PurgeResult> purgeItems(String account, List<String> idList, {void Function(PurgePhase)? onPhase}) async {
    if (purgeBusy) throw Exception('A deletion is already running. Wait and retry.');
    final ids = idList.where((x) => x.isNotEmpty).toSet();
    final result = PurgeResult();
    if (ids.isEmpty) return result;
    purgeBusy = true;
    void phase(String text, int cur, int total, [String? live]) =>
        onPhase?.call(PurgePhase(text, cur, total, live: live, indeterminate: total <= 0));
    try {
      phase('Checking all account queues…', 0, 0);
      final snapshots = <String, Map<dynamic, dynamic>>{};
      try {
        await Future.wait(dbs.entries.map((e) async {
          final v = await e.value.get('wallpaperQueue');
          snapshots[e.key] = v is Map ? v : <dynamic, dynamic>{};
        }));
      } catch (e) {
        result.verifyFailed = true;
        result.retained = ids.length;
        result.errors.add('Could not read all account queues. Nothing deleted: $e');
        return result;
      }
      final rows = <String, Map<dynamic, dynamic>>{};
      final references = <String, Set<String>>{};
      final urls = <String, String>{};
      final outside = <String>{};
      final blocked = <String, String>{};
      Set<String> keysOf(dynamic row) {
        final out = <String>{};
        for (final u in collectR2Urls(row, <String>{})) {
          final key = R2Client.keyFromUrl(u);
          out.add(key);
          urls[key] = u;
        }
        return out;
      }
      for (final e in snapshots.entries) {
        for (final r in e.value.entries) {
          final id = '${r.key}';
          final row = r.value;
          if (e.key == account && ids.contains(id)) {
            rows[id] = row is Map ? row : <dynamic, dynamic>{};
            try {
              references[id] = keysOf(row);
            } catch (err) {
              blocked[id] = '$err'.replaceFirst('Exception: ', '');
              references[id] = <String>{};
            }
          } else {
            for (final u in collectR2Urls(row, <String>{})) {
              try {
                outside.add(R2Client.keyFromUrl(u));
              } catch (_) {}
            }
          }
        }
      }
      for (final e in rows.entries) {
        final id = e.key, row = e.value;
        final refs = references[id] ?? <String>{};
        if (refs.isEmpty) blocked[id] = 'No stored R2 URL. Record retained for manual review.';
        if (row['status'] == 'processing') blocked[id] = 'Upload is processing. Wait before deleting.';
        if (refs.any(outside.contains)) blocked[id] = 'File is shared by another retained queue item. Remove its other references first.';
      }
      // Keep an entire shared group if any selected member is blocked.
      var changed = true;
      while (changed) {
        changed = false;
        final protectedKeys = <String>{...outside};
        for (final id in blocked.keys) {
          protectedKeys.addAll(references[id] ?? const <String>{});
        }
        for (final e in references.entries) {
          if (!blocked.containsKey(e.key) && e.value.any(protectedKeys.contains)) {
            blocked[e.key] = 'Shares a file with a retained item.';
            changed = true;
          }
        }
      }
      result.kept = blocked.length;
      result.errors.addAll(blocked.values.take(2));
      final eligible = rows.keys.where((id) => !blocked.containsKey(id)).toList();
      if (eligible.isEmpty) {
        result.retained = rows.length;
        return result;
      }
      phase('Reserving ${eligible.length} record(s) in Firebase…', 0, 0);
      for (var i = 0; i < eligible.length; i += 200) {
        final patch = <String, dynamic>{};
        for (final id in eligible.sublist(i, (i + 200).clamp(0, eligible.length).toInt())) {
          patch['wallpaperQueue/$id/status'] = 'deleting';
          patch['wallpaperQueue/$id/deleteState'] = 'pending';
          patch['wallpaperQueue/$id/deleteError'] = null;
          patch['wallpaperQueue/$id/deleteRequestedAt'] = FirebaseRtdb.serverTimestamp;
        }
        await db(account).update('', patch);
      }
      final unique = <String>{};
      for (final id in eligible) {
        unique.addAll(references[id] ?? const <String>{});
      }
      final outcomes = <String, String?>{};
      final pending = unique.toList();
      final totalFiles = unique.length;
      var doneFiles = 0;
      phase('Deleting $totalFiles file(s) from R2 (verified)…', 0, totalFiles);
      Future<void> worker() async {
        while (pending.isNotEmpty) {
          final key = pending.removeAt(0);
          String live;
          try {
            await r2.deleteFile(urls[key]!);
            outcomes[key] = null;
            result.files++;
            live = '✓ $key';
          } catch (e) {
            final msg = '$e'.replaceFirst('Exception: ', '');
            outcomes[key] = msg;
            result.failed++;
            if (e is! Exception || msg.contains('SocketException') || msg.contains('Failed host lookup') || msg.contains('Connection')) {
              result.corsBlocked = true;
            }
            live = '✗ $key — $msg';
          }
          doneFiles++;
          phase('Deleting $totalFiles file(s) from R2 (verified)…', doneFiles, totalFiles, live);
        }
      }
      final workers = List.generate(pending.length < 6 ? pending.length : 6, (_) => worker());
      await Future.wait(workers);
      phase('Verifying queue and removing records…', totalFiles, totalFiles);
      Map<dynamic, dynamic> latest;
      try {
        final v = await db(account).get('wallpaperQueue');
        latest = v is Map ? v : <dynamic, dynamic>{};
      } catch (e) {
        result.retained = rows.length;
        result.verifyFailed = true;
        result.errors.add('Final Firebase check failed; retry Delete. $e');
        return result;
      }
      for (var i = 0; i < eligible.length; i += 200) {
        final patch = <String, dynamic>{};
        final removed = <String>[];
        for (final id in eligible.sublist(i, (i + 200).clamp(0, eligible.length).toInt())) {
          final row = latest[id];
          if (row == null) continue;
          final refs = references[id] ?? <String>{};
          var reason = refs.map((k) => outcomes[k]).where((x) => x != null && x.isNotEmpty).firstOrNull ?? '';
          Set<String>? current;
          try {
            current = keysOf(row);
          } catch (e) {
            reason = '$e'.replaceFirst('Exception: ', '');
          }
          final rowMap = row is Map ? row : const {};
          if (current == null || current.length != refs.length || refs.any((k) => !current!.contains(k)) || rowMap['deleteState'] != 'pending') {
            reason = 'Record changed while deleting. Review and retry Delete.';
          }
          if (reason.isEmpty) {
            patch['wallpaperQueue/$id'] = null;
            removed.add(id);
          } else {
            patch['wallpaperQueue/$id/status'] = 'failed';
            patch['wallpaperQueue/$id/deleteState'] = 'incomplete';
            patch['wallpaperQueue/$id/deleteError'] = reason;
            patch['wallpaperQueue/$id/error'] = 'Deletion incomplete — retry Delete, not Requeue. $reason';
            patch['wallpaperQueue/$id/failedAt'] = FirebaseRtdb.serverTimestamp;
            result.errors.add(reason);
          }
        }
        try {
          if (patch.isNotEmpty) await db(account).update('', patch);
          result.rows += removed.length;
          result.deletedIds.addAll(removed);
        } catch (e) {
          result.verifyFailed = true;
          result.errors.add('Firebase cleanup failed. R2 was checked; retry Delete. $e');
          break;
        }
      }
      result.retained = rows.length - result.rows;
      return result;
    } finally {
      purgeBusy = false;
    }
  }

  // ---------------------------------------------------------------- metadata JSON absorb
  /// `zMetaAbsorb(files)` - loads sidecar .json files into the MetaBook and returns the rest.
  Future<List<LocalFile>> zMetaAbsorb(List<LocalFile> files, ToastFn toast) async {
    final jsons = files.where((f) => f.isJson || f.mime == 'application/json').toList();
    if (jsons.isEmpty) return files;
    for (final j in jsons) {
      try {
        final r = metaBook.parse(utf8.decode(await j.bytes(), allowMalformed: true), j.name);
        toast('Metadata JSON "${j.name}": ${r.added} entr${r.added == 1 ? 'y' : 'ies'} loaded${r.problems.isNotEmpty ? ', ${r.problems.length} skipped' : ''}',
            r.problems.isNotEmpty ? 'warn' : 'ok');
      } catch (e) {
        toast('Metadata JSON "${j.name}" invalid: ${'$e'.replaceFirst('Exception: ', '')}', 'err');
      }
    }
    return files.where((f) => !jsons.contains(f)).toList();
  }

  Map<String, dynamic> zMetaFields(List<String?> names, String? contentType) => metaBook.fields(names, contentType).toPayload();

  // ---------------------------------------------------------------- Upload queue (active account)
  /// `handleActiveQueueUpload(files)` (archives are handled by the caller through [smartArchiveImport]).
  Future<void> handleActiveQueueUpload(
    String account,
    List<LocalFile> files,
    List<QueueItem> queueItems, {
    required ConfirmFn confirm,
    required StatusFn status,
    void Function(String name, Object error)? onError,
  }) async {
    if (files.isEmpty) return;
    if (!acquireUploadLock()) throw UploadBusyException();
    try {
      var n = 0;
      for (final file in files) {
        n++;
        try {
          if (queueItems.any((q) => q.name == file.name)) {
            if (!await confirm('"${file.name}" is already in this queue. Add it again anyway?')) continue;
          }
          final isAudio = file.isMp3;
          status('Uploading $n/${files.length}: ${file.name}...');
          Uint8List blob = await file.bytes();
          final fileType = isAudio ? (file.mime.isNotEmpty ? file.mime : 'audio/mpeg') : 'image/jpeg';
          if (!isAudio) blob = await resizeImageTo1620x2880(blob);
          final fileUrl = await r2.upload(blob, file.name, account, mimeType: fileType);
          await db(account).push('wallpaperQueue', {
            'name': file.name,
            'type': fileType,
            'size': blob.length,
            'isMp3': isAudio,
            'contentType': isAudio ? 'RINGTONE' : 'WALLPAPER',
            'fileUrl': fileUrl,
            ...zMetaFields([file.name], isAudio ? 'RINGTONE' : 'WALLPAPER'),
            'status': 'queued',
            'createdAt': FirebaseRtdb.serverTimestamp,
          });
        } catch (err) {
          onError?.call(file.name, err);
        }
      }
    } finally {
      releaseUploadLock();
    }
  }

  // ---------------------------------------------------------------- sets (24H / Dual / Battery)
  Future<void> submitSet(String account, String type, Map<String, LocalFile> slotFiles, {required StatusFn status}) async {
    final meta = kSetTypeMeta[type];
    if (meta == null) return;
    if (meta.slots.any((s) => slotFiles[s] == null)) return;
    if (!acquireUploadLock()) throw UploadBusyException();
    try {
      final files = <String, String>{};
      var totalSize = 0;
      for (final slot in meta.slots) {
        status('Resizing & uploading $slot image...');
        final f = slotFiles[slot]!;
        final resized = await resizeImageTo1620x2880(await f.bytes());
        final url = await r2.upload(resized, '${meta.prefix}_${slot}_${f.name}', '$account/${meta.prefix}', mimeType: 'image/jpeg');
        files[slot] = url;
        totalSize += resized.length;
      }
      final name = type == 'WALLPAPER_24H' ? '24H Set ${_stampNow()}' : '${meta.label} ${_stampNow()}';
      await db(account).push('wallpaperQueue', {
        'name': name,
        'type': 'image/jpeg',
        'size': totalSize,
        'isMp3': false,
        'contentType': type,
        'files': files,
        'fileUrl': files[meta.slots.first],
        ...zMetaFields([slotFiles[meta.slots.first]!.name], type),
        'status': 'queued',
        'createdAt': FirebaseRtdb.serverTimestamp,
      });
      status(type == 'WALLPAPER_24H' ? '24H set queued successfully!' : '${meta.label} queued successfully!');
    } finally {
      releaseUploadLock();
    }
  }

  // ---------------------------------------------------------------- video (Live wallpaper / Charging animation)
  Future<void> submitVideoItem(String account, String vType, LocalFile video, Uint8List thumb, {required StatusFn status}) async {
    final meta = kVideoTypeMeta[vType] ?? kVideoTypeMeta['LIVE_WALLPAPER']!;
    if (!acquireUploadLock()) throw UploadBusyException();
    try {
      status('Uploading video to R2...');
      final videoUrl = await r2.upload(await video.bytes(), '${meta.prefix}_${video.name}', '$account/${meta.prefix}',
          mimeType: video.mime.isNotEmpty ? video.mime : 'video/mp4');
      status('Uploading auto thumbnail...');
      final thumbUrl = await r2.upload(thumb, '${meta.prefix}_thumb_${video.name}.jpg', '$account/${meta.prefix}', mimeType: 'image/jpeg');
      await db(account).push('wallpaperQueue', {
        'name': video.name,
        'type': video.mime.isNotEmpty ? video.mime : 'video/mp4',
        'size': video.size,
        'isMp3': false,
        'contentType': vType,
        'fileUrl': videoUrl,
        'thumbUrl': thumbUrl,
        ...zMetaFields([video.name], vType),
        'status': 'queued',
        'createdAt': FirebaseRtdb.serverTimestamp,
      });
      status('${meta.label} queued successfully!');
    } finally {
      releaseUploadLock();
    }
  }

  // ---------------------------------------------------------------- distribution
  /// `buildDistributionPayload(file, targetDbKey)`
  Future<Map<String, dynamic>> buildDistributionPayload(LocalFile file, String targetDbKey, String distVideoType, StatusFn status) async {
    if (file.isMp3) {
      final url = await r2.upload(await file.bytes(), file.name, targetDbKey, mimeType: file.mime.isNotEmpty ? file.mime : 'audio/mpeg');
      return {'name': file.name, 'type': file.mime.isNotEmpty ? file.mime : 'audio/mpeg', 'size': file.size, 'isMp3': true, 'contentType': 'RINGTONE', 'fileUrl': url};
    }
    if (file.isVideo) {
      final vType = distVideoType == 'CHARGING_ANIMATION' ? 'CHARGING_ANIMATION' : 'LIVE_WALLPAPER';
      final vMeta = kVideoTypeMeta[vType]!;
      status('Capturing cover thumbnail from ${file.name}...');
      final path = file.path ?? await _tempFile(file);
      final frames = await VideoTools.captureVideoFrames(path, count: 5);
      final thumb = frames[frames.length ~/ 2];
      status('Uploading ${vMeta.label} ${file.name} → ${targetDbKey.toUpperCase()}...');
      final fileUrl = await r2.upload(await file.bytes(), '${vMeta.prefix}_${file.name}', '$targetDbKey/${vMeta.prefix}',
          mimeType: file.mime.isNotEmpty ? file.mime : 'video/mp4');
      final thumbUrl = await r2.upload(thumb, '${vMeta.prefix}_thumb_${file.name}.jpg', '$targetDbKey/${vMeta.prefix}', mimeType: 'image/jpeg');
      return {
        'name': file.name,
        'type': file.mime.isNotEmpty ? file.mime : 'video/mp4',
        'size': file.size,
        'isMp3': false,
        'contentType': vType,
        'fileUrl': fileUrl,
        'thumbUrl': thumbUrl
      };
    }
    final resized = await resizeImageTo1620x2880(await file.bytes());
    final url = await r2.upload(resized, file.name, targetDbKey, mimeType: 'image/jpeg');
    return {
      'name': file.name,
      'type': 'image/jpeg',
      'size': resized.length,
      'width': kWallpaperWidth,
      'height': kWallpaperHeight,
      'isMp3': false,
      'contentType': 'WALLPAPER',
      'fileUrl': url
    };
  }

  Future<String> _tempFile(LocalFile f) async {
    final tmp = await Directory.systemTemp.createTemp('zedge_media_');
    final out = File('${tmp.path}/${f.name}');
    await out.writeAsBytes(await f.bytes());
    return out.path;
  }

  /// Loose-file round-robin distribution (`handleDistributionUpload` main branch).
  Future<(int ok, int fail)> distributeFiles(
    List<LocalFile> files, {
    required String distVideoType,
    required ConfirmFn confirm,
    required StatusFn status,
    required void Function(double pct) progress,
    required void Function() onPointerMoved,
  }) async {
    if (!acquireUploadLock()) throw UploadBusyException();
    var successCount = 0, failCount = 0;
    try {
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final isImg = file.isImage, isAud = file.isMp3, isVid = file.isVideo;
        final isOk = (isImg || isAud || isVid) && !(isVid && file.size > kVideoMaxBytes);
        if (!isOk) continue;
        if (distPushedNames.contains(file.name) && !await confirm('"${file.name}" was already distributed in this session. Distribute again anyway?')) {
          continue;
        }
        final targetDbKey = distOrder[distPointer % distOrder.length];
        onPointerMoved();
        status('Uploading image ${i + 1}/${files.length}: ${file.name} → ${targetDbKey.toUpperCase()}...');
        try {
          final payload = await buildDistributionPayload(file, targetDbKey, distVideoType, status);
          await db(targetDbKey).push('wallpaperQueue', {
            ...payload,
            ...zMetaFields([file.name], payload['contentType'] as String?),
            'status': 'queued',
            'distributedTo': targetDbKey,
            'createdAt': FirebaseRtdb.serverTimestamp,
          });
          distPushedNames.add(file.name);
          successCount++;
          distPointer++;
        } catch (_) {
          failCount++;
        }
        progress((i + 1) / files.length);
      }
    } finally {
      releaseUploadLock();
      progress(0);
      onPointerMoved();
    }
    return (successCount, failCount);
  }

  /// `handleSetDistribution(files, setType)` - N images per set, one set per account in turn.
  Future<(int ok, int fail)?> distributeSets(
    List<LocalFile> files,
    String setType, {
    required ConfirmFn confirm,
    required StatusFn status,
    required void Function(double pct) progress,
    required void Function() onPointerMoved,
  }) async {
    final meta = kSetTypeMeta[setType];
    if (meta == null) return null;
    final nonImages = files.where((f) => !f.isImage).length;
    if (nonImages > 0) {
      status('Error: ${meta.label} mode accepts image files only - remove $nonImages non-image file(s) (MP3/video) and try again.');
      return null;
    }
    final size = meta.slots.length;
    if (files.length % size != 0) {
      final remainder = files.length % size;
      status('Error: ${meta.label} needs $size images per set. You selected ${files.length} - that leaves $remainder extra. Select a multiple of $size (e.g. ${files.length - remainder} or ${files.length + size - remainder}).');
      return null;
    }
    final sorted = List<LocalFile>.from(files)..sort((a, b) => natCmp(a.name, b.name));
    final sets = <List<LocalFile>>[];
    for (var i = 0; i < sorted.length; i += size) {
      sets.add(sorted.sublist(i, i + size));
    }
    final previewLines = <String>[];
    for (var idx = 0; idx < sets.length && idx < 3; idx++) {
      final target = distOrder[(distPointer + idx) % distOrder.length];
      previewLines.add('Set ${idx + 1} -> ${target.toUpperCase()}: ${sets[idx].map((f) => f.name).join(', ')}');
    }
    final moreNote = sets.length > 3 ? '\n\n...and ${sets.length - 3} more set(s)' : '';
    const howGrouped = 'grouped in name order - Zedge auto-assigns on upload';
    final okGo = await confirm('${sets.length} ${meta.label}(s) will be created ($howGrouped):\n\n${previewLines.join('\n')}$moreNote\n\nContinue?');
    if (!okGo) {
      status('Set distribution cancelled - nothing was uploaded.');
      return null;
    }
    if (!acquireUploadLock()) throw UploadBusyException();
    var okSets = 0, failSets = 0, uploadedFiles = 0;
    final totalFiles = sorted.length;
    try {
      for (var sIdx = 0; sIdx < sets.length; sIdx++) {
        final chunk = sets[sIdx];
        final targetDbKey = distOrder[distPointer % distOrder.length];
        onPointerMoved();
        try {
          final filesMap = <String, String>{};
          var totalSize = 0;
          for (var j = 0; j < meta.slots.length; j++) {
            final slot = meta.slots[j];
            final f = chunk[j];
            status('${meta.short} set ${sIdx + 1}/${sets.length}: uploading image ${j + 1}/${meta.slots.length} ($slot: ${f.name}) → ${targetDbKey.toUpperCase()}...');
            final resized = await resizeImageTo1620x2880(await f.bytes());
            final url = await r2.upload(resized, '${meta.prefix}_${slot}_${f.name}', '$targetDbKey/${meta.prefix}', mimeType: 'image/jpeg');
            filesMap[slot] = url;
            totalSize += resized.length;
            uploadedFiles++;
            progress(uploadedFiles / totalFiles);
          }
          await db(targetDbKey).push('wallpaperQueue', {
            'name': '${meta.label} ${_stampNow()} #${sIdx + 1}',
            'type': 'image/jpeg',
            'size': totalSize,
            'isMp3': false,
            'contentType': setType,
            'importedFrom': null,
            'files': filesMap,
            'fileUrl': filesMap[meta.slots.first],
            ...zMetaFields([null, chunk.first.name], setType),
            'status': 'queued',
            'distributedTo': targetDbKey,
            'createdAt': FirebaseRtdb.serverTimestamp,
          });
          okSets++;
          distPointer++;
        } catch (_) {
          failSets++;
        }
      }
    } finally {
      releaseUploadLock();
      progress(0);
      onPointerMoved();
    }
    return (okSets, failSets);
  }

  // ---------------------------------------------------------------- smart archive import
  /// `buildSetPayload(unit, dbKey, onSlot)` - uploads one set unit and returns the queue payload.
  Future<Map<String, dynamic>> buildSetPayload(ImportUnit unit, String dbKey, void Function(String slot)? onSlot) async {
    final meta = kSetTypeMeta[unit.type]!;
    final urls = <String, String>{};
    var totalSize = 0;
    for (final slot in meta.slots) {
      onSlot?.call(slot);
      final entry = unit.files![slot]!;
      final bytes = await entry.data();
      final resized = await resizeImageTo1620x2880(bytes);
      urls[slot] = await r2.upload(resized, '${meta.prefix}_${slot}_${baseName(entry.name)}', '$dbKey/${meta.prefix}', mimeType: 'image/jpeg');
      totalSize += resized.length;
    }
    return {
      'name': unit.label.isNotEmpty ? '${meta.label} - ${unit.label}' : '${meta.label} ${_stampNow()}',
      'type': 'image/jpeg',
      'size': totalSize,
      'isMp3': false,
      'contentType': unit.type,
      'files': urls,
      'fileUrl': urls[meta.slots.first],
    };
  }

  /// `smartArchiveImport(archiveFiles, { mode, fallbackType })`
  /// mode "queue": everything into [account]. mode "distribute": round-robin across accounts.
  Future<void> smartArchiveImport(
    List<LocalFile> archives, {
    required String mode,
    required String account,
    String? fallbackType,
    required String distVideoType,
    required ConfirmFn confirm,
    required AlertFn alert,
    required StatusFn status,
    required ToastFn toast,
    void Function(double pct)? progress,
    void Function(String label)? onButton,
    void Function()? onPointerMoved,
  }) async {
    final files = archives.where((f) => f.path != null || f.size > 0).toList();
    if (files.isEmpty) return;
    if (!acquireUploadLock()) throw UploadBusyException();
    onButton?.call('Reading...');
    var ok = 0;
    final failed = <String>[];
    try {
      final units = <ImportUnit>[];
      final notes = <String>[];
      final problems = <String>[];
      for (final af in files) {
        status('Reading ${af.name} (${formatBytes(af.size)})...');
        List<ArchiveEntry> entries;
        try {
          entries = await ArchiveReader.readArchiveEntries(af.path ?? await _tempFile(af));
        } catch (e) {
          problems.add('${af.name}: ${'$e'.replaceFirst('Exception: ', '')}');
          continue;
        }
        // v22: metadata .json inside the archive -> load it, then drop it from the media list
        for (final je in entries.where((e) => !isJunkPath(e.name) && e.name.toLowerCase().endsWith('.json'))) {
          try {
            final txt = utf8.decode(await je.data(), allowMalformed: true);
            final mr = metaBook.parse(txt, '${af.name} › ${baseName(je.name)}');
            notes.add('${baseName(je.name)}: metadata for ${mr.added} file(s) loaded${mr.problems.isNotEmpty ? ', ${mr.problems.length} entr${mr.problems.length == 1 ? 'y' : 'ies'} skipped' : ''}');
          } catch (e) {
            problems.add('${baseName(je.name)}: metadata JSON invalid - ${'$e'.replaceFirst('Exception: ', '')}');
          }
        }
        entries = entries.where((e) => !e.name.toLowerCase().endsWith('.json')).toList();
        final r = classifyArchiveEntries(entries, af.name, fallbackType);
        if (r.mediaCount == 0) problems.add('${af.name}: no images / mp3 / videos inside');
        units.addAll(r.units);
        notes.addAll(r.notes);
      }
      if (units.isEmpty) {
        status('Nothing usable found in the archive.');
        await alert('Nothing to import.${problems.isNotEmpty ? '\n\n${problems.join('\n')}' : ''}');
        return;
      }
      final setUnits = units.where((u) => u.isSet).toList();
      final preview = <String>[];
      for (var i = 0; i < setUnits.length && i < 10; i++) {
        final u = setUnits[i];
        final meta = kSetTypeMeta[u.type]!;
        preview.add('  ${i + 1}. [${meta.short}] ${u.label.isNotEmpty ? u.label : baseName(u.archive ?? '')}${u.byName ? '' : ' (file order = slot order)'}: ${meta.slots.map((sl) => '$sl=${baseName(u.files![sl]!.name)}').join(', ')}');
      }
      final target = mode == 'distribute'
          ? 'across ${distOrder.map((k) => k.toUpperCase()).join(' -> ')} (one set / file per account in turn)'
          : 'into ${account.toUpperCase()}';
      final msg = 'Smart import detected: ${describeUnits(units)}.'
          '${notes.isNotEmpty ? '\n\nNotes:\n- ${notes.join('\n- ')}' : ''}'
          '${problems.isNotEmpty ? '\n\nProblems:\n- ${problems.join('\n- ')}' : ''}'
          '${preview.isNotEmpty ? '\n\nSets:\n${preview.join('\n')}${setUnits.length > 10 ? '\n  ...and ${setUnits.length - 10} more' : ''}' : ''}'
          '\n\nUpload everything $target?';
      if (!await confirm(msg)) {
        status('Import cancelled.');
        return;
      }
      final total = units.length;
      for (var i = 0; i < units.length; i++) {
        final u = units[i];
        final dbKey = mode == 'distribute' ? distOrder[distPointer % distOrder.length] : account;
        final title = u.title;
        final pct = ((i / total) * 100).round();
        if (mode == 'distribute') onPointerMoved?.call();
        onButton?.call('$pct% - ${i + 1}/$total');
        try {
          Map<String, dynamic> payload;
          final dest = mode == 'distribute' ? ' → ${dbKey.toUpperCase()}' : '';
          if (u.isSet) {
            payload = await buildSetPayload(u, dbKey, (slot) => status('${i + 1}/$total $title - $slot: uploading$dest... $pct%'));
          } else {
            status('${i + 1}/$total $title: uploading$dest... $pct%');
            final e = u.entry!;
            final lf = LocalFile.fromBytes(baseName(e.name), await e.data(), mime: distMime(baseName(e.name)));
            payload = await buildDistributionPayload(lf, dbKey, distVideoType, status);
          }
          final firstSlotName = u.isSet ? u.files![kSetTypeMeta[u.type]!.slots.first]?.name : u.entry?.name;
          await db(dbKey).push('wallpaperQueue', {
            ...payload,
            ...zMetaFields([firstSlotName, title], payload['contentType'] as String?),
            'status': 'queued',
            'importedFrom': u.isSet ? u.archive : u.entry?.zArchive,
            if (mode == 'distribute') 'distributedTo': dbKey,
            'createdAt': FirebaseRtdb.serverTimestamp,
          });
          ok++;
          if (mode == 'distribute') {
            distPointer++;
            distPushedNames.add(title);
          }
        } catch (err) {
          failed.add('$title: ${'$err'.replaceFirst('Exception: ', '')}');
        }
        if (mode == 'distribute') progress?.call((i + 1) / total);
      }
      final summary = '$ok/$total item(s) queued${failed.isNotEmpty ? ', ${failed.length} failed' : ''}';
      status(summary + (mode == 'distribute' ? '' : ' - ${describeUnits(units)}'));
      toast(summary, failed.isNotEmpty ? 'warn' : 'ok');
      if (failed.isNotEmpty) await alert('${failed.length} item(s) could not be uploaded:\n\n${failed.join('\n')}');
    } catch (err) {
      status('Import stopped after $ok item(s) - ${'$err'.replaceFirst('Exception: ', '')}');
    } finally {
      releaseUploadLock();
      onButton?.call('Choose Archive');
      if (mode == 'distribute') {
        progress?.call(0);
        onPointerMoved?.call();
      }
    }
  }

  // ---------------------------------------------------------------- modal actions
  Future<void> saveModalMetadata(String account, String id,
      {required String title, required String tags, required String category, required String description, String? scheduledDate}) async {
    await db(account).update('wallpaperQueue/$id', {
      'title': title.trim(),
      'tags': tags.trim(),
      'category': category.trim().toUpperCase(),
      'description': description.trim(),
      'scheduledDate': (scheduledDate == null || scheduledDate.isEmpty) ? null : scheduledDate,
    });
  }

  /// `copyModalItemToOtherAccounts()`
  Future<List<String>> copyItemToOtherAccounts(String account, QueueItem item) async {
    final others = distOrder.where((k) => k != account).toList();
    final copy = Map<String, dynamic>.from(item.raw)..remove('id');
    copy['status'] = 'queued';
    copy['createdAt'] = FirebaseRtdb.serverTimestamp;
    for (final key in others) {
      copy['distributedTo'] = key;
      await db(key).push('wallpaperQueue', Map<String, dynamic>.from(copy));
    }
    return others;
  }

  // ---------------------------------------------------------------- pins
  Future<void> unpinItem(String account, String id) => db(account).update('wallpaperQueue/$id', {'scheduledDate': null});

  Future<void> setItemScheduledDate(String account, String id, String dateKey) =>
      db(account).update('wallpaperQueue/$id', {'scheduledDate': dateKey});

  /// `bulkPinUpdate(items, value)` - value null = unpin.
  Future<void> bulkPinUpdate(String account, List<String> ids, String? value) async {
    final updates = <String, dynamic>{};
    for (final id in ids) {
      updates['wallpaperQueue/$id/scheduledDate'] = value;
    }
    await db(account).update('', updates);
  }

  // ---------------------------------------------------------------- schedule / mix mode
  Future<void> saveSchedule(String key, List<RunSlot> slots) async {
    final sorted = cloneSlots(slots)..sort((a, b) => a.startMin.compareTo(b.startMin));
    final err = validateSlots(sorted);
    if (err != null) throw Exception(err);
    await db(key).set('dashboardSettings/schedule', {
      'windows': sorted.map((x) => x.hour).toList(),
      'slots': sorted.map((x) => x.toJson()).toList(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'updatedBy': 'panel',
    });
  }

  Future<void> saveVariety(String key, {required bool enabled, required bool strict, required List<String> types}) async {
    await db(key).set('dashboardSettings/variety', {
      'enabled': enabled,
      'strict': strict,
      'types': types,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'updatedBy': 'panel',
    });
  }
}
