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

class SetTypes {
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
          '4 images per prompt: Morning, Afternoon, Evening, Night.',
        SetType.dual =>
          '2 images per prompt: Lock (tight close-up) + Home (pulled-back wide).',
        SetType.battery =>
          '6 images per prompt: 0%, 20%, 40%, 60%, 80%, 100% charge stages.',
        SetType.mix =>
          'Split your prompts across 24-Hour, Battery, Dual and Single sets. '
          'Set the counts yourself or auto-distribute.',
      };

  static const Map<SetType, List<SetVariant>> variants = {
    SetType.single: [
      SetVariant('Image', ''),
    ],
    SetType.h24: [
      SetVariant('Morning', ', soft morning light, dawn glow'),
      SetVariant('Afternoon', ', bright afternoon light, crisp daylight'),
      SetVariant('Evening', ', warm evening glow, golden hour'),
      SetVariant('Night', ', moonlit night, deep blue tones'),
    ],
    SetType.dual: [
      SetVariant(
          'Lock', ', lock screen wallpaper, tight close-up composition'),
      SetVariant('Home',
          ', home screen wallpaper, pulled-back wide view with calm empty space'),
    ],
    SetType.battery: [
      SetVariant('0%',
          ', dormant and dark, completely uncharged, 0 percent battery, no glow'),
      SetVariant(
          '20%', ', faint initial glow waking up, 20 percent battery charge'),
      SetVariant('40%',
          ', growing brightness and energy, 40 percent battery charge'),
      SetVariant('60%', ', bright and vivid, 60 percent battery charge'),
      SetVariant(
          '80%', ', intense luminous glow, 80 percent battery charge'),
      SetVariant('100%',
          ', maximum radiance, fully charged 100 percent battery'),
    ],
    // Mix has no fixed variants: each prompt is assigned one of the
    // concrete set types at generation time.
    SetType.mix: [],
  };
}
