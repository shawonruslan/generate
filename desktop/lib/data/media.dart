import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
///
/// v28.4: ffmpeg is looked up in many more places and, when it is missing
/// entirely, frames are grabbed through media_kit (mpv) instead, so thumbnail
/// capture also works on a clean Windows machine without ffmpeg installed.
class VideoTools {
  static String? _ffmpeg;
  static String? _ffprobe;
  static bool _searched = false;

  /// Last human readable reason why frame capture failed (shown in the UI).
  static String lastError = '';

  static List<String> _candidatePaths(String tool) {
    final exe = Platform.isWindows ? '$tool.exe' : tool;
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final out = <String>[
      p.join(exeDir, exe),
      p.join(exeDir, 'bin', exe),
      p.join(exeDir, 'ffmpeg', exe),
      p.join(exeDir, 'ffmpeg', 'bin', exe),
      p.join(exeDir, 'data', 'flutter_assets', 'assets', 'bin', exe),
    ];
    if (Platform.isWindows) {
      final env = Platform.environment;
      for (final root in [env['ProgramFiles'], env['ProgramFiles(x86)'], env['LOCALAPPDATA'], env['ProgramData']]) {
        if (root == null || root.isEmpty) continue;
        out.addAll([
          p.join(root, 'ffmpeg', 'bin', exe),
          p.join(root, 'ffmpeg', exe),
        ]);
      }
      final la = env['LOCALAPPDATA'];
      if (la != null && la.isNotEmpty) {
        out.add(p.join(la, 'Microsoft', 'WinGet', 'Links', exe));
        out.add(p.join(la, 'Programs', 'ffmpeg', 'bin', exe));
      }
      final pd = env['ProgramData'];
      if (pd != null && pd.isNotEmpty) out.add(p.join(pd, 'chocolatey', 'bin', exe));
      out.addAll([p.join(r'C:\ffmpeg\bin', exe), p.join(r'C:\ffmpeg', exe)]);
    } else {
      out.addAll(['/usr/bin/$tool', '/usr/local/bin/$tool', '/opt/homebrew/bin/$tool', '/snap/bin/$tool', '/opt/local/bin/$tool']);
    }
    // everything on PATH
    final rawPath = Platform.environment['PATH'] ?? '';
    for (final dir in rawPath.split(Platform.isWindows ? ';' : ':')) {
      if (dir.trim().isEmpty) continue;
      out.add(p.join(dir.trim(), exe));
    }
    return out;
  }

  static Future<String?> _find(String tool) async {
    try {
      final r = await Process.run(Platform.isWindows ? 'where' : 'which', [tool]);
      if (r.exitCode == 0 && r.stdout.toString().trim().isNotEmpty) {
        final hit = r.stdout.toString().trim().split(RegExp(r'\r?\n')).first.trim();
        if (hit.isNotEmpty && File(hit).existsSync()) return hit;
      }
    } catch (_) {}
    for (final c in _candidatePaths(tool)) {
      try {
        if (File(c).existsSync()) return c;
      } catch (_) {}
    }
    return null;
  }

  static Future<void> _ensureTools() async {
    if (_searched) return;
    _searched = true;
    _ffmpeg = await _find('ffmpeg');
    _ffprobe = await _find('ffprobe');
    if (_ffprobe == null && _ffmpeg != null) {
      // ffprobe usually sits next to ffmpeg
      final sibling = p.join(p.dirname(_ffmpeg!), Platform.isWindows ? 'ffprobe.exe' : 'ffprobe');
      if (File(sibling).existsSync()) _ffprobe = sibling;
    }
  }

  /// Re-run the lookup (used after the user installs ffmpeg without restarting).
  static void resetToolCache() {
    _searched = false;
    _ffmpeg = null;
    _ffprobe = null;
  }

  static Future<bool> available() async {
    await _ensureTools();
    return _ffmpeg != null;
  }

  static Future<VideoProbe?> probe(String path) async {
    await _ensureTools();
    if (_ffprobe != null) {
      try {
        final r = await Process.run(_ffprobe!, [
          '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height:format=duration', '-of', 'json', path
        ]);
        if (r.exitCode == 0) {
          final j = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
          final streams = (j['streams'] as List?) ?? const [];
          final s = streams.isNotEmpty ? streams.first as Map<String, dynamic> : const <String, dynamic>{};
          final dur = double.tryParse('${(j['format'] as Map?)?['duration'] ?? ''}') ?? 0;
          if (dur > 0 || (s['width'] as num?) != null) {
            return VideoProbe(durationSec: dur, width: (s['width'] as num?)?.toInt() ?? 0, height: (s['height'] as num?)?.toInt() ?? 0);
          }
        }
      } catch (_) {}
    }
    // fall back to parsing `ffmpeg -i`
    if (_ffmpeg != null) {
      try {
        final r = await Process.run(_ffmpeg!, ['-hide_banner', '-i', path]);
        final text = '${r.stderr}${r.stdout}';
        final d = RegExp(r'Duration:\s*(\d+):(\d+):(\d+\.?\d*)').firstMatch(text);
        final wh = RegExp(r',\s(\d{2,5})x(\d{2,5})[,\s]').firstMatch(text);
        if (d != null) {
          final sec = int.parse(d.group(1)!) * 3600 + int.parse(d.group(2)!) * 60 + double.parse(d.group(3)!);
          return VideoProbe(
            durationSec: sec,
            width: wh != null ? int.parse(wh.group(1)!) : 0,
            height: wh != null ? int.parse(wh.group(2)!) : 0,
          );
        }
      } catch (_) {}
    }
    return null;
  }

  static List<double> _frameTimes(double duration, int count) {
    final d = duration > 0 ? duration : 2.0;
    return [0.08, 0.28, 0.5, 0.72, 0.92].take(count).map((pct) {
      final t = d * pct;
      final cap = d - 0.05 < 0 ? 0.0 : d - 0.05;
      return t < cap ? t : cap;
    }).toList();
  }

  /// `captureVideoFrames(file, 5)` - frames at 8/28/50/72/92 % of the duration,
  /// cover-scaled onto a 1620x2880 canvas and encoded as JPEG (q 0.92).
  static Future<List<Uint8List>> captureVideoFrames(String path, {int count = 5}) async {
    lastError = '';
    await _ensureTools();
    if (_ffmpeg != null) {
      try {
        final frames = await _framesViaFfmpeg(path, count);
        if (frames.isNotEmpty) return frames;
      } catch (e) {
        lastError = 'ffmpeg: $e';
      }
    } else {
      lastError = 'ffmpeg not found on this computer';
    }
    // Fallback: decode through media_kit (mpv) - always bundled with the app.
    final viaPlayer = await _framesViaMediaKit(path, count);
    if (viaPlayer.isNotEmpty) return viaPlayer;
    throw Exception(
      'Could not read frames from this video. ${lastError.isEmpty ? '' : '($lastError) '}'
      'Install ffmpeg and add it to PATH, or place ffmpeg.exe next to the app, then try again.',
    );
  }

  static Future<List<Uint8List>> _framesViaFfmpeg(String path, int count) async {
    final pr = await probe(path);
    final times = _frameTimes(pr?.durationSec ?? 0, count);
    const vf = 'scale=$kWallpaperWidth:$kWallpaperHeight:force_original_aspect_ratio=increase,crop=$kWallpaperWidth:$kWallpaperHeight';
    final frames = <Uint8List>[];
    final tmp = await Directory.systemTemp.createTemp('zedge_frames_');
    try {
      for (var i = 0; i < times.length; i++) {
        final out = p.join(tmp.path, 'frame_$i.jpg');
        // 1) fast seek, 2) accurate seek, 3) very first frame
        final attempts = <List<String>>[
          ['-y', '-ss', times[i].toStringAsFixed(3), '-i', path, '-frames:v', '1', '-vf', vf, '-q:v', '2', out],
          ['-y', '-i', path, '-ss', times[i].toStringAsFixed(3), '-frames:v', '1', '-vf', vf, '-q:v', '2', out],
          ['-y', '-i', path, '-frames:v', '1', '-vf', vf, '-q:v', '2', out],
        ];
        for (final args in attempts) {
          try {
            final r = await Process.run(_ffmpeg!, args);
            final f = File(out);
            if (r.exitCode == 0 && f.existsSync() && await f.length() > 0) {
              frames.add(await f.readAsBytes());
              break;
            }
            if (r.exitCode != 0) lastError = r.stderr.toString().trim().split('\n').last;
          } catch (e) {
            lastError = '$e';
          }
        }
      }
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
    return frames;
  }

  static Future<List<Uint8List>> _framesViaMediaKit(String path, int count) async {
    Player? player;
    try {
      player = Player();
      final controller = VideoController(player);
      await player.setVolume(0);
      await player.open(Media(path), play: false);
      await controller.waitUntilFirstFrameRendered.timeout(const Duration(seconds: 20), onTimeout: () {});
      var d = player.state.duration;
      if (d.inMilliseconds <= 0) {
        try {
          d = await player.stream.duration.firstWhere((x) => x > Duration.zero).timeout(const Duration(seconds: 8));
        } catch (_) {
          d = const Duration(seconds: 2);
        }
      }
      final out = <Uint8List>[];
      for (final t in _frameTimes(d.inMilliseconds / 1000, count)) {
        try {
          await player.seek(Duration(milliseconds: (t * 1000).round()));
          await Future<void>.delayed(const Duration(milliseconds: 350));
          final shot = await player.screenshot(format: 'image/jpeg');
          if (shot != null && shot.isNotEmpty) out.add(await resizeImageTo1620x2880(shot));
        } catch (e) {
          lastError = 'media_kit: $e';
        }
      }
      return out;
    } catch (e) {
      lastError = 'media_kit: $e';
      return const <Uint8List>[];
    } finally {
      try {
        await player?.dispose();
      } catch (_) {}
    }
  }
}
