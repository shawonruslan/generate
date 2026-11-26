import 'dart:math' as math;

/// Legacy originality levels (v1.10). Kept only to migrate saved
/// settings to a similarity target.
enum CreativityLevel { faithful, balanced, creative, bold }

extension CreativityLevelX on CreativityLevel {
  int get target => switch (this) {
        CreativityLevel.faithful => 85,
        CreativityLevel.balanced => 65,
        CreativityLevel.creative => 50,
        CreativityLevel.bold => 30,
      };
}

/// Allowed similarity-target range (percent similar to the reference).
const int minSimilarityTarget = 20;
const int maxSimilarityTarget = 90;
const int defaultSimilarityTarget = 60;

/// Quick presets shown above the slider.
const List<(String, int)> similarityPresets = [
  ('Near copy', 90),
  ('Close', 75),
  ('Balanced', 60),
  ('Inspired', 45),
  ('Fresh', 30),
];

/// One visual aspect of the picture, in the order it is changed: the
/// first entries are the least defining (props), the last the most
/// defining (subject type, style). A target keeps the most defining
/// aspects and changes the rest.
class _Aspect {
  const _Aspect(this.name, this.keep, this.change);
  final String name;
  final String keep;
  final List<String> change;
}

const List<_Aspect> _aspects = [
  _Aspect('Small props & details',
      'keep the same small props, accessories and secondary details', [
    'swap the small props and secondary details for different ones of the same theme',
    'replace the accessories and minor details with new, fitting ones',
  ]),
  _Aspect('Time & weather', 'keep the same time of day, season and weather', [
    'shift the time of day (e.g. sunset -> blue hour or morning) with matching light',
    'change the weather or atmosphere (mist, light rain, clear air, dust, snow)',
  ]),
  _Aspect('Pose & orientation',
      'keep the same pose, gesture and orientation of the subject', [
    'give the subject a different pose, gesture or orientation',
    'turn the subject to a different direction / show it from another side',
  ]),
  _Aspect('Background details',
      'keep the same background elements and their placement', [
    'keep the type of environment but redesign its specific background elements',
    'use different background shapes, landmarks and depth layers of the same environment type',
  ]),
  _Aspect(
      'Camera & framing',
      'keep the same camera angle, shot size, lens feel and subject placement',
      [
        'use a different camera angle (low, high, eye-level) and move the subject in the frame',
        'change the shot size (closer or wider) and the lens feel',
      ]),
  _Aspect('Lighting', 'keep the same light direction, quality and contrast', [
    'change the key light direction and quality (backlight, side light, soft overcast, rim light)',
    'add or remove a light source to change the atmosphere',
  ]),
  _Aspect('Colour palette',
      'keep the same colour palette and colour of the subject', [
    'shift the colour palette to a different harmonious scheme, including the subject colour',
    'recolour the subject and accents with a new palette that keeps the mood',
  ]),
  _Aspect('Setting / location', 'keep the same kind of location', [
    'move the scene to a different location of the same genre',
    'change the environment type (field -> forest, city -> coast, indoor -> outdoor)',
  ]),
  _Aspect('Subject design',
      'keep the same subject design, variety, identity and materials', [
    'redesign the main subject (other variety / identity / outfit / shape) while keeping what kind of thing it is',
  ]),
  _Aspect('Subject type', 'keep the same kind of main subject', [
    'replace the main subject with a different but related subject of the same theme',
  ]),
  _Aspect(
      'Style & medium', 'keep the same art style, medium and rendering look', [
    'reinterpret it in a neighbouring style or medium',
  ]),
];

/// What a similarity target keeps and changes.
class SimilarityPlan {
  SimilarityPlan(this.target, this.keep, this.change);
  final int target;

  /// Aspect names kept identical / changed.
  final List<String> keep;
  final List<String> change;

  String get band => target >= 85
      ? 'Near copy'
      : target >= 70
          ? 'Close variation'
          : target >= 55
              ? 'Balanced variation'
              : target >= 40
                  ? 'Inspired new picture'
                  : 'Fresh new picture';
}

int _changeCount(int target) {
  final t = target.clamp(minSimilarityTarget, maxSimilarityTarget);
  // Calibrated against the AI (human-like) judge: keeping camera,
  // framing and background already reads ~90 % similar, so mid targets
  // must change them. 90 -> 1, 80 -> 3, 65 -> 5, 50 -> 7, 30 -> 9.
  if (t >= 88) return 1;
  if (t >= 82) return 2;
  if (t >= 75) return 3;
  if (t >= 68) return 4;
  if (t >= 60) return 5;
  if (t >= 52) return 6;
  if (t >= 44) return 7;
  if (t >= 34) return 8;
  return 9;
}

SimilarityPlan planFor(int target) {
  final n = _changeCount(target);
  return SimilarityPlan(
    target,
    [for (final a in _aspects.skip(n)) a.name],
    [for (final a in _aspects.take(n)) a.name],
  );
}

/// The SIMILARITY TARGET block appended to the instruction. It is
/// explicit about what stays and what changes, so Gemini follows the
/// chosen percentage instead of guessing.
String similarityBrief(int target, int seed, {String boost = ''}) {
  final t = target.clamp(minSimilarityTarget, maxSimilarityTarget);
  final n = _changeCount(t);
  final r = math.Random(seed);
  final intensity = t >= 75
      ? 'subtle but clearly visible'
      : t >= 50
          ? 'clear'
          : 'strong';
  final viewer = t >= 85
      ? 'a viewer sees the same scene, re-shot with small differences'
      : t >= 70
          ? 'a viewer instantly recognises the same subject and scene, with a few obvious differences'
          : t >= 55
              ? 'a viewer recognises the same subject and theme, but it is clearly a different picture'
              : t >= 40
                  ? 'a viewer sees the same theme and mood, but a new picture with its own subject details and scene'
                  : 'only the genre, mood and quality level are shared; everything else is new';
  final b = StringBuffer()
    ..write('\n\nSIMILARITY TARGET: $t% (this overrides every other '
        'originality rule above).\n')
    ..write('The new image must look about $t% similar to the reference - '
        '$viewer.\n')
    ..write('KEEP IDENTICAL (describe these exactly as seen):\n');
  for (final a in _aspects.skip(n)) {
    b.write('- ${a.keep}\n');
  }
  b.write('CHANGE ($intensity changes, exactly these and nothing else):\n');
  for (final a in _aspects.take(n)) {
    b.write('- ${a.change[r.nextInt(a.change.length)]}\n');
  }
  b
    ..write('Do not change more than listed and do not change less. Before '
        'answering, picture both images side by side and check that the '
        'similarity really is about $t%. ')
    ..write('Never mention the reference, the target or these lists in the '
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
