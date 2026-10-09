package com.zedge.contentstudio.ui.components

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateIntAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import com.zedge.contentstudio.ui.theme.ThemeState
import kotlinx.coroutines.delay
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * v27 Glass UI helpers.
 * - [AuroraBackground]: slowly drifting primary/accent glow blobs behind every screen (theme aware).
 * - [glassLine]: hairline border color for translucent cards.
 * - [AnimatedCount]: numbers count up/down when the value changes.
 * - [DhakaClock]: live HH:MM AM/PM in Asia/Dhaka (bot time).
 */
@Composable
fun AuroraBackground(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val p = ThemeState.palette
    val t = rememberInfiniteTransition(label = "aurora")
    val a by t.animateFloat(0f, 1f, infiniteRepeatable(tween(14000, easing = LinearEasing), RepeatMode.Reverse), label = "a")
    val b by t.animateFloat(0f, 1f, infiniteRepeatable(tween(19000, easing = LinearEasing), RepeatMode.Reverse), label = "b")
    val alpha = if (p.isDark) 0.34f else 0.18f
    Box(modifier.fillMaxSize().background(p.bg)) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height
            val c1 = Offset(w * (0.05f + 0.25f * a), h * (0.02f + 0.12f * b))
            val c2 = Offset(w * (1.0f - 0.2f * b), h * (0.35f + 0.2f * a))
            val c3 = Offset(w * (0.4f + 0.2f * b), h * (1.05f - 0.1f * a))
            drawCircle(Brush.radialGradient(listOf(p.primary.copy(alpha = alpha), Color.Transparent), center = c1, radius = w * 0.85f), radius = w * 0.85f, center = c1)
            drawCircle(Brush.radialGradient(listOf(p.accent.copy(alpha = alpha * 0.8f), Color.Transparent), center = c2, radius = w * 0.8f), radius = w * 0.8f, center = c2)
            drawCircle(Brush.radialGradient(listOf(p.primary.copy(alpha = alpha * 0.6f), Color.Transparent), center = c3, radius = w * 0.9f), radius = w * 0.9f, center = c3)
        }
        content()
    }
}

@Composable
fun glassLine(): Color {
    val p = ThemeState.palette
    return if (p.isDark) Color.White.copy(alpha = 0.10f) else p.text.copy(alpha = 0.09f)
}

@Composable
fun glassSurface(alpha: Float = 0.68f): Color = ThemeState.palette.card.copy(alpha = alpha) // v27.8 follows the "card" element colour

@Composable
fun AnimatedCount(value: String, style: TextStyle, color: Color = Color.Unspecified, modifier: Modifier = Modifier) {
    val n = value.trim().toIntOrNull()
    if (n == null) {
        Text(value, modifier, style = style, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
        return
    }
    val anim by animateIntAsState(n, tween(650, easing = FastOutSlowInEasing), label = "count")
    Text(anim.toString(), modifier, style = style, color = color, maxLines = 1, fontWeight = FontWeight.ExtraBold)
}

private fun dhakaClockText(): String {
    val c = Calendar.getInstance(TimeZone.getTimeZone("Asia/Dhaka"))
    val h = c.get(Calendar.HOUR_OF_DAY)
    val m = c.get(Calendar.MINUTE)
    val h12 = if (h % 12 == 0) 12 else h % 12
    return String.format(Locale.US, "%d:%02d %s", h12, m, if (h < 12) "AM" else "PM")
}

@Composable
fun DhakaClock(color: Color, modifier: Modifier = Modifier, style: TextStyle = MaterialTheme.typography.headlineSmall) {
    var now by remember { mutableStateOf(dhakaClockText()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = dhakaClockText()
            delay(1000)
        }
    }
    Text(now, modifier, style = style, color = color, fontWeight = FontWeight.ExtraBold, maxLines = 1)
}
