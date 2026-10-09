/// Model catalog and option lists for the Cloudinary Image Generation API.
class AiModels {
  /// Valid `model.id` values for POST /text_to_image.
  static const List<String> textToImage = [
    'nano-banana-1',
    'nano-banana-2-lite',
    'nano-banana-2',
    'flux-2-klein-9b',
    'flux-2-flash',
    'flux-2-pro',
    'recraft-v3',
    'recraft-v4',
    'recraft-v4.1-utility',
    'recraft-v4.1-utility-pro',
    'gpt-image-1-mini',
    'gpt-image-2',
    'gpt-image-2.5-flare',
    'gpt-image-2.5-sunburst',
    'ideogram-v4-base',
    'ideogram-v4-turbo',
    'muse-image',
    'mai-image-2.5',
    'seedream-5-lite',
    'seedream-5-pro',
    'grok-imagine-image',
    'grok-imagine-image-2.0-low',
    'qwen-image-3',
  ];

  /// Base ids that have a `-edit` counterpart usable on POST /image_to_image.
  static const Set<String> _editCapable = {
    'nano-banana-1',
    'nano-banana-2-lite',
    'nano-banana-2',
    'flux-2-klein-9b',
    'flux-2-flash',
    'flux-2-pro',
    'recraft-v3',
    'gpt-image-1-mini',
    'gpt-image-2',
    'gpt-image-2.5-flare',
    'gpt-image-2.5-sunburst',
    'muse-image',
    'mai-image-2.5',
    'seedream-5-lite',
    'seedream-5-pro',
    'grok-imagine-image',
    'grok-imagine-image-2.0-low',
    'qwen-image-3',
  };

  /// Returns the `-edit` model id for image_to_image, or null when the model
  /// has no edit counterpart (use auto mode instead).
  static String? editIdFor(String baseId) =>
      _editCapable.contains(baseId) ? '$baseId-edit' : null;

  /// `-edit` model ids offered in the image-to-image picker.
  static List<String> get imageToImage =>
      textToImage.where(_editCapable.contains).map((m) => '$m-edit').toList();
}

/// Supported aspect ratios (Cloudinary DeclarativeImageSize).
class AspectRatios {
  static const List<String> all = ['1:1', '16:9', '9:16', '4:3', '3:4'];

  /// Width/height factors used to draw the ratio preview chips.
  static List<double> factors(String ratio) {
    switch (ratio) {
      case '16:9':
        return [16, 9];
      case '9:16':
        return [9, 16];
      case '4:3':
        return [4, 3];
      case '3:4':
        return [3, 4];
      default:
        return [1, 1];
    }
  }
}

/// Supported resolutions (longest edge: 0.5K~512, 1K~1024, 2K~2048, 4K~4096).
class Resolutions {
  static const List<String> all = ['0.5K', '1K', '2K', '4K'];
}

/// Supported output formats.
class OutputFormats {
  static const List<String> all = ['png', 'jpeg', 'webp'];
}

/// Batch set types mirroring the Drawstock wallpaper pipeline.
enum SetType { single, h24, dual, battery, mix }

class SetVariant {
  final String label;
  final String suffix;
  const SetVariant(this.label, this.suffix);
}

/// A story arc: how a set's subject progresses across its variants.
/// Stages are prompt fragments, one per variant (4 for 24h, 6 for battery).
class SetArc {
  final String id;
  final String label;
  final String hint;
  final List<String> stages;
  const SetArc(this.id, this.label, this.hint, this.stages);
}

class SetArcs {
  static const List<SetArc> h24 = [
    SetArc(
      'light',
      'Light only',
      'Only the lighting and atmosphere change.',
      [
        ', soft dawn light washing over the scene, warm rose-gold color temperature, gentle misty atmosphere, delicate long soft shadows, fresh tranquil mood, photorealistic fine detail',
        ', harsh bright midday light, neutral white sunlight from above, strong crisp shadows, vivid true colors, intense clarity',
        ', warm ember-orange sunset light raking low across the scene, long dramatic shadows, glowing rim light tracing every edge, rich warmth',
        ', cold blue moonlight, deep dark shadows, silver highlights gliding over surfaces, dark tranquil nocturnal mood',
      ],
    ),
    SetArc(
      'bloom',
      'Bloom cycle',
      'The subject blooms and rests through the day.',
      [
        ', soft dawn light, the subject newly awakening, delicate buds beginning to open, rose-gold glow, misty fresh atmosphere',
        ', harsh midday sun, the subject in full bloom at its peak, vivid saturated colors lit brightly, intense vitality',
        ', ember-orange sunset light, the subject mature and complete, warm glowing rim light on its form, rich dramatic warmth',
        ', cold moonlight, the subject at rest gently closed, silver highlights on its silhouette, deep blue calm',
      ],
    ),
    SetArc(
      'rhythm',
      'Daily rhythm',
      'The scene goes quiet, busy, then quiet again.',
      [
        ', soft pale dawn light, the scene calm and nearly empty, misty quiet atmosphere, gentle stillness',
        ', harsh bright midday light, the scene alive with movement, sharp shadows, vivid energetic clarity',
        ', ember-orange evening light, long dramatic shadows, warm glowing atmosphere as the light fades',
        ', cold blue moonlight, the scene asleep and empty, deep shadows, silent tranquil mood',
      ],
    ),
  ];

  static const List<SetArc> battery = [
    SetArc(
      'energy',
      'Energy glow',
      'Pure glow progression, identical scene and identical hue.',
      [
        ', charge 0 of 100: about 5 percent of the frame lit, one coin-sized dim ember of the scene own glow hue, no bloom, the rest crushed black',
        ', charge 20 of 100: about 20 percent of the frame lit, the same hue as a thin low-intensity core with a tight halo twice its size, faint spill on the nearest surface, outer frame still deep shadow',
        ', charge 40 of 100: about 40 percent of the frame lit, the identical hue clearly brighter, halo reaching a quarter of the frame width, visible rays and reflections at mid distance, edges still dark',
        ', charge 60 of 100: about 60 percent of the frame lit and two stops brighter than before, the same hue burning hot with bloom across half the frame, strong rays over the whole mid-ground, only corners dark',
        ', charge 80 of 100: about 80 percent of the frame lit, the unchanged hue near-white hot at the core, heavy bloom, lens flare and volumetric beams, bright haze, almost no shadow left',
        ', charge 100 of 100: the entire frame flooded at maximum output, core blown out white with the same hue at its rim, extreme bloom and star-burst flare, glowing haze everywhere, zero dark areas',
      ],
    ),
    SetArc(
      'growth',
      'Growth',
      'The subject grows from tiny to monumental, same glow hue throughout.',
      [
        ', charge 0 of 100: a tiny seed of the subject occupying about a tenth of the frame height in near-darkness, about 5 percent of the frame lit by one faint ember of its own glow hue',
        ', charge 20 of 100: the subject sprouting to about a quarter of the frame height, about 20 percent of the frame lit, the same hue a thin core with a tight halo, the rest in deep shadow',
        ', charge 40 of 100: the subject at about half the frame height, about 40 percent of the frame lit, the identical hue brighter with a halo a quarter of the frame wide, rays and reflections appearing',
        ', charge 60 of 100: the subject filling about two thirds of the frame and two stops brighter, the same hue burning hot, bloom across half the frame, only corners dark',
        ', charge 80 of 100: the subject near-monumental filling most of the frame, about 80 percent of the frame lit, the unchanged hue near-white hot, heavy bloom, flare and volumetric beams',
        ', charge 100 of 100: the subject monumental and dominating the frame, the whole image flooded at maximum output in the same hue, blown out white core, extreme bloom, star-burst flare, zero dark areas',
      ],
    ),
    SetArc(
      'awaken',
      'Awakening',
      'The subject wakes from stillness to full dynamism, same glow hue throughout.',
      [
        ', charge 0 of 100: the subject dormant and perfectly still, about 5 percent of the frame lit by a dying ember of its own glow hue, no bloom, crushed black surroundings',
        ', charge 20 of 100: the first stir, about 20 percent of the frame lit, one thin crack of the same hue with a tight halo breaking the dark, everything else in deep shadow',
        ', charge 40 of 100: the subject stirring awake with gentle motion, about 40 percent of the frame lit, the identical hue spreading, halo a quarter of the frame wide, rays and reflections at mid distance',
        ', charge 60 of 100: the subject active and dynamic, about 60 percent of the frame lit and two stops brighter, the same hue burning hot, bloom across half the frame, motion trails, only corners dark',
        ', charge 80 of 100: the subject intensely alive, about 80 percent of the frame lit, the unchanged hue near-white hot, heavy bloom, lens flare, volumetric beams, energy streaming off its form',
        ', charge 100 of 100: the subject at explosive peak vitality, the whole frame flooded at maximum output in the exact same hue, blown out white core, extreme bloom and star-burst flare, zero dark areas',
      ],
    ),
  ];

  static bool _hasAny(String p, List<String> words) =>
      words.any(p.contains);

  /// Smart pick for 24h arcs from prompt keywords (local, no API call).
  static String suggestH24(String prompt) {
    final p = prompt.toLowerCase();
    if (_hasAny(p, [
      'flower', 'lotus', 'bloom', 'blossom', 'plant', 'tree', 'leaf',
      'leaves', 'garden', 'petal', 'rose', 'nature', 'forest', 'flora'
    ])) {
      return 'bloom';
    }
    if (_hasAny(p, [
      'city', 'street', 'urban', 'people', 'crowd', 'market', 'traffic',
      'cafe', 'town', 'village', 'lifestyle'
    ])) {
      return 'rhythm';
    }
    return 'light';
  }

  /// Smart pick for battery arcs from prompt keywords (local, no API call).
  static String suggestBattery(String prompt) {
    final p = prompt.toLowerCase();
    if (_hasAny(p, [
      'flower', 'plant', 'tree', 'seed', 'leaf', 'garden', 'crystal',
      'bloom', 'nature', 'lotus'
    ])) {
      return 'growth';
    }
    if (_hasAny(p, [
      'creature', 'dragon', 'animal', 'being', 'spirit', 'robot',
      'phoenix', 'bird', 'beast'
    ])) {
      return 'awaken';
    }
    return 'energy';
  }
}

class SetTypes {
  /// Shared negative guard: wallpapers must never contain rendered text,
  /// numbers, symbols, icons or watermarks. Battery stages are described
  /// purely as light energy - never with percents or the word "battery" -
  /// because mentioning them makes models draw "20%" text or battery icons.
  static const noTextGuard =
      ', no text, no letters, no numbers, no symbols, no icons, no watermark';

  static String label(SetType t) => switch (t) {
        SetType.single => 'Single',
        SetType.h24 => '24-Hour',
        SetType.dual => 'Dual',
        SetType.battery => 'Battery',
        SetType.mix => 'Mix',
      };

  static String description(SetType t) => switch (t) {
        SetType.single =>
          'Portrait wallpaper plus its 1:1 foldable/tablet companion (2000x2000), re-framed from the same artwork.',
        SetType.h24 =>
          '4 images per prompt. A neutral anchor image is generated first '
          '(used only as the chaining reference, not part of the set); '
          'Morning, Afternoon, Evening and Night are chained from it via '
          'image-to-image, keeping the identical subject and background. '
          'Never any text or watermarks. Story arc auto-picks per prompt '
          '(light, bloom, rhythm) or set it manually.',
        SetType.dual =>
          '2 images per prompt. A neutral anchor image is generated first '
          '(reference only, not part of the set); Lock (tight close-up) and '
          'Home (pulled-back wide view) are chained from it.',
        SetType.battery =>
          '6 images per prompt as a pure light-energy progression. A neutral '
          'anchor image is generated first (reference only, not part of the '
          'set); the 0%-100% stages are chained from it - identical scene, '
          'growing glow, never any text, numbers, percent signs or battery icons. '
          'Story arc auto-picks per prompt (energy, growth, awakening) or set it manually.',
        SetType.mix =>
          'Split your prompts across 24-Hour, Battery, Dual and Single sets. '
          'Set the counts yourself or auto-distribute. Every multi-image set '
          'chains its variants from its own hidden anchor image for consistency.',
      };

  static const Map<SetType, List<SetVariant>> variants = {
    SetType.single: [
      // The portrait master: also the chaining anchor for its companion.
      SetVariant('Wallpaper', ''),
      // 1:1 foldable/tablet companion. NEVER a new scene: the portrait
      // artwork is recomposed to a square frame via image edit - same
      // subject, palette and mood, background extended to fill the square.
      SetVariant(
          'Landscape',
          ', recompose this wallpaper into a square 1:1 frame'
          ', keep the exact same subject identity, geometry, pose, materials, color palette, lighting direction, rendering style and mood'
          ' - it must be recognizably the same wallpaper at thumbnail size'
          ', extend the existing background, environment and atmosphere naturally to fill the square canvas'
          ', hero mass slightly below center, whole hero inside the frame with at least 6 percent safe margin on every edge'
          ', quiet low-detail upper third for the clock and widgets'
          ', do not crop the subject, do not stretch or squash, do not duplicate the subject or add new structures or elements the reference does not contain$noTextGuard'),
    ],
    SetType.h24: [
      SetVariant('Morning',
          ', 6 am dawn: key light low on the horizon from the left at about 10 degrees elevation, roughly 3000K rose-gold color temperature, long soft shadows stretching to the right, low-lying mist, cool blue shadow tones, high-key gentle contrast, fresh tranquil mood$noTextGuard'),
      SetVariant('Afternoon',
          ', 1 pm midday: key light almost straight overhead at about 80 degrees elevation, roughly 5600K neutral white daylight, short hard shadows directly under the subject, no mist, maximum color saturation and micro-detail, bright high-contrast clarity$noTextGuard'),
      SetVariant('Evening',
          ', 6 pm golden hour: key light raking in low from the right at about 8 degrees elevation, roughly 2200K amber-orange color temperature, long dramatic shadows falling to the left, warm haze and strong rim light tracing every edge, glowing low-sun flare$noTextGuard'),
      SetVariant('Night',
          ', 11 pm night: no sun, only cool moonlight from high behind at roughly 7500K deep indigo, about 70 percent of the frame in deep shadow, silver specular highlights on edges only, soft local glow from the scene own light sources, low-key nocturnal calm$noTextGuard'),
    ],
    SetType.dual: [
      SetVariant('Lock',
          ', lock screen framing: macro close-up, the hero fills about 80 percent of the frame height, shallow depth of field with a softly blurred background, striking fine surface detail, hero mass in the lower two thirds$noTextGuard'),
      SetVariant('Home',
          ', home screen framing: wide establishing view of the same scene pulled far back, the hero now occupies only about 30 percent of the frame height and sits low, deep focus, generous calm negative space and quiet low-detail area across the upper half for icons and widgets$noTextGuard'),
    ],
    SetType.battery: [
      // Measurable luminance ladder. Each stage states an ABSOLUTE target
      // (lit area, brightness, bloom radius, shadow depth) instead of a
      // vague adjective, because "bright" vs "brilliant" vs "maximum"
      // makes image models produce near-identical frames at the top end.
      SetVariant('0%',
          ', charge level 0 of 100: the scene is almost completely dark, about 5 percent of the frame carries any light, a single dim ember of its own glow hue no larger than a coin, no bloom, no light spill, deep crushed black shadows filling the rest of the frame$noTextGuard'),
      SetVariant('20%',
          ', charge level 20 of 100: about 20 percent of the frame is lit, the glow is a thin low-intensity core with a tight halo roughly twice its own size, faint light spill on the nearest surface only, the outer two thirds of the frame still sit in deep shadow$noTextGuard'),
      SetVariant('40%',
          ', charge level 40 of 100: about 40 percent of the frame is lit, the glow core is clearly brighter and its halo now reaches roughly a quarter of the frame width, visible light rays and reflections on mid-distance surfaces, shadows softened to dark grey but the frame edges stay dark$noTextGuard'),
      SetVariant('60%',
          ', charge level 60 of 100: about 60 percent of the frame is lit and roughly two stops brighter than the previous stage, the glow core is burning hot with a wide bloom reaching half the frame width, strong rays and reflections across the whole mid-ground, only the frame corners remain dark$noTextGuard'),
      SetVariant('80%',
          ', charge level 80 of 100: about 80 percent of the frame is lit and clearly brighter again, the glow core is near-white hot at its center, heavy bloom with visible lens flare and volumetric light beams crossing the frame, bright haze filling the air, barely any shadow left except thin contact shadows$noTextGuard'),
      SetVariant('100%',
          ', charge level 100 of 100: the whole frame is flooded with light at maximum output, the glow core is blown out pure white at its center with saturated hue at its rim, extreme bloom covering the entire frame, strong star-burst flare, glowing atmospheric haze everywhere, zero dark areas anywhere in the image$noTextGuard'),
    ],
    // Mix has no fixed variants: each prompt is assigned one of the
    // concrete set types at generation time.
    SetType.mix: [],
  };
}
