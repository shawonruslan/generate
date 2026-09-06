package com.zedge.contentstudio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.Fmt
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.components.StatusPill
import com.zedge.contentstudio.ui.components.TypeBadge
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.typeColor

/** Bottom sheet: phone-mockup preview + metadata editor + actions (same as the dashboard modal). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ItemDetailSheet(vm: MainViewModel, item: QueueItem, onDismiss: () -> Unit) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val active by vm.activeKey.collectAsStateWithLifecycle()
    val copyState by vm.copyState.collectAsStateWithLifecycle()
    val plan by vm.plan.collectAsStateWithLifecycle()
    var title by remember(item.id) { mutableStateOf(item.title) }
    var tags by remember(item.id) { mutableStateOf(item.tags) }
    var category by remember(item.id) { mutableStateOf(item.category) }
    var description by remember(item.id) { mutableStateOf(item.description) }
    var scheduled by remember(item.id) { mutableStateOf(item.scheduledDate ?: "") }
    var showDate by remember { mutableStateOf(false) }
    var slotIdx by remember(item.id) { mutableStateOf(0) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(item.displayTitle, style = MaterialTheme.typography.titleLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(item.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                TypeBadge(item.dayType, long = true)
            }
            Spacer(Modifier.height(12.dp))

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                // Phone mockup
                Column(Modifier.weight(0.42f)) {
                    PhoneMockup(item, slotIdx)
                    if (item.isSetType) {
                        Spacer(Modifier.height(8.dp))
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            items(item.slots.size) { i ->
                                val sel = i == slotIdx
                                Box(Modifier.clip(RoundedCornerShape(999.dp)).background(if (sel) typeColor(item.dayType) else MaterialTheme.colorScheme.surfaceVariant).clickable { slotIdx = i }.padding(horizontal = 8.dp, vertical = 3.dp)) {
                                    Text(item.slots[i], color = if (sel) Color.White else MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.labelSmall)
                                }
                            }
                        }
                    }
                }
                // Facts
                Column(Modifier.weight(0.58f)) {
                    Fact("Status") { StatusPill(item.status.uppercase(), if (item.isQueued) MaterialTheme.colorScheme.primary else if (item.status == "error") MaterialTheme.colorScheme.error else Ok) }
                    Fact("Account") { Text(Accounts.byKey(active).label) }
                    Fact("Size") { Text(Fmt.bytes(item.size)) }
                    Fact("Added") { Text(if (item.createdAt > 0) java.text.SimpleDateFormat("dd MMM yyyy HH:mm", java.util.Locale.UK).format(java.util.Date(item.createdAt)) else "-") }
                    Fact("Schedule") {
                        Text(
                            if (item.isPinned) "Pinned · ${RealTime.prettyKey(item.scheduledDate)}"
                            else plan.predictedDateFor(item.id)?.let { "Auto · ${RealTime.prettyKey(it)}" } ?: (if (item.isQueued) "Waiting for stock" else "-")
                        )
                    }
                    if (item.distributedTo != null) Fact("Distributed to") { Text(item.distributedTo!!.uppercase()) }
                    if (item.importedFrom != null) Fact("Imported from") { Text(item.importedFrom!!, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    if (item.error.isNotBlank()) Fact("Error") { Text(item.error, color = MaterialTheme.colorScheme.error, maxLines = 3, overflow = TextOverflow.Ellipsis) }
                }
            }

            if (item.isVideoType && item.fileUrl.isNotBlank()) { Spacer(Modifier.height(12.dp)); VideoPlayer(item.fileUrl) }
            if (item.isMp3 && item.fileUrl.isNotBlank()) { Spacer(Modifier.height(12.dp)); AudioPlayer(item.fileUrl) }

            Spacer(Modifier.height(16.dp))
            Text("Metadata", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(), label = { Text("Title") }, singleLine = true)
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(tags, { tags = it }, Modifier.fillMaxWidth(), label = { Text("Tags (comma separated)") })
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(category, { category = it }, Modifier.fillMaxWidth(), label = { Text("Category") }, singleLine = true)
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(description, { description = it }, Modifier.fillMaxWidth().height(100.dp), label = { Text("Description") })
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(scheduled, { scheduled = it }, Modifier.weight(1f), label = { Text("Pinned date (YYYY-MM-DD, empty = auto)") }, singleLine = true)
                Spacer(Modifier.width(8.dp))
                OutlinedButton(onClick = { showDate = true }) { Text("Pick") }
            }

            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { vm.saveMetadata(item, title, tags, category, description, scheduled.ifBlank { null }); onDismiss() }) { Text("Save") }
                if (!item.isQueued) OutlinedButton(onClick = { vm.requeue(item) }) { Text("Requeue") }
                if (item.isPinned) OutlinedButton(onClick = { vm.unpin(item) }) { Text("Unpin") }
                TextButton(onClick = { vm.delete(item) }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            }
            Spacer(Modifier.height(8.dp))
            FilledTonalButton(onClick = { vm.copyToOtherAccounts(item) }, enabled = copyState == "idle", modifier = Modifier.fillMaxWidth()) {
                Text(
                    when (copyState) {
                        "copying" -> "Copying..."
                        "done" -> "Copied to " + Accounts.distOrder.filter { it != active }.joinToString(" + ") { it.uppercase() }
                        "failed" -> "Failed - try again"
                        else -> "Copy to Other Accounts"
                    }
                )
            }
        }
    }

    if (showDate) DateKeyPicker(initialKey = scheduled.ifBlank { null }, onDismiss = { showDate = false }) { scheduled = it; showDate = false }
}

@Composable
private fun Fact(label: String, value: @Composable () -> Unit) {
    Column(Modifier.padding(bottom = 8.dp)) {
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        value()
    }
}

/** Phone-frame preview (like the dashboard's mockup): thumbnail, notch, clock, type-specific overlay. */
@Composable
fun PhoneMockup(item: QueueItem, slotIdx: Int, modifier: Modifier = Modifier) {
    val c = typeColor(item.dayType)
    val url = if (item.isSetType) item.slotUrl(item.slots.getOrElse(slotIdx) { item.slots.firstOrNull() ?: "" }).ifBlank { item.previewUrl } else item.previewUrl
    Box(
        modifier.fillMaxWidth().aspectRatio(9f / 19f).clip(RoundedCornerShape(26.dp)).background(BrandDark).border(6.dp, BrandDark, RoundedCornerShape(26.dp)).padding(4.dp)
    ) {
        Box(Modifier.fillMaxSize().clip(RoundedCornerShape(22.dp)).background(c.copy(alpha = 0.6f))) {
            if (url.isNotBlank()) AsyncImage(model = url, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            // notch
            Box(Modifier.align(Alignment.TopCenter).padding(top = 8.dp).width(60.dp).height(14.dp).clip(RoundedCornerShape(999.dp)).background(BrandDark))
            Column(Modifier.align(Alignment.TopCenter).padding(top = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(RealTime.dhakaNow().toLocalTime().withSecond(0).toString().take(5), color = Color.White, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Light)
                Text(RealTime.longKey(RealTime.key(RealTime.dhakaDate())), color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.labelSmall)
            }
            if (item.isMp3) Box(Modifier.align(Alignment.Center).size(56.dp).clip(RoundedCornerShape(999.dp)).background(Color.White.copy(alpha = 0.25f)), contentAlignment = Alignment.Center) { Icon(Icons.Default.PlayArrow, null, tint = Color.White) }
            Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 10.dp).clip(RoundedCornerShape(999.dp)).background(Color.Black.copy(alpha = 0.45f)).padding(horizontal = 10.dp, vertical = 4.dp)) {
                Text(if (item.isSetType) item.slots.getOrElse(slotIdx) { "" }.uppercase() else ContentTypes.dayUi(item.dayType).label, color = Color.White, style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}

@Composable
fun VideoPlayer(url: String) {
    val ctx = LocalContext.current
    val exo = remember(url) { ExoPlayer.Builder(ctx).build().apply { setMediaItem(MediaItem.fromUri(url)); repeatMode = Player.REPEAT_MODE_ALL; prepare(); playWhenReady = false } }
    DisposableEffect(exo) { onDispose { exo.release() } }
    AndroidView(factory = { PlayerView(it).apply { player = exo; useController = true } }, modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(12.dp)))
}

@Composable
fun AudioPlayer(url: String) {
    val ctx = LocalContext.current
    val player = remember(url) { ExoPlayer.Builder(ctx).build().apply { setMediaItem(MediaItem.fromUri(url)); prepare() } }
    var playing by remember { mutableStateOf(false) }
    DisposableEffect(player) {
        val l = object : Player.Listener { override fun onIsPlayingChanged(isPlaying: Boolean) { playing = isPlaying } }
        player.addListener(l)
        onDispose { player.removeListener(l); player.release() }
    }
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceVariant).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { if (playing) player.pause() else player.play() }) { Icon(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, null) }
        Text(if (playing) "Playing ringtone preview" else "Play ringtone preview", style = MaterialTheme.typography.bodyMedium)
    }
}
