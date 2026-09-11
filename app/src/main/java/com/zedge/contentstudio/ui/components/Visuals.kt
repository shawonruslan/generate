package com.zedge.contentstudio.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Cake
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Celebration
import androidx.compose.material.icons.filled.ChildCare
import androidx.compose.material.icons.filled.Construction
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Female
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.filled.LocalPizza
import androidx.compose.material.icons.filled.Male
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.SentimentSatisfied
import androidx.compose.material.icons.filled.SentimentVerySatisfied
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.Spa
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.VolunteerActivism
import androidx.compose.material.icons.filled.Wallpaper
import androidx.compose.material.icons.filled.Waves
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import java.util.Locale

/** Professional Material icon for each content type (no emoji anywhere in the app). */
fun typeIcon(type: String?): ImageVector = when (if (type == "RINGTONE") "AUDIO" else type) {
    "AUDIO" -> Icons.Filled.MusicNote
    "WALLPAPER" -> Icons.Filled.Wallpaper
    "WALLPAPER_24H" -> Icons.Filled.Schedule
    "WALLPAPER_DUAL" -> Icons.Filled.Smartphone
    "WALLPAPER_BATTERY" -> Icons.Filled.BatteryChargingFull
    "LIVE_WALLPAPER" -> Icons.Filled.Movie
    "CHARGING_ANIMATION" -> Icons.Filled.Bolt
    else -> Icons.Filled.Wallpaper
}

/** Material icon for a special-day icon key (replaces the old emoji map). */
fun holidayIcon(key: String): ImageVector = when (key) {
    "champagne", "sleigh" -> Icons.Filled.Celebration
    "pizza" -> Icons.Filled.LocalPizza
    "heart" -> Icons.Filled.Favorite
    "venus" -> Icons.Filled.Female
    "mars" -> Icons.Filled.Male
    "face-smile" -> Icons.Filled.SentimentSatisfied
    "face-grin", "face-laugh" -> Icons.Filled.SentimentVerySatisfied
    "palette" -> Icons.Filled.Palette
    "earth" -> Icons.Filled.Public
    "jedi" -> Icons.Filled.AutoAwesome
    "mug-hot", "mug-saucer" -> Icons.Filled.LocalCafe
    "leaf" -> Icons.Filled.Eco
    "water" -> Icons.Filled.Waves
    "music" -> Icons.Filled.MusicNote
    "cookie", "egg" -> Icons.Filled.Cake
    "user-group" -> Icons.Filled.Groups
    "cat", "dog", "paw" -> Icons.Filled.Pets
    "camera" -> Icons.Filled.PhotoCamera
    "dove" -> Icons.Filled.Spa
    "wind" -> Icons.Filled.Air
    "chalkboard" -> Icons.Filled.School
    "brain" -> Icons.Filled.Psychology
    "ghost" -> Icons.Filled.DarkMode
    "hand-heart" -> Icons.Filled.VolunteerActivism
    "child" -> Icons.Filled.ChildCare
    "snowflake" -> Icons.Filled.AcUnit
    "gifts" -> Icons.Filled.CardGiftcard
    "user-tie" -> Icons.Filled.Work
    "tags" -> Icons.Filled.LocalOffer
    "laptop" -> Icons.Filled.Laptop
    "drumstick" -> Icons.Filled.Restaurant
    "flag" -> Icons.Filled.Flag
    "hammer" -> Icons.Filled.Construction
    "medal" -> Icons.Filled.MilitaryTech
    "box-open" -> Icons.Filled.Inventory2
    "landmark" -> Icons.Filled.AccountBalance
    else -> Icons.Filled.Star
}

/** Country helpers: ISO-2 code -> English name and flag glyph (regional-indicator pair, rendered as the national flag). */
object Country {
    fun name(code: String): String {
        val c = code.trim().uppercase()
        if (c.length != 2) return code
        val n = Locale("", c).getDisplayCountry(Locale.ENGLISH)
        return if (n.isBlank() || n == c) code else n
    }

    fun flag(code: String): String {
        val c = code.trim().uppercase()
        if (c.length != 2 || !c.all { it in 'A'..'Z' }) return ""
        val sb = StringBuilder()
        c.forEach { sb.appendCodePoint(0x1F1E6 + (it - 'A')) }
        return sb.toString()
    }
}

/** Dark pill with the type icon + short label, e.g. "24H SET" (planner header style). */
@Composable
fun TypePill(type: String?, modifier: Modifier = Modifier, container: Color = BrandDark, content: Color = BrandYellow) {
    val ui = ContentTypes.dayUi(if (type == "RINGTONE") "AUDIO" else type)
    Row(
        modifier.clip(CircleShape).background(container).padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(typeIcon(ui.type), null, Modifier.size(13.dp), tint = content)
        Spacer(Modifier.width(5.dp))
        Text(ui.short.uppercase(), color = content, fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 0.6.sp, maxLines = 1)
    }
}

/** Small round icon holder used in planner rows. */
@Composable
fun IconDot(icon: ImageVector, tint: Color, background: Color, modifier: Modifier = Modifier, size: Int = 30) {
    Box(modifier.size(size.dp).clip(CircleShape).background(background), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size((size * 0.55f).dp), tint = tint)
    }
}
