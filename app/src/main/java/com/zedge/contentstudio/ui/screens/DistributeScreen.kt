package com.zedge.contentstudio.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.ChipRow
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.components.SectionCard
import com.zedge.contentstudio.ui.components.StatTile
import com.zedge.contentstudio.ui.theme.BrandAmber
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.typeColor

@Composable
fun DistributeScreen(vm: MainViewModel) {
    val busy by vm.busy.collectAsStateWithLifecycle()
    val status by vm.distStatusText.collectAsStateWithLifecycle()
    val progress by vm.progress.collectAsStateWithLifecycle()
    var imageMode by rememberSaveable { mutableStateOf("WALLPAPER") }
    var videoType by rememberSaveable { mutableStateOf("LIVE_WALLPAPER") }
    val pointer = vm.repo.distPointer % Accounts.distOrder.size

    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> if (uris.isNotEmpty()) vm.distribute(uris, imageMode, videoType) }

    LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // Round robin visual
        item {
            SectionCard("Round-robin", "Each file goes to the next account in turn: ZEDGE1 → ZEDGE2 → ZEDGE3 → ZEDGE4.") {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Accounts.distOrder.forEachIndexed { i, key ->
                        val next = i == pointer
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(
                                Modifier.size(52.dp).clip(CircleShape).background(if (next) BrandYellow else MaterialTheme.colorScheme.surfaceVariant)
                                    .border(if (next) 2.dp else 1.dp, if (next) BrandAmber else MaterialTheme.colorScheme.outlineVariant, CircleShape),
                                contentAlignment = Alignment.Center
                            ) { Text(Accounts.byKey(key).label.replace("ZEDGE", "Z"), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = if (next) BrandDark else MaterialTheme.colorScheme.onSurface) }
                            Spacer(Modifier.height(4.dp))
                            Text(if (next) "NEXT" else Accounts.byKey(key).label, style = MaterialTheme.typography.labelSmall, color = if (next) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (i < Accounts.distOrder.size - 1) Icon(Icons.Default.ArrowForward, null, Modifier.padding(horizontal = 10.dp).padding(bottom = 18.dp).size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        // Modes
        item {
            SectionCard("Image mode", "WALLPAPER = single files. 24H / DUAL / BATTERY = images grouped by name into sets (4 / 2 / 6 per set). Archives are auto-detected.") {
                ChipRow(options = listOf("WALLPAPER" to "WALLPAPER") + ContentTypes.SET_TYPES.values.map { it.type to it.short }, selected = imageMode, onSelect = { t: String -> imageMode = t })
                Spacer(Modifier.height(14.dp))
                Text("Video type", style = MaterialTheme.typography.titleSmall)
                Spacer(Modifier.height(6.dp))
                ChipRow(options = ContentTypes.VIDEO_TYPES.values.map { it.type to it.label }, selected = videoType, onSelect = { t: String -> videoType = t })
            }
        }
        // Picker
        item {
            SectionCard("Distribute files") {
                DropZone(icon = { Icon(Icons.Default.Hub, null, Modifier.size(32.dp), tint = typeColor(imageMode)) }, title = "Choose files or ZIP / RAR", hint = "Images, MP3, MP4/MOV, archives — multiple allowed", enabled = !busy) {
                    pick.launch(arrayOf("image/*", "audio/mpeg", "video/*", "application/zip", "application/x-zip-compressed", "application/vnd.rar", "application/x-rar-compressed", "application/octet-stream"))
                }
                Spacer(Modifier.height(10.dp))
                if (progress != null) Text(progress!!.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(status.ifBlank { "Idle — nothing distributed yet in this session." }, style = MaterialTheme.typography.bodySmall, color = if (status.startsWith("Error")) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface)
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile("Sent this session", vm.repo.distPushedNames.size.toString(), Modifier.weight(1f), Ok)
                StatTile("Next account", Accounts.byKey(Accounts.distOrder[pointer]).label, Modifier.weight(1f), BrandAmber)
            }
        }
        item { Spacer(Modifier.height(56.dp)) }
    }
}
