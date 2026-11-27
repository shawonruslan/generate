import 'package:flutter/material.dart';

/// Design tokens lifted from the Team Drive web app (index-12.html).
/// Flat solid colors only — no gradients, no neon. Night = dark gray,
/// Day = off-white glassy (frosted) panels.
class AppColors {
  // Brand (indigo) — exact web-app tokens: light #4a5fd0, dark #5b7cfa.
  static const Color brandLight = Color(0xFF4A5FD0);
  static const Color brandDark = Color(0xFF5B7CFA);
  static const Color brandDeepLight = Color(0xFF3D4FB8);
  static const Color brandDeepDark = Color(0xFF4A68E8);

  static const Color dangerLight = Color(0xFFE5484D);
  static const Color dangerDark = Color(0xFFC24040);
  static const Color okLight = Color(0xFF46A758);
  static const Color okDark = Color(0xFF3D8B4F);
  static const Color warn = Color(0xFFB45309);

  // Night (dark gray)
  static const Color nightBg = Color(0xFF161616);
  static const Color nightPanel = Color(0xFF1E1E1E);
  static const Color nightSide = Color(0xFF111111);
  static const Color nightSide2 = Color(0xFF2A2A2A);
  static const Color nightLine = Color(0xFF2D2D2D);
  static const Color nightLine2 = Color(0xFF262626);
  static const Color nightHover = Color(0xFF2B2B2B);
  static const Color nightText = Color(0xFFE9E9E9);
  static const Color nightMuted = Color(0xFF909090);
  static const Color nightSideText = Color(0xFFA6A6A6);
  static const Color nightBrandTint = Color(0xFF2B3242); // active nav pill (night)

  // Day — exact web tokens: page bg warm cream-gray, chrome solid white.
  static const Color dayBg = Color(0xFFECEAE2);
  static const Color dayPanel = Color(0xFFFFFFFF);
  static const Color daySide = Color(0xFFFFFFFF);
  static const Color daySide2 = Color(0xFFFFFFFF);
  static const Color daySoft = Color(0xFFF4F2ED); // icon chips / search resting bg
  static const Color dayBrandTint = Color(0xFFE8F0FF); // active nav pill (day)
  static const Color dayLine = Color(0xFFE3E0D6);
  static const Color dayText = Color(0xFF222222);
  static const Color dayMuted = Color(0xFF888888);
  static const Color daySideText = Color(0xFF5D6169);
}

class AppTheme {
  static ThemeData night() {
    const brand = AppColors.brandDark;
    final scheme = ColorScheme.dark(
      primary: brand,
      secondary: brand,
      surface: AppColors.nightPanel,
      error: AppColors.dangerDark,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Poppins',
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.nightBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.nightSide,
        foregroundColor: AppColors.nightText,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: AppColors.nightPanel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.nightLine2),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.nightSide2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.nightLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.nightLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: brand, width: 1.6),
        ),
        hintStyle: const TextStyle(color: AppColors.nightMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: brand),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      dividerColor: AppColors.nightLine2,
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.nightPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Colors.black,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: AppColors.nightSide2,
        labelStyle: TextStyle(color: AppColors.nightText),
      ),
    );
  }

  static ThemeData day() {
    const brand = AppColors.brandLight;
    final scheme = ColorScheme.light(
      primary: brand,
      secondary: brand,
      surface: AppColors.dayPanel,
      error: AppColors.dangerLight,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Poppins',
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.dayBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.daySide,
        foregroundColor: AppColors.dayText,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: AppColors.dayPanel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.dayLine),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.dayLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.dayLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: brand, width: 1.6),
        ),
        hintStyle: const TextStyle(color: AppColors.dayMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: brand),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      dividerColor: AppColors.dayLine,
      dialogTheme: DialogTheme(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Colors.black,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: Color(0xFFEFEDE6),
        labelStyle: TextStyle(color: AppColors.dayText),
      ),
    );
  }
}
