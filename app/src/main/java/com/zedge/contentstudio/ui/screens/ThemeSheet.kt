package com.zedge.contentstudio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.data.ThemeConfig
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.theme.parseHex
import kotlin.math.roundToInt

private val TS_QUICK_COLORS = listOf(
    "#ffd400", "#ffab00", "#ff8a00", "#ff5c8a", "#ef4444", "#a78bfa", "#7c5cff", "#2f80ed", "#38bdf8", "#22c55e", "#10b981", "#14b8a6",
    "#ffffff", "#fffdf6", "#f5f5f5", "#211d12", "#181410", "#0f172a", "#000000",
)
private val TS_COLOR_KEYS = listOf("primary" to "Primary", "accent" to "Accent", "bg" to "Background", "surface" to "Cards", "text" to "Text")

/**
 * v26 Theme Studio: presets + 5 custom colours + font size + corner radius + density.
 * Live preview while editing; Save writes dashboardSettings/theme (per account, shared with the web panel).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ThemeSheet(vm: MainViewModel, activeKey: String, onDismiss: () -> Unit) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val themes by vm.theme.collectAsStateWithLifecycle()
    val saved = themes[activeKey] ?: ThemeConfig()
    var draft by remember(activeKey) { mutableStateOf(saved.sanitized()) }
    var editing by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(draft) { vm.previewTheme(draft) }
    val cancel: () -> Unit = { vm.previewTheme(null); onDismiss() }
    val accLabel = Accounts.byKey(activeKey).label

    ModalBottomSheet(onDismissRequest = cancel, sheetState = sheet) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(bottom = 28.dp)) {
            Text("Theme Studio", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
            Text("$accLabel \u00b7 saved in Firebase, shared with the web panel", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))

            TsLabel("Presets")
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {   // v30: wraps, nothing clipped
                ThemeConfig.PRESETS.forEach { p ->
                    val on = draft.matchesPreset()?.key == p.key
                    Column(
                        Modifier
                            .width(86.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(parseHex(p.surface, Color.White))
                            .border(2.dp, if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(12.dp))
                            .clickable { draft = draft.withPreset(p) }
                            .padding(8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                            listOf(p.primary, p.accent, p.bg, p.text).forEach { c ->
                                Box(Modifier.size(14.dp).clip(CircleShape).background(parseHex(c, Color.Gray)).border(1.dp, Color.Black.copy(alpha = 0.15f), CircleShape))
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(p.name, style = MaterialTheme.typography.labelSmall, color = parseHex(p.text, Color.Black), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }

            Spacer(Modifier.height(12.dp))
            TsLabel(if (draft.matchesPreset() == null) "Custom colors \u00b7 custom palette" else "Custom colors")
            TS_COLOR_KEYS.forEach { (key, name) ->
                TsColorRow(
                    name = name,
                    value = draft.colorOf(key),
                    expanded = editing == key,
                    onToggle = { editing = if (editing == key) null else key },
                    onChange = { hex -> draft = draft.withColor(key, hex) },
                )
            }

            // v27.8 per-element colours (same 7 keys as the web panel Theme Studio)
            Spacer(Modifier.height(12.dp))
            TsLabel("Element colors \u00b7 Auto = follows palette")
            ThemeConfig.ELEMENT_KEYS.forEach { (key, name) ->
                val v = draft.element(key)
                val autoHex = if (key == "card" || key == "sidebar") draft.surface else draft.primary
                TsElementRow(
                    name = name,
                    value = v,
                    autoValue = autoHex,
                    expanded = editing == "el:" + key,
                    onToggle = { editing = if (editing == "el:" + key) null else "el:" + key },
                    onChange = { hex -> draft = draft.withElement(key, hex) },
                    onAuto = { draft = draft.withElement(key, null); if (editing == "el:" + key) editing = null },
                )
            }

            Spacer(Modifier.height(10.dp))
            TsLabel("Font size \u00b7 " + (draft.fontScale * 100f).roundToInt() + "%")
            Slider(
                value = draft.fontScale,
                onValueChange = { draft = draft.copy(fontScale = ((it * 20f).roundToInt() / 20f).coerceIn(0.8f, 1.3f)) },
                valueRange = 0.8f..1.3f,
                steps = 9,
            )
            TsLabel("Corner radius \u00b7 " + (draft.radius * 100f).roundToInt() + "%")
            Slider(
                value = draft.radius,
                onValueChange = { draft = draft.copy(radius = ((it * 10f).roundToInt() / 10f).coerceIn(0f, 1.6f)) },
                valueRange = 0f..1.6f,
                steps = 15,
            )
            TsLabel("Density")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = draft.density != "compact", onClick = { draft = draft.copy(density = "comfortable") }, label = { Text("Comfortable") })
                FilterChip(selected = draft.density == "compact", onClick = { draft = draft.copy(density = "compact") }, label = { Text("Compact") })
            }

            Spacer(Modifier.height(18.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = { draft = ThemeConfig() }) { Text("Reset") }
                OutlinedButton(onClick = { vm.saveTheme(draft, allAccounts = true); onDismiss() }) { Text("All accounts") }
                Button(onClick = { vm.saveTheme(draft); onDismiss() }, modifier = Modifier.weight(1f)) { Text("Save \u00b7 $accLabel", maxLines = 1) }
            }
            TextButton(onClick = cancel, modifier = Modifier.align(Alignment.End)) { Text("Cancel (discard preview)") }
        }
    }
}

@Composable
private fun TsLabel(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 8.dp, bottom = 6.dp),
    )
}

@Composable
private fun TsColorRow(name: String, value: String, expanded: Boolean, onToggle: () -> Unit, onChange: (String) -> Unit) {
    var text by remember(value) { mutableStateOf(value) }
    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(parseHex(value, Color.Gray))
                .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(10.dp))
                .clickable(onClick = onToggle),
        )
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(if (expanded) "tap swatch to close" else "tap swatch for sliders", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        OutlinedTextField(
            value = text,
            onValueChange = { v ->
                text = v
                val n = ThemeConfig.normHex(v, "")
                if (n.isNotEmpty() && n != value) onChange(n)
            },
            singleLine = true,
            modifier = Modifier.width(118.dp),
            textStyle = MaterialTheme.typography.bodySmall,
        )
    }
    if (expanded) TsHsvEditor(value, onChange)
}

@Composable
private fun TsElementRow(name: String, value: String?, autoValue: String, expanded: Boolean, onToggle: () -> Unit, onChange: (String) -> Unit, onAuto: () -> Unit) {
    val shown = value ?: autoValue
    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(parseHex(shown, Color.Gray))
                .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(10.dp))
                .clickable(onClick = onToggle),
        )
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(if (value == null) "Auto \u00b7 tap swatch to customise" else value, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (value != null) TextButton(onClick = onAuto) { Text("Auto") }
    }
    if (expanded) TsHsvEditor(shown, onChange)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TsHsvEditor(hex: String, onChange: (String) -> Unit) {
    val hsv = remember(hex) {
        FloatArray(3).also { android.graphics.Color.colorToHSV(android.graphics.Color.parseColor(ThemeConfig.normHex(hex, "#888888")), it) }
    }
    fun emit(h: Float, s: Float, v: Float) {
        val argb = android.graphics.Color.HSVToColor(floatArrayOf(h.coerceIn(0f, 360f), s.coerceIn(0f, 1f), v.coerceIn(0f, 1f)))
        onChange(String.format("#%06x", argb and 0xFFFFFF))
    }
    Column(Modifier.fillMaxWidth().padding(start = 46.dp, bottom = 8.dp)) {
        TsSliderRow("Hue", hsv[0] / 360f) { emit(it * 360f, hsv[1], hsv[2]) }
        TsSliderRow("Saturation", hsv[1]) { emit(hsv[0], it, hsv[2]) }
        TsSliderRow("Brightness", hsv[2]) { emit(hsv[0], hsv[1], it) }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            TS_QUICK_COLORS.forEach { c ->
                Box(
                    Modifier
                        .size(26.dp)
                        .clip(CircleShape)
                        .background(parseHex(c, Color.Gray))
                        .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape)
                        .clickable { onChange(c) },
                )
            }
        }
    }
}

@Composable
private fun TsSliderRow(label: String, value: Float, onChange: (Float) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.width(80.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Slider(value = value.coerceIn(0f, 1f), onValueChange = onChange, modifier = Modifier.weight(1f))
    }
}
