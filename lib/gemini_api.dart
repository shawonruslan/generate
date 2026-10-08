import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
      '"tags": array of 8 to 12 single lowercase words (no spaces, no hyphens, no duplicates, no brand or franchise names), '
      '"category": one of ${jsonEncode(zedgeCategories)}, '
      '"description": string (1-2 sentences, max 200 characters, natural, no hashtags, no emoji)}.\n'
      'Set types: 24-HOUR = 4 time-of-day wallpapers; DUAL = lock + home screen pair; BATTERY = 6 charge-level wallpapers; SINGLE = one wallpaper. '
      'Mention the set behaviour naturally in the description when the type is not SINGLE. Never mention copyrighted characters, brands, humans or text. '
      'Do not describe the image in sentences - output only the JSON object.';

  static final _rand = Random();

  /// Natural per-call variation: every listing should read like a
  /// different human uploader wrote it - normal wording, but never the
  /// same structural pattern twice.
  static String _varietyNote() =>
      'Write like a normal human uploader, not a template: vary the title '
      'structure naturally (sometimes the subject, sometimes the mood, sometimes a short phrase), '
      'never start the description the same way twice, '
      'and pick tags that fit this specific image - specific over generic - shuffling their order every time.';

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
      String key, String model, String input, int maxTokens,
      {double temperature = 0.5,
      Duration timeout = const Duration(seconds: 60)}) async {
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
              'temperature': temperature,
              // Force valid JSON: the model is constrained to reply with a
              // JSON object instead of prose (supported by all current
              // Gemini models). Both metadata and the set director need it.
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(timeout);
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
      {required List<String> keys,
      required List<String> models,
      bool expectJson = false,
      double temperature = 0.5,
      Duration timeout = const Duration(seconds: 60)}) async {
    if (keys.isEmpty) throw Exception('Add at least one Gemini API key.');
    final modelList = models.isEmpty ? ['gemini-flash-latest'] : models;
    final deadKeys = <int>{};
    String lastError = 'no attempts';
    for (var mi = 0; mi < modelList.length; mi++) {
      for (var ki = 0; ki < keys.length; ki++) {
        if (deadKeys.contains(ki)) continue;
        try {
          final text = await _call(keys[ki], modelList[mi], input, maxTokens,
              temperature: temperature, timeout: timeout);
          if (text.isEmpty) break; // empty answer -> try next model
          if (expectJson && _extractJsonMap(text) == null) {
            // The model ignored the JSON instruction and replied in
            // prose. Not a result - try the next key/model instead of
            // surfacing it as a hard error.
            lastError =
                'Model ${modelList[mi]} replied in prose instead of JSON. '
                'Got: ${_replySnippet(text)}';
            continue; // next key, same model (fresh roll of the dice)
          }
          return (text: text, model: modelList[mi], keyIndex: ki);
        } on _GeminiFailure catch (e) {
          lastError = e.message;
          if (e.kind == _FailKind.key) {
            if (e.status != 429) deadKeys.add(ki);
            continue; // next key, same model
          }
          if (e.kind == _FailKind.model) break; // next model
          // transient: try next key
        } on TimeoutException {
          // A hung model is transient: try the next key/model instead of
          // aborting the whole failover chain.
          lastError = 'Model ${modelList[mi]} timed out';
          continue; // next key, same model
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
    // Per-call variation: a random authorial voice and a random
    // temperature (0.6 - 1.0) so listings from different users and runs
    // never read like one shared template.
    final temp = 0.6 + _rand.nextDouble() * 0.4;
    final input = '${_systemPrompt()}\n\n${_varietyNote()}\n\n'
        'Set type: $type\n'
        'Concept name: $concept\n'
        'Image prompt: $prompt\n\n'
        'Return the JSON object now.';
    final r = await _failover(input, 600,
        keys: keys,
        models: models,
        expectJson: true,
        temperature: temp,
        timeout: const Duration(seconds: 90));
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
      'Each stage MUST be dramatically, unmistakably different from the others: transform ONLY the light and atmosphere boldly \u2014 '
      'light direction, color temperature, glow, mist and mood \u2014 while keeping the exact same scene, objects, background and composition; '
      'never add, remove or rearrange anything, never near-duplicate moods. '
      'For BATTERY sets: keep the exact same glow and light hue across every stage \u2014 only brightness and intensity progress from dark to blinding, the hue never changes. '
      'so anyone comparing two stages immediately tells them apart \u2014 never near-duplicate moods. '
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
    final r = await _failover(input, 1200,
        keys: keys,
        models: models,
        expectJson: true,
        // Director plans are long; give slow models room before the
        // timeout failover kicks in.
        timeout: const Duration(seconds: 150));
    return parseDirection(r.text, variantLabels);
  }

  /// String-aware scan for top-level balanced {...} blocks: braces inside
  /// quoted strings (e.g. a description containing "{") don't count.
  /// Returns blocks largest-first so the full object beats inner fragments.
  static List<String> _balancedBlocks(String text) {
    final blocks = <String>[];
    var depth = 0;
    var start = -1;
    String? quote;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (c == '}') {
        if (depth > 0) {
          depth--;
          if (depth == 0 && start >= 0) {
            blocks.add(text.substring(start, i + 1));
            start = -1;
          }
        }
      }
    }
    blocks.sort((a, b) => b.length.compareTo(a.length));
    return blocks;
  }

  /// Decode [s] as a JSON object map. Tolerates trailing commas and a
  /// top-level array wrapping the object. Unwraps single-key wrappers
  /// like {"metadata": {...}}.
  static Map<String, dynamic>? _decodeJsonMap(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    Map<String, dynamic>? asMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      if (v is List) {
        for (final e in v) {
          final m = asMap(e);
          if (m != null) return m;
        }
      }
      return null;
    }

    const knownKeys = {
      'title',
      'tags',
      'category',
      'description',
      'arc',
      'anchor',
      'palette',
      'stages',
      'direction',
      'label'
    };
    Map<String, dynamic>? unwrap(Map<String, dynamic> m) {
      if (m.length == 1 &&
          m.keys.every((k) => !knownKeys.contains(k.toString())) &&
          m.values.first is Map) {
        return asMap(m.values.first);
      }
      return m;
    }

    for (final candidate in [
      t,
      // tolerate trailing commas: {"a": 1,}
      t.replaceAll(RegExp(r',\s*([}\]])'), r'$1'),
    ]) {
      try {
        final m = asMap(jsonDecode(candidate));
        if (m != null) return unwrap(m);
      } catch (_) {}
    }
    return null;
  }

  /// Best-effort extraction of the model's JSON object: the whole reply
  /// first, then the largest balanced {...} block. Returns null when
  /// nothing decodes.
  static Map<String, dynamic>? _extractJsonMap(String text) {
    final t =
        text.replaceAll(RegExp(r'```(?:\w+)?', caseSensitive: false), '');
    final direct = _decodeJsonMap(t);
    if (direct != null) return direct;
    for (final block in _balancedBlocks(t)) {
      final m = _decodeJsonMap(block);
      if (m != null) return m;
    }
    return null;
  }

  /// Short snippet of a raw model reply for error messages.
  static String _replySnippet(String text) {
    final s = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return s.substring(0, s.length.clamp(0, 120));
  }

  /// Parse and sanitize the director's JSON plan.
  static SetDirection parseDirection(String text, List<String> labels) {
    final meta = _extractJsonMap(text);
    if (meta == null) {
      throw Exception('The model did not return a valid plan. '
          'Got: ${_replySnippet(text)}');
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
    final meta = _extractJsonMap(text);
    if (meta == null) {
      throw Exception('The model did not return valid JSON. '
          'Got: ${_replySnippet(text)}');
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
        if (tags.length == 12) break;
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
}
