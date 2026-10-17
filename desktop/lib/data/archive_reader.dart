import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// One file inside a ZIP / RAR archive (mirrors the web `{ name, size, data() }` entry).
class ArchiveEntry {
  ArchiveEntry({required this.name, required this.size, required Future<Uint8List> Function() loader}) : _loader = loader;

  /// Path inside the archive (forward slashes).
  final String name;
  final int size;
  final Future<Uint8List> Function() _loader;

  /// Set by the classifier - which archive this entry came from.
  String? zArchive;
  Uint8List? _cache;

  Future<Uint8List> data() async => _cache ??= await _loader();

  ArchiveEntry copyWithName(String newName) {
    final e = ArchiveEntry(name: newName, size: size, loader: _loader);
    e._cache = _cache;
    e.zArchive = zArchive;
    return e;
  }
}

String baseName(String path) => path.split('/').last;

bool isJunkPath(String path) {
  final b = baseName(path);
  return b.isEmpty || path.contains('__MACOSX/') || b.startsWith('.') || b.toLowerCase() == 'thumbs.db';
}

final RegExp kImgNameRe = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);
final RegExp kAudioNameRe = RegExp(r'\.mp3$', caseSensitive: false);
final RegExp kVideoNameRe = RegExp(r'\.(mp4|mov)$', caseSensitive: false);
final RegExp kDistMediaRe = RegExp(r'\.(jpe?g|png|webp|mp3|mp4|mov)$', caseSensitive: false);
final RegExp kArchiveNameRe = RegExp(r'\.(zip|rar)$', caseSensitive: false);

String guessMime(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
}

String distMime(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (ext == 'mp3') return 'audio/mpeg';
  if (ext == 'mp4') return 'video/mp4';
  if (ext == 'mov') return 'video/quicktime';
  return guessMime(name);
}

bool isArchiveFile(String name) => kArchiveNameRe.hasMatch(name);

/// Reads .zip (stored + deflate, zip64 aware through the `archive` package) and
/// .rar (via an external extractor - the browser used node-unrar-js wasm).
class ArchiveReader {
  static Future<List<ArchiveEntry>> readArchiveEntries(String filePath) async {
    final f = File(filePath);
    final raf = await f.open();
    Uint8List head;
    try {
      head = await raf.read(7);
    } finally {
      await raf.close();
    }
    final isRar = head.length >= 4 && head[0] == 0x52 && head[1] == 0x61 && head[2] == 0x72 && head[3] == 0x21;
    final isZip = head.length >= 2 && head[0] == 0x50 && head[1] == 0x4b;
    final name = p.basename(filePath);
    if (isRar || (!isZip && name.toLowerCase().endsWith('.rar'))) return _readRar(filePath);
    if (isZip || name.toLowerCase().endsWith('.zip')) return _readZip(await f.readAsBytes());
    throw Exception('Only .zip and .rar archives are supported');
  }

  static List<ArchiveEntry> _readZip(Uint8List bytes) {
    late Archive arc;
    try {
      arc = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (e) {
      throw Exception('Not a valid ZIP file');
    }
    final out = <ArchiveEntry>[];
    for (final af in arc.files) {
      if (!af.isFile) continue;
      final n = af.name;
      if (n.endsWith('/')) continue;
      out.add(ArchiveEntry(
        name: n,
        size: af.size,
        loader: () async {
          try {
            final c = af.content;
            if (c is Uint8List) return c;
            if (c is List<int>) return Uint8List.fromList(c);
            throw Exception('Corrupt ZIP entry: $n');
          } catch (e) {
            final msg = '$e';
            if (msg.toLowerCase().contains('encrypt') || msg.toLowerCase().contains('password')) {
              throw Exception('"$n" is password protected - encrypted ZIPs are not supported');
            }
            throw Exception('Unsupported compression in "$n" - re-zip with normal Deflate ($msg)');
          }
        },
      ));
    }
    return out;
  }

  /// RAR: extract with the first available CLI tool (unrar / 7z / bsdtar) into a temp dir.
  static Future<List<ArchiveEntry>> _readRar(String filePath) async {
    final tmp = await Directory.systemTemp.createTemp('zedge_rar_');
    final tool = await _findRarTool();
    if (tool == null) {
      throw Exception('RAR engine not available - install "unrar" (or 7-Zip / bsdtar) and make sure it is on PATH, or re-pack the archive as .zip');
    }
    ProcessResult res;
    switch (tool) {
      case 'unrar':
        res = await Process.run('unrar', ['x', '-y', '-o+', filePath, '${tmp.path}${Platform.pathSeparator}']);
        break;
      case '7z':
      case '7za':
      case '7zz':
        res = await Process.run(tool, ['x', '-y', '-o${tmp.path}', filePath]);
        break;
      default:
        res = await Process.run(tool, ['-xf', filePath, '-C', tmp.path]);
    }
    if (res.exitCode != 0) {
      throw Exception('RAR extraction failed (${res.exitCode}): ${(res.stderr ?? res.stdout).toString().trim()}');
    }
    final out = <ArchiveEntry>[];
    await for (final ent in tmp.list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final rel = p.relative(ent.path, from: tmp.path).replaceAll('\\', '/');
      final len = await ent.length();
      out.add(ArchiveEntry(name: rel, size: len, loader: () => ent.readAsBytes()));
    }
    return out;
  }

  static Future<String?> _findRarTool() async {
    for (final t in const ['unrar', '7z', '7za', '7zz', 'bsdtar']) {
      try {
        final r = await Process.run(Platform.isWindows ? 'where' : 'which', [t]);
        if (r.exitCode == 0 && r.stdout.toString().trim().isNotEmpty) return t;
      } catch (_) {}
    }
    return null;
  }
}
