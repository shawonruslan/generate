import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../browser/image_prompt_service.dart';
import '../cloudinary_api.dart';
import 'colour_match.dart';
import 'originality.dart';
import 'similarity.dart';
import 'target_match.dart';

/// Result of [generateToTarget].
class TargetOutcome {
  TargetOutcome(this.result, this.similarity, this.target, this.tries);
  final GenerationResult result;
  final double? similarity;
  final int target;
  final int tries;
}

/// Uploaded reference URL per Image to Prompt item id.
final Map<String, String> _refUploads = {};

Future<Uint8List?> _fetch(String url) async {
  try {
    final r =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
    if (r.statusCode == 200) return r.bodyBytes;
  } catch (_) {}
  return null;
}

/// Generates [prompt] so the measured similarity to the Image to Prompt
/// reference [ref] lands near its target:
/// 1. targets >= 38 % start from the reference picture ([1]) with a
///    keep/change instruction + its exact palette and exposure,
/// 2. colours/tone are transferred towards the reference as strongly as
///    the target asks,
/// 3. the result is measured and regenerated with a corrected strength
///    (up to [ImagePromptService.matchTries] extra images),
/// 4. the closest image is kept (colour-matched copy uploaded).
/// Returns null when the reference picture is not available.
Future<TargetOutcome?> generateToTarget({
  required CloudinaryApi api,
  required String prompt,
  required ImagePromptItem ref,
  required String textModel,
  required String aspectRatio,
  required String resolution,
  required String format,
  required int Function(int attempt) seed,
  Future<void> Function()? beforeRetry,
  void Function(String status, Duration elapsed)? onProgress,
  void Function(String line)? onStatus,
  String Function(String url)? measureUrl,
}) async {
  final svc = ImagePromptService.instance;
  final target = (ref.target > 0 ? ref.target : svc.similarityTarget)
      .clamp(minSimilarityTarget, maxSimilarityTarget);
  final refBytes = await svc.referenceBytes(ref);
  if (refBytes == null) return null;
  Future<String?> refUrl() async {
    final have = _refUploads[ref.id];
    if (have != null) return have;
    try {
      final u = await api.uploadImage(refBytes);
      _refUploads[ref.id] = u;
      return u;
    } catch (e) {
      onStatus?.call('$e - using text-only generation.');
      return null;
    }
  }

  final look = await referenceLookInBackground(refBytes);
  final colourAmount = colourAmountFor(target);
  var step = firstMatchStep(target);
  GenerationResult? best;
  double? bestSim;
  Uint8List? bestFixed;
  final tries = svc.matchTries;
  var used = 0;
  var aiJudge = true;
  int? lastAi;
  for (var attempt = 0; attempt <= tries; attempt++) {
    if (attempt > 0) await beforeRetry?.call();
    used++;
    GenerationResult? r;
    if (step.mode == MatchMode.guided) {
      final u = await refUrl();
      if (u == null) {
        step = MatchStep(MatchMode.text, target);
      } else {
        try {
          r = await api.imageToImage(
            prompt: guidedPrompt(prompt, step.brief,
                palette: look?.paletteHex ?? const [],
                tone: look?.tone ?? '',
                elements: ref.elements),
            modelId: null,
            referenceUrls: [u],
            aspectRatio: aspectRatio,
            resolution: resolution,
            format: format,
            seed: seed(attempt),
            onProgress: onProgress,
          );
        } catch (e) {
          if (best != null) break;
          step = MatchStep(MatchMode.text, target);
        }
      }
    }
    r ??= await api.textToImage(
      prompt: prompt,
      modelId: textModel,
      aspectRatio: aspectRatio,
      resolution: resolution,
      format: format,
      seed: seed(attempt),
      onProgress: onProgress,
    );
    final gen = await _fetch(measureUrl?.call(r.imageUrl) ?? r.imageUrl);
    Uint8List? fixed;
    if (gen != null && colourAmount > 0.02) {
      onStatus?.call('Matching colours to the reference...');
      try {
        fixed = await matchColoursInBackground(gen, refBytes, colourAmount);
      } catch (_) {}
    }
    final measureOn = fixed ?? gen;
    double? sim = measureOn == null
        ? null
        : (await compareImagesInBackground(refBytes, measureOn))?.similarity;
    // Pixels under-read "same scene, slightly moved" (54 % pixels vs
    // 90 % to a human), so the AI judge decides when Gemini is set up.
    if (measureOn != null && aiJudge) {
      onStatus?.call('AI judge is comparing with the reference...');
      try {
        final ai = await svc.aiReview(refBytes, measureOn);
        if (ai.similarity > 0) {
          lastAi = ai.similarity;
          sim = ai.similarity.toDouble();
        }
      } catch (_) {
        aiJudge = false; // no Gemini session: pixel analysis only
      }
    }
    if (best == null ||
        (sim != null &&
            (bestSim == null ||
                (sim - target).abs() < (bestSim - target).abs()))) {
      best = r;
      bestSim = sim;
      bestFixed = fixed;
    }
    if (sim == null) break;
    final next = nextMatchStep(target, step, sim);
    final hit = isTargetHit(target, sim);
    onStatus?.call('Target $target% - try ${attempt + 1}: ${sim.round()}% '
        '${lastAi != null ? '(AI) ' : ''}'
        'similar${hit ? ' (hit)' : next == null || attempt == tries ? '' : ', correcting...'}');
    if (next == null) break;
    step = next;
  }
  final base = best;
  if (base == null) return null;
  GenerationResult out = base;
  if (bestFixed != null) {
    try {
      final u = await api.uploadImage(bestFixed, folder: 'ais_matched');
      out = out.withImage(u, bestFixed.length);
    } catch (_) {}
  }
  return TargetOutcome(out, bestSim, target, used);
}
