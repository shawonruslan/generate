import 'dart:convert';

import 'gemini_web.dart';

/// Zedge listing metadata generated through the **Gemini web (cookie)
/// session** only - the same path the Generator Hub workflow uses when a
/// GEMINI_SESSION is supplied. No API keys, no model pool, no quota:
/// one JSON object per set, validated and sanitized.

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

/// Metadata plus provenance: which Gemini surface wrote it.
class GeneratedMetadata {
  final SetMetadata metadata;
  final String model;

  const GeneratedMetadata({
    required this.metadata,
    required this.model,
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

class GeminiApi {
  GeminiApi._();

  static String _systemPrompt() =>
      'You write Zedge wallpaper listing metadata. Reply with ONE JSON object only, no markdown, no commentary.\n'
      'Schema: {"title": string (max 30 characters, Title Case, catchy, no emoji, no quotes), '
      '"tags": array of 8 to 12 single lowercase words (no spaces, no hyphens, no duplicates, no brand or franchise names), '
      '"category": one of ${jsonEncode(zedgeCategories)}, '
      '"description": string (1-2 sentences, max 200 characters, natural, no hashtags, no emoji)}.\n'
      'Set types: 24-HOUR = 4 time-of-day wallpapers; DUAL = lock + home screen pair; BATTERY = 6 charge-level wallpapers; SINGLE = one wallpaper. '
      'Mention the set behaviour naturally in the description when the type is not SINGLE. Never mention copyrighted characters, brands, humans or text. '
      'Do not describe the image in sentences - output only the JSON object.';

  /// Natural per-call variation: every listing should read like a
  /// different human uploader wrote it - normal wording, but never the
  /// same structural pattern twice.
  static String _varietyNote() =>
      'Write like a normal human uploader, not a template: vary the title '
      'structure naturally (sometimes the subject, sometimes the mood, sometimes a short phrase), '
      'never start the description the same way twice, '
      'and pick tags that fit this specific image - specific over generic - shuffling their order every time.';

  /// Extra instruction for the cookie (web) path: the web UI has no
  /// `responseMimeType`, so the JSON-only rule has to be spelled out the
  /// same way the workflow spells out its [TAG] template.
  static String _webJsonNote() =>
      'OUTPUT RULE: reply with the raw JSON object ONLY. No markdown, no '
      'code fences, no commentary, no explanation before or after it.';

  /// One completion through the cookie session, with the same retry +
  /// validation discipline the workflow uses (fresh chat per prompt,
  /// non-empty reply, parseable result, otherwise retry).
  static Future<String> _askWeb(GeminiWebClient web, String input,
      {bool expectJson = false, int attempts = 3}) async {
    Object? lastErr = 'no attempts';
    for (var i = 0; i < attempts; i++) {
      try {
        final text = await web.ask(input,
            attempts: 1,
            freshChat: true,
            timeout: const Duration(seconds: 150));
        if (text.trim().isEmpty) {
          lastErr = 'empty reply';
        } else if (expectJson && _extractJsonMap(text) == null) {
          lastErr = 'replied in prose instead of JSON. '
              'Got: ${_replySnippet(text)}';
        } else {
          return text;
        }
      } on GeminiWebException catch (e) {
        lastErr = e.message;
        if (e.expired) rethrow; // re-export cookies, retrying won't help
      } catch (e) {
        lastErr = e;
      }
      if (i < attempts - 1) {
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
    throw Exception('Gemini web (cookie session) failed. Last: $lastErr');
  }

  /// Runs one prompt through the Gemini web (cookie) session and returns
  /// the reply plus provenance.
  static Future<({String text, String model})> _complete(
      String input, GeminiWebClient web,
      {bool expectJson = false}) async {
    final text = await _askWeb(web, '$input\n\n${_webJsonNote()}',
        expectJson: expectJson);
    return (text: text, model: geminiWebModelLabel);
  }

  static Future<GeneratedMetadata> generate({
    required String type,
    required String concept,
    required String prompt,
    required String file,
    required GeminiWebClient web,
  }) async {
    final input = '${_systemPrompt()}\n\n${_varietyNote()}\n\n'
        'Set type: $type\n'
        'Concept name: $concept\n'
        'Image prompt: $prompt\n\n'
        'Return the JSON object now.';
    final r = await _complete(input, web, expectJson: true);
    final meta = parseMetadata(r.text, file: file);
    return GeneratedMetadata(metadata: meta, model: r.model);
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
    required GeminiWebClient web,
  }) async {
    final labels = variantLabels.map((l) => '"$l"').join(', ');
    final input = '${_directorSystem()}\n\n'
        'Set type: $type\n'
        'Variant labels in order: $labels\n'
        'User prompt: $prompt\n\n'
        'Return the JSON object now.';
    final r = await _complete(input, web, expectJson: true);
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
  static SetMetadata parseMetadata(String text, {required String file}) {
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
    // No fallback metadata: what the model generated stays, anything it
    // did not generate stays blank. An invalid category is not silently
    // replaced with DESIGNS, and an empty title is not backfilled from
    // the concept.
    var category = (meta['category']?.toString() ?? '').toUpperCase().trim();
    if (!zedgeCategories.contains(category)) category = '';
    return SetMetadata(
      file: file,
      title: _trunc((meta['title']?.toString() ?? '').trim()),
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

  static String _trunc(String s, [int n = 30]) =>
      s.length <= n ? s : s.substring(0, n);

  static String _ws(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
