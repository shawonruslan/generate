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
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
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

    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            SectionCard("Round-robin across accounts", "Files (or archive sets) go ZEDGE1 → ZEDGE2 → ZEDGE3, one per account in turn. The pointer persists for this app session.") {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                    Accounts.distOrder.forEachIndexed { i, key ->
                        val next = i == pointer
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(
                                Modifier.size(64.dp).clip(CircleShape).background(if (next) BrandYellow else MaterialTheme.colorScheme.surfaceVariant)
                                    .border(if (next) 3.dp else 1.dp, if (next) BrandDark else MaterialTheme.colorScheme.outlineVariant, CircleShape),
                                contentAlignment = Alignment.Center
                            ) { Text(Accounts.byKey(key).label.replace("ZEDGE", "Z"), fontWeight = FontWeight.Bold, color = if (next) BrandDark else MaterialTheme.colorScheme.onSurface) }
                            Spacer(Modifier.height(4.dp))
                            Text(if (next) "NEXT" else "", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                        }
                        if (i < Accounts.distOrder.size - 1) Text("→", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        item {
            SectionCard("Image mode", "WALLPAPER = single files. 24H / DUAL / BATTERY = images grouped in name order into sets (4 / 2 / 6 per set). Archives are always auto-detected.") {
                ChipRow(listOf("WALLPAPER" to "WALLPAPER") + ContentTypes.SET_TYPES.values.map { it.type to it.short }, imageMode, { imageMode = it })
                Spacer(Modifier.height(12.dp))
                Text("Video type", style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.height(6.dp))
                ChipRow(ContentTypes.VIDEO_TYPES.values.map { it.type to it.label }, videoType, { videoType = it })
            }
        }
        item {
            SectionCard("Distribute files") {
                DropZone(icon = { Icon(Icons.Default.Hub, null, Modifier.size(36.dp), tint = typeColor(imageMode)) }, title = "Choose files or ZIP / RAR", hint = "Images, MP3, MP4/MOV, archives — multiple allowed", enabled = !busy) {
                    pick.launch(arrayOf("image/*", "audio/mpeg", "video/*", "application/zip", "application/x-zip-compressed", "application/vnd.rar", "application/x-rar-compressed", "application/octet-stream"))
                }
                Spacer(Modifier.height(10.dp))
                if (progress != null) Text(progress!!.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(status.ifBlank { "Idle - nothing distributed yet in this session." }, style = MaterialTheme.typography.bodyMedium, color = if (status.startsWith("Error")) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface)
                Spacer(Modifier.height(6.dp))
                Text("Already distributed this session: ${vm.repo.distPushedNames.size} file(s)", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item { Spacer(Modifier.height(72.dp)) }
    }
}
