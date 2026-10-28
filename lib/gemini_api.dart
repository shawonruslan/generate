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

  /// Tags as a clean comma-separated string, ready to paste into a
  /// Search Tags text field (no brackets, no quotes).
  String get tagsCsv => tags.join(', ');

  Map<String, dynamic> toJson() => {
        'file': file,
        'title': title,
        'tags': tags,
        // Copy-paste friendly duplicate for upload forms.
        'keywords': tagsCsv,
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

  /// Art-director brief. The rules are deliberately quantitative: image
  /// models flatten vague superlatives ("bright" / "brilliant" / "maximum")
  /// into near-identical frames, so every stage must carry measurable,
  /// absolute values instead.
  static String _directorSystem(String type, int stageCount) {
    final perType = switch (type.toUpperCase()) {
      'BATTERY' => 'BATTERY set ($stageCount charge levels, 0% to 100%):\n'
          '- The glow HUE is locked by the concept and must be identical in every stage. Only the AMOUNT of light changes.\n'
          '- Every direction MUST state, as absolute values: the share of the frame that is lit (about 5, 20, 40, 60, 80 then 100 percent), the brightness of the glow core, the bloom radius, and how much of the frame is still in shadow.\n'
          '- Spread the ladder evenly and make the top half obvious: 60% must read as clearly dimmer than 80%, and 80% clearly dimmer than 100%. Use different physical light behaviour per stage (halo size, light rays, reflections, volumetric beams, lens flare, blown-out core, haze) so the upper levels can never look the same.\n'
          '- 0% is almost black, 100% has no dark area left anywhere in the frame.',
      '24-HOUR' || '24 HOUR' || '24H' =>
        '24-HOUR set ($stageCount times of day):\n'
            '- Every direction MUST state: the clock hour, the key-light direction and elevation in degrees, the color temperature in Kelvin, the shadow length and direction, and the amount of atmosphere (mist, haze, clarity).\n'
            '- Dawn is low warm light with long shadows, midday is near-overhead neutral light with short hard shadows, evening is low raking warm light with long shadows the opposite way, night has no sun at all, cool light and mostly deep shadow.\n'
            '- Shadow direction must visibly flip between morning and evening.',
      'DUAL' => 'DUAL set ($stageCount screens):\n'
          '- Lock and Home must differ in FRAMING, not in lighting. Keep the lighting and palette the same.\n'
          '- Every direction MUST state: how much of the frame height the hero fills (about 80 percent for Lock, about 30 percent for Home), the depth of field (shallow and blurred background for Lock, deep focus for Home), and where the calm empty space sits.\n'
          '- Home must leave a quiet low-detail area in the upper half for clock, icons and widgets.',
      _ => 'Each stage must differ in an obvious, measurable way; state concrete values (light direction, color temperature, lit area, framing) rather than adjectives.',
    };
    return 'You are a professional art director for premium mobile wallpaper sets sold on wallpaper marketplaces. Reply with ONE JSON object only, no markdown, no commentary.\n'
        'Schema: {"arc": string (short evocative arc name, e.g. "Bloom cycle"), '
        '"anchor": string (one neutral base-scene description fragment, no strong time-of-day or energy bias \u2014 it is the reference image every stage is re-lit from, so it must be a clean, mid-dark, unbiased rendering of the concept), '
        '"palette": array of 1-3 lowercase color words actually present in the concept, '
        '"stages": array with EXACTLY $stageCount objects, one per variant label in the given order, each {"label": string (the exact label), "direction": string (1-3 sentences describing ONLY what this stage looks like: lighting, state, atmosphere, framing \u2014 the subject, objects, background and art style stay identical)}}.\n'
        'Hard rules:\n'
        '- Never describe text, letters, numbers, symbols, icons, logos or watermarks in the image. Writing numeric values inside the direction (percentages, Kelvin, degrees) is fine: they describe the light, not something drawn.\n'
        '- Each direction is an ABSOLUTE description of that stage, never a relative one. Never write "brighter than before", "more than the previous", "slightly more intense".\n'
        '- Never reuse the same adjective, light behaviour or mood in two stages. Two stages placed side by side must be instantly tellable apart by anyone.\n'
        '- Never add, remove, resize or rearrange the subject, objects or background unless the set type explicitly asks for a framing change.\n'
        '- Write cinematic, specific, production-grade language tied to the user concept: name the real surfaces, materials and light sources of that scene instead of generic filler.\n'
        '$perType';
  }

  /// Ask the AI to direct one set: it decides the arc, the neutral anchor
  /// description, the palette and the per-variant directions.
  static Future<SetDirection> directSet({
    required String type,
    required List<String> variantLabels,
    required String prompt,
    required GeminiWebClient web,
  }) async {
    final labels = variantLabels.map((l) => '"$l"').join(', ');
    final input = '${_directorSystem(type, variantLabels.length)}\n\n'
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
