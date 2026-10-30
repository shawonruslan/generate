import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'secure_store.dart';
import 'browser/image_prompt_service.dart';
import 'cloudinary_api.dart';
import 'gemini_web.dart';
import 'local_image_server.dart';

/// Which service draws the pictures.
enum ImageEngineKind { cloudinary, gemini }

class ImageEngine {
  static ImageEngineKind kind = ImageEngineKind.cloudinary;
  static bool get isGemini => kind == ImageEngineKind.gemini;

  static Future<void> load() async {
    try {
      final p = await AppPrefs.prefs();
      kind = p.getString('image_engine') == 'gemini'
          ? ImageEngineKind.gemini
          : ImageEngineKind.cloudinary;
    } catch (_) {}
    if (isGemini) unawaited(LocalImageServer.instance.start());
  }

  static Future<void> set(ImageEngineKind k) async {
    kind = k;
    final p = await AppPrefs.prefs();
    await p.setString('image_engine', k.name);
    if (isGemini) await LocalImageServer.instance.start();
  }

  /// Generation API for the chosen engine (same calls for both).
  static CloudinaryApi api(CloudinaryCredentials creds) =>
      isGemini ? GeminiImageApi(creds) : CloudinaryApi(creds);
}

/// Image generation through the signed-in Gemini web session (no
/// Cloudinary): same calls as [CloudinaryApi], results are saved on the
/// device and served from http://127.0.0.1.
class GeminiImageApi extends CloudinaryApi {
  GeminiImageApi(super.creds);

  /// One Gemini conversation at a time (the web client is stateful).
  static Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() job) {
    final c = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await job());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  @override
  Future<GenerationResult> textToImage({
    required String prompt,
    required String modelId,
    required String aspectRatio,
    required String resolution,
    required String format,
    int? seed,
    void Function(String status)? onStatus,
    void Function(String status, Duration elapsed)? onProgress,
  }) =>
      _draw(prompt, const [], aspectRatio, resolution, format, seed,
          onProgress);

  @override
  Future<GenerationResult> imageToImage({
    required String prompt,
    String? modelId,
    required List<String> referenceUrls,
    required String aspectRatio,
    required String resolution,
    required String format,
    int? seed,
    void Function(String status)? onStatus,
    void Function(String status, Duration elapsed)? onProgress,
  }) =>
      _draw(prompt, referenceUrls, aspectRatio, resolution, format, seed,
          onProgress);

  /// "Upload" = keep it on the device.
  @override
  Future<String> uploadImage(List<int> bytes,
          {String folder = 'ais_references'}) =>
      LocalImageServer.instance.save(Uint8List.fromList(bytes));

  @override
  Future<bool> testConnection() async {
    final c = await ImagePromptService.instance.geminiClient();
    return (await c.test()).ok;
  }

  Future<GenerationResult> _draw(
    String prompt,
    List<String> refs,
    String aspectRatio,
    String resolution,
    String format,
    int? seed,
    void Function(String status, Duration elapsed)? onProgress,
  ) {
    final sw = Stopwatch()..start();
    onProgress?.call('pending', Duration.zero);
    return _serial(() async {
      final queued = sw.elapsed;
      final tick = Timer.periodic(const Duration(seconds: 1),
          (_) => onProgress?.call('processing', sw.elapsed));
      try {
        final svc = ImagePromptService.instance;
        await svc.load();
        final client = await svc.geminiClient();
        final files = <GeminiWebUpload>[];
        for (var i = 0; i < refs.length; i++) {
          final r = await http
              .get(Uri.parse(refs[i].trim()))
              .timeout(const Duration(seconds: 60));
          if (r.statusCode != 200) {
            throw GeminiWebException(
                'Reference image ${i + 1} could not be downloaded '
                '(HTTP ${r.statusCode}).');
          }
          files.add(await client.uploadImage(r.bodyBytes,
              filename: 'ref${i + 1}.jpg'));
        }
        final submit = sw.elapsed - queued;
        final out = await client.generateImages(
            geminiDrawPrompt(prompt, aspectRatio, refs.length),
            files: files);
        final raw = out.bytes ??
            await client.downloadGeneratedImage(out.urls.first,
                size: 4096); // largest the server has
        // Wallpaper deliverable: always JPG (1620x2880 for 9:16).
        final fitted = await fitToAspectInBackground(raw, aspectRatio, false);
        final bytes = fitted?.bytes ?? raw;
        final url = await LocalImageServer.instance
            .save(bytes, ext: 'jpg');
        sw.stop();
        return GenerationResult(
          imageUrl: url,
          width: fitted?.width ?? 0,
          height: fitted?.height ?? 0,
          bytes: bytes.length,
          format: 'jpg',
          modelId: 'gemini-web',
          seed: seed,
          requestId: 'gemini-${DateTime.now().millisecondsSinceEpoch}',
          quotaRemaining: null,
          quotaLimit: null,
          prompt: prompt,
          timing: GenerationTiming(
              submit: submit,
              queued: queued,
              render: sw.elapsed - queued - submit),
        );
      } finally {
        tick.cancel();
      }
    });
  }
}

/// Prompt sent to Gemini web: an explicit "draw" request (so Gemini
/// answers with an image, not text), the aspect ratio, and the
/// Cloudinary [n] reference syntax turned into "attached image n".
String geminiDrawPrompt(String prompt, String aspectRatio, int refCount) {
  var p = prompt.trim();
  if (refCount > 0) {
    p = p.replaceAllMapped(
        RegExp(r'\[(\d)\]'), (m) => 'attached image ${m.group(1)}');
  }
  final ar = aspectRatio.trim();
  final orient = _orientation(ar);
  final cartoonAsked = RegExp(
          r'cartoon|anime|chibi|comic|kawaii|pixel art|clip ?art|flat vector',
          caseSensitive: false)
      .hasMatch(p);
  final b = StringBuffer()
    ..write(refCount > 0
        ? 'Generate an image based on the attached '
            '${refCount == 1 ? 'image' : '$refCount images'}. '
        : 'Generate an image. ')
    ..write('Reply with the image only, no text and no questions. ');
  if (ar.isNotEmpty && ar != 'auto') {
    b.write('Compose natively for a $ar${orient.isEmpty ? '' : ' $orient'} '
        'frame filled edge to edge. ');
  }
  b
    ..write('\n\n')
    ..write(p)
    ..write('\n\nQUALITY: premium high-resolution wallpaper, tack-sharp focus '
        'on the main subject, crisp clean edges, rich fine detail and '
        'texture, professional lighting and colour grading, faithful to the '
        'style described above.\n')
    ..write('FRAMING: the whole main subject stays inside the frame with '
        'breathing room; nothing important touches or is cut by the edges.\n')
    ..write('AVOID: ')
    ..write(cartoonAsked ? '' : 'cartoonish or childish look, clip-art, ')
    ..write('blurry or soft focus, low resolution, pixelation, compression '
        'artifacts, noise, muddy or washed-out colours, oversaturation, '
        'plastic or waxy textures, distorted or duplicated subjects, cropped '
        'or cut-off subject, borders, frames, split panels, text, letters, '
        'watermark, signature, logo.');
  return b.toString();
}

String _orientation(String ar) {
  final f = _ratio(ar);
  if (f == null) return '';
  if ((f - 1).abs() < 0.02) return 'square';
  return f < 1 ? 'portrait' : 'landscape';
}

double? _ratio(String ar) {
  final m = RegExp(r'^(\d+(?:\.\d+)?)\s*[:x]\s*(\d+(?:\.\d+)?)$').firstMatch(ar);
  if (m == null) return null;
  final w = double.parse(m.group(1)!), h = double.parse(m.group(2)!);
  if (w <= 0 || h <= 0) return null;
  return w / h;
}

/// [fitToAspect] on a background isolate. Top-level on purpose: a
/// closure inside a method would capture that method's context (screen
/// state, futures, callbacks), which cannot be sent to an isolate.
Future<({Uint8List bytes, int width, int height})?> fitToAspectInBackground(
        Uint8List bytes, String aspectRatio, bool png) =>
    Isolate.run(() => fitToAspect(bytes, aspectRatio, png: png));

/// Long side of every Gemini picture after upscaling (9:16 -> 1620x2880).
const geminiLongSide = 2880;

/// Crops [bytes] to [aspectRatio] around the most detailed part of the
/// picture (not blindly the centre), upscales so the long side is
/// [longSide] (9:16 -> 1620x2880) with a light sharpen, and re-encodes.
/// Null when the picture cannot be read.
({Uint8List bytes, int width, int height})? fitToAspect(
    Uint8List bytes, String aspectRatio,
    {bool png = false, int longSide = geminiLongSide}) {
  final im = img.decodeImage(bytes);
  if (im == null) return null;
  final want = _ratio(aspectRatio.trim()) ?? im.width / im.height;
  var out = im;
  final have = im.width / im.height;
  if ((have - want).abs() / want > 0.01) {
    final cutWidth = have > want;
    final w = cutWidth ? (im.height * want).round() : im.width;
    final h = cutWidth ? im.height : (im.width / want).round();
    final off = cropOffset(im, cutWidth: cutWidth, window: cutWidth ? w : h);
    out = img.copyCrop(im,
        x: cutWidth ? off : 0, y: cutWidth ? 0 : off, width: w, height: h);
  }
  final tw = want >= 1 ? longSide : (longSide * want).round();
  final th = want >= 1 ? (longSide / want).round() : longSide;
  if (out.width != tw || out.height != th) {
    final up = out.width < tw;
    out = img.copyResize(out,
        width: tw, height: th, interpolation: img.Interpolation.cubic);
    if (up) {
      // Gentle unsharp after upscaling (keeps edges crisp, no halos).
      out = img.convolution(out,
          filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0], amount: 0.35);
    }
  }
  final enc = png ? img.encodePng(out) : img.encodeJpg(out, quality: 95);
  return (bytes: Uint8List.fromList(enc), width: out.width, height: out.height);
}

/// Best start (px) of a crop [window] along the cut axis: the position
/// holding the most edge detail (the subject), pulled slightly towards
/// the centre so plain scenes still crop centred.
int cropOffset(img.Image im, {required bool cutWidth, required int window}) {
  final full = cutWidth ? im.width : im.height;
  final slack = full - window;
  if (slack <= 0) return 0;
  const n = 96;
  final small = cutWidth
      ? img.copyResize(im, width: n, height: (n * im.height / im.width).round().clamp(8, 400))
      : img.copyResize(im, height: n, width: (n * im.width / im.height).round().clamp(8, 400));
  final prof = List<double>.filled(n, 0);
  for (var y = 1; y < small.height - 1; y++) {
    for (var x = 1; x < small.width - 1; x++) {
      final c = small.getPixel(x, y).luminance;
      final gx = (small.getPixel(x + 1, y).luminance - c).abs();
      final gy = (small.getPixel(x, y + 1).luminance - c).abs();
      prof[cutWidth ? x : y] += gx + gy;
    }
  }
  final win = (window / full * n).round().clamp(1, n);
  double sum = 0;
  for (var i = 0; i < win; i++) {
    sum += prof[i];
  }
  final total = prof.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return slack ~/ 2; // no detail anywhere: centre
  var best = 0, bestScore = -1.0;
  for (var i = 0; i + win <= n; i++) {
    if (i > 0) sum += prof[i + win - 1] - prof[i - 1];
    final centre = (n - win) / 2;
    final bias = total * 0.08 * (1 - ((i - centre).abs() / (centre == 0 ? 1 : centre)));
    final score = sum + bias;
    if (score > bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return (best / (n - win == 0 ? 1 : n - win) * slack).round().clamp(0, slack);
}
