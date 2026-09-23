import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ports of the v26/v27 theme engine (presets, sanitize, derived palette,
/// per-element colours). Persisted per account in `zedgeTheme:v26:<acc>` and
/// shared through Firebase `dashboardSettings/theme`.
class ThemePreset {
  const ThemePreset(this.key, this.name, this.mode, this.primary, this.accent, this.bg, this.surface, this.text, {this.vibe = ''});
  final String key, name, mode, primary, accent, bg, surface, text;
  /// v27.12 - short mood line shown on the preset tile.
  final String vibe;
  bool get isDark => mode == 'dark';
}

const List<ThemePreset> kThemePresets = [
  ThemePreset('sunflower', 'Sunflower', 'light', '#ffd400', '#ffab00', '#fffdf6', '#ffffff', '#211d12'),
  ThemePreset('dark', 'Dark Gold', 'dark', '#ffd400', '#ffab00', '#0e0c08', '#181410', '#f7f1dc'),
  ThemePreset('amoled', 'AMOLED', 'dark', '#ffd400', '#ffab00', '#000000', '#0c0c0c', '#f2f2f2'),
  ThemePreset('ocean', 'Ocean', 'light', '#2f80ed', '#56ccf2', '#f5f9ff', '#ffffff', '#0f1c2e'),
  ThemePreset('midnight', 'Midnight', 'dark', '#4f8cff', '#7cc4ff', '#0a0f1e', '#121a2e', '#e6edff'),
  ThemePreset('mint', 'Mint', 'light', '#22c55e', '#10b981', '#f4fdf7', '#ffffff', '#0f2417'),
  ThemePreset('rose', 'Rose', 'light', '#ff5c8a', '#ff8fab', '#fff5f8', '#ffffff', '#2b1220'),
  ThemePreset('violet', 'Violet', 'dark', '#a78bfa', '#c084fc', '#0f0a1e', '#1a1230', '#efe9ff'),
  // v27 presets
  ThemePreset('obsidian', 'Obsidian Glass', 'dark', '#7c5cff', '#22d3ee', '#070a14', '#111829', '#e6ebff'),
  ThemePreset('aurora', 'Aurora', 'dark', '#34d399', '#60a5fa', '#06111f', '#0e1d31', '#e3f6ff'),
  ThemePreset('ember', 'Ember', 'dark', '#fb7185', '#f59e0b', '#120a0f', '#1f121a', '#ffe9ee'),
  ThemePreset('graphite', 'Graphite', 'dark', '#38bdf8', '#818cf8', '#0b0d12', '#151922', '#e5e7eb'),
  // v27.12 presets (also in the web panel + Android app)
  ThemePreset('nebula', 'Nebula', 'dark', '#c084fc', '#f472b6', '#0a0614', '#160d26', '#f3e8ff', vibe: 'Purple-pink galaxy'),
  ThemePreset('cyber', 'Cyberpunk', 'dark', '#00f0ff', '#ff2bd6', '#050510', '#0d0f22', '#e0fbff', vibe: 'Neon cyan + magenta'),
  ThemePreset('royal', 'Royal Blue', 'dark', '#3b82f6', '#fbbf24', '#050a1a', '#0b1430', '#e8efff', vibe: 'Navy with gold accent'),
  ThemePreset('forest', 'Forest', 'dark', '#4ade80', '#a3e635', '#061009', '#0d1c12', '#e6ffee', vibe: 'Deep green calm'),
  ThemePreset('lava', 'Lava', 'dark', '#ff4d4d', '#ffb347', '#0f0505', '#1c0b0b', '#ffecec', vibe: 'Hot red + amber'),
  ThemePreset('coffee', 'Coffee', 'dark', '#d4a373', '#e9c46a', '#14100c', '#211a14', '#f5ead9', vibe: 'Warm brown latte'),
  ThemePreset('neon', 'Neon Lime', 'dark', '#a3ff12', '#00e5ff', '#070a06', '#101610', '#f0ffe0', vibe: 'Electric lime glow'),
  ThemePreset('sunset', 'Sunset', 'light', '#f97316', '#ec4899', '#fff8f3', '#ffffff', '#2a1508', vibe: 'Orange to pink sky'),
  ThemePreset('sakura', 'Sakura', 'light', '#f472b6', '#a78bfa', '#fff7fb', '#ffffff', '#2d1a2a', vibe: 'Soft pink blossom'),
  ThemePreset('candy', 'Candy', 'light', '#8b5cf6', '#06b6d4', '#f7f5ff', '#ffffff', '#1e1538', vibe: 'Violet + cyan pop'),
  ThemePreset('ice', 'Ice', 'light', '#0ea5e9', '#67e8f9', '#f0f9ff', '#ffffff', '#0c2a3a', vibe: 'Cool sky blue'),
  ThemePreset('slate', 'Slate Pro', 'light', '#475569', '#0ea5e9', '#f1f5f9', '#ffffff', '#0f172a', vibe: 'Clean corporate grey'),
];

ThemePreset? presetByKey(String k) => kThemePresets.where((p) => p.key == k).firstOrNull;

/// Element colour keys (v27.8 Theme Studio "Element colors").
const List<List<String>> kThemeElementKeys = [
  ['header', 'Header bar'],
  ['sidebar', 'Sidebar'],
  ['card', 'Cards & panels'],
  ['button', 'Buttons'],
  ['ticker', 'Live ticker'],
  ['badge', 'Badges & chips'],
  ['navActive', 'Active menu item'],
];

final RegExp _hex6 = RegExp(r'^#[0-9a-f]{6}$');

/// `norm(h, fb)`
String? normHex(dynamic h, String? fb) {
  var s = (h == null ? '' : '$h').trim().toLowerCase();
  if (s.isNotEmpty && !s.startsWith('#')) s = '#$s';
  if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(s)) s = '#${s[1]}${s[1]}${s[2]}${s[2]}${s[3]}${s[3]}';
  return _hex6.hasMatch(s) ? s : fb;
}

List<int> hexRgb(String h) {
  final n = normHex(h, '#000000')!;
  return [int.parse(n.substring(1, 3), radix: 16), int.parse(n.substring(3, 5), radix: 16), int.parse(n.substring(5, 7), radix: 16)];
}

String rgbHex(List<num> c) => '#${c.map((v) {
      final x = v.round().clamp(0, 255);
      return x.toRadixString(16).padLeft(2, '0');
    }).join()}';

String mixHex(String a, String b, double t) {
  final x = hexRgb(a), y = hexRgb(b);
  return rgbHex([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t]);
}

double lumHex(String h) {
  final c = hexRgb(h).map((v) {
    final d = v / 255;
    return d <= 0.03928 ? d / 12.92 : _pow((d + 0.055) / 1.055, 2.4);
  }).toList();
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

double _pow(double b, double e) => math.pow(b, e).toDouble();

Color colorFromHex(String h) {
  final c = hexRgb(h);
  return Color.fromARGB(255, c[0], c[1], c[2]);
}

String hexFromColor(Color c) => rgbHex([(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()]);

/// Sanitized theme config (`sanitize(c)`).
class ThemeConfig {
  ThemeConfig({
    required this.preset,
    required this.primary,
    required this.accent,
    required this.bg,
    required this.surface,
    required this.text,
    required this.fontScale,
    required this.radius,
    required this.density,
    this.updatedAt = 0,
    this.updatedBy,
    this.v271 = 0,
    Map<String, String>? elements,
  }) : elements = elements ?? {};

  String preset;
  String primary, accent, bg, surface, text;
  double fontScale;
  double radius;
  String density; // comfortable | compact
  int updatedAt;
  String? updatedBy;
  int v271;
  Map<String, String> elements;

  String get mode => lumHex(bg) < 0.35 ? 'dark' : 'light';
  bool get isDark => mode == 'dark';

  static ThemeConfig get defaults => ThemeConfig(
        preset: 'obsidian',
        primary: '#7c5cff',
        accent: '#22d3ee',
        bg: '#070a14',
        surface: '#111829',
        text: '#e6ebff',
        fontScale: 1,
        radius: 1,
        density: 'comfortable',
      );

  static double _num(dynamic v, double fb, double lo, double hi) {
    final n = v is num ? v.toDouble() : double.tryParse('$v');
    final x = (n == null || n.isNaN || n.isInfinite) ? fb : n;
    return x.clamp(lo, hi).toDouble();
  }

  static ThemeConfig sanitize(dynamic c) {
    final m = c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{};
    final d = defaults;
    final out = ThemeConfig(
      preset: (m['preset'] is String && (m['preset'] as String).isNotEmpty) ? m['preset'] as String : 'custom',
      primary: normHex(m['primary'], d.primary)!,
      accent: normHex(m['accent'], d.accent)!,
      bg: normHex(m['bg'], d.bg)!,
      surface: normHex(m['surface'], d.surface)!,
      text: normHex(m['text'], d.text)!,
      fontScale: _num(m['fontScale'], 1, 0.8, 1.3),
      radius: _num(m['radius'], 1, 0, 1.6),
      density: m['density'] == 'compact' ? 'compact' : 'comfortable',
      updatedAt: (m['updatedAt'] is num) ? (m['updatedAt'] as num).toInt() : int.tryParse('${m['updatedAt'] ?? ''}') ?? 0,
      updatedBy: m['updatedBy']?.toString(),
      v271: (m['v271'] == null || m['v271'] == 0 || m['v271'] == false || m['v271'] == '') ? 0 : 1,
      elements: cleanElements(m['elements']),
    );
    return out;
  }

  static Map<String, String> cleanElements(dynamic o) {
    final r = <String, String>{};
    if (o is! Map) return r;
    for (final k in kThemeElementKeys) {
      final v = normHex(o[k[0]], null);
      if (v != null) r[k[0]] = v;
    }
    return r;
  }

  ThemeConfig copy() => ThemeConfig.sanitize(toJson());

  Map<String, dynamic> toJson() => {
        'preset': preset,
        'mode': mode,
        'primary': primary,
        'accent': accent,
        'bg': bg,
        'surface': surface,
        'text': text,
        'fontScale': fontScale,
        'radius': radius,
        'density': density,
        'updatedAt': updatedAt,
        'updatedBy': updatedBy,
        'v271': v271,
        if (elements.isNotEmpty) 'elements': Map<String, String>.from(elements),
      };

  /// `presetOf(c)` - which preset matches the five colours (null = custom palette).
  String? matchingPreset() {
    for (final p in kThemePresets) {
      if (p.primary == primary && p.accent == accent && p.bg == bg && p.surface == surface && p.text == text) return p.key;
    }
    return null;
  }

  void applyPreset(ThemePreset p) {
    primary = p.primary;
    accent = p.accent;
    bg = p.bg;
    surface = p.surface;
    text = p.text;
    preset = matchingPreset() ?? 'custom';
  }
}

/// Derived palette (`apply(c)`), exposed as Flutter colours.
class ZedgePalette {
  ZedgePalette(this.cfg) {
    final dark = cfg.isDark;
    final p = cfg.primary, a = cfg.accent, sf = cfg.surface, tx = cfg.text;
    onPrimaryHex = lumHex(p) > 0.25 ? (lumHex(sf) < 0.1 ? sf : '#1c1a12') : '#ffffff';
    onInkHex = dark ? tx : '#ffffff';
    inkHex = dark ? mixHex(sf, tx, 0.14) : tx;
    primary2Hex = mixHex(p, a, 0.5);
    accent2Hex = mixHex(a, dark ? tx : '#000000', dark ? 0.18 : 0.14);
    primaryLightHex = mixHex(p, sf, 0.45);
    mutedHex = mixHex(tx, sf, 0.45);
    accentDeepHex = mixHex(a, tx, 0.35);
    ink2Hex = mixHex(inkHex, p, 0.10);
    surfaceHoverHex = mixHex(sf, p, 0.05);
    borderHex = mixHex(sf, tx, dark ? 0.14 : 0.10);
    headerStartHex = mixHex(p, sf, 0.25);
    warningEndHex = mixHex(p, a, 0.7);
    // DERIVED tints used by the web CSS (subset that matters for widgets)
    tintSoftHex = mixHex(mixHex(sf, p, 0.169), mutedHex, 0); // --x-fff9db (drop hover)
    tintCardHex = mixHex(mixHex(sf, p, 0.099), mutedHex, 0.009); // --x-fdf9ec
    tintChipHex = mixHex(mixHex(sf, p, 0.278), mutedHex, 0); // --x-fff3c4
    deepHex = mixHex(a, tx, 0.166); // --x-e07b00
  }

  final ThemeConfig cfg;
  late final String onPrimaryHex, onInkHex, inkHex, primary2Hex, accent2Hex, primaryLightHex, mutedHex, accentDeepHex, ink2Hex;
  late final String surfaceHoverHex, borderHex, headerStartHex, warningEndHex, tintSoftHex, tintCardHex, tintChipHex, deepHex;

  bool get isDark => cfg.isDark;
  Color get primary => colorFromHex(cfg.primary);
  Color get accent => colorFromHex(cfg.accent);
  Color get bg => colorFromHex(cfg.bg);
  Color get surface => colorFromHex(cfg.surface);
  Color get text => colorFromHex(cfg.text);
  Color get onPrimary => colorFromHex(onPrimaryHex);
  Color get onInk => colorFromHex(onInkHex);
  Color get ink => colorFromHex(inkHex);
  Color get ink2 => colorFromHex(ink2Hex);
  Color get primary2 => colorFromHex(primary2Hex);
  Color get accent2 => colorFromHex(accent2Hex);
  Color get primaryLight => colorFromHex(primaryLightHex);
  Color get muted => colorFromHex(mutedHex);
  Color get accentDeep => colorFromHex(accentDeepHex);
  Color get surfaceHover => colorFromHex(surfaceHoverHex);
  Color get border => colorFromHex(borderHex);
  Color get tintSoft => colorFromHex(tintSoftHex);
  Color get tintCard => colorFromHex(tintCardHex);
  Color get tintChip => colorFromHex(tintChipHex);
  Color get deep => colorFromHex(deepHex);

  double get radiusLg => 24 * cfg.radius;
  double get radiusMd => 16 * cfg.radius;
  double get radiusSm => 12 * cfg.radius;
  double get fontScale => cfg.fontScale;
  bool get compact => cfg.density == 'compact';

  LinearGradient get primaryGradient => LinearGradient(colors: [primary, accent], begin: Alignment.topLeft, end: Alignment.bottomRight);
  LinearGradient get secondaryGradient => LinearGradient(colors: [primaryLight, primary2], begin: Alignment.topLeft, end: Alignment.bottomRight);
  LinearGradient get accentGradient => LinearGradient(colors: [primary2, accent2], begin: Alignment.topLeft, end: Alignment.bottomRight);
  LinearGradient get warningGradient => LinearGradient(colors: [primary, colorFromHex(warningEndHex)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  LinearGradient get headerGradient => LinearGradient(colors: [colorFromHex(headerStartHex), primary2, accent2], stops: const [0, 0.55, 1], begin: Alignment.centerLeft, end: Alignment.centerRight);

  /// Element override colour (Theme Studio "Element colors"), null = Auto.
  Color? element(String key) {
    final v = cfg.elements[key];
    return v == null ? null : colorFromHex(v);
  }

  /// `E.fg(hex)` - readable foreground for an element colour.
  Color elementFg(String hex) => lumHex(hex) > 0.4 ? const Color(0xff14121a) : const Color(0xffffffff);

  Color get headerColor => element('header') ?? surface;
  Color get sidebarColor => element('sidebar') ?? surface;
  Color get cardColor => element('card') ?? surface;
  Color get buttonColor => element('button') ?? primary;
  Color get buttonFg => cfg.elements['button'] != null ? elementFg(cfg.elements['button']!) : onPrimary;
  Color get tickerColor => element('ticker') ?? surface;
  Color get badgeColor => element('badge') ?? primary;
  Color get badgeFg => cfg.elements['badge'] != null ? elementFg(cfg.elements['badge']!) : onPrimary;
  Color get navActiveColor => element('navActive') ?? primary;
  Color get navActiveFg => cfg.elements['navActive'] != null ? elementFg(cfg.elements['navActive']!) : onPrimary;
  LinearGradient get buttonGradient => cfg.elements['button'] != null
      ? LinearGradient(colors: [buttonColor, colorFromHex(mixHex(cfg.elements['button']!, cfg.accent, 0.45))], begin: Alignment.topLeft, end: Alignment.bottomRight)
      : primaryGradient;

  // semantic colours used by the web CSS
  Color get ok => const Color(0xff22c55e);
  Color get warn => const Color(0xfff59e0b);
  Color get danger => const Color(0xffef4444);
  Color get info => const Color(0xff38bdf8);
}

/// Local persistence (`zedgeTheme:v26:<acc>`, `zedgeThemeEl:v27:<acc>`).
class ThemeStore {
  static String lsKey(String acc) => 'zedgeTheme:v26:${acc.isEmpty ? 'zedge1' : acc}';
  static String elKey(String acc) => 'zedgeThemeEl:v27:${acc.isEmpty ? 'zedge1' : acc}';

  static Future<ThemeConfig?> loadLocal(String acc) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(lsKey(acc));
      if (raw == null || raw.isEmpty) return null;
      final cfg = ThemeConfig.sanitize(jsonDecode(raw));
      final el = sp.getString(elKey(acc));
      if (el != null && el.isNotEmpty) cfg.elements = ThemeConfig.cleanElements(jsonDecode(el));
      return cfg;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLocal(String acc, ThemeConfig cfg) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = ThemeConfig.sanitize(cfg.toJson());
      await sp.setString(lsKey(acc), jsonEncode(s.toJson()));
      if (cfg.elements.isNotEmpty) {
        await sp.setString(elKey(acc), jsonEncode(cfg.elements));
      } else {
        await sp.remove(elKey(acc));
      }
    } catch (_) {}
  }
}
