import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v31 theme engine: strictly Zedge Panel (light default) and Night (dark) themes.
/// Shared through Firebase `dashboardSettings/theme`.
class ThemePreset {
  const ThemePreset(this.key, this.name, this.mode, this.primary, this.accent, this.bg, this.surface, this.text, {this.vibe = ''});
  final String key, name, mode, primary, accent, bg, surface, text;
  final String vibe;
  bool get isDark => mode == 'dark';
}

const List<ThemePreset> kThemePresets = [
  ThemePreset('zedge', 'Zedge Panel', 'light', '#783db0', '#783db0', '#f8f9fb', '#ffffff', '#18181b', vibe: 'Official Zedge panel theme'),
  ThemePreset('night', 'Night', 'dark', '#783db0', '#783db0', '#0b0e14', '#131822', '#f1f5f9', vibe: 'Dark night mode'),
];

ThemePreset? presetByKey(String k) => kThemePresets.where((p) => p.key == k).firstOrNull;

const List<List<String>> kThemeElementKeys = [];

final RegExp _hex6 = RegExp(r'^#[0-9a-f]{6}$');

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
    this.v271 = 1,
    Map<String, String>? elements,
  }) : elements = const {};

  String preset;
  String primary, accent, bg, surface, text;
  double fontScale;
  double radius;
  String density;
  int updatedAt;
  String? updatedBy;
  int v271;
  Map<String, String> elements;

  String get mode => preset == 'night' ? 'dark' : 'light';
  bool get isDark => mode == 'dark';

  static ThemeConfig get defaults => ThemeConfig(
        preset: 'zedge',
        primary: '#783db0',
        accent: '#783db0',
        bg: '#f8f9fb',
        surface: '#ffffff',
        text: '#18181b',
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
    final pk = m['preset'] == 'night' ? 'night' : 'zedge';
    final p = presetByKey(pk) ?? kThemePresets.first;
    return ThemeConfig(
      preset: p.key,
      primary: p.primary,
      accent: p.accent,
      bg: p.bg,
      surface: p.surface,
      text: p.text,
      fontScale: _num(m['fontScale'], 1, 0.8, 1.3),
      radius: _num(m['radius'], 1, 0, 1.6),
      density: m['density'] == 'compact' ? 'compact' : 'comfortable',
      updatedAt: (m['updatedAt'] is num) ? (m['updatedAt'] as num).toInt() : int.tryParse('${m['updatedAt'] ?? ''}') ?? 0,
      updatedBy: m['updatedBy']?.toString(),
      v271: 1,
      elements: const {},
    );
  }

  static Map<String, String> cleanElements(dynamic o) => <String, String>{};

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
        'v271': 1,
        'v31': 1,
        'v32': 1,
        'v34': 1,
        'v35': 1,
      };

  String? matchingPreset() => preset == 'night' ? 'night' : 'zedge';

  void applyPreset(ThemePreset p) {
    preset = p.key;
    primary = p.primary;
    accent = p.accent;
    bg = p.bg;
    surface = p.surface;
    text = p.text;
  }
}

class ZedgePalette {
  ZedgePalette(this.cfg) {
    final dark = cfg.isDark;
    final p = cfg.primary, a = cfg.accent, sf = cfg.surface, tx = cfg.text;
    onPrimaryHex = dark ? '#ebe6f5' : '#ffffff';
    onInkHex = dark ? '#ebe6f5' : '#ffffff';
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
    tintSoftHex = mixHex(mixHex(sf, p, 0.169), mutedHex, 0);
    tintCardHex = mixHex(mixHex(sf, p, 0.099), mutedHex, 0.009);
    tintChipHex = mixHex(mixHex(sf, p, 0.278), mutedHex, 0);
    deepHex = mixHex(a, tx, 0.166);
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





  Color? element(String key) => null;
  Color elementFg(String hex) => lumHex(hex) > 0.4 ? const Color(0xff14121a) : const Color(0xffffffff);

  Color get headerColor => surface;
  Color get sidebarColor => surface;
  Color get cardColor => surface;
  Color get buttonColor => primary;
  Color get buttonFg => onPrimary;
  Color get tickerColor => surface;
  Color get badgeColor => primary;
  Color get badgeFg => onPrimary;
  Color get navActiveColor => primary;
  Color get navActiveFg => onPrimary;

  Color get ok => const Color(0xff783db0);
  Color get warn => const Color(0xfff59e0b);
  Color get danger => const Color(0xffef4444);
  Color get info => const Color(0xff38bdf8);
}

class ThemeStore {
  static String lsKey(String acc) => 'zedgeTheme:v35:${acc.isEmpty ? 'zedge1' : acc}';
  static String elKey(String acc) => 'zedgeThemeEl:v35:${acc.isEmpty ? 'zedge1' : acc}';

  static Future<ThemeConfig?> loadLocal(String acc) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(lsKey(acc));
      if (raw == null || raw.isEmpty) return null;
      return ThemeConfig.sanitize(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLocal(String acc, ThemeConfig cfg) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = ThemeConfig.sanitize(cfg.toJson());
      await sp.setString(lsKey(acc), jsonEncode(s.toJson()));
    } catch (_) {}
  }
}
