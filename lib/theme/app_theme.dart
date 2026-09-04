import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The golden "sunshine" palette of the original dashboard, ported to Material 3.
class Zc {
  static const Color gold = Color(0xFFFFD400);
  static const Color goldDeep = Color(0xFFF5A800);
  static const Color amber = Color(0xFFFFAB00);
  static const Color orange = Color(0xFFFF8A00);
  static const Color ink = Color(0xFF211D12);
  static const Color inkSoft = Color(0xFF6B5510);
  static const Color muted = Color(0xFF8A7A52);
  static const Color cream = Color(0xFFFFFDF6);
  static const Color creamDeep = Color(0xFFFFF6D8);
  static const Color line = Color(0xFFF0E4C0);
  static const Color canvas = Color(0xFFFCF7E8);
  static const Color panel = Colors.white;
  static const Color ok = Color(0xFF1E9E5A);
  static const Color warn = Color(0xFFE07A00);
  static const Color danger = Color(0xFFD64545);
  static const Color info = Color(0xFF2F7DD1);

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[gold, amber],
  );

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF2A2415), Color(0xFF15120A)],
  );

  /// Status colour used by badges and the queue list.
  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'done':
      case 'uploaded':
      case 'completed':
        return ok;
      case 'processing':
      case 'uploading':
        return info;
      case 'failed':
      case 'error':
        return danger;
      case 'scheduled':
        return warn;
      default:
        return goldDeep;
    }
  }

  static IconData typeIcon(String contentType) {
    switch (contentType) {
      case 'AUDIO':
      case 'RINGTONE':
        return Icons.music_note_rounded;
      case 'WALLPAPER_24H':
        return Icons.schedule_rounded;
      case 'WALLPAPER_DUAL':
        return Icons.smartphone_rounded;
      case 'WALLPAPER_BATTERY':
        return Icons.battery_charging_full_rounded;
      case 'LIVE_WALLPAPER':
        return Icons.movie_creation_rounded;
      case 'CHARGING_ANIMATION':
        return Icons.bolt_rounded;
      default:
        return Icons.wallpaper_rounded;
    }
  }
}

class AppTheme {
  static ThemeData build() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: Zc.goldDeep,
      primary: Zc.goldDeep,
      onPrimary: Zc.ink,
      secondary: Zc.orange,
      surface: Zc.panel,
      brightness: Brightness.light,
    );

    TextTheme text;
    try {
      text = GoogleFonts.outfitTextTheme();
    } catch (_) {
      text = Typography.material2021().black;
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Zc.canvas,
      textTheme: text.apply(bodyColor: Zc.ink, displayColor: Zc.ink),
      dividerColor: Zc.line,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        color: Zc.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFEBE2CB)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Zc.cream,
        side: const BorderSide(color: Zc.line),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
          color: Zc.inkSoft,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Zc.cream,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Zc.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Zc.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Zc.goldDeep, width: 2),
        ),
        labelStyle: const TextStyle(
          color: Zc.muted,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Zc.goldDeep,
          foregroundColor: Zc.ink,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Zc.inkSoft,
          side: const BorderSide(color: Zc.line, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Zc.ink,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    );
  }
}

/// Shared soft shadow used by cards and the phone mock-up.
const List<BoxShadow> kSoftShadow = <BoxShadow>[
  BoxShadow(color: Color(0x14211D12), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x1A4C3C14), blurRadius: 10, offset: Offset(0, 4)),
  BoxShadow(color: Color(0x0F4C3C14), blurRadius: 30, offset: Offset(0, 16)),
];
