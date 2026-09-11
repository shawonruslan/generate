package com.zedge.contentstudio.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Brightness3
import androidx.compose.material.icons.filled.Church
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Park
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zedge.contentstudio.domain.SpecialDay
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import kotlinx.coroutines.delay

/** Visual identity for one holiday topic: icon + gradient palette. */
data class HolidayTheme(val icon: ImageVector, val colors: List<Color>, val accent: Color)

fun holidayTheme(iconKey: String): HolidayTheme {
    val icon = when (iconKey) {
        "moon" -> Icons.Filled.Brightness3
        "lamp" -> Icons.Filled.Lightbulb
        "book" -> Icons.Filled.MenuBook
        "church" -> Icons.Filled.Church
        "tree" -> Icons.Filled.Park
        "sun" -> Icons.Filled.WbSunny
        else -> holidayIcon(iconKey)
    }
    val (colors, accent) = when (iconKey) {
        "champagne", "sleigh" -> listOf(Color(0xFF6B4E00), Color(0xFF2A1F00)) to Color(0xFFFFE066)
        "pizza", "cookie", "egg", "drumstick", "mug-hot", "mug-saucer" -> listOf(Color(0xFFB4470F), Color(0xFF4A1A00)) to Color(0xFFFFD9A8)
        "heart", "hand-heart", "venus" -> listOf(Color(0xFFC2185B), Color(0xFF4A0B2A)) to Color(0xFFFFC1D9)
        "flag" -> listOf(Color(0xFF1E3A8A), Color(0xFF7F1D1D)) to Color(0xFFFFFFFF)
        "medal", "landmark" -> listOf(Color(0xFF334155), Color(0xFF0F172A)) to Color(0xFFFFD400)
        "earth", "leaf", "paw", "cat", "dog", "dove", "tree" -> listOf(Color(0xFF15803D), Color(0xFF052E1F)) to Color(0xFFB9F6CA)
        "water", "snowflake", "wind" -> listOf(Color(0xFF0369A1), Color(0xFF0B2A4A)) to Color(0xFFBFEFFF)
        "ghost" -> listOf(Color(0xFF4C1D95), Color(0xFFEA580C)) to Color(0xFFFFE8B0)
        "gifts" -> listOf(Color(0xFFB91C1C), Color(0xFF14532D)) to Color(0xFFFFF3B0)
        "music", "palette", "camera", "face-smile", "face-grin", "face-laugh" -> listOf(Color(0xFF7C3AED), Color(0xFFDB2777)) to Color(0xFFFFFFFF)
        "brain", "chalkboard", "laptop", "user-tie", "tags", "box-open", "hammer", "book" -> listOf(Color(0xFF475569), Color(0xFF111827)) to Color(0xFFFFD400)
        "jedi" -> listOf(Color(0xFF0F172A), Color(0xFF1D4ED8)) to Color(0xFF9EDBFF)
        "child", "user-group", "sun" -> listOf(Color(0xFFF59E0B), Color(0xFFC2410C)) to Color(0xFFFFFFFF)
        "moon", "lamp" -> listOf(Color(0xFF064E3B), Color(0xFF0F172A)) to Color(0xFFFFE066)
        "church" -> listOf(Color(0xFF6D28D9), Color(0xFF1E1B4B)) to Color(0xFFFFE066)
        else -> listOf(Color(0xFF3A3320), BrandDark) to BrandYellow
    }
    return HolidayTheme(icon, colors, accent)
}

/**
 * Holiday banner shown on top of a day card. Themed gradient art per topic, watermark icon,
 * glassy sweeping highlight, auto-slides between holidays every few seconds (tap to skip).
 */
@Composable
fun HolidayBanner(special: List<SpecialDay>, modifier: Modifier = Modifier, autoSlideMs: Long = 4200L) {
    if (special.isEmpty()) return
    var idx by remember(special) { mutableIntStateOf(0) }
    LaunchedEffect(special, idx) {
        if (special.size > 1) { delay(autoSlideMs); idx = (idx + 1) % special.size }
    }

    // glass sweep 0..1 across the banner
    val shimmer = rememberInfiniteTransition(label = "glass")
    val sweep by shimmer.animateFloat(
        initialValue = -0.6f, targetValue = 1.6f,
        animationSpec = infiniteRepeatable(tween(2600, easing = LinearEasing), RepeatMode.Restart), label = "sweep"
    )

    AnimatedContent(
        targetState = idx,
        transitionSpec = {
            (slideInHorizontally(tween(420)) { it / 2 } + fadeIn(tween(420))) togetherWith
                (slideOutHorizontally(tween(320)) { -it / 2 } + fadeOut(tween(260)))
        },
        label = "holiday",
        modifier = modifier.clickable(enabled = special.size > 1) { idx = (idx + 1) % special.size },
    ) { i ->
        val s = special[i % special.size]
        val theme = remember(s.icon) { holidayTheme(s.icon) }
        val countries = s.countries ?: emptyList<String>()

        Box(
            Modifier.fillMaxWidth().height(62.dp)
                .background(Brush.linearGradient(theme.colors))
                .drawWithContent {
                    drawContent()
                    // moving glass highlight
                    val w = size.width
                    val x = w * sweep
                    drawRect(
                        Brush.linearGradient(
                            listOf(Color.Transparent, Color.White.copy(alpha = 0.22f), Color.Transparent),
                            start = Offset(x - w * 0.25f, 0f), end = Offset(x + w * 0.25f, size.height)
                        )
                    )
                    // top glass edge
                    drawRect(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.18f), Color.Transparent), endY = size.height * 0.55f))
                }
        ) {
            // identity art: big soft watermark icon on the right
            Icon(theme.icon, null, Modifier.align(Alignment.CenterEnd).padding(end = 26.dp).size(72.dp).rotate(-14f).alpha(0.16f), tint = Color.White)
            Icon(theme.icon, null, Modifier.align(Alignment.TopEnd).padding(end = 82.dp, top = 4.dp).size(26.dp).rotate(12f).alpha(0.10f), tint = Color.White)

            Row(Modifier.fillMaxSize().padding(start = 12.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                // themed icon medallion (+ flag when a country is known)
                Box(
                    Modifier.size(38.dp).clip(RoundedCornerShape(12.dp))
                        .background(Color.White.copy(alpha = 0.16f))
                        .border(1.dp, Color.White.copy(alpha = 0.35f), RoundedCornerShape(12.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    if (countries.isNotEmpty()) Text(Country.flag(countries[0]), fontSize = 20.sp, lineHeight = 22.sp)
                    else Icon(theme.icon, null, Modifier.size(20.dp), tint = theme.accent)
                }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (countries.isNotEmpty()) {
                            Icon(theme.icon, null, Modifier.size(12.dp), tint = theme.accent)
                            Spacer(Modifier.width(5.dp))
                        }
                        Text(s.name.uppercase(), color = theme.accent, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 0.6.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Text(
                        if (countries.isEmpty()) "International day"
                        else countries.take(3).joinToString(", ") { Country.name(it) } + if (countries.size > 3) " +${countries.size - 3} more" else "",
                        color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                }
                if (special.size > 1) {
                    Spacer(Modifier.width(8.dp))
                    Column(horizontalAlignment = Alignment.End) {
                        Box(Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.18f)).border(1.dp, Color.White.copy(alpha = 0.3f), CircleShape).padding(horizontal = 8.dp, vertical = 3.dp)) {
                            Text("${(i % special.size) + 1}/${special.size}", color = Color.White, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
                        }
                        Spacer(Modifier.height(5.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                            repeat(special.size.coerceAtMost(6)) { d ->
                                Box(Modifier.size(width = if (d == i % special.size) 12.dp else 5.dp, height = 5.dp).clip(CircleShape).background(Color.White.copy(alpha = if (d == i % special.size) 0.95f else 0.4f)))
                            }
                        }
                    }
                }
            }
        }
    }
}
