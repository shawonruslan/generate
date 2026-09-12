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
import androidx.compose.material3.TextButton
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.luminance
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

/** v17: calm inline holiday notes. All events remain accessible without auto-rotation. */
@Suppress("UNUSED_PARAMETER")
@Composable
fun HolidayBanner(special: List<SpecialDay>, modifier: Modifier = Modifier, autoSlideMs: Long = 4200L) {
    if (special.isEmpty()) return
    val items = special.sortedBy { when (it.kind) { "festival" -> 0; "bd" -> 1; "global" -> 2; else -> 3 } }
    var expanded by remember(special.map { it.slug }) { mutableStateOf(false) }
    val colors = MaterialTheme.colorScheme
    val dark = colors.surface.luminance() < 0.5f
    val shape = RoundedCornerShape(11.dp)
    Column(modifier.fillMaxWidth().clip(shape)
        .background(if (dark) Color(0xFF332B17) else Color(0xFFFFFAE3))
        .border(1.dp, BrandYellow.copy(alpha = if (dark) 0.20f else 0.32f), shape)) {
        Row(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 9.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (items.size == 1) "HOLIDAY & OBSERVANCE" else "HOLIDAYS & OBSERVANCES", modifier = Modifier.weight(1f), fontSize = 9.sp, lineHeight = 13.sp, letterSpacing = 0.5.sp, fontWeight = FontWeight.Bold, color = colors.onSurfaceVariant)
            if (items.size > 1) Text("${items.size} events", fontSize = 9.sp, color = colors.onSurfaceVariant)
        }
        HolidayNoteRow(items.first())
        if (expanded) {
            items.drop(1).forEach { event ->
                Box(Modifier.fillMaxWidth().height(1.dp).background(BrandYellow.copy(alpha = 0.16f)))
                HolidayNoteRow(event)
            }
        }
        if (items.size > 1) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(BrandYellow.copy(alpha = 0.16f)))
            TextButton(onClick = { expanded = !expanded }, modifier = Modifier.fillMaxWidth(), contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (expanded) "Show less" else "View ${items.size - 1} more", modifier = Modifier.weight(1f), fontSize = 11.sp, color = colors.onSurfaceVariant)
                    Text(if (expanded) "⌃" else "⌄", fontSize = 15.sp, color = colors.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun HolidayNoteRow(event: SpecialDay) {
    val colors = MaterialTheme.colorScheme
    val countries = event.countries ?: emptyList<String>()
    val country = if (countries.isNotEmpty()) countries.joinToString(" · ") { Country.name(it) }
        else if (event.kind == "global") "Worldwide" else "Country not listed"
    val kind = when (event.kind) { "holiday" -> "Public holiday"; "festival" -> "Festival"; "global" -> "Observance"; else -> "Special day" }
    Row(Modifier.fillMaxWidth().padding(10.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(32.dp).clip(RoundedCornerShape(9.dp)).background(BrandYellow.copy(alpha = 0.13f)).border(1.dp, BrandYellow.copy(alpha = 0.20f), RoundedCornerShape(9.dp)), contentAlignment = Alignment.Center) {
            if (countries.isNotEmpty()) Text(Country.flag(countries.first()), fontSize = 19.sp, lineHeight = 22.sp)
            else Icon(holidayTheme(event.icon).icon, null, Modifier.size(16.dp), tint = colors.onSurfaceVariant)
        }
        Spacer(Modifier.width(9.dp))
        Column(Modifier.weight(1f)) {
            Text(event.name, fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold, color = colors.onSurface)
            Spacer(Modifier.height(3.dp))
            Text("$country · $kind", fontSize = 10.sp, lineHeight = 15.sp, color = colors.onSurfaceVariant)
        }
    }
}
