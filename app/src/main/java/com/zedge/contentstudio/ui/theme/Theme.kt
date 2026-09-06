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
val TypeAudio = Color(0xFF7C3AED)
val TypeWallpaper = Color(0xFF0EA5E9)
val Type24h = Color(0xFFF59E0B)
val TypeDual = Color(0xFF10B981)
val TypeBattery = Color(0xFFEF4444)
val TypeLive = Color(0xFFEC4899)
val TypeCharging = Color(0xFF14B8A6)
val Ok = Color(0xFF16A34A)
val Warn = Color(0xFFD97706)
val Danger = Color(0xFFDC2626)

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
    surfaceVariant = Color(0xFFFFF8E1),
    onSurfaceVariant = BrandMuted,
    outline = BrandLine,
    outlineVariant = BrandLine,
    error = Danger,
)

private val DarkScheme: ColorScheme = darkColorScheme(
    primary = BrandYellow,
    onPrimary = BrandDark,
    primaryContainer = Color(0xFF4A3F00),
    onPrimaryContainer = BrandYellow,
    secondary = BrandAmber,
    onSecondary = BrandDark,
    secondaryContainer = Color(0xFF3B3320),
    onSecondaryContainer = Color(0xFFFFE58A),
    background = Color(0xFF15120B),
    onBackground = Color(0xFFF5EFD8),
    surface = Color(0xFF1F1A10),
    onSurface = Color(0xFFF5EFD8),
    surfaceVariant = Color(0xFF2A2415),
    onSurfaceVariant = Color(0xFFB8AE93),
    outline = Color(0xFF3B3320),
    outlineVariant = Color(0xFF3B3320),
    error = Color(0xFFFF6B6B),
)

val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

val AppTypography = Typography(
    headlineSmall = Typography().headlineSmall.copy(fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.5).sp),
    titleLarge = Typography().titleLarge.copy(fontWeight = FontWeight.Bold),
    titleMedium = Typography().titleMedium.copy(fontWeight = FontWeight.Bold),
    titleSmall = Typography().titleSmall.copy(fontWeight = FontWeight.SemiBold),
    labelSmall = Typography().labelSmall.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp),
)

@Composable
fun ContentStudioTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val scheme = if (darkTheme) DarkScheme else LightScheme
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = scheme.background.toArgb()
            window.navigationBarColor = scheme.surface.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = !darkTheme
        }
    }
    MaterialTheme(colorScheme = scheme, typography = AppTypography, shapes = AppShapes, content = content)
}
