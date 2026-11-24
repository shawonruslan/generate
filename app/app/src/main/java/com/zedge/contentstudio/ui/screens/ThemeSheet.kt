package com.zedge.contentstudio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
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

/**
 * v31 Theme Switcher: strictly uses the Zedge Panel color theme (default) and Night theme.
 * No extra custom themes or custom color overrides.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThemeSheet(vm: MainViewModel, activeKey: String, onDismiss: () -> Unit) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val themes by vm.theme.collectAsStateWithLifecycle()
    val saved = themes[activeKey] ?: ThemeConfig()
    var draft by remember(activeKey) { mutableStateOf(saved.sanitized()) }
    LaunchedEffect(draft) { vm.previewTheme(draft) }
    val cancel: () -> Unit = { vm.previewTheme(null); onDismiss() }
    val accLabel = Accounts.byKey(activeKey).label

    ModalBottomSheet(onDismissRequest = cancel, sheetState = sheet) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(bottom = 28.dp)) {
            Text("Theme", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
            Text("$accLabel · Zedge Panel & Night theme", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(14.dp))

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ThemeConfig.PRESETS.forEach { p ->
                    val on = draft.matchesPreset().key == p.key
                    Column(
                        Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(14.dp))
                            .background(parseHex(p.surface, Color.White))
                            .border(2.dp, if (on) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(14.dp))
                            .clickable { draft = draft.withPreset(p) }
                            .padding(14.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            listOf(p.primary, p.accent, p.bg, p.text).forEach { c ->
                                Box(Modifier.size(16.dp).clip(CircleShape).background(parseHex(c, Color.Gray)).border(1.dp, Color.Black.copy(alpha = 0.15f), CircleShape))
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        Text(p.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = parseHex(p.text, Color.Black), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(if (p.key == "night") "Dark mode" else "Default light", style = MaterialTheme.typography.labelSmall, color = parseHex(p.text, Color.Black).copy(alpha = 0.65f))
                    }
                }
            }

            Spacer(Modifier.height(20.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = { draft = ThemeConfig().sanitized() }) { Text("Zedge Default") }
                OutlinedButton(onClick = { vm.saveTheme(draft, allAccounts = true); onDismiss() }) { Text("All accounts") }
                Button(onClick = { vm.saveTheme(draft); onDismiss() }, modifier = Modifier.weight(1f)) { Text("Save · $accLabel", maxLines = 1) }
            }
            TextButton(onClick = cancel, modifier = Modifier.align(Alignment.End)) { Text("Cancel") }
        }
    }
}
