package com.zedge.contentstudio.ui.screens

import android.graphics.Paint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.min
import kotlin.math.sin

/** v40.1: donut chart for "Split by revenue type". Tap a slice (or a legend row) to see its amount in the middle. */
@Composable
internal fun InsDonut(
    values: List<Double>,
    colors: List<Color>,
    labelColor: Color,
    labels: List<String> = emptyList(),
    money: (Double) -> String = { String.format("$%.2f", it) },
    selected: Int? = null,
    onSelect: (Int?) -> Unit = {},
    size: Dp = 220.dp,
) {
    val tot = values.sumOf { if (it > 0) it else 0.0 }
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(
            Modifier
                .size(size)
                .pointerInput(values) {
                    detectTapGestures { o ->
                        if (tot <= 0) return@detectTapGestures
                        val c = Offset(this.size.width / 2f, this.size.height / 2f)
                        val outer = this.size.width / 2f - 30.dp.toPx()
                        val d = (o - c).getDistance()
                        if (d < outer * 0.5f || d > outer + 12.dp.toPx()) { onSelect(null); return@detectTapGestures }
                        var ang = kotlin.math.atan2((o.y - c.y).toDouble(), (o.x - c.x).toDouble()) + PI / 2
                        if (ang < 0) ang += 2 * PI
                        var acc = 0.0
                        var hit: Int? = null
                        for (i in values.indices) {
                            if (values[i] <= 0) continue
                            acc += values[i] / tot * 2 * PI
                            if (ang <= acc) { hit = i; break }
                        }
                        onSelect(if (hit == selected) null else hit)
                    }
                },
        ) {
            if (tot <= 0) return@Canvas
            val outer = this.size.minDimension / 2 - 30.dp.toPx()
            val sw = outer * 0.48f
            val r = outer - sw / 2
            val n = values.count { it > 0 }
            val txt = Paint().apply { isAntiAlias = true; color = labelColor.toArgb(); textSize = 11.dp.toPx(); isFakeBoldText = true }
            // [mid(rad), right side?, y, text]
            val labs = ArrayList<Array<Any>>()
            var a0 = -90.0
            values.forEachIndexed { i, v ->
                if (v <= 0) return@forEachIndexed
                val sweep = v / tot * 360.0
                val g = if (n > 1) min(1.4, sweep / 2) else 0.0
                val mid = (a0 + sweep / 2) * PI / 180
                val on = selected == i
                val off = if (on) Offset((cos(mid) * 6.dp.toPx()).toFloat(), (sin(mid) * 6.dp.toPx()).toFloat()) else Offset.Zero
                drawArc(
                    color = colors[i % colors.size].copy(alpha = if (selected == null || on) 0.9f else 0.4f),
                    startAngle = (a0 + g / 2).toFloat(),
                    sweepAngle = (sweep - g).toFloat(),
                    useCenter = false,
                    topLeft = Offset(center.x - r, center.y - r) + off,
                    size = Size(r * 2, r * 2),
                    style = Stroke(width = sw, cap = StrokeCap.Butt),
                )
                labs.add(arrayOf(mid, cos(mid) >= 0, center.y + (outer + 16.dp.toPx()) * sin(mid).toFloat(), String.format("%.1f%%", v / tot * 100)))
                a0 += sweep
            }
            // keep labels apart: per side sort by y and push down (no overlapping % texts)
            val gapY = 14.dp.toPx()
            for (side in listOf(true, false)) {
                val ls = labs.filter { it[1] == side }.sortedBy { it[2] as Float }
                for (k in 1 until ls.size) if ((ls[k][2] as Float) - (ls[k - 1][2] as Float) < gapY) ls[k][2] = (ls[k - 1][2] as Float) + gapY
                for (l in ls) {
                    val mid = l[0] as Double
                    val y = l[2] as Float
                    val ex = center.x + cos(mid).toFloat() * (outer + 3.dp.toPx())
                    val ey = center.y + sin(mid).toFloat() * (outer + 3.dp.toPx())
                    val kx = center.x + cos(mid).toFloat() * (outer + 12.dp.toPx())
                    val tx = if (side) maxOf(kx, center.x + 6.dp.toPx()) + 8.dp.toPx() else minOf(kx, center.x - 6.dp.toPx()) - 8.dp.toPx()
                    val lc = labelColor.copy(alpha = 0.35f)
                    drawLine(lc, Offset(ex, ey), Offset(kx, y), 1.dp.toPx())
                    drawLine(lc, Offset(kx, y), Offset(if (side) tx - 3.dp.toPx() else tx + 3.dp.toPx(), y), 1.dp.toPx())
                    val s = l[3] as String
                    val w = txt.measureText(s)
                    drawContext.canvas.nativeCanvas.drawText(s, if (side) tx else tx - w, y + txt.textSize / 3, txt)
                }
            }
        }
        val s = selected
        if (s != null && s in values.indices && tot > 0) {
            androidx.compose.foundation.layout.Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(money(values[s]), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = labelColor)
                Text(labels.getOrNull(s) ?: "", style = MaterialTheme.typography.labelSmall, color = labelColor.copy(alpha = 0.65f))
                Text(String.format("%.1f%%", values[s] / tot * 100), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = labelColor.copy(alpha = 0.65f))
            }
        }
    }
}

private class InsMapShape(val path: Path, val rings: List<FloatArray>)

private val insMapShapes: Map<String, InsMapShape> by lazy {
    WorldMapData.countries.mapValues { (_, v) ->
        val path = Path()
        val rings = ArrayList<FloatArray>()
        for (ring in v.split('|')) {
            val pts = ring.split(' ')
            val arr = FloatArray(pts.size * 2)
            var j = 0
            for (p in pts) {
                val c = p.indexOf(',')
                if (c <= 0) continue
                arr[j++] = p.substring(0, c).toFloatOrNull() ?: 0f
                arr[j++] = p.substring(c + 1).toFloatOrNull() ?: 0f
            }
            if (j < 6) continue
            val a = if (j == arr.size) arr else arr.copyOf(j)
            rings.add(a)
            path.moveTo(a[0], a[1])
            var k = 2
            while (k < a.size) { path.lineTo(a[k], a[k + 1]); k += 2 }
            path.close()
        }
        InsMapShape(path, rings)
    }
}

private fun insInside(r: FloatArray, x: Float, y: Float): Boolean {
    var inside = false
    var j = r.size - 2
    var i = 0
    while (i < r.size) {
        val xi = r[i]; val yi = r[i + 1]; val xj = r[j]; val yj = r[j + 1]
        if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside
        j = i; i += 2
    }
    return inside
}

/** v39: world map coloured by revenue per country. Tap a country to see its amount. */
@Composable
internal fun InsWorldMap(values: Map<String, Double>, names: Map<String, String>, money: (Double) -> String) {
    var sel by remember { mutableStateOf<String?>(null) }
    val empty = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.10f)
    val line = MaterialTheme.colorScheme.surface
    val mx = values.values.maxOrNull() ?: 0.0
    val lmx = ln(1 + mx * 100)
    Box(Modifier.fillMaxWidth()) {
        Canvas(
            Modifier
                .fillMaxWidth()
                .aspectRatio(WorldMapData.W / WorldMapData.H)
                .pointerInput(values) {
                    detectTapGestures { o ->
                        val s = size.width / WorldMapData.W
                        val x = o.x / s; val y = o.y / s
                        sel = values.keys.firstOrNull { k -> insMapShapes[k]?.rings?.any { insInside(it, x, y) } == true }
                    }
                },
        ) {
            val s = size.width / WorldMapData.W
            scale(s, s, pivot = Offset.Zero) {
                for ((k, shp) in insMapShapes) {
                    val v = values[k]
                    var col = empty
                    if (v != null) {
                        val t = if (lmx > 0) (ln(1 + v * 100) / lmx).toFloat().coerceIn(0f, 1f) else 0f
                        col = lerp(Color(0xFFC9E3FF), Color(0xFF008CDF), t)
                        if (k == sel) col = lerp(col, Color.Black, 0.2f)
                    }
                    drawPath(shp.path, col)
                    drawPath(shp.path, line, style = Stroke(width = 0.8f))
                }
            }
        }
        val k = sel
        if (k != null) {
            Text(
                "${names[k] ?: k}  ${money(values[k] ?: 0.0)}",
                Modifier.align(Alignment.TopStart).padding(6.dp).background(Color(0xFF008CDF), RoundedCornerShape(6.dp)).padding(horizontal = 10.dp, vertical = 5.dp),
                color = Color.White,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
