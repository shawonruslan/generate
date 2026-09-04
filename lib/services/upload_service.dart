import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../app_config.dart';
import '../state/app_state.dart';
import 'media_service.dart';
import 'r2_service.dart';

/// A file picked by the user, with bytes loaded in memory.
class PickedFile {
  PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  int get size => bytes.length;
  bool get isImage => MediaService.isImageName(name);
  bool get isVideo => MediaService.isVideoName(name);
  bool get isAudio => MediaService.isAudioName(name);

  static Future<PickedFile?> fromPlatform(PlatformFile file) async {
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return null;
    return PickedFile(name: file.name, bytes: bytes);
  }
}

/// Opens the OS picker. Returns an empty list when cancelled.
Future<List<PickedFile>> pickFiles({
  required List<String> extensions,
  bool multiple = true,
  String? title,
}) async {
  final FilePickerResult? result = await FilePicker.platform.pickFiles(
    allowMultiple: multiple,
    type: extensions.isEmpty ? FileType.any : FileType.custom,
    allowedExtensions: extensions.isEmpty ? null : extensions,
    withData: true,
    dialogTitle: title,
  );
  if (result == null) return <PickedFile>[];
  final List<PickedFile> out = <PickedFile>[];
  for (final PlatformFile f in result.files) {
    final PickedFile? p = await PickedFile.fromPlatform(f);
    if (p != null) out.add(p);
  }
  return out;
}

const List<String> kImageExt = <String>['jpg', 'jpeg', 'png', 'webp'];
const List<String> kAudioExt = <String>['mp3'];
const List<String> kVideoExt = <String>['mp4', 'mov'];

String _stamp(DateTime dhaka) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dhaka.day)}/${two(dhaka.month)}/${dhaka.year} '
      '${two(dhaka.hour)}:${two(dhaka.minute)}';
}

/// Base queue row shared by every upload path (same keys as the web app).
Map<String, dynamic> baseRow({
  required String name,
  required String mime,
  required int size,
  required String contentType,
  required String fileUrl,
  String thumbUrl = '',
  Map<String, String>? files,
  int width = 0,
  int height = 0,
  String? distributedTo,
}) {
  final Map<String, dynamic> row = <String, dynamic>{
    'name': name,
    'type': mime,
    'size': size,
    'isMp3': isAudioType(contentType),
    'contentType': contentType,
    'fileUrl': fileUrl,
    'thumbUrl': thumbUrl.isEmpty ? fileUrl : thumbUrl,
    'title': '',
    'tags': '',
    'category': '',
    'description': '',
    'status': 'queued',
    'scheduledDate': null,
    'createdAt': kServerTimestamp,
  };
  if (files != null) row['files'] = files;
  if (width > 0) row['width'] = width;
  if (height > 0) row['height'] = height;
  if (distributedTo != null) row['distributedTo'] = distributedTo;
  return row;
}

/// Uploads one single file (JPEG wallpaper or MP3) and returns the row.
/// Images are cover-cropped to 1620x2880 before upload.
Future<Map<String, dynamic>> prepareSingleRow(
  PickedFile file,
  ZedgeAccount account, {
  void Function(String)? log,
}) async {
  Uint8List bytes = file.bytes;
  String name = file.name;
  String mime = R2Service.guessContentType(name);
  int width = 0;
  int height = 0;
  String contentType = 'WALLPAPER';

  if (file.isAudio) {
    contentType = 'AUDIO';
    mime = 'audio/mpeg';
  } else if (file.isImage) {
    log?.call('Resizing $name to ${kImageTargetWidth}x$kImageTargetHeight...');
    final ProcessedImage processed = await MediaService.resizeWallpaper(bytes);
    bytes = processed.bytes;
    width = processed.width;
    height = processed.height;
    name = '${name.replaceAll(RegExp(r'\.[^.]+$'), '')}.jpg';
    mime = 'image/jpeg';
  } else {
    throw Exception('Unsupported file: ${file.name} (use JPEG/PNG or MP3)');
  }

  log?.call('Uploading $name to R2...');
  final String url = await R2Service.upload(
    bytes: bytes,
    key: R2Service.buildKey(account.id, name),
    contentType: mime,
  );

  return baseRow(
    name: name,
    mime: mime,
    size: bytes.length,
    contentType: contentType,
    fileUrl: url,
    width: width,
    height: height,
  );
}

/// Uploads a wallpaper set (24H / Dual / Battery). [slotFiles] must contain
/// every slot of the type.
Future<Map<String, dynamic>> prepareSetRow(
  String contentType,
  Map<String, PickedFile> slotFiles,
  ZedgeAccount account,
  DateTime dhakaNow, {
  void Function(String)? log,
}) async {
  final List<String> slots = kSetSlots[contentType] ?? const <String>[];
  final TypeMeta meta = metaFor(contentType);
  final Map<String, String> urls = <String, String>{};
  int total = 0;
  int width = 0;
  int height = 0;

  for (final String slot in slots) {
    final PickedFile? file = slotFiles[slot];
    if (file == null) throw Exception('Missing file for slot "$slot"');
    log?.call('Resizing $slot (${file.name})...');
    final ProcessedImage processed =
        await MediaService.resizeWallpaper(file.bytes);
    width = processed.width;
    height = processed.height;
    total += processed.bytes.length;
    final String clean =
        '${meta.prefix}_${slot}_${file.name.replaceAll(RegExp(r'\.[^.]+$'), '')}.jpg';
    log?.call('Uploading $slot...');
    urls[slot] = await R2Service.upload(
      bytes: processed.bytes,
      key: R2Service.buildKey('${account.id}/${meta.prefix}', clean),
      contentType: 'image/jpeg',
    );
  }

  return baseRow(
    name: '${meta.label} ${_stamp(dhakaNow)}',
    mime: 'image/jpeg',
    size: total,
    contentType: contentType,
    fileUrl: urls[slots.first] ?? '',
    thumbUrl: urls[slots.first] ?? '',
    files: urls,
    width: width,
    height: height,
  );
}

/// Uploads a live wallpaper / charging animation video with an optional cover.
Future<Map<String, dynamic>> prepareVideoRow(
  String contentType,
  PickedFile video,
  PickedFile? cover,
  ZedgeAccount account, {
  void Function(String)? log,
}) async {
  if (video.size > kVideoMaxBytes) {
    throw Exception(
        'Video is ${(video.size / 1048576).toStringAsFixed(1)} MB - limit is 50 MB');
  }
  final TypeMeta meta = metaFor(contentType);
  final String base = video.name.replaceAll(RegExp(r'\.[^.]+$'), '');
  final String mime = R2Service.guessContentType(video.name);

  log?.call('Uploading video ${video.name}...');
  final String videoUrl = await R2Service.upload(
    bytes: video.bytes,
    key: R2Service.buildKey('${account.id}/${meta.prefix}', video.name),
    contentType: mime,
  );

  Uint8List coverBytes;
  int width = 0;
  int height = 0;
  if (cover != null && cover.isImage) {
    log?.call('Resizing cover...');
    final ProcessedImage processed =
        await MediaService.resizeWallpaper(cover.bytes);
    coverBytes = processed.bytes;
    width = processed.width;
    height = processed.height;
  } else {
    log?.call('Generating cover...');
    coverBytes = await MediaService.placeholderCover(meta.label);
  }
  log?.call('Uploading cover...');
  final String thumbUrl = await R2Service.upload(
    bytes: coverBytes,
    key: R2Service.buildKey(
        '${account.id}/${meta.prefix}', '${meta.prefix}_thumb_$base.jpg'),
    contentType: 'image/jpeg',
  );

  return baseRow(
    name: video.name,
    mime: mime,
    size: video.size,
    contentType: contentType,
    fileUrl: videoUrl,
    thumbUrl: thumbUrl,
    width: width,
    height: height,
  );
}
