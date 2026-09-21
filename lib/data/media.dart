import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../core/constants.dart';

/// A file picked by the user or produced in memory (mirrors the browser `File`).
class LocalFile {
  LocalFile({required this.name, required this.size, this.path, Uint8List? bytes, String? mime})
      : _bytes = bytes,
        mime = mime ?? mimeForName(name);

  final String name;
  final int size;
  final String? path;
  final String mime;
  Uint8List? _bytes;

  static Future<LocalFile> fromPath(String path) async {
    final f = File(path);
    final len = await f.length();
    return LocalFile(name: p.basename(path), size: len, path: path);
  }

  static LocalFile fromBytes(String name, Uint8List bytes, {String? mime}) =>
      LocalFile(name: name, size: bytes.length, bytes: bytes, mime: mime);

  Future<Uint8List> bytes() async {
    if (_bytes != null) return _bytes!;
    if (path == null) return Uint8List(0);
    return _bytes = await File(path!).readAsBytes();
  }

  bool get isImage => mime.startsWith('image/') || RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(name);
  bool get isMp3 => mime == 'audio/mpeg' || name.toLowerCase().endsWith('.mp3');
  bool get isVideo => mime.startsWith('video/') || RegExp(r'\.(mp4|mov)$', caseSensitive: false).hasMatch(name);
  bool get isJson => name.toLowerCase().endsWith('.json');
  bool get isArchive => RegExp(r'\.(zip|rar)$', caseSensitive: false).hasMatch(name);

  static String mimeForName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'mp3':
        return 'audio/mpeg';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'json':
        return 'application/json';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/vnd.rar';
      default:
        return 'application/octet-stream';
    }
  }
}

/// `resizeImageTo1620x2880` - cover-scale, centre, JPEG quality 0.92. Runs in an isolate.
Future<Uint8List> resizeImageTo1620x2880(Uint8List src) async {
  return Isolate.run(() => _resizeSync(src));
}

Uint8List _resizeSync(Uint8List src) {
  final decoded = img.decodeImage(src);
  if (decoded == null) throw Exception('Image loader failed');
  const tw = kWallpaperWidth, th = kWallpaperHeight;
  final scale = (tw / decoded.width) > (th / decoded.height) ? tw / decoded.width : th / decoded.height;
  final sw = (decoded.width * scale).round();
  final sh = (decoded.height * scale).round();
  final scaled = img.copyResize(decoded, width: sw, height: sh, interpolation: img.Interpolation.linear);
  final canvas = img.Image(width: tw, height: th);
  img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
  img.compositeImage(canvas, scaled, dstX: ((tw - sw) / 2).round(), dstY: ((th - sh) / 2).round());
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 92));
}

class VideoProbe {
  const VideoProbe({required this.durationSec, required this.width, required this.height});
  final double durationSec;
  final int width;
  final int height;
}

/// ffmpeg / ffprobe based helpers (the browser used a hidden `<video>` + canvas).
class VideoTools {
  static String? _ffmpeg;
  static String? _ffprobe;

  static Future<String?> _find(String tool) async {
    try {
      final r = await Process.run(Platform.isWindows ? 'where' : 'which', [tool]);
      if (r.exitCode == 0 && r.stdout.toString().trim().isNotEmpty) return r.stdout.toString().trim().split(RegExp(r'\r?\n')).first;
    } catch (_) {}
    // bundled next to the executable
    final local = p.join(p.dirname(Platform.resolvedExecutable), Platform.isWindows ? '$tool.exe' : tool);
    if (File(local).existsSync()) return local;
    return null;
  }

  static Future<bool> available() async {
    _ffmpeg ??= await _find('ffmpeg');
    return _ffmpeg != null;
  }

  static Future<VideoProbe?> probe(String path) async {
    _ffprobe ??= await _find('ffprobe');
    if (_ffprobe == null) return null;
    try {
      final r = await Process.run(_ffprobe!, [
        '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height:format=duration', '-of', 'json', path
      ]);
      if (r.exitCode != 0) return null;
      final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
      final streams = (j['streams'] as List?) ?? const [];
      final s = streams.isNotEmpty ? streams.first as Map<String, dynamic> : const <String, dynamic>{};
      final dur = double.tryParse('${(j['format'] as Map?)?['duration'] ?? ''}') ?? 0;
      return VideoProbe(durationSec: dur, width: (s['width'] as num?)?.toInt() ?? 0, height: (s['height'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  /// `captureVideoFrames(file, 5)` - frames at 8/28/50/72/92 % of the duration,
  /// cover-scaled onto a 1620x2880 canvas and encoded as JPEG (q 0.92).
  static Future<List<Uint8List>> captureVideoFrames(String path, {int count = 5}) async {
    _ffmpeg ??= await _find('ffmpeg');
    if (_ffmpeg == null) {
      throw Exception('ffmpeg not found - install ffmpeg (and ffprobe) and add it to PATH to capture video thumbnails');
    }
    final pr = await probe(path);
    final d = (pr?.durationSec ?? 0) > 0 ? pr!.durationSec : 2.0;
    final times = [0.08, 0.28, 0.5, 0.72, 0.92].take(count).map((pct) {
      final t = d * pct;
      final cap = d - 0.05 < 0 ? 0.0 : d - 0.05;
      return t < cap ? t : cap;
    }).toList();
    final frames = <Uint8List>[];
    final tmp = await Directory.systemTemp.createTemp('zedge_frames_');
    try {
      for (var i = 0; i < times.length; i++) {
        final out = p.join(tmp.path, 'frame_$i.jpg');
        final r = await Process.run(_ffmpeg!, [
          '-y', '-ss', times[i].toStringAsFixed(3), '-i', path, '-frames:v', '1',
          '-vf', 'scale=$kWallpaperWidth:$kWallpaperHeight:force_original_aspect_ratio=increase,crop=$kWallpaperWidth:$kWallpaperHeight',
          '-q:v', '2', out
        ]);
        if (r.exitCode == 0 && File(out).existsSync()) frames.add(await File(out).readAsBytes());
      }
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
    if (frames.isEmpty) throw Exception('Frame capture failed');
    return frames;
  }
}
