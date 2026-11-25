import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gemini_web.dart';

/// Desktop port of Gemini HD Studio's headless image RPCs
/// (background.js: uploadImageToGeminiForImg2Img, callGeminiStreamGenerate,
/// fetchGeminiHdBlob). One upload + one StreamGenerate call, no polling.
class GeminiAttachment {
  final String uploadPath;
  final String mimeType;
  final String filename;
  final String? processFileUuid;

  const GeminiAttachment({
    required this.uploadPath,
    required this.mimeType,
    required this.filename,
    this.processFileUuid,
  });
}

class GeminiImageReply {
  final List<String> urls;
  final String text;
  const GeminiImageReply(this.urls, this.text);
}

class GeminiHdImage {
  final Uint8List bytes;
  final String mimeType;
  final String url;
  const GeminiHdImage(this.bytes, this.mimeType, this.url);

  String get ext => mimeType == 'image/png'
      ? 'png'
      : mimeType == 'image/webp'
          ? 'webp'
          : 'jpg';
}

class GeminiImageClient {
  GeminiImageClient(this.web);

  final GeminiWebClient web;

  static const _uploadHost = 'push.clients6.google.com';
  static const _uploadInit = 'https://$_uploadHost/upload/';
  static const _pushId = 'feeds/mcudyrk2a4khkz';
  static const _pctx = 'CgcSBWjK7pYx';
  static const _tenant = 'bard-storage';

  int _reqid = 100000 + Random().nextInt(800000);

  /// Signed-in accounts for failover (from GeminiAccounts / scan).
  List<GeminiAccount> accounts = [];

  /// Switch to the next account when one hits its image limit.
  bool autoSwitch = true;

  /// Called after an automatic account switch.
  void Function(String message)? onAccountSwitch;

  String get activeAccount {
    for (final a in accounts) {
      if (a.authUser == web.authUser) return a.label;
    }
    return web.email.isEmpty ? 'Account u/${web.authUser}' : web.email;
  }

  static bool isLimitError(Object e) =>
      e is GeminiWebException && isQuotaText(e.message);

  Future<bool> _switchNext(Set<int> tried) async {
    if (!autoSwitch || accounts.length < 2) return false;
    final i = accounts.indexWhere((a) => a.authUser == web.authUser);
    for (var k = 1; k < accounts.length; k++) {
      final next = accounts[(i + k) % accounts.length];
      if (tried.contains(next.authUser)) continue;
      final from = activeAccount;
      web.authUser = next.authUser;
      try {
        await web.init();
      } catch (_) {
        tried.add(next.authUser);
        continue;
      }
      onAccountSwitch?.call('$from hit its limit — switched to $activeAccount');
      return true;
    }
    return false;
  }

  /// Text/image-to-image with Gemini HD Studio's account failover: on a
  /// limit/quota reply the next signed-in account is used (the image is
  /// re-uploaded there, since uploads belong to one account).
  Future<GeminiImageReply> generateWithFailover(String prompt,
      {Uint8List? image,
      String filename = 'image.jpg',
      String? aspectRatio}) async {
    final tried = <int>{};
    while (true) {
      tried.add(web.authUser);
      try {
        final att =
            image == null ? null : await upload(image, filename: filename);
        return await generate(prompt, attachment: att, aspectRatio: aspectRatio);
      } catch (e) {
        if (!isLimitError(e) || !await _switchNext(tried)) rethrow;
      }
    }
  }

  static const imageToPromptInstruction =
      'Analyze this image and write ONE detailed text-to-image prompt that '
      'would recreate it: subject, composition, camera/lens, lighting, color '
      'palette, mood, art style, materials and fine details. Output only the '
      'prompt as a single paragraph, no preamble, no markdown, no quotes.';

  Future<void> _ensure() async {
    if (!web.ready) await web.init();
  }

  Uri _rpc(String method) =>
      Uri.parse('${web.rpcBase}/$method?${web.rpcQuery(_reqid += 100000)}');

  Map<String, String> _pushHeaders(Map<String, String> extra) {
    final h = web.requestHeaders();
    h.remove('X-Same-Domain');
    h['Cookie'] = web.session.cookieHeaderFor(_uploadHost);
    h['X-Goog-AuthUser'] = '${web.authUser}';
    h['Push-Id'] = _pushId;
    h['X-Client-Pctx'] = _pctx;
    h['X-Tenant-Id'] = _tenant;
    h['Sec-Fetch-Site'] = 'same-site';
    h.addAll(extra);
    return h;
  }

  /// Uploads an image to Gemini (bard-storage) for image-to-image or
  /// image-to-prompt. ~1–2 s in the HAR capture.
  Future<GeminiAttachment> upload(Uint8List bytes,
      {String filename = 'image.jpg', String? mimeType}) async {
    await _ensure();
    final mime = mimeType ?? _sniffMime(bytes);
    final start = await http
        .post(Uri.parse('$_uploadInit?authuser=${web.authUser}'),
            headers: _pushHeaders({
              'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
              'X-Goog-Upload-Command': 'start',
              'X-Goog-Upload-Header-Content-Length': '${bytes.length}',
              'X-Goog-Upload-Protocol': 'resumable',
            }),
            body: 'File name: $filename')
        .timeout(const Duration(seconds: 30));
    if (start.statusCode != 200) {
      throw GeminiWebException(
          'Gemini upload init failed (HTTP ${start.statusCode}).',
          expired: start.statusCode == 401 || start.statusCode == 403);
    }
    final rawUploadUrl = start.headers['x-goog-upload-url'] ??
        start.headers['x-goog-upload-control-url'];
    final uploadUri =
        rawUploadUrl == null ? null : Uri.tryParse(rawUploadUrl.trim());
    // Cookies are only ever sent back to the exact Google upload host.
    if (uploadUri == null ||
        uploadUri.scheme != 'https' ||
        uploadUri.host.toLowerCase() != _uploadHost) {
      throw GeminiWebException(
          'Gemini upload returned an unexpected upload URL.');
    }
    final fin = await http
        .post(uploadUri,
            headers: _pushHeaders({
              'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
              'X-Goog-Upload-Command': 'upload, finalize',
              'X-Goog-Upload-Offset': '0',
            }),
            body: bytes)
        .timeout(const Duration(seconds: 90));
    if (fin.statusCode != 200) {
      throw GeminiWebException(
          'Gemini image upload failed (HTTP ${fin.statusCode}).');
    }
    final path = fin.body.trim();
    if (!path.startsWith('/contrib_service/')) {
      throw GeminiWebException('Unexpected Gemini upload path.');
    }

    String? uuid;
    try {
      final inner = jsonEncode([
        [
          [path, null, 1, mime],
          filename, null, null, null, null, null, null, [0]
        ],
        null,
        1,
        ['en'],
      ]);
      final res = await http
          .post(_rpc('ProcessFile'),
              headers: web.requestHeaders(form: true),
              body: {'f.req': jsonEncode([null, inner]), 'at': web.atToken!})
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        uuid = RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-'
                r'[0-9a-f]{12}', caseSensitive: false)
            .firstMatch(res.body)
            ?.group(0);
      }
    } catch (_) {}

    return GeminiAttachment(
        uploadPath: path, mimeType: mime, filename: filename,
        processFileUuid: uuid);
  }

  List<dynamic> _wrap(List<dynamic> first, {bool extended = false}) {
    final inner = <dynamic>[
      first, ['en'], ['', '', ''], null, null, null, [1], 1, null, null, 1, 0,
    ];
    if (extended) {
      while (inner.length < 41) {
        inner.add(null);
      }
      inner.add([1]); // index 41
    }
    return inner;
  }

  List<List<dynamic>> _variants(String prompt, GeminiAttachment? a,
      String? aspectHint) {
    if (a == null) {
      return [_wrap([prompt, 0, null, null, null, null, 0])];
    }
    final desc1 = a.processFileUuid != null
        ? [a.uploadPath, 1, null, a.mimeType, a.processFileUuid]
        : [a.uploadPath, 1, null, a.mimeType];
    final att1 = [desc1, a.filename, null, null, null, null, null, null, [0]];
    final aspect = aspectHint == null
        ? null
        : [null, null, null, null, null, null, [null, [null, aspectHint]]];
    final first1 = aspect == null
        ? [prompt, 0, null, [att1], null, null, 0]
        : [prompt, 0, null, [att1], null, null, 0, null, null, aspect];
    final att2 = [
      [a.uploadPath, null, 1, a.mimeType],
      a.filename, null, null, null, null, null, null, [0]
    ];
    return [
      _wrap(first1, extended: true),
      _wrap([prompt, 0, null, [att2], null, null, 0]),
      _wrap([
        prompt, 0, null,
        [
          [[a.uploadPath], a.filename]
        ],
        null, null, 0
      ]),
    ];
  }

  Future<String> _post(List<dynamic> inner, Duration timeout) async {
    await _ensure();
    final body = {
      'f.req': jsonEncode([null, jsonEncode(inner)]),
      'at': web.atToken!,
    };
    var res = await http
        .post(_rpc('StreamGenerate'),
            headers: web.requestHeaders(form: true), body: body)
        .timeout(timeout);
    if (res.statusCode == 400 || res.statusCode == 401 ||
        res.statusCode == 403) {
      await web.init(); // token rotated
      body['at'] = web.atToken!;
      res = await http
          .post(_rpc('StreamGenerate'),
              headers: web.requestHeaders(form: true), body: body)
          .timeout(timeout);
    }
    if (res.statusCode == 429 || res.statusCode == 503) {
      throw GeminiWebException(
          'Gemini is rate limiting this account (HTTP ${res.statusCode}).');
    }
    if (res.statusCode != 200) {
      throw GeminiWebException('Gemini StreamGenerate HTTP ${res.statusCode}.',
          expired: res.statusCode == 401 || res.statusCode == 403);
    }
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  /// Text-to-image (no attachment) or image-to-image (with [attachment]).
  Future<GeminiImageReply> generate(String prompt,
      {GeminiAttachment? attachment,
      String? aspectRatio,
      Duration timeout = const Duration(seconds: 150)}) async {
    final p = buildImagePrompt(prompt, aspectRatio);
    var last = const GeminiImageReply([], '');
    Object? lastErr;
    for (final v in _variants(p, attachment, aspectRatio)) {
      try {
        final parsed = parseStream(await _post(v, timeout));
        if (parsed.urls.isNotEmpty) return parsed;
        last = parsed;
        if (isQuotaText(parsed.text)) break;
      } on GeminiWebException catch (e) {
        lastErr = e;
        if (e.expired) rethrow;
      } on TimeoutException {
        lastErr = 'Gemini timed out after ${timeout.inSeconds}s.';
      }
    }
    if (last.text.isNotEmpty) {
      throw GeminiWebException('Gemini returned no image: '
          '${last.text.length > 240 ? last.text.substring(0, 240) : last.text}');
    }
    throw GeminiWebException('Gemini returned no image. ${lastErr ?? ''}');
  }

  /// Image-to-prompt: upload + one Gemini call (no image model, no polling).
  Future<String> imageToPrompt(Uint8List bytes,
      {String filename = 'image.jpg', String? extra}) async {
    final a = await upload(bytes, filename: filename);
    final ask = extra == null || extra.trim().isEmpty
        ? imageToPromptInstruction
        : '$imageToPromptInstruction\nAlso: ${extra.trim()}';
    Object? lastErr;
    for (final v in _variants(ask, a, null)) {
      try {
        final t = parseStream(await _post(v, const Duration(seconds: 90)))
            .text
            .trim();
        if (t.isNotEmpty) return cleanPrompt(t);
      } on GeminiWebException catch (e) {
        lastErr = e;
        if (e.expired) rethrow;
      } on TimeoutException {
        lastErr = 'timeout';
      }
    }
    throw GeminiWebException('Image to prompt failed. ${lastErr ?? ''}');
  }

  /// Downloads the full-resolution (=s0) image Gemini produced.
  Future<GeminiHdImage> fetchHd(String baseUrl) async {
    var url = toHdUrl(baseUrl);
    for (var hop = 0; hop < 4; hop++) {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' ||
          !GeminiWebSession.isAllowedGeminiHost(uri.host)) {
        throw GeminiWebException('Refusing non-Google image host ${uri.host}.');
      }
      final res = await http.get(uri, headers: {
        'User-Agent': geminiWebUserAgent,
        'Cookie': web.session.cookieHeaderFor(uri.host),
        'Origin': 'https://gemini.google.com',
        'Referer': 'https://gemini.google.com/',
      }).timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        throw GeminiWebException('Gemini HD fetch HTTP ${res.statusCode}.');
      }
      final type = (res.headers['content-type'] ?? '').toLowerCase();
      if (type.contains('text/plain')) {
        final next = res.body.trim();
        if (next.startsWith('https://')) {
          url = toHdUrl(next);
          continue;
        }
        throw GeminiWebException('Unexpected text reply for Gemini image.');
      }
      final mime = type.contains('png')
          ? 'image/png'
          : type.contains('webp')
              ? 'image/webp'
              : 'image/jpeg';
      return GeminiHdImage(res.bodyBytes, mime, url);
    }
    throw GeminiWebException('Too many redirects fetching Gemini image.');
  }

  // ---------------------------------------------------------------- helpers

  static String toHdUrl(String u) =>
      '${u.replaceAll(RegExp(r'\?.*$'), '').replaceAll(RegExp(r'=[a-zA-Z0-9\-_]+$'), '')}=s0';

  static String buildImagePrompt(String raw, String? aspect) {
    var p = raw.trim();
    final hasVerb = RegExp(
            r'^(generate|create|draw|make|paint|render|design)\s+(an?\s+)?'
            r'(image|picture|photo|illustration|art|wallpaper)',
            caseSensitive: false)
        .hasMatch(p);
    if (!hasVerb) p = 'Generate an image of: $p';
    if (aspect != null && aspect != 'auto' &&
        !p.toLowerCase().contains('aspect ratio')) {
      p = '$p (aspect ratio $aspect)';
    }
    return p;
  }

  static bool isQuotaText(String t) {
    final s = t.toLowerCase();
    return const [
      'reached your limit', 'rate limit', 'quota', 'too many requests',
      'try again later', 'cannot generate more', 'can not generate more',
      'limit for generating images', 'create more images tomorrow',
      'high demand',
    ].any(s.contains);
  }

  static String cleanPrompt(String t) => t
      .replaceAll(RegExp(r'^```[a-z]*\s*|\s*```$'), '')
      .replaceAll(RegExp(r'^(prompt|here is[^:]*):\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'^["“]|["”]$'), '')
      .trim();

  static String _sniffMime(Uint8List b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  static final _imgUrl = RegExp(
      r'https://(?:lh3\.googleusercontent\.com|[a-zA-Z0-9\-]+\.fife\.usercontent\.google\.com)/[a-zA-Z0-9_\-/=+%]+');

  static void _collect(dynamic node, Set<String> out) {
    if (node is String) {
      for (final m in _imgUrl.allMatches(node)) {
        final u = m.group(0)!;
        if (!u.contains('/a/') && !u.contains('/a-/') && u.length > 48) {
          out.add(u);
        }
      }
      final t = node.trim();
      if ((t.startsWith('[') && t.endsWith(']')) ||
          (t.startsWith('{') && t.endsWith('}'))) {
        try {
          _collect(jsonDecode(t), out);
        } catch (_) {}
      }
    } else if (node is List) {
      for (final e in node) {
        _collect(e, out);
      }
    } else if (node is Map) {
      for (final e in node.values) {
        _collect(e, out);
      }
    }
  }

  /// Port of parseStreamGenerateResponse(): image URLs + answer text.
  static GeminiImageReply parseStream(String raw) {
    final cand = <String>{};
    final fallback = <String>{};
    var text = '';
    for (final line in LineSplitter.split(raw)) {
      final t = line.trim();
      if (!t.startsWith('[')) continue;
      dynamic outer;
      try {
        outer = jsonDecode(t);
      } catch (_) {
        continue;
      }
      _collect(outer, fallback);
      if (outer is! List) continue;
      for (final e in outer) {
        if (e is List && e.length > 2 && e[0] == 'wrb.fr' && e[2] is String) {
          try {
            final inner = jsonDecode(e[2] as String);
            if (inner is List && inner.length > 4 && inner[4] is List) {
              _collect(inner[4], cand);
              final c0 = (inner[4] as List).isNotEmpty ? inner[4][0] : null;
              if (c0 is List && c0.length > 1 && c0[1] is List &&
                  (c0[1] as List).isNotEmpty && c0[1][0] is String) {
                final s = c0[1][0] as String;
                if (s.trim().length >= text.trim().length) text = s;
              }
            }
          } catch (_) {}
        }
      }
    }
    final unescaped = raw
        .replaceAll(r'\u003d', '=')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\/', '/');
    for (final m in RegExp(
            r'https://(?:lh3\.googleusercontent\.com|[a-zA-Z0-9\-]+\.fife\.usercontent\.google\.com)/(?:gg-dl|rd-gg-dl|gg)/[a-zA-Z0-9_\-/=+%]+')
        .allMatches(unescaped)) {
      fallback.add(m.group(0)!);
    }
    final src = cand.isNotEmpty ? cand : fallback;
    final byBase = <String, String>{};
    for (final u in src) {
      final clean =
          u.replaceAll(RegExp(r'''["'\\]+$'''), '').replaceAll(RegExp(r'\?.*$'), '');
      byBase[clean.replaceAll(RegExp(r'=[a-zA-Z0-9\-_]+$'), '')] = clean;
    }
    return GeminiImageReply(byBase.keys.toList(), text);
  }
}
