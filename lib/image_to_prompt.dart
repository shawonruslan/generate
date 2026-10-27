import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'gemini_web.dart';

/// Prompt style for image -> prompt.
enum PromptStyle { detailed, concise, wallpaper }

class PromptStyles {
  static String label(PromptStyle s) => switch (s) {
        PromptStyle.detailed => 'Detailed',
        PromptStyle.concise => 'Concise',
        PromptStyle.wallpaper => 'Wallpaper',
      };

  static String instruction(PromptStyle s) => switch (s) {
        PromptStyle.detailed =>
          'Write it as one flowing paragraph of 70 to 130 words.',
        PromptStyle.concise =>
          'Keep it short: one line of 25 to 45 words.',
        PromptStyle.wallpaper =>
          'Write it as a portrait 9:16 phone wallpaper prompt of 60 to 110 '
              'words: one strong focal point, clean composition, quiet '
              'low-detail upper third for the clock, rich lighting.',
      };
}

/// A downloaded image ready for Gemini.
class PreparedImage {
  final Uint8List bytes;
  final String mime;
  final String fileName;
  const PreparedImage(this.bytes, this.mime, this.fileName);
}

/// Image -> text-to-image prompt through the Gemini web cookie session.
class ImageToPrompt {
  ImageToPrompt._();

  static final _complete = RegExp(r'\[/PROMPT\]', caseSensitive: false);

  static String buildInstruction(PromptStyle style) =>
      'You are an expert prompt engineer for AI image generators '
      '(Imagen, nano-banana, Flux, Midjourney). Study the attached image and '
      'write ONE text-to-image prompt that would recreate it as closely as '
      'possible. Cover the main subject and its details, setting and '
      'background, composition and framing, camera angle and lens, lighting, '
      'color palette, art style or medium, textures and mood. '
      '${PromptStyles.instruction(style)} '
      'Use English, descriptive comma-separated phrases. Do not describe or '
      'reproduce any visible text, logos, watermarks, UI elements or brand '
      'names, and do not say it is a screenshot or a web image. '
      'Reply with only the prompt, wrapped exactly like this: '
      '[PROMPT]your prompt here[/PROMPT]';

  /// Pulls the prompt out of Gemini's reply.
  static String parse(String reply) {
    final m = RegExp(r'\[PROMPT\]([\s\S]*?)\[/PROMPT\]', caseSensitive: false)
        .firstMatch(reply);
    var t = (m?.group(1) ?? reply).trim();
    t = t.replaceAll(RegExp(r'^```[a-z]*|```$'), '').trim();
    t = t.replaceAll(RegExp(r'^["“]+|["”]+$'), '').trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  static const _direct = {'image/jpeg', 'image/png', 'image/webp'};

  static String _sniffMime(Uint8List b, String fallback) {
    if (b.length > 12) {
      if (b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
      if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) return 'image/png';
      if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
      if (b[0] == 0x52 &&
          b[1] == 0x49 &&
          b[2] == 0x46 &&
          b[8] == 0x57 &&
          b[9] == 0x45) {
        return 'image/webp';
      }
      if (b[0] == 0x42 && b[1] == 0x4D) return 'image/bmp';
    }
    return fallback.split(';').first.trim().toLowerCase();
  }

  /// Turns raw bytes into something Gemini accepts: JPEG/PNG/WEBP pass
  /// through (downscaled when huge), GIF/BMP are re-encoded to JPEG.
  /// Returns null when the format cannot be decoded here (AVIF, SVG, ...),
  /// so the caller can fall back to the in-page canvas grab.
  static PreparedImage? prepare(Uint8List bytes, {String mimeHint = ''}) {
    if (bytes.length < 64) return null;
    final mime = _sniffMime(bytes, mimeHint);
    final tooBig = bytes.length > 6 * 1024 * 1024;
    if (_direct.contains(mime) && !tooBig) {
      final ext = mime == 'image/jpeg' ? 'jpg' : mime.split('/').last;
      return PreparedImage(bytes, mime, 'image.$ext');
    }
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      var out = decoded;
      const maxEdge = 2048;
      if (decoded.width > maxEdge || decoded.height > maxEdge) {
        out = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: maxEdge)
            : img.copyResize(decoded, height: maxEdge);
      }
      return PreparedImage(
          Uint8List.fromList(img.encodeJpg(out, quality: 92)),
          'image/jpeg',
          'image.jpg');
    } catch (_) {
      return null;
    }
  }

  /// Crops screenshot areas (CSS px rects [left, top, width, height] of a
  /// viewport [viewportW] CSS px wide) out of one WebView screenshot.
  /// Used for targeted / region capture and as a fallback for images the
  /// site refuses to hand over. Runs the decode once for every rect.
  static List<PreparedImage?> cropShots(
      Uint8List png, double viewportW, List<List<double>> rects) {
    final shot = img.decodeImage(png);
    if (shot == null) return List.filled(rects.length, null);
    final scale = viewportW > 0 ? shot.width / viewportW : 1.0;
    return rects.map((r) {
      if (r.length < 4) return null;
      final x0 = (r[0] * scale).round().clamp(0, shot.width);
      final y0 = (r[1] * scale).round().clamp(0, shot.height);
      final x1 = ((r[0] + r[2]) * scale).round().clamp(0, shot.width);
      final y1 = ((r[1] + r[3]) * scale).round().clamp(0, shot.height);
      if (x1 - x0 < 24 || y1 - y0 < 24) return null;
      final c = img.copyCrop(shot,
          x: x0, y: y0, width: x1 - x0, height: y1 - y0);
      return prepare(Uint8List.fromList(img.encodeJpg(c, quality: 92)),
          mimeHint: 'image/jpeg');
    }).toList();
  }

  /// Decodes a `data:image/...;base64,` URL.
  static PreparedImage? fromDataUrl(String dataUrl) {
    final m = RegExp(r'^data:([^;,]*)(;base64)?,(.*)$', dotAll: true)
        .firstMatch(dataUrl);
    if (m == null) return null;
    try {
      final bytes = m.group(2) != null
          ? base64Decode(m.group(3)!)
          : Uint8List.fromList(utf8.encode(Uri.decodeComponent(m.group(3)!)));
      return prepare(Uint8List.fromList(bytes), mimeHint: m.group(1) ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Downloads an image the way the page would (same Referer), so most
  /// hot-link protected CDNs still answer.
  static Future<PreparedImage?> download(String url, String pageUrl) async {
    if (url.startsWith('data:')) return fromDataUrl(url);
    if (!url.startsWith('http')) return null;
    for (final u in _candidates(url)) {
      // With and without the page as Referer: some CDNs need it, a few
      // (and Pinterest's pinimg for some pins) reject foreign referers.
      for (final withRef in [true, false]) {
        if (withRef && !pageUrl.startsWith('http')) continue;
        try {
          final res = await http.get(Uri.parse(u), headers: {
            'User-Agent': geminiWebUserAgent,
            // No AVIF: the app cannot decode it, so ask for classic formats.
            'Accept': 'image/webp,image/png,image/jpeg,image/*;q=0.8',
            if (withRef) 'Referer': pageUrl,
          }).timeout(const Duration(seconds: 45));
          if (res.statusCode != 200) continue;
          final img = prepare(res.bodyBytes,
              mimeHint: res.headers['content-type'] ?? '');
          if (img != null) return img;
        } catch (_) {}
      }
    }
    return null;
  }

  /// Pinterest renditions to try in order (736x always exists; originals
  /// can be missing or a GIF; 474x/236x are the last resort).
  static List<String> _candidates(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.host.endsWith('pinimg.com')) return [url];
    final re = RegExp(r'/(\d+x\d*(_RS)?|originals)/');
    if (!re.hasMatch(url)) return [url];
    final out = <String>[url];
    for (final size in ['736x', 'originals', '474x', '236x']) {
      final u = url.replaceFirst(re, '/$size/');
      if (!out.contains(u)) out.add(u);
    }
    return out;
  }

  static final _refusal = RegExp(
      r"(I can(no|')t help|I'm (not able|unable)|I am (not able|unable)|"
      r"can't (assist|help|describe)|cannot (assist|help|describe)|"
      r"I'm just a language model|not able to help with that|"
      r"can't process (images|that)|Sorry, I can)",
      caseSensitive: false);

  /// Softer second-try wording: Gemini web refuses some photos of people
  /// when the request sounds like identifying them.
  static String _safeInstruction(PromptStyle style) =>
      'Describe the visual style of the attached picture as an image '
      'generation prompt, as if an artist were recreating the scene with '
      'fictional, unidentified people. Do not identify anyone. Describe '
      'subject appearance in general terms, pose, clothing, setting, '
      'composition, camera angle, lighting, colors, art style and mood. '
      '${PromptStyles.instruction(style)} English, comma-separated '
      'phrases, no text or logos. Reply with only: [PROMPT]...[/PROMPT]';

  /// Image -> prompt. Throws [GeminiWebException] on failure.
  ///
  /// The reply is accepted even when Gemini forgets the [PROMPT] tags, as
  /// long as it is a real description; a refusal is retried once with a
  /// softer instruction instead of failing the image.
  static Future<String> generate({
    required GeminiWebClient web,
    required PreparedImage image,
    PromptStyle style = PromptStyle.detailed,
  }) async {
    String last = '';
    for (final instruction in [
      buildInstruction(style),
      _safeInstruction(style),
    ]) {
      final reply = await web.askWithImage(
        instruction,
        imageBytes: image.bytes,
        fileName: image.fileName,
        mime: image.mime,
      );
      last = reply;
      final tagged = _complete.hasMatch(reply);
      final prompt = _stripPreamble(parse(reply));
      final refused = !tagged && _refusal.hasMatch(reply);
      if (!refused && prompt.length >= (tagged ? 12 : 40)) return prompt;
    }
    final snip = last.replaceAll(RegExp(r'\s+'), ' ').trim();
    throw GeminiWebException(snip.isEmpty
        ? 'Gemini returned no usable prompt.'
        : 'Gemini declined this image: '
            '${snip.substring(0, snip.length.clamp(0, 120))}');
  }

  /// Drops a chatty first sentence ("Here is a prompt ...:").
  static String _stripPreamble(String t) {
    final m = RegExp(r"^(here('s| is)[^:]{0,80}:|sure[^:]{0,80}:|prompt:)\s*",
            caseSensitive: false)
        .firstMatch(t);
    return m == null ? t : t.substring(m.end).trim();
  }
}
