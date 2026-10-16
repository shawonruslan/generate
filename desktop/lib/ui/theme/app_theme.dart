import 'package:flutter/material.dart';

import '../../domain/theme_engine.dart';

/// Builds the Material theme from the panel palette so every widget follows Theme Studio.
ThemeData buildAppTheme(ZedgePalette p) {
  final dark = p.isDark;
  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.accent,
    onSecondary: p.onPrimary,
    error: p.danger,
    onError: Colors.white,
    surface: p.surface,
    onSurface: p.text,
    surfaceContainerHighest: p.surfaceHover,
    outline: p.border,
    tertiary: p.accent2,
    onTertiary: p.onPrimary,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: scheme.brightness);
  final radius = BorderRadius.circular(p.radiusSm);
  final textTheme = base.textTheme.apply(bodyColor: p.text, displayColor: p.text);
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.surface,
    cardColor: p.cardColor,
    dividerColor: p.border,
    textTheme: textTheme,
    iconTheme: IconThemeData(color: p.text, size: 18),
    visualDensity: p.compact ? VisualDensity.compact : VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
      textStyle: TextStyle(color: p.onInk, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.bg.withValues(alpha: dark ? 0.55 : 0.6),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.primary, width: 1.4)),
      hintStyle: TextStyle(color: p.muted, fontSize: 13),
      labelStyle: TextStyle(color: p.muted, fontSize: 13),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : Colors.transparent),
      checkColor: WidgetStatePropertyAll(p.onPrimary),
      side: BorderSide(color: p.border, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onPrimary : p.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : p.surfaceHover),
      trackOutlineColor: WidgetStatePropertyAll(p.border),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: p.primary, inactiveTrackColor: p.border, thumbColor: p.accent, overlayColor: p.primary.withValues(alpha: 0.2)),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.radiusLg), side: BorderSide(color: p.border)),
      titleTextStyle: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700),
      contentTextStyle: TextStyle(color: p.text, fontSize: 14, height: 1.45),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.radiusMd), side: BorderSide(color: p.border)),
      textStyle: TextStyle(color: p.text, fontSize: 13),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: TextStyle(color: p.text, fontSize: 13)),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.primary.withValues(alpha: 0.45)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(8),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary, linearTrackColor: p.border),
    snackBarTheme: SnackBarThemeData(backgroundColor: p.ink, contentTextStyle: TextStyle(color: p.onInk)),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
  );
}
