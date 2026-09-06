package com.zedge.contentstudio.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat

// Brand palette (same as the web dashboard)
val BrandYellow = Color(0xFFFFD400)
val BrandAmber = Color(0xFFFFAB00)
val BrandDark = Color(0xFF211D12)
val BrandBg = Color(0xFFFFFDF6)
val BrandMuted = Color(0xFF8D8471)
val BrandCard = Color(0xFFFFFFFF)
val BrandLine = Color(0xFFEFE6CC)

// Content type accents
val TypeAudio = Color(0xFF8B5CF6)
val TypeWallpaper = Color(0xFF38BDF8)
val Type24h = Color(0xFFFBBF24)
val TypeDual = Color(0xFF34D399)
val TypeBattery = Color(0xFFF87171)
val TypeLive = Color(0xFFF472B6)
val TypeCharging = Color(0xFF2DD4BF)
val Ok = Color(0xFF22C55E)
val Warn = Color(0xFFF59E0B)
val Danger = Color(0xFFEF4444)

fun typeColor(type: String?): Color = when (type) {
    "AUDIO", "RINGTONE" -> TypeAudio
    "WALLPAPER" -> TypeWallpaper
    "WALLPAPER_24H" -> Type24h
    "WALLPAPER_DUAL" -> TypeDual
    "WALLPAPER_BATTERY" -> TypeBattery
    "LIVE_WALLPAPER" -> TypeLive
    "CHARGING_ANIMATION" -> TypeCharging
    else -> BrandMuted
}

private val LightScheme: ColorScheme = lightColorScheme(
    primary = BrandDark,
    onPrimary = BrandYellow,
    primaryContainer = BrandYellow,
    onPrimaryContainer = BrandDark,
    secondary = BrandAmber,
    onSecondary = BrandDark,
    secondaryContainer = Color(0xFFFFF3B0),
    onSecondaryContainer = BrandDark,
    tertiary = Color(0xFF6D5D2A),
    background = BrandBg,
    onBackground = BrandDark,
    surface = BrandCard,
    onSurface = BrandDark,
    surfaceVariant = Color(0xFFFFF6DA),
    onSurfaceVariant = Color(0xFF6F6753),
    surfaceContainerLow = Color(0xFFFFFBEE),
    surfaceContainer = Color(0xFFFFF8E4),
    surfaceContainerHigh = Color(0xFFFFF3D6),
    surfaceContainerHighest = Color(0xFFFFEFC8),
    outline = Color(0xFFE2D8B8),
    outlineVariant = BrandLine,
    error = Danger,
)

private val DarkScheme: ColorScheme = darkColorScheme(
    primary = BrandYellow,
    onPrimary = BrandDark,
    primaryContainer = Color(0xFF3E3400),
    onPrimaryContainer = Color(0xFFFFE066),
    secondary = BrandAmber,
    onSecondary = BrandDark,
    secondaryContainer = Color(0xFF3B3320),
    onSecondaryContainer = Color(0xFFFFE58A),
    background = Color(0xFF0E0C08),
    onBackground = Color(0xFFF7F1DC),
    surface = Color(0xFF181410),
    onSurface = Color(0xFFF7F1DC),
    surfaceVariant = Color(0xFF251F13),
    onSurfaceVariant = Color(0xFFCBC0A3),
    surfaceContainerLow = Color(0xFF1B1711),
    surfaceContainer = Color(0xFF201B12),
    surfaceContainerHigh = Color(0xFF272013),
    surfaceContainerHighest = Color(0xFF2E2716),
    outline = Color(0xFF4A4028),
    outlineVariant = Color(0xFF2F2816),
    error = Color(0xFFFF7A7A),
)

val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(20.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

/** Compact, phone-friendly type scale. Everything is a step smaller than Material defaults. */
val AppTypography = Typography(
    displaySmall = TextStyle(fontSize = 30.sp, lineHeight = 36.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    headlineMedium = TextStyle(fontSize = 24.sp, lineHeight = 30.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.4).sp),
    headlineSmall = TextStyle(fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.3).sp),
    titleLarge = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.Bold),
    titleMedium = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Bold),
    titleSmall = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 15.sp, lineHeight = 22.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Normal),
    bodySmall = TextStyle(fontSize = 11.5.sp, lineHeight = 16.sp, fontWeight = FontWeight.Normal),
    labelLarge = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 11.5.sp, lineHeight = 16.sp, fontWeight = FontWeight.SemiBold),
    labelSmall = TextStyle(fontSize = 10.sp, lineHeight = 14.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.4.sp),
)

@Composable
fun ContentStudioTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val scheme = if (darkTheme) DarkScheme else LightScheme
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            @Suppress("DEPRECATION")
            window.statusBarColor = scheme.background.toArgb()
            @Suppress("DEPRECATION")
            window.navigationBarColor = scheme.surface.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = !darkTheme
        }
    }
    MaterialTheme(colorScheme = scheme, typography = AppTypography, shapes = AppShapes, content = content)
}
