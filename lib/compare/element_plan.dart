/// Picture-specific similarity control: Gemini first lists every visual
/// element of the reference (subjects, objects, background layers,
/// textures, text, effects and the global look: composition, camera,
/// lighting, palette, time/weather, style, mood) with a visual-impact and
/// an identity weight. The app then picks exactly which elements change
/// so the kept share of visual weight matches the similarity target.
library;

/// One visual element of the reference picture.
class SceneElement {
  SceneElement({
    required this.name,
    required this.category,
    required this.impact,
    required this.identity,
    this.change = false,
  });

  /// Short concrete description, e.g. "wooden canoe in the lower centre".
  final String name;

  /// subject, object, background, texture, text, effect, composition,
  /// camera, lighting, colour, time, style, mood.
  final String category;

  /// 1-10: share of what the eye sees (area, contrast, focus).
  final int impact;

  /// 1-10: how much it makes the picture recognisable as THIS picture.
  final int identity;

  /// Planned: replace/redesign this element.
  bool change;

  Map<String, dynamic> toJson() => {
        'n': name,
        'c': category,
        'i': impact,
        'd': identity,
        if (change) 'x': true,
      };

  static SceneElement? fromJson(dynamic j) {
    if (j is! Map) return null;
    final n = (j['n'] ?? '').toString();
    if (n.isEmpty) return null;
    return SceneElement(
      name: n,
      category: (j['c'] ?? 'object').toString(),
      impact: ((j['i'] as num?)?.toInt() ?? 5).clamp(1, 10),
      identity: ((j['d'] as num?)?.toInt() ?? 5).clamp(1, 10),
      change: j['x'] == true,
    );
  }
}

/// Global rows every inventory must contain (so "look" can be planned
/// like any object).
const List<String> globalCategories = [
  'composition',
  'camera',
  'lighting',
  'colour',
  'time',
  'style',
  'mood',
];

/// Step 1 instruction: element inventory of the attached picture.
const String elementInventoryInstruction =
    'Analyse the attached picture and list EVERY visual element in it, so '
    'a designer could rebuild it. Include: each main subject, every '
    'secondary object or prop, each background layer (sky, horizon, '
    'landmarks, foliage, water, buildings...), notable textures and '
    'materials, any text/logo/graphic, visual effects (glow, particles, '
    'reflections, bokeh, fog), and these global rows: composition (layout '
    '/ placement), camera (angle, shot size, lens), lighting, colour '
    '(palette), time (time of day, season, weather), style (medium / '
    'render look), mood. Be concrete and short, with position when it '
    'matters (e.g. "wooden canoe, lower centre, pointing up-left").\n'
    'For each element give impact 1-10 (how much of what the eye sees it '
    'is: area, contrast, focus) and identity 1-10 (how much it makes the '
    'picture recognisable as THIS picture).\n'
    'Return 10 to 24 lines in exactly this format and nothing else:\n'
    '[ELEMENTS]\n'
    'name | category | impact | identity\n'
    '[/ELEMENTS]\n'
    'category is one of: subject, object, background, texture, text, '
    'effect, composition, camera, lighting, colour, time, style, mood.';

/// Parses the [ELEMENTS] block (tolerant of markdown, bullets, escaped
/// brackets, header rows).
List<SceneElement> parseElements(String reply) {
  var t = reply.replaceAll(r'\[', '[').replaceAll(r'\]', ']');
  final m = RegExp(r'\[ELEMENTS\]([\s\S]*?)(\[/ELEMENTS\]|$)',
          caseSensitive: false)
      .firstMatch(t);
  if (m != null) t = m.group(1)!;
  final out = <SceneElement>[];
  final seen = <String>{};
  for (var line in t.split('\n')) {
    line = line
        .replaceAll('**', '')
        .replaceAll(RegExp(r'^\s*([-*•]|\d+[.)])\s*'), '')
        .replaceAll(RegExp(r'\[cite[^\]]*\]', caseSensitive: false), '')
        .trim();
    if (line.startsWith('|')) line = line.substring(1);
    if (line.endsWith('|')) line = line.substring(0, line.length - 1);
    final p = line.split('|').map((e) => e.trim()).toList();
    if (p.length < 4) continue;
    final impact = int.tryParse(RegExp(r'\d+').stringMatch(p[2]) ?? '');
    final identity = int.tryParse(RegExp(r'\d+').stringMatch(p[3]) ?? '');
    if (impact == null || identity == null) continue; // header / divider
    final name = p[0];
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    out.add(SceneElement(
      name: name,
      category: p[1].toLowerCase(),
      impact: impact.clamp(1, 10),
      identity: identity.clamp(1, 10),
    ));
  }
  return out;
}

/// Share (0..1) of the total visual weight that stays unchanged.
double keptShare(List<SceneElement> els) {
  var all = 0.0, kept = 0.0;
  for (final e in els) {
    final w = _w(e);
    all += w;
    if (!e.change) kept += w;
  }
  return all == 0 ? 1 : kept / all;
}

/// Weight of an element in "how similar does it look": what the eye sees
/// plus what makes it recognisable.
double _w(SceneElement e) => e.impact * 0.6 + e.identity * 0.4;

/// Marks which elements change so the kept weight share is as close as
/// possible to [target] %. The least defining elements change first; at
/// least one element always changes (never a copy).
List<SceneElement> planElements(List<SceneElement> els, int target) {
  for (final e in els) {
    e.change = false;
  }
  if (els.isEmpty) return els;
  final total = els.fold<double>(0, (a, e) => a + _w(e));
  final goal = (1 - target.clamp(5, 95) / 100) * total; // weight to change
  final order = [...els]..sort((a, b) {
      final c = _order(a).compareTo(_order(b));
      return c != 0 ? c : a.impact.compareTo(b.impact);
    });
  var changed = 0.0;
  for (final e in order) {
    final w = _w(e);
    if ((changed + w - goal).abs() < (changed - goal).abs()) {
      e.change = true;
      changed += w;
    }
  }
  if (!els.any((e) => e.change)) order.first.change = true;
  return els;
}

/// Change order: identity, nudged by category. The art style and the
/// main subject change last; camera, time and mood early (keeping the
/// exact camera/framing alone already reads as "the same picture").
double _order(SceneElement e) =>
    e.identity +
    switch (e.category) {
      'style' => 5.0,
      'subject' => 2.5,
      'colour' => 1.0,
      'camera' => -2.0,
      'composition' => -1.0,
      'time' || 'mood' => -1.5,
      _ => 0.0,
    };

/// Step 2 brief appended to the prompt instruction: the concrete keep /
/// change lists for THIS picture.
String elementBrief(List<SceneElement> els, int target, {String boost = ''}) {
  final kept = els.where((e) => !e.change).toList();
  final changed = els.where((e) => e.change).toList();
  final share = (keptShare(els) * 100).round();
  final intensity = target >= 75
      ? 'subtle but clearly visible'
      : target >= 50
          ? 'clear'
          : 'strong';
  final b = StringBuffer()
    ..write('\n\nSIMILARITY TARGET: $target% (this overrides every other '
        'originality rule above).\n')
    ..write('The picture was analysed into elements. Keeping the elements '
        'below keeps about $share% of its visual weight, which gives the '
        '$target% target.\n')
    ..write('KEEP IDENTICAL (describe each exactly as seen):\n');
  for (final e in kept) {
    b.write('- ${e.name}\n');
  }
  b.write('CHANGE ($intensity changes; replace or redesign each one with a '
      'new, fitting version and describe the NEW version):\n');
  for (final e in changed) {
    b.write('- ${e.name}\n');
  }
  b.write('Change exactly these elements and nothing else. Never mention '
      'the reference, the target or these lists in the prompt.');
  if (boost.isNotEmpty) b.write('\n$boost');
  return b.toString();
}
