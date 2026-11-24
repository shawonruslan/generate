package com.zedge.contentstudio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AudioFile
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PieChart
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.zedge.contentstudio.ui.components.SectionCard
import org.json.JSONObject

/**
 * v37 Earnings insights - the extra Zedge dashboard sections the bot now saves under
 * dashboardSettings/earnings/insights: revenue split, top profiles, top content per type
 * (wallpapers / ringtones / dynamic 24h / battery ...) and top countries.
 */
private val INS_ORDER = listOf("WALLPAPER", "AUDIO", "DYNAMIC_24H_WALLPAPER", "DYNAMIC_BATTERY_LEVEL_WALLPAPER", "LIVE_WALLPAPER", "EXT_VIDEO", "CHARGE_SCREEN", "STICKER_PACK", "ANY_CTYPE")
private val INS_SPLIT_COLOR = mapOf("AD_VIEW" to Color(0xFF0096DF), "AD_SKIP" to Color(0xFF5ECCC6), "BUYING" to Color(0xFF783DB0))

private fun insMoney(v: Double): String = if (v >= 1) "$" + String.format("%,.2f", v) else "$" + String.format("%.4f", v).trimEnd('0').let { if (it.endsWith(".")) it + "00" else it }
private fun insFlag(cc: String): String {
    val c = cc.uppercase()
    if (c.length != 2 || !c.all { it in 'A'..'Z' }) return ""
    return String(Character.toChars(0x1F1E6 + (c[0] - 'A'))) + String(Character.toChars(0x1F1E6 + (c[1] - 'A')))
}
private fun insIcon(k: String): ImageVector = when (k) {
    "WALLPAPER" -> Icons.Filled.Image
    "AUDIO" -> Icons.Filled.AudioFile
    "DYNAMIC_24H_WALLPAPER" -> Icons.Filled.Schedule
    "DYNAMIC_BATTERY_LEVEL_WALLPAPER" -> Icons.Filled.BatteryChargingFull
    else -> Icons.Filled.Star
}

@Composable
private fun InsBar(frac: Float, color: Color, modifier: Modifier = Modifier) {
    Box(modifier.height(6.dp).clip(RoundedCornerShape(4.dp)).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(frac.coerceIn(0.02f, 1f)).clip(RoundedCornerShape(4.dp)).background(color))
    }
}

@Composable
private fun InsItem(rank: Int, thumb: String, name: String, sub: String, value: Double, max: Double, color: Color) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("$rank", Modifier.width(20.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Box(Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))) {
            if (thumb.isNotBlank()) AsyncImage(model = thumb, contentDescription = name, modifier = Modifier.size(40.dp), contentScale = ContentScale.Crop)
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (sub.isNotBlank()) Text(sub, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(3.dp))
            InsBar(if (max > 0) (value / max).toFloat() else 0f, color, Modifier.fillMaxWidth())
        }
        Spacer(Modifier.width(10.dp))
        Text(insMoney(value), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
    }
}

fun LazyListScope.earnInsightsItems(data: JSONObject?) {
    val ins = data?.optJSONObject("insights") ?: return
    val range = earnInsRange(ins)

    val split = ins.optJSONArray("split")
    if (split != null && split.length() > 0) item {
        SectionCard(title = "Split by revenue type", subtitle = range, icon = Icons.Filled.PieChart) {
            var tot = 0.0
            for (i in 0 until split.length()) tot += split.optJSONObject(i)?.optDouble("value", 0.0) ?: 0.0
            // v40.1: Zedge order (Ad skips, Ad plays, Zedge credits) - small slices land on both sides of the top
            val order = listOf("AD_SKIP", "AD_VIEW", "BUYING")
            val rows = (0 until split.length()).mapNotNull { split.optJSONObject(it) }
                .sortedBy { s -> order.indexOf(s.optString("category")).let { if (it < 0) 9 else it } }
            var sel by remember { mutableStateOf<Int?>(null) }
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                InsDonut(
                    values = rows.map { it.optDouble("value", 0.0) },
                    colors = rows.map { INS_SPLIT_COLOR[it.optString("category")] ?: Color.Gray },
                    labelColor = MaterialTheme.colorScheme.onSurface,
                    labels = rows.map { it.optString("label", it.optString("category")) },
                    money = { insMoney(it) },
                    selected = sel,
                    onSelect = { sel = it },
                )
            }
            Spacer(Modifier.height(8.dp))
            for ((i, s) in rows.withIndex()) {
                val v = s.optDouble("value", 0.0)
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp))
                        .background(if (sel == i) Color(0xFF0096DF).copy(alpha = 0.10f) else Color.Transparent)
                        .clickable { sel = if (sel == i) null else i }
                        .padding(vertical = 6.dp, horizontal = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(10.dp).clip(CircleShape).background(INS_SPLIT_COLOR[s.optString("category")] ?: Color.Gray))
                    Spacer(Modifier.width(8.dp))
                    Text(s.optString("label", s.optString("category")), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                    Text(if (tot > 0) String.format("%.1f%%", v / tot * 100) else "--", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(10.dp))
                    Text(insMoney(v), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                }
            }
        }
    }

    val prof = ins.optJSONArray("topProfiles")
    if (prof != null && prof.length() > 0) item {
        SectionCard(title = "Top profiles", subtitle = range, icon = Icons.Filled.Person) {
            var mx = 0.0
            for (i in 0 until prof.length()) mx = maxOf(mx, prof.optJSONObject(i)?.optDouble("total", 0.0) ?: 0.0)
            for (i in 0 until prof.length()) {
                val p = prof.optJSONObject(i) ?: continue
                InsItem(i + 1, p.optString("thumbUrl"), p.optString("name"), "", p.optDouble("total", 0.0), mx, Color(0xFF783DB0))
            }
        }
    }

    val tc = ins.optJSONObject("topContent")
    if (tc != null) {
        val keys = tc.keys().asSequence().toList().sortedBy { k -> INS_ORDER.indexOf(k).let { if (it < 0) 99 else it } }
        for (k in keys) {
            val g = tc.optJSONObject(k) ?: continue
            val items = g.optJSONArray("items") ?: continue
            if (items.length() == 0) continue
            item {
                SectionCard(title = "Top " + g.optString("label", k).lowercase(), subtitle = range, icon = insIcon(k)) {
                    var mx = 0.0
                    for (i in 0 until items.length()) mx = maxOf(mx, items.optJSONObject(i)?.optDouble("total", 0.0) ?: 0.0)
                    for (i in 0 until items.length()) {
                        val x = items.optJSONObject(i) ?: continue
                        InsItem(i + 1, x.optString("thumbUrl"), x.optString("name"), x.optString("profileName"), x.optDouble("total", 0.0), mx, Color(0xFF0096DF))
                    }
                }
            }
        }
    }

    val cs = ins.optJSONArray("topCountries")
    if (cs != null && cs.length() > 0) item {
        var all by remember { mutableStateOf(false) }
        SectionCard(title = "Top countries", subtitle = "$range • ${cs.length()} countries", icon = Icons.Filled.Public) {
            val mx = cs.optJSONObject(0)?.optDouble("value", 0.0) ?: 0.0
            val mv = HashMap<String, Double>(); val mn = HashMap<String, String>()
            for (i in 0 until cs.length()) {
                val c = cs.optJSONObject(i) ?: continue
                val id = c.optString("id").uppercase()
                if (id.isNotBlank()) { mv[id] = c.optDouble("value", 0.0); mn[id] = c.optString("name") }
            }
            InsWorldMap(mv, mn) { insMoney(it) }
            Text("Tap a country to see its revenue", Modifier.padding(top = 4.dp, bottom = 6.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            val n = if (all) cs.length() else minOf(10, cs.length())
            for (i in 0 until n) {
                val c = cs.optJSONObject(i) ?: continue
                val v = c.optDouble("value", 0.0)
                Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("${i + 1}", Modifier.width(20.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(insFlag(c.optString("id")), Modifier.width(24.dp))
                    Text(c.optString("name"), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    InsBar(if (mx > 0) (v / mx).toFloat() else 0f, Color(0xFF5ECCC6), Modifier.weight(1f))
                    Text(insMoney(v), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                }
            }
            if (cs.length() > 10) {
                Text(
                    if (all) "Show top 10" else "Show all ${cs.length()} countries",
                    Modifier.padding(top = 8.dp).clickable { all = !all },
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

private fun earnInsRange(ins: JSONObject): String {
    val a = ins.optString("rangeStart", "").replace("-", "/")
    val b = ins.optString("rangeEnd", "").replace("-", "/")
    return if (a.isBlank()) "" else "$a - $b"
}
