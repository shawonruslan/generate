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
        ', serene dawn atmosphere, soft first light of day, gentle warm-gold horizon glow melting into cool soft blues, delicate long shadows, fresh tranquil mood, photorealistic fine detail',
        ', bright afternoon daylight, vivid crystal-clear illumination, strong natural sunlight, sharp defined details, vibrant true colors, energetic clarity',
        ', warm golden hour light, amber and rose tones raking across the scene, long soft shadows, glowing edges, gentle warmth',
        ', tranquil moonlit night, deep indigo and blue tones, soft silver lunar highlights, gentle glow on key surfaces, calm nocturnal serenity',
      ],
    ),
    SetArc(
      'bloom',
      'Bloom cycle',
      'The subject blooms and rests through the day.',
      [
        ', early morning, the subject newly awakening, delicate buds beginning to open, fresh dewy softness, gentle dawn light',
        ', midday, the subject in full bloom at its peak, vibrant and alive, maximum vitality, bright clear light',
        ', golden evening, the subject mature and complete, warm rich fullness, graceful and radiant',
        ', night, the subject at rest, gently closed in calm slumber, serene moonlit tranquility',
      ],
    ),
    SetArc(
      'rhythm',
      'Daily rhythm',
      'The scene goes quiet, busy, then quiet again.',
      [
        ', quiet early morning, the scene calm and nearly empty, soft first light, peaceful awakening, stillness',
        ', bustling midday peak, the scene alive with movement and energy, vibrant activity all around',
        ', evening wind-down, warm sociable glow, movement slowing gracefully, relaxed and inviting atmosphere',
        ', deep night stillness, the scene asleep and empty, tranquil solitude under soft moonlight',
      ],
    ),
  ];

  static const List<SetArc> battery = [
    SetArc(
      'energy',
      'Energy glow',
      'Pure glow progression, identical scene.',
      [
        ', dormant scene at rest, deep velvety shadows, only the faintest ember-like residual glow, stillness, minimal light, quiet and dark',
        ', a faint glow awakening at the heart of the scene, subtle luminous traces along edges, darkness yielding to first light',
        ', growing radiant energy, luminous light spreading gracefully through the scene, balanced interplay of glow and shadow',
        ', bright vivid illumination, strong flowing luminous energy, confident brilliance, rich highlights and depth',
        ', intense brilliant luminosity, light blooming outward from the core, striking highlights, powerful radiant presence',
        ', maximum radiance, the entire scene blazing with full luminous power, dazzling brilliant light, breathtaking glow',
      ],
    ),
    SetArc(
      'growth',
      'Growth',
      'The subject grows from tiny to monumental.',
      [
        ', a tiny seed of the subject, minimal and small, vast quiet space around it, dormant potential',
        ', the subject sprouting, small but reaching upward, first signs of life and growth',
        ', the subject growing steadily, gaining form, presence and detail',
        ', the subject large and thriving, bold confident presence filling the frame',
        ', the subject near-monumental, powerful and expansive, commanding the scene',
        ', the subject at monumental full scale, breathtaking complete form, awe-inspiring presence',
      ],
    ),
    SetArc(
      'awaken',
      'Awakening',
      'The subject wakes from stillness to full dynamism.',
      [
        ', the subject dormant and utterly still, deep in slumber, motionless silence',
        ', the faintest stir, the first hint of movement, quiet anticipation',
        ', the subject stirring awake, becoming aware, gentle graceful motion beginning',
        ', the subject active and dynamic, full of flowing motion and life',
        ', the subject intensely alive, powerful dynamic energy radiating outward',
        ', the subject at peak vitality, explosive lifelike dynamism, utterly captivating',
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
        SetType.single => 'One image per prompt.',
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
      SetVariant('Image', ''),
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
