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
        ', near darkness, the scene barely lit, only the faintest ember of its own glow hue flickering in deep shadow, mysterious gloom',
        ', the scene\'s own glow hue awakening dimly, thin luminous traces in the same color fighting deep shadow',
        ', the identical glow hue surging brighter, luminous color spreading over surfaces, bold clash of brilliant light and shadow',
        ', the same hue at full vivid brightness flooding the scene, powerful flowing light, glowing atmosphere, rich dramatic highlights',
        ', the unchanged hue blazing intensely, brilliant bloom and flare across the scene, overwhelming luminous brilliance',
        ', blinding maximum radiance in the exact same hue, the entire scene flooded with dazzling light of the unchanged color, extreme bloom, breathtaking brilliance',
      ],
    ),
    SetArc(
      'growth',
      'Growth',
      'The subject grows from tiny to monumental, same glow hue throughout.',
      [
        ', a tiny seed of the subject in dim near-darkness, lit only by the faintest ember of the scene\'s own glow hue, minimal and fragile',
        ', the subject sprouting, small but reaching, the same glow hue gathering faintly around it in the gloom',
        ', the subject growing steadily, the identical hue strengthening and revealing its form, the atmosphere brightening',
        ', the subject large and thriving, the same color at bright vivid intensity, bold presence, luminous atmosphere',
        ', the subject near-monumental, the unchanged hue crackling radiantly over its form, powerful brilliance',
        ', the subject at monumental full scale bathed in blinding radiant light of the exact same hue, epic luminous glory',
      ],
    ),
    SetArc(
      'awaken',
      'Awakening',
      'The subject wakes from stillness to full dynamism, same glow hue throughout.',
      [
        ', the subject dormant in near-darkness, utterly still, faint cold shadows, barely lit by a dying ember of its own glow hue',
        ', the faintest stir, a thin crack of the same glow hue breaking the dark, quiet anticipation in the gloom',
        ', the subject stirring awake, the identical hue spreading over its form, gentle motion in strengthening light of the same color',
        ', the subject active and dynamic, bright energy of the unchanged hue radiating, vivid light and flowing motion',
        ', the subject intensely alive, the same color blazing over the scene, powerful brilliance',
        ', the subject at peak vitality, engulfed in dazzling radiant light of the exact same hue, explosive brilliance',
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
          ', serene dawn atmosphere, soft first light of day, gentle warm-gold horizon glow melting into cool soft blues, delicate long shadows, fresh tranquil mood, photorealistic fine detail$noTextGuard'),
      SetVariant('Afternoon',
          ', bright afternoon daylight, vivid crystal-clear illumination, strong natural sunlight, sharp defined details, vibrant true colors, energetic clarity$noTextGuard'),
      SetVariant('Evening',
          ', warm golden hour light, amber and rose tones raking across the scene, long soft shadows, glowing edges, gentle warmth$noTextGuard'),
      SetVariant('Night',
          ', tranquil moonlit night, deep indigo and blue tones, soft silver lunar highlights, gentle glow on key surfaces, calm nocturnal serenity$noTextGuard'),
    ],
    SetType.dual: [
      SetVariant('Lock',
          ', lock screen wallpaper, tight close-up composition, striking fine detail$noTextGuard'),
      SetVariant('Home',
          ', home screen wallpaper, pulled-back wide view with calm empty space$noTextGuard'),
    ],
    SetType.battery: [
      SetVariant('0%',
          ', dormant scene at rest, deep velvety shadows, only the faintest ember-like residual glow, stillness, minimal light, quiet and dark$noTextGuard'),
      SetVariant('20%',
          ', a faint glow awakening at the heart of the scene, subtle luminous traces along edges, darkness yielding to first light$noTextGuard'),
      SetVariant('40%',
          ', growing radiant energy, luminous light spreading gracefully through the scene, balanced interplay of glow and shadow$noTextGuard'),
      SetVariant('60%',
          ', bright vivid illumination, strong flowing luminous energy, confident brilliance, rich highlights and depth$noTextGuard'),
      SetVariant('80%',
          ', intense brilliant luminosity, light blooming outward from the core, striking highlights, powerful radiant presence$noTextGuard'),
      SetVariant('100%',
          ', maximum radiance, the entire scene blazing with full luminous power, dazzling brilliant light, breathtaking glow$noTextGuard'),
    ],
    // Mix has no fixed variants: each prompt is assigned one of the
    // concrete set types at generation time.
    SetType.mix: [],
  };
}
