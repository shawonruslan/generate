import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Serves images made on this device (Gemini web engine) over
/// http://127.0.0.1 so every screen that shows / downloads / shares an
/// image URL keeps working exactly like with Cloudinary URLs.
class LocalImageServer {
  LocalImageServer._();
  static final LocalImageServer instance = LocalImageServer._();

  /// Fixed port so saved history links stay valid after a restart.
  static const preferredPort = 47823;

  HttpServer? _server;
  Directory? _dir;
  Future<void>? _starting;

  int get port => _server?.port ?? preferredPort;

  Future<Directory> _folder() async {
    final have = _dir;
    if (have != null) return have;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}gemini_images');
    await d.create(recursive: true);
    return _dir = d;
  }

  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    final dir = await _folder();
    HttpServer s;
    try {
      s = await HttpServer.bind(InternetAddress.loopbackIPv4, preferredPort,
          shared: true);
    } catch (_) {
      s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    _server = s;
    s.listen((req) async {
      final res = req.response;
      try {
        final seg = req.uri.pathSegments;
        if (seg.length == 2 && seg[0] == 'g' && _safe.hasMatch(seg[1])) {
          final f = File('${dir.path}${Platform.pathSeparator}${seg[1]}');
          if (await f.exists()) {
            final fill = RegExp(r'^(\d{2,5})x(\d{2,5})$')
                .firstMatch(req.uri.queryParameters['fill'] ?? '');
            final jpg = req.uri.queryParameters['f'] == 'jpg';
            res.headers
              ..contentType = seg[1].endsWith('.png') && !jpg
                  ? ContentType('image', 'png')
                  : ContentType('image', 'jpeg')
              ..set('Access-Control-Allow-Origin', '*')
              ..set('Cache-Control', 'max-age=31536000');
            if (fill != null) {
              final w = int.parse(fill.group(1)!), h = int.parse(fill.group(2)!);
              final src = await f.readAsBytes();
              final out = await Isolate.run(
                  () => fillCrop(src, w, h, jpg: jpg || !seg[1].endsWith('.png')));
              if (out != null) {
                res.add(out);
                await res.close();
                return;
              }
            }
            await res.addStream(f.openRead());
            await res.close();
            return;
          }
        }
        res.statusCode = HttpStatus.notFound;
        await res.close();
      } catch (_) {
        try {
          await res.close();
        } catch (_) {}
      }
    });
  }

  static final RegExp _safe = RegExp(r'^[A-Za-z0-9_-]+\.(jpg|png)$');

  /// Stores [bytes] and returns its http://127.0.0.1 link.
  Future<String> save(Uint8List bytes, {String ext = 'jpg'}) async {
    await start();
    final dir = await _folder();
    final name = 'g_${DateTime.now().millisecondsSinceEpoch}_'
        '${Random().nextInt(1 << 30).toRadixString(36)}.$ext';
    await File('${dir.path}${Platform.pathSeparator}$name')
        .writeAsBytes(bytes, flush: true);
    return 'http://127.0.0.1:$port/g/$name';
  }

  static bool isLocal(String url) => url.startsWith('http://127.0.0.1:');
}

/// Cloudinary-style c_fill: scale to cover [w]x[h], centre-crop.
Uint8List? fillCrop(Uint8List bytes, int w, int h, {bool jpg = true}) {
  final im = img.decodeImage(bytes);
  if (im == null) return null;
  final scale = (w / im.width) > (h / im.height)
      ? w / im.width
      : h / im.height;
  final sw = (im.width * scale).ceil(), sh = (im.height * scale).ceil();
  final scaled = img.copyResize(im,
      width: sw, height: sh, interpolation: img.Interpolation.cubic);
  final out = img.copyCrop(scaled,
      x: (sw - w) ~/ 2, y: (sh - h) ~/ 2, width: w, height: h);
  return Uint8List.fromList(
      jpg ? img.encodeJpg(out, quality: 100) : img.encodePng(out));
}
