import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;

/// Cloudinary account credentials used for the Image Generation API.
class CloudinaryCredentials {
  final String cloudName;
  final String apiKey;
  final String apiSecret;

  const CloudinaryCredentials({
    required this.cloudName,
    required this.apiKey,
    required this.apiSecret,
  });

  bool get isComplete =>
      cloudName.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      apiSecret.trim().isNotEmpty;
}

/// A finished generation.
class GenerationResult {
  final String imageUrl;
  final int width;
  final int height;
  final int bytes;
  final String format;
  final String modelId;
  final int? seed;
  final String requestId;
  final int? quotaRemaining;
  final int? quotaLimit;
  final String prompt;

  /// Where the time went (null for results restored from history).
  final GenerationTiming? timing;

  const GenerationResult({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.bytes,
    required this.format,
    required this.modelId,
    required this.seed,
    required this.requestId,
    required this.quotaRemaining,
    required this.quotaLimit,
    required this.prompt,
    this.timing,
  });

  /// Same result pointing at a processed copy (e.g. colour-matched).
  GenerationResult withImage(String url, int size) => GenerationResult(
        imageUrl: url,
        width: width,
        height: height,
        bytes: size,
        format: 'jpg',
        modelId: modelId,
        seed: seed,
        requestId: requestId,
        quotaRemaining: quotaRemaining,
        quotaLimit: quotaLimit,
        prompt: prompt,
        timing: timing,
      );

  GenerationResult withTiming(GenerationTiming t) => GenerationResult(
        imageUrl: imageUrl,
        width: width,
        height: height,
        bytes: bytes,
        format: format,
        modelId: modelId,
        seed: seed,
        requestId: requestId,
        quotaRemaining: quotaRemaining,
        quotaLimit: quotaLimit,
        prompt: prompt,
        timing: t,
      );
}

/// Time split of one generation: upload of the request, waiting in
/// Cloudinary's queue, and the model actually rendering.
class GenerationTiming {
  const GenerationTiming(
      {required this.submit, required this.queued, required this.render});
  final Duration submit;
  final Duration queued;
  final Duration render;
  Duration get total => submit + queued + render;

  static String fmt(Duration d) {
    final s = d.inMilliseconds / 1000;
    if (s < 60) return '${s.toStringAsFixed(s < 10 ? 1 : 0)}s';
    return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  }

  /// e.g. "24s total - queue 9s - render 14s".
  String get summary =>
      '${fmt(total)} total - queue ${fmt(queued)} - render ${fmt(render)}';
}

/// Typed API failure carrying the Cloudinary error envelope.
class CloudinaryApiException implements Exception {
  final String category;
  final String code;
  final String message;

  const CloudinaryApiException({
    required this.category,
    required this.code,
    required this.message,
  });

  /// True when the failure is rate limiting (HTTP 429 / "too many
  /// requests"): the request may succeed if retried after a wait.
  bool get isRateLimited {
    final c = code.toUpperCase();
    final m = message.toLowerCase();
    final cat = category.toLowerCase();
    return c.contains('429') ||
        c.contains('RATE_LIMIT') ||
        cat.contains('rate') ||
        m.contains('rate limit') ||
        m.contains('too many requests');
  }

  @override
  String toString() => message;
}

/// Thin client for the Cloudinary Image Generation REST API
/// (https://api.cloudinary.com/v2/generate/{cloud}/...).
class CloudinaryApi {
  CloudinaryApi(this.creds);

  final CloudinaryCredentials creds;

  static const _base = 'https://api.cloudinary.com/v2';

  Map<String, String> get _headers => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${creds.apiKey.trim()}:${creds.apiSecret.trim()}'))}',
        'Content-Type': 'application/json',
      };

  String get _cloud => creds.cloudName.trim();

  Future<GenerationResult> textToImage({
    required String prompt,
    required String modelId,
    required String aspectRatio,
    required String resolution,
    required String format,
    int? seed,
    void Function(String status)? onStatus,
    void Function(String status, Duration elapsed)? onProgress,
  }) {
    return _generate(
      '/generate/$_cloud/text_to_image',
      {
        'prompt': prompt,
        'model': {'id': modelId},
        'image_size': {'aspect_ratio': aspectRatio, 'resolution': resolution},
        'format': format,
        if (seed != null) 'seed': seed,
        'target': {'target_type': 'managed_asset'},
        'async': true,
      },
      prompt: prompt,
      onStatus: onStatus,
      onProgress: onProgress,
    );
  }

  Future<GenerationResult> imageToImage({
    required String prompt,
    String? modelId, // null -> {"mode": "auto"} (always resolves to an edit model)
    required List<String> referenceUrls,
    required String aspectRatio,
    required String resolution,
    required String format,
    int? seed,
    void Function(String status)? onStatus,
    void Function(String status, Duration elapsed)? onProgress,
  }) {
    return _generate(
      '/generate/$_cloud/image_to_image',
      {
        'prompt': prompt,
        'model': modelId == null ? {'mode': 'auto'} : {'id': modelId},
        'reference_images': [
          for (final u in referenceUrls)
            {'source_type': 'url', 'url': u.trim()}
        ],
        'image_size': {'aspect_ratio': aspectRatio, 'resolution': resolution},
        'format': format,
        if (seed != null) 'seed': seed,
        'target': {'target_type': 'managed_asset'},
        'async': true,
      },
      prompt: prompt,
      onStatus: onStatus,
      onProgress: onProgress,
    );
  }

  /// Signed upload of a local picture (e.g. an Image to Prompt
  /// reference) so it can be used as an image_to_image base. Returns the
  /// secure URL.
  Future<String> uploadImage(List<int> bytes,
      {String folder = 'ais_references'}) async {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final sig = sha1
        .convert(utf8.encode(
            'folder=$folder&timestamp=$ts${creds.apiSecret.trim()}'))
        .toString();
    final req = http.MultipartRequest('POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$_cloud/image/upload'))
      ..fields.addAll({
        'api_key': creds.apiKey.trim(),
        'timestamp': ts,
        'folder': folder,
        'signature': sig,
      })
      ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: 'ref.jpg'));
    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 90)));
    final j = res.body.isEmpty ? null : jsonDecode(res.body);
    final url = j is Map ? (j['secure_url'] ?? j['url'])?.toString() : null;
    if (res.statusCode != 200 || url == null || url.isEmpty) {
      final msg = j is Map && j['error'] is Map
          ? '${(j['error'] as Map)['message']}'
          : 'HTTP ${res.statusCode}';
      throw CloudinaryApiException(
          category: 'upload_error',
          code: 'UPLOAD_${res.statusCode}',
          message: 'Reference upload failed: $msg');
    }
    return url;
  }

  Future<GenerationResult> _generate(
    String path,
    Map<String, dynamic> body, {
    required String prompt,
    void Function(String status)? onStatus,
    void Function(String status, Duration elapsed)? onProgress,
  }) async {
    final started = DateTime.now();
    http.Response res;
    try {
      res = await http
          .post(Uri.parse('$_base$path'),
              headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const CloudinaryApiException(
        category: 'network_error',
        code: 'TIMEOUT',
        message: 'Request timed out. Check your connection and try again.',
      );
    } catch (e) {
      throw CloudinaryApiException(
        category: 'network_error',
        code: 'CONNECTION_FAILED',
        message: 'Could not reach the Cloudinary API: $e',
      );
    }

    if (res.statusCode == 202) {
      final decoded = _decode(res);
      final taskId =
          ((decoded['data'] as Map?)?['task_id'])?.toString() ?? '';
      if (taskId.isEmpty) {
        throw const CloudinaryApiException(
          category: 'server_error',
          code: 'NO_TASK_ID',
          message:
              'The API accepted the request but returned no task id. Try again.',
        );
      }
      final submitted = DateTime.now();
      DateTime? renderStart;
      final r = await _pollTask(taskId, prompt: prompt, onStatus: (st) {
        if (st == 'processing') renderStart ??= DateTime.now();
        final t = DateTime.now().difference(started);
        onStatus?.call(st);
        onProgress?.call(st, t);
      });
      final end = DateTime.now();
      final rs = renderStart ?? submitted;
      return r.withTiming(GenerationTiming(
        submit: submitted.difference(started),
        queued: rs.difference(submitted),
        render: end.difference(rs),
      ));
    }
    if (res.statusCode == 200) {
      final d = DateTime.now().difference(started);
      return _parseResult(_decode(res), prompt: prompt).withTiming(
          GenerationTiming(submit: Duration.zero, queued: Duration.zero, render: d));
    }
    throw _parseError(res);
  }

  Future<GenerationResult> _pollTask(
    String taskId, {
    required String prompt,
    void Function(String status)? onStatus,
  }) async {
    final url = Uri.parse('$_base/generate/$_cloud/tasks/$taskId');
    // Only answered polls count. Connection drops (phone asleep, Wi-Fi
    // switching, server hiccups) are waited out for up to 10 minutes, so a
    // task that is already running on Cloudinary is not thrown away.
    var polls = 0;
    DateTime? failingSince;
    bool stillFailing() {
      final now = DateTime.now();
      failingSince ??= now;
      return now.difference(failingSince!) < const Duration(minutes: 10);
    }

    // Adaptive polling: fast at first (most images finish in 5-30 s, so a
    // fixed 3 s step wasted ~1.5 s per image), slower for long jobs.
    // Same overall limit as before (about 7.5 minutes of answered polls).
    final begin = DateTime.now();
    while (polls < 400 &&
        DateTime.now().difference(begin) < const Duration(minutes: 8)) {
      final waited = DateTime.now().difference(begin).inSeconds;
      await Future<void>.delayed(Duration(
          milliseconds: polls == 0
              ? 1200
              : waited < 30
                  ? 1500
                  : waited < 90
                      ? 2500
                      : 4000));
      http.Response res;
      try {
        res = await http
            .get(url, headers: _headers)
            .timeout(const Duration(seconds: 30));
      } catch (_) {
        if (stillFailing()) continue; // transient - keep polling
        throw const CloudinaryApiException(
          category: 'network_error',
          code: 'POLL_CONNECTION_LOST',
          message: 'Lost the connection while waiting for the result.',
        );
      }
      if (res.statusCode == 429 || res.statusCode >= 500) {
        if (stillFailing()) continue;
        throw _parseError(res);
      }
      failingSince = null;
      polls++;
      if (res.statusCode != 200) throw _parseError(res);
      final data = (_decode(res)['data'] as Map?) ?? {};
      final status = data['status']?.toString() ?? 'processing';
      onStatus?.call(status);
      if (status == 'completed') {
        return _parseResult(_decode(res), prompt: prompt);
      }
      if (status == 'failed') {
        throw const CloudinaryApiException(
          category: 'server_error',
          code: 'TASK_FAILED',
          message:
              'The generation task failed on Cloudinary\'s side. Try again or pick another model.',
        );
      }
    }
    throw const CloudinaryApiException(
      category: 'server_error',
      code: 'POLL_TIMEOUT',
      message:
          'Timed out waiting for the result. The image may still finish - check your Cloudinary Media Library.',
    );
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw CloudinaryApiException(
        category: 'server_error',
        code: 'BAD_RESPONSE',
        message:
            'Unexpected response from the API (HTTP ${res.statusCode}).',
      );
    }
  }

  GenerationResult _parseResult(Map<String, dynamic> json,
      {required String prompt}) {
    try {
      final data = json['data'] as Map<String, dynamic>? ?? {};
      // Sync responses carry the asset directly under `data`, but async
      // task results nest it under `data.result` (per the API docs).
      final result =
          (data['result'] as Map<String, dynamic>?) ?? data;
      final assets = result['assets'] as List?;
      if (assets == null || assets.isEmpty) {
        throw 'no assets in response '
            '(top-level keys: ${result.keys.join(', ')})';
      }
      final asset = assets.first as Map<String, dynamic>;
      final storage = asset['storage'] as Map<String, dynamic>? ?? {};
      final secureUrl = storage['secure_url']?.toString() ?? '';
      if (secureUrl.isEmpty) {
        throw 'asset has no secure_url '
            '(asset keys: ${asset.keys.join(', ')})';
      }
      final model = (asset['model'] as Map?) ?? {};
      int? remaining;
      int? limit;
      final quotas =
          (result['limits'] as Map?)?['addons_quota'] as List?;
      if (quotas != null) {
        for (final q in quotas) {
          final m = q as Map;
          if (m['type'] == 'image_generation') {
            remaining = (m['remaining'] as num?)?.toInt();
            limit = (m['limit'] as num?)?.toInt();
          }
        }
      }
      return GenerationResult(
        imageUrl: secureUrl,
        width: (asset['width'] as num?)?.toInt() ?? 0,
        height: (asset['height'] as num?)?.toInt() ?? 0,
        bytes: (asset['bytes'] as num?)?.toInt() ?? 0,
        format: asset['format']?.toString() ?? '',
        modelId: model['id']?.toString() ?? '',
        seed: (asset['seed'] as num?)?.toInt(),
        requestId: json['request_id']?.toString() ?? '',
        quotaRemaining: remaining,
        quotaLimit: limit,
        prompt: prompt,
      );
    } catch (e) {
      throw CloudinaryApiException(
        category: 'server_error',
        code: 'PARSE_ERROR',
        message: 'Could not understand the API response: $e',
      );
    }
  }

  CloudinaryApiException _parseError(http.Response res) {
    try {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final err = decoded['error'] as Map<String, dynamic>;
      return CloudinaryApiException(
        category: err['category']?.toString() ?? 'unknown',
        code: err['code']?.toString() ?? 'HTTP_${res.statusCode}',
        message: err['message']?.toString() ??
            'Request failed (HTTP ${res.statusCode}).',
      );
    } catch (_) {
      final body = res.body;
      return CloudinaryApiException(
        category: 'http_error',
        code: 'HTTP_${res.statusCode}',
        message: body.isEmpty
            ? 'Request failed (HTTP ${res.statusCode}).'
            : (body.length > 280 ? '${body.substring(0, 280)}...' : body),
      );
    }
  }

  /// Validates the credentials without spending generation quota, via the
  /// Admin API usage endpoint (HTTP 200 = credentials accepted).
  Future<bool> testConnection() async {
    final url = Uri.parse('https://api.cloudinary.com/v1_1/$_cloud/usage');
    try {
      final res = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

/// Inserts a Cloudinary delivery transformation into a secure delivery URL.
/// Example: transformImageUrl(url, 'w_1620,h_2880,c_fill/f_jpg,q_100')
String transformImageUrl(String secureUrl, String transformation) {
  const marker = '/image/upload/';
  final i = secureUrl.indexOf(marker);
  if (i < 0) return secureUrl;
  final at = i + marker.length;
  return '${secureUrl.substring(0, at)}$transformation/${secureUrl.substring(at)}';
}

/// Export presets: how the final image is delivered / saved.
class ExportPreset {
  final String label;
  final String? transformation;

  const ExportPreset(this.label, this.transformation);

  bool get isJpg => transformation?.contains('f_jpg') ?? false;
}

class ExportPresets {
  static const List<ExportPreset> all = [
    ExportPreset('Original', null),
    ExportPreset('1620x2880 JPG', 'w_1620,h_2880,c_fill/f_jpg,q_100'),
  ];

  /// Delivery URL for [url] under the preset at [index].
  static String displayUrl(String url, int index) {
    final t = all[index.clamp(0, all.length - 1)].transformation;
    return t == null ? url : transformImageUrl(url, t);
  }
}
