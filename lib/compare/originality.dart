import 'dart:math' as math;

/// How far a generated prompt may move away from its reference picture.
enum CreativityLevel { faithful, balanced, creative, bold }

extension CreativityLevelX on CreativityLevel {
  String get label => switch (this) {
        CreativityLevel.faithful => 'Faithful',
        CreativityLevel.balanced => 'Balanced',
        CreativityLevel.creative => 'Creative',
        CreativityLevel.bold => 'Bold',
      };

  String get hint => switch (this) {
        CreativityLevel.faithful =>
          'Close to the picture (only for your own artwork).',
        CreativityLevel.balanced =>
          'Same idea, 3 deliberate changes. ~45-60% similar.',
        CreativityLevel.creative =>
          'Same vibe, 5 forced changes + anti-repeat. ~30-45% similar.',
        CreativityLevel.bold =>
          'Only the mood and style survive. Under ~30% similar.',
      };

  /// Number of forced remix directives per prompt.
  int get changes => switch (this) {
        CreativityLevel.faithful => 0,
        CreativityLevel.balanced => 3,
        CreativityLevel.creative => 5,
        CreativityLevel.bold => 7,
      };
}

/// Pools of concrete changes. Every prompt draws a different random mix,
/// so a whole Pinterest board never turns into near-identical prompts.
const Map<String, List<String>> _remixPools = {
  'subject': [
    'give the main subject a completely different identity: other age, face, hairstyle and body type (or another species / object design)',
    'replace the main subject with a different but related subject of the same theme',
    'redesign the outfit or surface materials of the main subject from scratch',
    'change the number of subjects (one becomes two, a group becomes a single hero, or vice versa)',
  ],
  'pose': [
    'use a new pose or action that tells a different moment of the story',
    'turn the subject to a different direction and change the gesture',
    'show the subject interacting with a new meaningful prop',
  ],
  'setting': [
    'move the scene to a different location of the same genre',
    'invent a new background with different landmarks, props and depth layers',
    'change the environment type (indoor <-> outdoor, city <-> nature, land <-> water or sky)',
  ],
  'time': [
    'switch the time of day (dawn, blue hour, midnight, harsh noon) with matching light',
    'change the season or weather (snow, rain, fog, heat haze, wind)',
  ],
  'camera': [
    'use a different camera angle (low angle, high angle, top-down, eye-level, dutch tilt)',
    'change the shot size (extreme close-up <-> wide establishing shot)',
    'move the subject to a different place in the frame and change the negative space',
    'change the lens feel (ultra-wide 16 mm, 50 mm, 135 mm telephoto compression, macro)',
  ],
  'colour': [
    'shift the accent colour to a new harmonious hue while keeping the overall mood',
    'use a different colour scheme family (complementary, analogous, triadic, monochrome)',
  ],
  'light': [
    'change the key light direction and quality (rim light, backlight, side light, soft overcast)',
    'add a new light source that changes the atmosphere (neon, candle, bioluminescence, god rays)',
  ],
  'style': [
    'reinterpret it in a neighbouring medium (e.g. photo -> cinematic 3D render, painting -> gouache illustration)',
    'add a distinct texture treatment (film grain, paper texture, brush strokes, glass reflections)',
  ],
  'twist': [
    'add one fresh story detail that is not in the reference and fits the theme',
    'add an atmospheric effect that is absent in the reference (particles, mist, sparks, petals, dust)',
  ],
};

/// Builds the per-image variation brief appended to the instruction.
/// [seed] makes it reproducible per picture; [boost] adds an extra
/// "too similar" warning (used for the anti-repeat retry / remix).
String variationBrief(CreativityLevel level, int seed, {String boost = ''}) {
  if (level == CreativityLevel.faithful) return '';
  final r = math.Random(seed);
  final cats = _remixPools.keys.toList()..shuffle(r);
  // Bold always rewrites subject and setting; others pick at random.
  if (level == CreativityLevel.bold) {
    cats
      ..remove('subject')
      ..remove('setting')
      ..insertAll(0, ['subject', 'setting']);
  }
  final picks = <String>[];
  for (final c in cats.take(level.changes)) {
    final pool = _remixPools[c]!;
    picks.add(pool[r.nextInt(pool.length)]);
  }
  final maxSim = switch (level) {
    CreativityLevel.balanced => 55,
    CreativityLevel.creative => 40,
    _ => 25,
  };
  final b = StringBuffer()
    ..write('\n\nORIGINALITY BRIEF (mandatory for this image):\n')
    ..write('Apply ALL of these changes to the reference:\n');
  for (var i = 0; i < picks.length; i++) {
    b.write('- ${picks[i]}\n');
  }
  b
    ..write('Keep only the transferable feel: genre, overall mood, '
        'rendering quality and a related colour harmony. ')
    ..write('Self-check before answering: imagine the generated picture next '
        'to the reference - a viewer must NOT think it is the same image or a '
        'copy; at most ~$maxSim% of the concrete visible details may match. '
        'If more would match, change more. ')
    ..write('Do not mention the reference, the changes or this brief in the '
        'prompt.');
  if (boost.isNotEmpty) b.write('\n$boost');
  return b.toString();
}

const _stop = {
  'the',
  'and',
  'with',
  'from',
  'into',
  'over',
  'under',
  'that',
  'this',
  'their',
  'there',
  'very',
  'soft',
  'high',
  'ultra',
  'detailed',
  'sharp',
  'focus',
  'dynamic',
  'range',
  'light',
  'lighting',
  'while',
  'which',
  'its',
  'for',
  'are',
  'has',
  'have',
  'background',
  'foreground',
  'image',
  'style',
};

Set<String> _words(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) => w.length > 3 && !_stop.contains(w))
    .toSet();

/// Word-set Jaccard similarity 0..1 between two prompts.
double promptSimilarity(String a, String b) {
  final x = _words(a), y = _words(b);
  if (x.isEmpty || y.isEmpty) return 0;
  final inter = x.intersection(y).length;
  return inter / (x.length + y.length - inter);
}

/// Highest similarity of [prompt] to any of [others] (0..1).
double maxPromptSimilarity(String prompt, Iterable<String> others) {
  var best = 0.0;
  for (final o in others) {
    best = math.max(best, promptSimilarity(prompt, o));
  }
  return best;
}
