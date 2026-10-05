import 'dart:convert';

import 'package:http/http.dart' as http;

/// Zedge listing metadata generated with Google's Gemini API,
/// mirroring the web studio (index.php): multiple API keys with
/// automatic failover (429/bad key -> next key, unknown model -> next
/// model), one JSON object per set, validated and sanitized.

/// The 20 Zedge categories accepted by the upload pipeline.
const zedgeCategories = [
  'ANIMALS', 'ANIME', 'CARS_N_VEHICLES', 'COMICS', 'DESIGNS', 'DRAWINGS',
  'ENTERTAINMENT', 'FUNNY', 'GAMES', 'HOLIDAYS', 'LOVE', 'MUSIC', 'NATURE',
  'PATTERNS', 'PEOPLE', 'SAYINGS', 'SPACE', 'SPIRITUAL', 'SPORTS',
  'TECHNOLOGY',
];

/// One metadata.json entry for a wallpaper set.
class SetMetadata {
  final String file;
  final String title;
  final List<String> tags;
  final String category;
  final String description;

  const SetMetadata({
    required this.file,
    required this.title,
    required this.tags,
    required this.category,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'file': file,
        'title': title,
        'tags': tags,
        'category': category,
        'description': description,
      };
}

/// Metadata plus provenance: which model and key wrote it.
class GeneratedMetadata {
  final SetMetadata metadata;
  final String model;
  final int keyIndex;

  const GeneratedMetadata({
    required this.metadata,
    required this.model,
    required this.keyIndex,
  });
}

/// One directed stage of a set: the variant label plus the AI's visual
/// direction fragment for it.
class StageDirection {
  final String label;
  final String direction;
  const StageDirection(this.label, this.direction);
}

/// The AI Set Director's full plan for one prompt's set.
class SetDirection {
  final String arc;
  final String anchorDirection;
  final List<String> palette;
  final List<StageDirection> stages;

  const SetDirection({
    required this.arc,
    required this.anchorDirection,
    required this.palette,
    required this.stages,
  });
}

enum _FailKind { key, model, retry }

class _GeminiFailure implements Exception {
  final _FailKind kind;
  final int status;
  final String message;
  _GeminiFailure(this.kind, this.status, this.message);
}

class KeyTestResult {
  final int index;
  final bool ok;
  final int status;
  final int ms;
  final String model;
  final String message;
  KeyTestResult(this.index, this.ok, this.status, this.ms, this.model,
      this.message);
}

class ModelTestResult {
  final String model;
  final bool ok;
  final int status;
  final int ms;
  final String message;
  ModelTestResult(this.model, this.ok, this.status, this.ms, this.message);
}

class GeminiApi {
  GeminiApi._();

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  static String _modelId(String m) {
    m = m.trim();
    return m.startsWith('models/') ? m.substring(7) : m;
  }

  static String _systemPrompt() =>
      'You write Zedge wallpaper listing metadata. Reply with ONE JSON object only, no markdown, no commentary.\n'
      'Schema: {"title": string (max 30 characters, Title Case, catchy, no emoji, no quotes), '
      '"tags": array of exactly 10 single lowercase words (no spaces, no hyphens, no duplicates, no brand or franchise names), '
      '"category": one of ${jsonEncode(zedgeCategories)}, '
      '"description": string (1-2 sentences, max 200 characters, natural, no hashtags, no emoji)}.\n'
      'Set types: 24-HOUR = 4 time-of-day wallpapers; DUAL = lock + home screen pair; BATTERY = 6 charge-level wallpapers; SINGLE = one wallpaper. '
      'Mention the set behaviour naturally in the description when the type is not SINGLE. Never mention copyrighted characters, brands, humans or text.';

  /// Pull every "text" string out of a Gemini response body.
  static String _extractText(dynamic node) {
    final acc = <String>[];
    void walk(dynamic n) {
      if (n is Map) {
        n.forEach((k, v) {
          if ((k == 'text' || k == 'output_text') &&
              v is String &&
              v.trim().isNotEmpty) {
            acc.add(v);
          } else {
            walk(v);
          }
        });
      } else if (n is List) {
        for (final v in n) {
          walk(v);
        }
      }
    }

    walk(node);
    return acc.join('\n').trim();
  }

  static String _errorMessage(dynamic body) {
    if (body is Map) {
      final e = body['error'];
      final m = e is Map
          ? e['message']
          : (body['detail'] ?? body['message'] ?? '');
      return m?.toString() ?? '';
    }
    return '';
  }

  static _FailKind _failKind(int status, String msg) {
    final m = msg.toLowerCase();
    if (status == 400 &&
        (m.contains('api key') || m.contains('api_key'))) {
      return _FailKind.key;
    }
    if (status == 401 || status == 403 || status == 402 || status == 429) {
      return _FailKind.key;
    }
    if (status == 400 || status == 404 || status == 422) {
      return _FailKind.model;
    }
    return _FailKind.retry;
  }

  /// One generateContent call. Returns the raw text (may be empty).
  /// Throws [_GeminiFailure] on HTTP errors.
  static Future<String> _call(
      String key, String model, String input, int maxTokens) async {
    final url = Uri.parse(
        '$_base/models/${Uri.encodeComponent(_modelId(model))}:generateContent');
    final res = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': key.trim(),
          },
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': input}
                ]
              }
            ],
            'generationConfig': {
              'maxOutputTokens': maxTokens,
              'temperature': 0.5,
            },
          }),
        )
        .timeout(const Duration(seconds: 60));
    dynamic body;
    try {
      body = res.body.isEmpty ? {} : jsonDecode(res.body);
    } catch (_) {
      body = {'raw': res.body.substring(0, res.body.length.clamp(0, 300))};
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return _extractText(body);
    }
    final msg = _errorMessage(body);
    throw _GeminiFailure(
        _failKind(res.statusCode, msg),
        res.statusCode,
        msg.isEmpty ? 'HTTP ${res.statusCode}' : 'HTTP ${res.statusCode}: $msg');
  }

  /// Shared key/model failover: rate-limited or bad key -> next key,
  /// unknown/down model -> next model, empty answer -> next model,
  /// transient errors -> next key. Returns the text plus provenance.
  static Future<({String text, String model, int keyIndex})> _failover(
      String input, int maxTokens,
      {required List<String> keys, required List<String> models}) async {
    if (keys.isEmpty) throw Exception('Add at least one Gemini API key.');
    final modelList = models.isEmpty ? ['gemini-flash-latest'] : models;
    final deadKeys = <int>{};
    String lastError = 'no attempts';
    for (var mi = 0; mi < modelList.length; mi++) {
      for (var ki = 0; ki < keys.length; ki++) {
        if (deadKeys.contains(ki)) continue;
        try {
          final text = await _call(keys[ki], modelList[mi], input, maxTokens);
          if (text.isEmpty) break; // empty answer -> try next model
          return (text: text, model: modelList[mi], keyIndex: ki);
        } on _GeminiFailure catch (e) {
          lastError = e.message;
          if (e.kind == _FailKind.key) {
            if (e.status != 429) deadKeys.add(ki);
            continue; // next key, same model
          }
          if (e.kind == _FailKind.model) break; // next model
          // transient: try next key
        }
      }
    }
    throw Exception('All Gemini keys/models failed. Last: $lastError');
  }

  /// Generate metadata for one set, rotating through models and keys.
  static Future<GeneratedMetadata> generate({
    required String type,
    required String concept,
    required String prompt,
    required String file,
    required List<String> keys,
    required List<String> models,
  }) async {
    final input = '${_systemPrompt()}\n\n'
        'Set type: $type\n'
        'Concept name: $concept\n'
        'Image prompt: $prompt\n\n'
        'Return the JSON object now.';
    final r = await _failover(input, 600, keys: keys, models: models);
    final meta = parseMetadata(r.text, file: file, concept: concept);
    return GeneratedMetadata(
        metadata: meta, model: r.model, keyIndex: r.keyIndex);
  }

  static String _directorSystem() =>
      'You are an art director for mobile wallpaper sets. Reply with ONE JSON object only, no markdown, no commentary.\n'
      'Schema: {"arc": string (short evocative arc name, e.g. "Bloom cycle"), '
      '"anchor": string (one neutral base-scene description fragment, no strong time-of-day or energy bias \u2014 it is the chaining reference every variant derives from), '
      '"palette": array of 1-3 lowercase color words actually present in the concept, '
      '"stages": array with one object per variant label in the given order, each {"label": string (the exact label), "direction": string (1-2 sentence visual direction fragment describing ONLY what changes in that stage: light, state, mood, movement \u2014 the subject itself stays identical)}}.\n'
      'Rules: never describe text, letters, numbers, symbols, icons, logos or watermarks anywhere. '
      'Keep every fragment vivid, specific to the user prompt, and written as a continuation (lowercase start is fine).';

  /// Ask the AI to direct one set: it decides the arc, the neutral anchor
  /// description, the palette and the per-variant directions.
  static Future<SetDirection> directSet({
    required String type,
    required List<String> variantLabels,
    required String prompt,
    required List<String> keys,
    required List<String> models,
  }) async {
    final labels = variantLabels.map((l) => '"$l"').join(', ');
    final input = '${_directorSystem()}\n\n'
        'Set type: $type\n'
        'Variant labels in order: $labels\n'
        'User prompt: $prompt\n\n'
        'Return the JSON object now.';
    final r = await _failover(input, 1200, keys: keys, models: models);
    return parseDirection(r.text, variantLabels);
  }

  /// Extract the last balanced {...} block from a model reply.
  static String _extractJsonObject(String text) {
    var t =
        text.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '');
    final matches = <String>[];
    var depth = 0;
    var start = -1;
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (c == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          matches.add(t.substring(start, i + 1));
          start = -1;
        }
      }
    }
    return matches.isNotEmpty ? matches.last : t;
  }

  /// Parse and sanitize the director's JSON plan.
  static SetDirection parseDirection(String text, List<String> labels) {
    final obj = _extractJsonObject(text);
    Map<String, dynamic> meta;
    try {
      meta = jsonDecode(obj.trim()) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('The model did not return a valid plan.');
    }
    final stages = <StageDirection>[];
    final rawStages = meta['stages'];
    if (rawStages is List) {
      for (var i = 0; i < rawStages.length && i < labels.length; i++) {
        final s = rawStages[i];
        if (s is Map) {
          stages.add(StageDirection(
              labels[i], s['direction']?.toString().trim() ?? ''));
        }
      }
    }
    if (stages.length != labels.length ||
        stages.any((s) => s.direction.isEmpty)) {
      throw Exception('The model returned an incomplete plan.');
    }
    final palette = <String>[];
    final rawPalette = meta['palette'];
    if (rawPalette is List) {
      for (final c in rawPalette) {
        final w =
            c.toString().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
        if (w.isNotEmpty && !palette.contains(w)) palette.add(w);
        if (palette.length == 3) break;
      }
    }
    return SetDirection(
      arc: meta['arc']?.toString() ?? '',
      anchorDirection: meta['anchor']?.toString().trim() ?? '',
      palette: palette,
      stages: stages,
    );
  }

  /// Parse and sanitize the model's JSON reply into a [SetMetadata].
  static SetMetadata parseMetadata(String text,
      {required String file, required String concept}) {
    var t = text.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '');
    // Take the last balanced {...} block.
    final matches = <String>[];
    var depth = 0;
    var start = -1;
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (c == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          matches.add(t.substring(start, i + 1));
          start = -1;
        }
      }
    }
    if (matches.isNotEmpty) t = matches.last;
    Map<String, dynamic> meta;
    try {
      meta = jsonDecode(t.trim()) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('The model did not return valid JSON.');
    }
    final tags = <String>[];
    final rawTags = meta['tags'];
    if (rawTags is List) {
      for (final tag in rawTags) {
        final clean = tag
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (clean.isNotEmpty && !tags.contains(clean)) tags.add(clean);
        if (tags.length == 10) break;
      }
    }
    var category = (meta['category']?.toString() ?? 'DESIGNS').toUpperCase();
    if (!zedgeCategories.contains(category)) category = 'DESIGNS';
    return SetMetadata(
      file: file,
      title: _trunc((meta['title']?.toString() ?? '').trim().isEmpty
          ? concept
          : meta['title'].toString().trim()),
      tags: tags,
      category: category,
      description: _trunc(_ws(meta['description']?.toString() ?? ''), 200),
    );
  }

  /// Fallback when no Gemini key is configured: derive metadata from the
  /// prompt's own words, like the web studio. The ZIP always works.
  static SetMetadata metadataFromPrompt(
      {required String file,
      required String concept,
      required String prompt}) {
    final tags = <String>[];
    final words = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
        .split(RegExp(r'\s+'));
    for (final w in words) {
      if (w.length > 2 && !_stopwords.contains(w) && !tags.contains(w)) {
        tags.add(w);
      }
      if (tags.length == 10) break;
    }
    return SetMetadata(
      file: file,
      title: _trunc(concept.trim().isEmpty ? 'Wallpaper' : concept.trim()),
      tags: tags,
      category: 'DESIGNS',
      description: _trunc(_ws(prompt), 200),
    );
  }

  /// Pretty-printed metadata.json content for the ZIP.
  static String metadataJson(List<SetMetadata> entries) {
    const enc = JsonEncoder.withIndent('  ');
    return enc.convert([for (final e in entries) e.toJson()]);
  }

  /// Connection test mirroring the web studio: each key is OK if any
  /// model answers; each model is tested with the first working key.
  static Future<(List<KeyTestResult>, List<ModelTestResult>)> testPool(
      List<String> keys, List<String> models) async {
    const ping = 'Reply with the single word OK.';
    final modelList = models.isEmpty ? ['gemini-flash-latest'] : models;
    final keyResults = <KeyTestResult>[];
    String? goodKey;
    for (var ki = 0; ki < keys.length; ki++) {
      KeyTestResult? last;
      for (final model in modelList) {
        final sw = Stopwatch()..start();
        try {
          await _call(keys[ki], model, ping, 16);
          sw.stop();
          last = KeyTestResult(ki + 1, true, 200, sw.elapsedMilliseconds,
              model, 'OK');
          goodKey ??= keys[ki];
          break;
        } on _GeminiFailure catch (e) {
          sw.stop();
          last = KeyTestResult(ki + 1, false, e.status,
              sw.elapsedMilliseconds, model, e.message);
          if (e.kind == _FailKind.key) break;
        } catch (e) {
          sw.stop();
          last = KeyTestResult(ki + 1, false, 0, sw.elapsedMilliseconds,
              model, 'network: $e');
        }
      }
      keyResults.add(last!);
    }
    final modelResults = <ModelTestResult>[];
    for (final model in modelList) {
      if (goodKey == null) {
        modelResults.add(ModelTestResult(
            model, false, 0, 0, 'No working key to test with'));
        continue;
      }
      final sw = Stopwatch()..start();
      try {
        final text = await _call(goodKey, model, ping, 16);
        sw.stop();
        modelResults.add(ModelTestResult(model, true, 200,
            sw.elapsedMilliseconds, 'OK - ${text.isEmpty ? '(empty)' : text}'));
      } on _GeminiFailure catch (e) {
        sw.stop();
        modelResults.add(ModelTestResult(
            model, false, e.status, sw.elapsedMilliseconds, e.message));
      } catch (e) {
        sw.stop();
        modelResults.add(ModelTestResult(
            model, false, 0, sw.elapsedMilliseconds, 'network: $e'));
      }
    }
    return (keyResults, modelResults);
  }

  static String _trunc(String s, [int n = 30]) =>
      s.length <= n ? s : s.substring(0, n);

  static String _ws(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static const _stopwords = {
    'the', 'and', 'with', 'from', 'that', 'this', 'for', 'are', 'was',
    'have', 'has', 'had', 'will', 'would', 'can', 'not', 'but', 'all',
    'its', 'into', 'over', 'under', 'between', 'through', 'during',
    'very', 'more', 'most', 'such', 'only', 'own', 'same', 'than',
    'too', 'also', 'just', 'like', 'out', 'about', 'after', 'before',
    'each', 'few', 'how', 'our', 'their', 'them', 'then', 'there',
    'these', 'they', 'what', 'when', 'where', 'which', 'while', 'who',
    'whom', 'your', 'you', 'she', 'him', 'her', 'his', 'hers',
  };
}
