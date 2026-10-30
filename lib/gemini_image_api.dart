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
                size: resolution.toLowerCase().contains('4k') ? 4096 : 2048);
        final png = format.toLowerCase() == 'png';
        final fitted =
            await Isolate.run(() => fitToAspect(raw, aspectRatio, png: png));
        final bytes = fitted?.bytes ?? raw;
        final url = await LocalImageServer.instance
            .save(bytes, ext: png ? 'png' : 'jpg');
        sw.stop();
        return GenerationResult(
          imageUrl: url,
          width: fitted?.width ?? 0,
          height: fitted?.height ?? 0,
          bytes: bytes.length,
          format: png ? 'png' : 'jpg',
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
  final b = StringBuffer()
    ..write(refCount > 0
        ? 'Generate an image based on the attached '
            '${refCount == 1 ? 'image' : '$refCount images'}. '
        : 'Generate an image. ')
    ..write('Reply with the image only, no text and no questions. ');
  if (ar.isNotEmpty && ar != 'auto') {
    b.write('Aspect ratio $ar${orient.isEmpty ? '' : ' ($orient)'}. ');
  }
  b.write('No watermark, no text or logos unless the prompt asks for them.\n\n');
  b.write(p);
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

/// Centre-crops [bytes] to [aspectRatio] (Gemini does not always follow
/// it exactly) and re-encodes. Null when the picture cannot be read.
({Uint8List bytes, int width, int height})? fitToAspect(
    Uint8List bytes, String aspectRatio,
    {bool png = false}) {
  final im = img.decodeImage(bytes);
  if (im == null) return null;
  final want = _ratio(aspectRatio.trim());
  var out = im;
  if (want != null) {
    final have = im.width / im.height;
    if ((have - want).abs() / want > 0.01) {
      var w = im.width, h = im.height;
      if (have > want) {
        w = (h * want).round();
      } else {
        h = (w / want).round();
      }
      out = img.copyCrop(im,
          x: (im.width - w) ~/ 2, y: (im.height - h) ~/ 2, width: w, height: h);
    }
  }
  final enc = png ? img.encodePng(out) : img.encodeJpg(out, quality: 95);
  return (bytes: Uint8List.fromList(enc), width: out.width, height: out.height);
}
