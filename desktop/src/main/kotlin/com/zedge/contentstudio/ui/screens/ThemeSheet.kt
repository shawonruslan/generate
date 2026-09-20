package com.zedge.contentstudio.ui.screens

import androidx.compose.runtime.DisposableEffect
import kotlinx.coroutines.delay
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.Brush
import androidx.compose.foundation.BorderStroke
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import com.zedge.contentstudio.ui.components.MhLogoMark

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

// =============================================================================================
// v30: Theme Studio as a full desktop PAGE (Ctrl+T) - not a modal sheet.
// Left: presets grid, palette, element colours, typography/shape. Right: live mock preview + logo.
// The whole app previews the draft while editing; leaving the page discards an unsaved preview.
// =============================================================================================

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ThemeStudioScreen(vm: MainViewModel, activeKey: String, onClose: () -> Unit) {
    val themes by vm.theme.collectAsStateWithLifecycle()
    val saved = themes[activeKey] ?: ThemeConfig()
    var draft by remember(activeKey) { mutableStateOf(saved.sanitized()) }
    var editing by remember { mutableStateOf<String?>(null) }
    var savedFlash by remember { mutableStateOf(false) }
    LaunchedEffect(draft) { vm.previewTheme(draft) }
    DisposableEffect(Unit) { onDispose { vm.previewTheme(null) } }
    if (savedFlash) LaunchedEffect(savedFlash) { delay(2400); savedFlash = false }
    val accLabel = Accounts.byKey(activeKey).label
    val cs = MaterialTheme.colorScheme
    val dirty = draft != saved.sanitized()
    val dPrimary = parseHex(draft.primary, cs.primary)
    val dText = parseHex(draft.text, cs.onSurface)
    val dSurface = parseHex(draft.surface, cs.surface)

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 36.dp)) {
        // ---- Header: logo (live colours) + title + actions ----
        Row(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            MhLogoMark(Modifier.size(54.dp), primary = dPrimary, ink = dText, tile = dSurface, corner = 16.dp)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text("Theme Studio", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.ExtraBold)
                Text("$accLabel \u00b7 saved in Firebase \u00b7 shared with the web panel and the Android app \u00b7 Ctrl+T", style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
            }
            if (savedFlash) {
                Text("\u2713 Saved \u00b7 panel & app update live", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = cs.primary)
                Spacer(Modifier.width(12.dp))
            } else if (dirty) {
                Text("Previewing unsaved changes", style = MaterialTheme.typography.labelMedium, color = cs.onSurfaceVariant)
                Spacer(Modifier.width(12.dp))
            }
            OutlinedButton(onClick = { draft = ThemeConfig(); editing = null }) { Text("Reset") }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = { vm.saveTheme(draft, allAccounts = true); savedFlash = true }) { Text("Save to all accounts") }
            Spacer(Modifier.width(8.dp))
            Button(onClick = { vm.saveTheme(draft); savedFlash = true }) { Text("Save \u00b7 $accLabel", maxLines = 1) }
            Spacer(Modifier.width(8.dp))
            TextButton(onClick = { vm.previewTheme(null); onClose() }) { Text("Close") }
        }

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            // ---------------- LEFT: editors ----------------
            Column(Modifier.weight(1.25f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                TsCard("Presets", "${ThemeConfig.PRESETS.size} professional palettes \u00b7 click to apply, then fine-tune below") {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        ThemeConfig.PRESETS.forEach { p ->
                            val on = draft.matchesPreset()?.key == p.key
                            TsPresetCard(p, on) { draft = draft.withPreset(p); editing = null }
                        }
                    }
                }
                TsCard(if (draft.matchesPreset() == null) "Palette \u00b7 custom" else "Palette \u00b7 " + (draft.matchesPreset()?.name ?: ""), "Five base colours - every other colour is derived from them") {
                    TS_COLOR_KEYS.forEach { (key, name) ->
                        TsColorRow(
                            name = name,
                            value = draft.colorOf(key),
                            expanded = editing == key,
                            onToggle = { editing = if (editing == key) null else key },
                            onChange = { hex -> draft = draft.withColor(key, hex) },
                        )
                    }
                }
                TsCard("Element colours", "Auto = follows the palette. Same seven keys as the web panel.") {
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
                }
                TsCard("Typography & shape", "Font size, corner radius and density") {
                    TsLabel("Font size \u00b7 " + (draft.fontScale * 100f).roundToInt() + "%")
                    Slider(
                        value = draft.fontScale,
                        onValueChange = { draft = draft.copy(fontScale = ((it * 20f).roundToInt() / 20f).coerceIn(0.8f, 1.3f)) },
                        valueRange = 0.8f..1.3f,
                    )
                    TsLabel("Corner radius \u00b7 " + (draft.radius * 100f).roundToInt() + "%")
                    Slider(
                        value = draft.radius,
                        onValueChange = { draft = draft.copy(radius = ((it * 10f).roundToInt() / 10f).coerceIn(0f, 1.6f)) },
                        valueRange = 0f..1.6f,
                    )
                    TsLabel("Density")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(selected = draft.density != "compact", onClick = { draft = draft.copy(density = "comfortable") }, label = { Text("Comfortable") })
                        FilterChip(selected = draft.density == "compact", onClick = { draft = draft.copy(density = "compact") }, label = { Text("Compact") })
                    }
                }
            }

            // ---------------- RIGHT: live preview ----------------
            Column(Modifier.weight(0.85f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                TsCard("Live preview", "How the panel, app and desktop will look with this palette") {
                    TsPreviewPanel(draft)
                }
                TsCard("Logo", "The monogram re-tints with the primary and text colours - also the window, taskbar, tray and web favicon") {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        MhLogoMark(Modifier.size(72.dp), primary = dPrimary, ink = dText, tile = dSurface, corner = 20.dp)
                        MhLogoMark(Modifier.size(48.dp), primary = dPrimary, ink = dText, tile = dSurface, corner = 14.dp)
                        MhLogoMark(Modifier.size(32.dp), primary = dPrimary, ink = dText, tile = dSurface, corner = 9.dp)
                        MhLogoMark(Modifier.size(20.dp), primary = dPrimary, ink = dText, tile = dSurface, corner = 6.dp, outline = null)
                        Spacer(Modifier.width(6.dp))
                        Column {
                            Text("Meta Hawladar", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.ExtraBold)
                            Text("primary ${draft.primary} \u00b7 ink ${draft.text}", style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TsCard(title: String, subtitle: String, content: @Composable ColumnScope.() -> Unit) {
    val cs = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(18.dp)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(cs.surfaceContainerHigh.copy(alpha = 0.92f)).border(1.dp, cs.outline.copy(alpha = 0.32f), shape).padding(16.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Text(subtitle, style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant)
        Spacer(Modifier.height(10.dp))
        content()
    }
}

@Composable
private fun TsPresetCard(p: ThemeConfig.Preset, on: Boolean, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val bg = parseHex(p.bg, Color.White)
    val sf = parseHex(p.surface, Color.White)
    val pr = parseHex(p.primary, Color.Gray)
    val ac = parseHex(p.accent, Color.Gray)
    val tx = parseHex(p.text, Color.Black)
    val shape = RoundedCornerShape(14.dp)
    Column(
        Modifier.width(138.dp).clip(shape).background(bg)
            .border(if (on) 2.dp else 1.dp, if (on) cs.primary else cs.outlineVariant, shape)
            .clickable(onClick = onClick)
            .padding(10.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(50.dp).clip(RoundedCornerShape(10.dp)).background(sf).padding(8.dp)) {
            Column {
                Box(Modifier.width(44.dp).height(7.dp).clip(CircleShape).background(pr))
                Spacer(Modifier.height(6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box(Modifier.width(26.dp).height(6.dp).clip(CircleShape).background(tx.copy(alpha = 0.75f)))
                    Box(Modifier.width(16.dp).height(6.dp).clip(CircleShape).background(ac))
                    Box(Modifier.width(10.dp).height(6.dp).clip(CircleShape).background(tx.copy(alpha = 0.3f)))
                }
            }
            if (on) Icon(Icons.Default.CheckCircle, null, Modifier.align(Alignment.TopEnd).size(15.dp), tint = pr)
        }
        Spacer(Modifier.height(8.dp))
        Text(p.name, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = tx, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(if (bg.luminance() < 0.35f) "Dark" else "Light", style = MaterialTheme.typography.labelSmall, color = tx.copy(alpha = 0.6f))
    }
}

@Composable
private fun TsPreviewPanel(d: ThemeConfig) {
    val p = parseHex(d.primary, Color.Gray)
    val a = parseHex(d.accent, Color.Gray)
    val bg = parseHex(d.bg, Color.White)
    val sf = parseHex(d.surface, Color.White)
    val tx = parseHex(d.text, Color.Black)
    val onP = if (p.luminance() > 0.45f) Color(0xFF1C1A12) else Color.White
    val r = (14f * d.radius).dp
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(bg).border(1.dp, tx.copy(alpha = 0.12f), RoundedCornerShape(18.dp)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            MhLogoMark(Modifier.size(34.dp), primary = p, ink = tx, tile = sf, corner = 10.dp, outline = tx.copy(alpha = 0.15f))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text("Meta Hawladar", color = tx, fontWeight = FontWeight.ExtraBold, style = MaterialTheme.typography.titleSmall)
                Text("Dashboard \u00b7 Zedge automation", color = tx.copy(alpha = 0.62f), style = MaterialTheme.typography.labelSmall)
            }
            Row(Modifier.clip(CircleShape).background(a.copy(alpha = 0.18f)).padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(a))
                Spacer(Modifier.width(6.dp))
                Text("LIVE SYNC", color = if (bg.luminance() < 0.35f) a else tx, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
            }
        }
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(r)).background(Brush.linearGradient(listOf(p, a))).padding(14.dp)) {
            Column {
                Text("All done for today", color = onP, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.ExtraBold)
                Text("3 / 3 uploads \u00b7 next 9:40 PM", color = onP.copy(alpha = 0.85f), style = MaterialTheme.typography.bodySmall)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("28" to "Ringtones", "12" to "Wallpapers", "3" to "Live").forEach { (n, l) ->
                Column(Modifier.weight(1f).clip(RoundedCornerShape(r)).background(sf).border(1.dp, tx.copy(alpha = 0.1f), RoundedCornerShape(r)).padding(10.dp)) {
                    Text(n, color = tx, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
                    Text(l, color = tx.copy(alpha = 0.65f), style = MaterialTheme.typography.labelSmall)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = {}, shape = RoundedCornerShape(r), colors = ButtonDefaults.buttonColors(containerColor = p, contentColor = onP)) { Text("Primary") }
            OutlinedButton(onClick = {}, shape = RoundedCornerShape(r), colors = ButtonDefaults.outlinedButtonColors(contentColor = tx), border = BorderStroke(1.dp, tx.copy(alpha = 0.35f))) { Text("Secondary") }
            Text("Accent link", color = a, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(r)).background(sf).border(1.dp, tx.copy(alpha = 0.1f), RoundedCornerShape(r)).padding(12.dp)) {
            Text("Body text sample - readable on cards", color = tx, style = MaterialTheme.typography.bodyMedium)
            Text("Muted caption \u00b7 " + (d.fontScale * 100f).roundToInt() + "% font \u00b7 " + d.density, color = tx.copy(alpha = 0.6f), style = MaterialTheme.typography.labelSmall)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf("DONE" to p, "NEXT" to a, "CLOSED" to tx.copy(alpha = 0.35f)).forEach { (t, c) ->
                    Text(t, color = if (c.luminance() > 0.45f) Color(0xFF1C1A12) else Color.White, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold,
                        modifier = Modifier.clip(CircleShape).background(c).padding(horizontal = 8.dp, vertical = 3.dp))
                }
            }
        }
    }
}
