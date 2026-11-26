import 'element_plan.dart';
import 'originality.dart';

/// How one attempt is generated while matching a similarity target.
enum MatchMode {
  /// Text only (prompt from Image to Prompt): the model invents its own
  /// composition, so pixel similarity usually lands around 10-25 %.
  text,

  /// The reference picture is the base image (image_to_image) and the
  /// prompt lists what to keep / change: layout and palette carry over,
  /// so 40-90 % targets become reachable.
  guided,
}

class MatchStep {
  const MatchStep(this.mode, this.brief);
  final MatchMode mode;

  /// Similarity asked for in the guided edit instruction (can differ
  /// from the user's target to correct the previous miss).
  final int brief;

  @override
  String toString() => '${mode.name}:$brief';
}

/// Measured similarity within +-[matchTolerance] of the target counts as
/// a hit.
const int matchTolerance = 10;


/// Every attempt sends the source picture (the one the prompt was made
/// from) as [1] together with the generated prompt.
MatchStep firstMatchStep(int target) => MatchStep(MatchMode.guided, target);

bool isTargetHit(int target, double measured) =>
    (measured - target).abs() <= matchTolerance;

/// Next attempt after [last] measured [measured] %, or null when the
/// target is hit or no better move exists. Always image_to_image; only
/// the similarity asked for in the prompt is corrected.
MatchStep? nextMatchStep(int target, MatchStep last, double measured) {
  if (isTargetHit(target, measured)) return null;
  final miss = (target - measured).round(); // >0: too different
  final delta = miss.abs().clamp(10, 30);
  final b = miss > 0
      ? (last.brief + delta).clamp(minSimilarityTarget, maxSimilarityTarget)
      : (last.brief - delta).clamp(minSimilarityTarget, maxSimilarityTarget);
  if (b == last.brief) return null;
  return MatchStep(MatchMode.guided, b);
}

/// image_to_image prompt: the source picture is [1] (Cloudinary
/// reference syntax) and the generated prompt describes the picture to
/// make; the target says how close to [1] it must stay.
String guidedPrompt(String prompt, int brief,
    {List<String> palette = const [],
    String tone = '',
    List<SceneElement> elements = const []}) {
  final b = brief.clamp(minSimilarityTarget, maxSimilarityTarget);
  if (elements.length >= 5) {
    return _elementGuidedPrompt(prompt, b, elements,
        palette: palette, tone: tone);
  }
  final plan = planFor(b);
  final keepColour = plan.keep.contains('Colour palette');
  final keepLight = plan.keep.contains('Lighting');
  final keepFrame = plan.keep.contains('Camera & framing');
  final keep = plan.keep.map((e) => e.toLowerCase()).join(', ');
  final change = plan.change.map((e) => e.toLowerCase()).join(', ');
  final sb = StringBuffer()
    ..write('Generate a new image from reference image [1] and this '
        'prompt: ${prompt.trim()}\n\n')
    ..write('Similarity to [1]: about $b%. ')
    ..write('Keep from [1]: $keep. ');
  if (keepFrame) {
    sb.write('Same camera angle, shot size, subject size and position as '
        '[1]. ');
  }
  if (keepColour && palette.isNotEmpty) {
    sb.write('Same colour palette as [1] (${palette.join(', ')}). ');
  }
  if (keepLight && tone.isNotEmpty) {
    sb.write('Same lighting and exposure as [1]: $tone. ');
  }
  final strength = b >= 75
      ? 'Small but clearly visible changes'
      : b >= 55
          ? 'Clear changes'
          : 'Strong, obvious changes';
  sb.write('$strength to: $change. Never an exact copy of [1].');
  return sb.toString();
}

/// Element-level version: the exact elements of [1] to keep and to
/// change for this similarity (re-planned for corrected briefs).
String _elementGuidedPrompt(String prompt, int b, List<SceneElement> source,
    {List<String> palette = const [], String tone = ''}) {
  final els = [
    for (final e in source)
      SceneElement(
          name: e.name,
          category: e.category,
          impact: e.impact,
          identity: e.identity)
  ];
  planElements(els, b);
  final keep = els.where((e) => !e.change).toList();
  final change = els.where((e) => e.change).toList();
  bool kept(String c) => keep.any((e) => e.category == c);
  final sb = StringBuffer()
    ..write('Generate a new image from reference image [1] and this '
        'prompt: ${prompt.trim()}\n\n')
    ..write('Similarity to [1]: about $b% of its visual weight stays.\n')
    ..write('KEEP exactly as in [1]:\n');
  for (final e in keep) {
    sb.write('- ${e.name}\n');
  }
  if (kept('colour') && palette.isNotEmpty) {
    sb.write('- colour palette ${palette.join(', ')}\n');
  }
  if (kept('lighting') && tone.isNotEmpty) {
    sb.write('- exposure: $tone\n');
  }
  final strength = b >= 75
      ? 'small but clearly visible'
      : b >= 55
          ? 'clear'
          : 'strong, obvious';
  sb.write('CHANGE ($strength changes, as described in the prompt):\n');
  for (final e in change) {
    sb.write('- ${e.name}\n');
  }
  sb.write('Nothing else changes. Never an exact copy of [1].');
  return sb.toString();
}
