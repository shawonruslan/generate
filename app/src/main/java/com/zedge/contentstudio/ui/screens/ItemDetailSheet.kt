package com.zedge.contentstudio.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.BatteryAlert
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.BatteryFull
import androidx.compose.material.icons.filled.BatteryStd
import androidx.compose.material.icons.filled.Brightness3
import androidx.compose.material.icons.filled.Brightness4
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.CropPortrait
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Notes
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.PhoneIphone
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SignalCellular4Bar
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Tablet
import androidx.compose.material.icons.filled.Title
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material.icons.filled.ZoomOut
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
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
import com.zedge.contentstudio.ui.components.TypePill
import com.zedge.contentstudio.ui.components.typeIcon
import com.zedge.contentstudio.ui.theme.BrandAmber
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.typeColor
import kotlinx.coroutines.delay

// ------------------------------------------------------------------------------------------------
// Device frames (same presets as the web studio's "device chooser")
// ------------------------------------------------------------------------------------------------
private enum class Notch { ISLAND, NOTCH, DOT, DOT_LEFT, DROP, NONE }

private enum class DeviceFrame(val label: String, val icon: ImageVector, val ratio: Float, val screenCorner: Int, val notch: Notch, val bezelH: Int, val bezelTop: Int, val bezelBottom: Int, val homeButton: Boolean) {
    IOS_ISLAND("iPhone Pro", Icons.Default.PhoneIphone, 9f / 19.5f, 30, Notch.ISLAND, 8, 8, 8, false),
    IOS_NOTCH("iPhone 14", Icons.Default.PhoneIphone, 9f / 19.5f, 28, Notch.NOTCH, 8, 8, 8, false),
    IOS_CLASSIC("iPhone SE", Icons.Default.CropPortrait, 9f / 16f, 4, Notch.NONE, 8, 34, 34, true),
    AND_DOT("Dot notch", Icons.Default.PhoneAndroid, 9f / 20f, 26, Notch.DOT, 7, 7, 7, false),
    AND_DOT_LEFT("Dot left", Icons.Default.PhoneAndroid, 9f / 20f, 26, Notch.DOT_LEFT, 7, 7, 7, false),
    AND_DROP("Teardrop", Icons.Default.Smartphone, 9f / 19f, 24, Notch.DROP, 7, 7, 7, false),
    AND_FLAT("Bezel-less", Icons.Default.Smartphone, 9f / 20f, 18, Notch.NONE, 5, 5, 5, false),
    TABLET("Tablet", Icons.Default.Tablet, 3f / 4f, 14, Notch.NONE, 14, 18, 18, false);
}

private val PRES_SPEEDS = listOf(2000L, 3000L, 5000L, 8000L)
private data class PresFrame(val url: String, val title: String, val slot: String? = null)

private fun slotIcon(slot: String): ImageVector = when (slot) {
    "morning" -> Icons.Default.WbSunny
    "afternoon" -> Icons.Default.Cloud
    "evening" -> Icons.Default.Brightness4
    "night" -> Icons.Default.Brightness3
    "lock" -> Icons.Default.Lock
    "home" -> Icons.Default.Home
    "critical" -> Icons.Default.BatteryAlert
    "low", "mid" -> Icons.Default.BatteryStd
    "high", "full" -> Icons.Default.BatteryFull
    "charging" -> Icons.Default.BatteryChargingFull
    else -> Icons.Default.Image
}

private fun slotColor(slot: String): Color = when (slot) {
    "critical" -> Color(0xFFE53935)
    "low" -> Color(0xFFFB8C00)
    "mid" -> BrandAmber
    "high" -> Color(0xFF7CB342)
    "full" -> Color(0xFF43A047)
    "charging" -> Color(0xFF1E88E5)
    "night", "lock" -> Color(0xFF5C6BC0)
    "evening" -> Color(0xFF8E24AA)
    else -> BrandAmber
}

// ------------------------------------------------------------------------------------------------
// Sheet
// ------------------------------------------------------------------------------------------------
/** Asset details: device preview + auto presentation + storage metadata + publishing fields + actions. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ItemDetailSheet(vm: MainViewModel, item: QueueItem, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val active by vm.activeKey.collectAsStateWithLifecycle()
    val copyState by vm.copyState.collectAsStateWithLifecycle()
    val plan by vm.plan.collectAsStateWithLifecycle()
    val queue by vm.items.collectAsStateWithLifecycle()

    var title by remember(item.id) { mutableStateOf(item.title) }
    var tags by remember(item.id) { mutableStateOf(item.tags) }
    var category by remember(item.id) { mutableStateOf(item.category) }
    var description by remember(item.id) { mutableStateOf(item.description) }
    var scheduled by remember(item.id) { mutableStateOf(item.scheduledDate ?: "") }
    var showDate by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var zoomUrl by remember { mutableStateOf<String?>(null) }

    // Device frame (persisted like the web version)
    val prefs = remember { ctx.getSharedPreferences("studio_ui", 0) }
    var device by remember { mutableStateOf(runCatching { DeviceFrame.valueOf(prefs.getString("device", "") ?: "") }.getOrDefault(DeviceFrame.IOS_ISLAND)) }

    // Presentation frames: set slots, or every wallpaper in the queue starting from this one
    val frames = remember(item.id, queue.size) {
        when {
            item.isSetType -> item.slots.map { PresFrame(item.slotUrl(it), "${item.displayTitle} - $it", it) }.filter { it.url.isNotBlank() }
            item.isMp3 || item.isVideoType -> emptyList()
            else -> {
                val all = queue.filter { it.dayType == "WALLPAPER" && !it.isMp3 && it.previewUrl.isNotBlank() }.map { PresFrame(it.previewUrl, it.displayTitle) }
                if (all.none { it.url == item.previewUrl } && item.previewUrl.isNotBlank()) listOf(PresFrame(item.previewUrl, item.displayTitle)) + all else all
            }
        }
    }
    var presIdx by remember(item.id) { mutableIntStateOf(maxOf(0, frames.indexOfFirst { it.url == item.previewUrl })) }
    var playing by remember(item.id) { mutableStateOf(item.isSetType && frames.size > 1) }
    var speed by remember { mutableLongStateOf(prefs.getLong("presSpeed", 3000L)) }
    LaunchedEffect(playing, speed, frames.size) {
        while (playing && frames.size > 1) { delay(speed); presIdx = (presIdx + 1) % frames.size }
    }
    val current = frames.getOrNull(presIdx)
    val shownUrl = current?.url ?: item.previewUrl
    val shownSlot = current?.slot ?: item.slots.firstOrNull()

    val c = typeColor(item.dayType)
    val statusColor = when (item.status) { "uploaded" -> Ok; "processing" -> BrandAmber; "failed", "error" -> MaterialTheme.colorScheme.error; else -> MaterialTheme.colorScheme.primary }
    val statusIcon = when (item.status) { "uploaded" -> Icons.Default.CheckCircle; "processing" -> Icons.Default.Sync; "failed", "error" -> Icons.Default.Warning; else -> Icons.Default.Schedule }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet, containerColor = MaterialTheme.colorScheme.surface) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 40.dp)) {

            // ---------------- Header
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TypePill(item.dayType)
                        Spacer(Modifier.width(8.dp))
                        Row(Modifier.clip(CircleShape).background(statusColor.copy(alpha = 0.15f)).padding(horizontal = 9.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(statusIcon, null, Modifier.size(12.dp), tint = statusColor)
                            Spacer(Modifier.width(4.dp))
                            Text(item.status.uppercase(), color = statusColor, fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 0.6.sp)
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(item.displayTitle, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text("Preview, publishing fields and storage metadata", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, "Close") }
            }
            Spacer(Modifier.height(14.dp))

            // ---------------- Preview card
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp))
                    .background(Brush.verticalGradient(listOf(c.copy(alpha = 0.22f), MaterialTheme.colorScheme.surfaceContainer)))
                    .padding(14.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                PhoneMockup(item, shownUrl, shownSlot, device, Modifier.width(if (device == DeviceFrame.TABLET) 250.dp else 208.dp), onTap = { if (shownUrl.isNotBlank() && !item.isMp3 && !item.isVideoType) zoomUrl = shownUrl })

                // Device chooser
                Spacer(Modifier.height(12.dp))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    DeviceFrame.entries.forEach { d ->
                        val sel = d == device
                        Row(
                            Modifier.clip(CircleShape).background(if (sel) BrandYellow else MaterialTheme.colorScheme.surface)
                                .border(1.dp, if (sel) BrandAmber else MaterialTheme.colorScheme.outlineVariant, CircleShape)
                                .clickable { device = d; prefs.edit().putString("device", d.name).apply() }
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(d.icon, null, Modifier.size(13.dp), tint = if (sel) BrandDark else MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.width(5.dp))
                            Text(d.label, fontSize = 10.5.sp, lineHeight = 12.sp, fontWeight = FontWeight.ExtraBold, color = if (sel) BrandDark else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }

                // Auto presentation
                if (frames.size > 1) {
                    Spacer(Modifier.height(12.dp))
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        RoundBtn(Icons.Default.SkipPrevious) { playing = false; presIdx = (presIdx - 1 + frames.size) % frames.size }
                        val pulse by animateFloatAsState(if (playing) 1.08f else 1f, tween(300), label = "pulse")
                        Box(Modifier.size(40.dp).scale(pulse).clip(CircleShape).background(Brush.linearGradient(listOf(BrandYellow, BrandAmber))).clickable { playing = !playing }, contentAlignment = Alignment.Center) {
                            Icon(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (playing) "Pause" else "Play", tint = BrandDark)
                        }
                        RoundBtn(Icons.Default.SkipNext) { playing = false; presIdx = (presIdx + 1) % frames.size }
                        Text("${presIdx + 1} / ${frames.size}", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Box(
                            Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.surface).border(1.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape)
                                .clickable { speed = PRES_SPEEDS[(PRES_SPEEDS.indexOf(speed).coerceAtLeast(0) + 1) % PRES_SPEEDS.size]; prefs.edit().putLong("presSpeed", speed).apply() }
                                .padding(horizontal = 10.dp, vertical = 6.dp)
                        ) { Text("${speed / 1000}s", fontSize = 10.5.sp, lineHeight = 12.sp, fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.onSurface) }
                    }
                    if (playing) {
                        Spacer(Modifier.height(8.dp))
                        SlideProgress(key = presIdx, duration = speed, modifier = Modifier.fillMaxWidth(0.6f))
                    }
                    if (!item.isSetType) {
                        Spacer(Modifier.height(6.dp))
                        Text(current?.title ?: "", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }

                // Slot chips for sets
                if (item.isSetType) {
                    Spacer(Modifier.height(12.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        item.slots.forEach { s ->
                            val sel = s == shownSlot
                            val sc = slotColor(s)
                            Row(
                                Modifier.clip(CircleShape).background(if (sel) sc else sc.copy(alpha = 0.12f)).border(1.dp, sc.copy(alpha = if (sel) 1f else 0.5f), CircleShape)
                                    .clickable { playing = false; val i = frames.indexOfFirst { it.slot == s }; if (i >= 0) presIdx = i }
                                    .padding(horizontal = 10.dp, vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(slotIcon(s), null, Modifier.size(13.dp), tint = if (sel) Color.White else sc)
                                Spacer(Modifier.width(5.dp))
                                Text(s.replaceFirstChar { it.uppercase() }, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Bold, color = if (sel) Color.White else MaterialTheme.colorScheme.onSurface)
                            }
                        }
                    }
                }

                if (item.isMp3 && item.fileUrl.isNotBlank()) { Spacer(Modifier.height(12.dp)); AudioPlayer(item.fileUrl) }
            }

            // ---------------- Storage metadata
            Spacer(Modifier.height(16.dp))
            SectionTitle(Icons.Default.Storage, "Storage metadata")
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MetaBadge(statusIcon, "Status", item.status.uppercase(), statusColor, Modifier.weight(1f))
                MetaBadge(typeIcon(item.dayType), "Type", ContentTypes.dayUi(item.dayType).label, c, Modifier.weight(1f))
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MetaBadge(Icons.Default.Folder, "Category", category.ifBlank { "UNCLASSIFIED" }.uppercase(), BrandAmber, Modifier.weight(1f))
                MetaBadge(Icons.Default.Storage, "Size", Fmt.bytes(item.size), MaterialTheme.colorScheme.onSurfaceVariant, Modifier.weight(1f))
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MetaBadge(Icons.Default.Event, "Schedule",
                    if (item.isPinned) "Pinned \u00b7 ${RealTime.prettyKey(item.scheduledDate)}"
                    else plan.predictedDateFor(item.id)?.let { "Auto \u00b7 ${RealTime.prettyKey(it)}" } ?: (if (item.isQueued) "Waiting for stock" else "-"),
                    BrandYellow, Modifier.weight(1f))
                MetaBadge(Icons.Default.AccountCircle, "Account", Accounts.byKey(active).label, MaterialTheme.colorScheme.onSurfaceVariant, Modifier.weight(1f))
            }
            Spacer(Modifier.height(8.dp))
            MetaBadge(Icons.Default.DateRange, "Added", if (item.createdAt > 0) java.text.SimpleDateFormat("dd MMM yyyy, HH:mm", java.util.Locale.UK).format(java.util.Date(item.createdAt)) else "-", MaterialTheme.colorScheme.onSurfaceVariant)
            if (item.distributedTo != null) { Spacer(Modifier.height(8.dp)); MetaBadge(Icons.Default.Share, "Distributed to", item.distributedTo!!.uppercase(), Ok) }
            if (item.importedFrom != null) { Spacer(Modifier.height(8.dp)); MetaBadge(Icons.Default.FolderOpen, "Imported from", item.importedFrom!!, MaterialTheme.colorScheme.onSurfaceVariant) }
            if (item.error.isNotBlank()) { Spacer(Modifier.height(8.dp)); MetaBadge(Icons.Default.ErrorOutline, "Error", item.error, MaterialTheme.colorScheme.error, lines = 3) }

            // Tags (live preview of the field below)
            Spacer(Modifier.height(14.dp))
            SectionTitle(Icons.Default.LocalOffer, "Active search tags")
            Spacer(Modifier.height(8.dp))
            val tagList = tags.split(',').map { it.trim() }.filter { it.isNotEmpty() }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (tagList.isEmpty()) {
                    Box(Modifier.clip(CircleShape).border(1.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape).padding(horizontal = 10.dp, vertical = 5.dp)) {
                        Text("No tags defined", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                tagList.forEachIndexed { i, t ->
                    val tc = listOf(BrandYellow, BrandAmber, Color(0xFFFFD54F), Color(0xFFFF8A00), Color(0xFFE6B800))[i % 5]
                    Box(Modifier.clip(CircleShape).background(tc.copy(alpha = 0.14f)).border(1.dp, tc.copy(alpha = 0.6f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp)) {
                        Text("#$t", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                    }
                }
            }

            // ---------------- Publishing fields
            Spacer(Modifier.height(18.dp))
            SectionTitle(Icons.Default.Notes, "Publishing fields")
            Spacer(Modifier.height(10.dp))
            val shape = RoundedCornerShape(12.dp)
            OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(), label = { Text("Item title") }, placeholder = { Text("Title used in publishing") }, singleLine = true, shape = shape,
                leadingIcon = { Icon(Icons.Default.Title, null, Modifier.size(18.dp)) })
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(tags, { tags = it }, Modifier.fillMaxWidth(), label = { Text("Search tags") }, placeholder = { Text("cute, neon, cartoon") }, shape = shape,
                leadingIcon = { Icon(Icons.Default.LocalOffer, null, Modifier.size(18.dp)) }, supportingText = { Text("Comma separated") })
            Spacer(Modifier.height(4.dp))
            OutlinedTextField(category, { category = it }, Modifier.fillMaxWidth(), label = { Text("Main category") }, placeholder = { Text("CATEGORY") }, singleLine = true, shape = shape,
                leadingIcon = { Icon(Icons.Default.Folder, null, Modifier.size(18.dp)) }, supportingText = { Text("Saved in upper case") })
            Spacer(Modifier.height(4.dp))
            OutlinedTextField(description, { description = it }, Modifier.fillMaxWidth().height(110.dp), label = { Text("Publishing description") }, placeholder = { Text("Describe the media context...") }, shape = shape,
                leadingIcon = { Icon(Icons.Default.Notes, null, Modifier.size(18.dp)) })
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.Top) {
                OutlinedTextField(scheduled, { scheduled = it }, Modifier.weight(1f), label = { Text("Scheduled upload date") }, placeholder = { Text("YYYY-MM-DD") }, singleLine = true, shape = shape,
                    leadingIcon = { Icon(Icons.Default.PushPin, null, Modifier.size(18.dp)) },
                    supportingText = { Text("Pin to a specific day. Empty = automatic rotation.") })
                Spacer(Modifier.width(8.dp))
                FilledTonalIconButton(onClick = { showDate = true }, modifier = Modifier.padding(top = 4.dp).size(48.dp)) { Icon(Icons.Default.DateRange, "Pick date") }
            }

            // ---------------- Actions
            Spacer(Modifier.height(14.dp))
            Button(
                onClick = { vm.saveMetadata(item, title.trim(), tags.trim(), category.trim().uppercase(), description.trim(), scheduled.trim().ifBlank { null }); onDismiss() },
                modifier = Modifier.fillMaxWidth().height(50.dp), shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = BrandYellow, contentColor = BrandDark),
            ) { Icon(Icons.Default.Save, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); Text("Save changes", fontWeight = FontWeight.Bold) }
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (!item.isQueued) OutlinedButton(onClick = { vm.requeue(item) }, shape = RoundedCornerShape(12.dp), modifier = Modifier.weight(1f)) {
                    Icon(Icons.Default.Refresh, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Requeue", maxLines = 1)
                }
                OutlinedButton(onClick = { vm.copyToOtherAccounts(item) }, enabled = copyState == "idle", shape = RoundedCornerShape(12.dp), modifier = Modifier.weight(1.4f)) {
                    Icon(if (copyState == "done") Icons.Default.Done else Icons.Default.ContentCopy, null, Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(
                        when (copyState) {
                            "copying" -> "Copying..."
                            "done" -> "Copied to " + Accounts.distOrder.filter { it != active }.joinToString(" + ") { it.uppercase() }
                            "failed" -> "Copy failed - retry"
                            else -> "Copy to other accounts"
                        }, maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = { confirmDelete = true }, shape = RoundedCornerShape(12.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error), modifier = Modifier.weight(1f)) {
                    Icon(Icons.Default.DeleteOutline, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Delete")
                }
                TextButton(onClick = onDismiss, modifier = Modifier.weight(1f)) { Text("Close") }
            }
        }
    }

    if (showDate) DateKeyPicker(initialKey = scheduled.ifBlank { null }, onDismiss = { showDate = false }) { scheduled = it; showDate = false }

    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false },
        icon = { Icon(Icons.Default.DeleteOutline, null, tint = MaterialTheme.colorScheme.error) },
        title = { Text("Delete this file?") },
        text = { Text("\"${item.displayTitle}\" will be removed from the queue of ${Accounts.byKey(active).label}. This cannot be undone.") },
        confirmButton = { Button(onClick = { confirmDelete = false; vm.delete(item); onDismiss() }, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)) { Text("Delete") } },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
    )

    zoomUrl?.let { url -> ZoomDialog(url, current?.title ?: item.displayTitle) { zoomUrl = null } }
}

// ------------------------------------------------------------------------------------------------
// Pieces
// ------------------------------------------------------------------------------------------------
@Composable
private fun SectionTitle(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(15.dp), tint = BrandAmber)
        Spacer(Modifier.width(6.dp))
        Text(text.uppercase(), fontSize = 10.5.sp, lineHeight = 12.sp, letterSpacing = 1.sp, fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun RoundBtn(icon: ImageVector, onClick: () -> Unit) {
    Box(Modifier.size(32.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surface).border(1.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurface)
    }
}

/** Thin progress line that fills over one presentation interval. */
@Composable
private fun SlideProgress(key: Int, duration: Long, modifier: Modifier = Modifier) {
    var p by remember(key) { mutableFloatStateOf(0f) }
    LaunchedEffect(key, duration) {
        val start = System.currentTimeMillis()
        while (p < 1f) { delay(40); p = ((System.currentTimeMillis() - start).toFloat() / duration).coerceAtMost(1f) }
    }
    LinearProgressIndicator(progress = { p }, modifier = modifier.height(3.dp).clip(CircleShape), color = BrandAmber, trackColor = BrandAmber.copy(alpha = 0.2f))
}

@Composable
private fun MetaBadge(icon: ImageVector, label: String, value: String, accent: Color, modifier: Modifier = Modifier, lines: Int = 1) {
    Row(
        modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(accent.copy(alpha = 0.10f)).border(1.dp, accent.copy(alpha = 0.35f), RoundedCornerShape(12.dp)).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, Modifier.size(16.dp), tint = accent)
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Text(label.uppercase(), fontSize = 9.5.sp, lineHeight = 11.sp, letterSpacing = 0.8.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface, maxLines = lines, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Device-frame preview: status bar, notch style, wallpaper / video / ringtone disc, slot label, home indicator. */
@Composable
private fun PhoneMockup(item: QueueItem, url: String, slot: String?, frame: DeviceFrame, modifier: Modifier = Modifier, onTap: () -> Unit) {
    val c = typeColor(item.dayType)
    val outer = RoundedCornerShape((frame.screenCorner + 8).dp)
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.fillMaxWidth().clip(outer).background(Brush.linearGradient(listOf(Color(0xFF2A2517), Color(0xFF14110A))))
                .border(2.dp, Color(0xFF3A3426), outer)
                .padding(start = frame.bezelH.dp, end = frame.bezelH.dp, top = frame.bezelTop.dp, bottom = frame.bezelBottom.dp)
        ) {
            Box(Modifier.fillMaxWidth().aspectRatio(frame.ratio).clip(RoundedCornerShape(frame.screenCorner.dp)).background(c.copy(alpha = 0.55f)).clickable(onClick = onTap)) {
                // Screen content
                when {
                    item.isVideoType && item.fileUrl.isNotBlank() -> ScreenVideo(item.fileUrl)
                    item.isMp3 -> RingtoneScreen(item)
                    url.isNotBlank() -> AnimatedContent(url, transitionSpec = { fadeIn(tween(350)) togetherWith fadeOut(tween(350)) }, label = "shot") { u ->
                        AsyncImage(model = u, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    }
                    else -> Icon(typeIcon(item.dayType), null, Modifier.align(Alignment.Center).size(40.dp), tint = Color.White.copy(alpha = 0.7f))
                }
                // Status bar
                Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = if (frame.notch == Notch.ISLAND) 12.dp else 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(RealTime.dhakaNow().toLocalTime().toString().take(5), color = Color.White, fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.weight(1f))
                    Icon(Icons.Default.SignalCellular4Bar, null, Modifier.size(10.dp), tint = Color.White)
                    Spacer(Modifier.width(3.dp))
                    Icon(Icons.Default.Wifi, null, Modifier.size(11.dp), tint = Color.White)
                    Spacer(Modifier.width(3.dp))
                    Icon(Icons.Default.BatteryFull, null, Modifier.size(11.dp).rotate(90f), tint = Color.White)
                }
                // Notch
                when (frame.notch) {
                    Notch.ISLAND -> Box(Modifier.align(Alignment.TopCenter).padding(top = 9.dp).width(64.dp).height(18.dp).clip(CircleShape).background(Color(0xFF05040A)))
                    Notch.NOTCH -> Box(Modifier.align(Alignment.TopCenter).width(84.dp).height(22.dp).clip(RoundedCornerShape(bottomStart = 14.dp, bottomEnd = 14.dp)).background(Color(0xFF05040A)))
                    Notch.DOT -> Box(Modifier.align(Alignment.TopCenter).padding(top = 8.dp).size(12.dp).clip(CircleShape).background(Color(0xFF05040A)))
                    Notch.DOT_LEFT -> Box(Modifier.align(Alignment.TopStart).padding(top = 8.dp, start = 14.dp).size(12.dp).clip(CircleShape).background(Color(0xFF05040A)))
                    Notch.DROP -> Box(Modifier.align(Alignment.TopCenter).width(26.dp).height(18.dp).clip(RoundedCornerShape(bottomStart = 13.dp, bottomEnd = 13.dp)).background(Color(0xFF05040A)))
                    Notch.NONE -> {}
                }
                // Clock (lock-screen style) - not for ringtone
                if (!item.isMp3) Column(Modifier.align(Alignment.TopCenter).padding(top = if (frame.notch == Notch.NONE) 34.dp else 44.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(RealTime.dhakaNow().toLocalTime().toString().take(5), color = Color.White, fontSize = 30.sp, lineHeight = 32.sp, fontWeight = FontWeight.Light)
                    Text(RealTime.longKey(RealTime.key(RealTime.dhakaDate())), color = Color.White.copy(alpha = 0.85f), fontSize = 10.sp, lineHeight = 12.sp)
                }
                // Bottom label
                Row(Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)).padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (item.isSetType && slot != null) { Icon(slotIcon(slot), null, Modifier.size(11.dp), tint = Color.White); Spacer(Modifier.width(4.dp)) }
                    Text(if (item.isSetType && slot != null) slot.uppercase() else ContentTypes.dayUi(item.dayType).label.uppercase(), color = Color.White, fontSize = 9.sp, lineHeight = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp)
                }
                if (!item.isMp3 && !item.isVideoType && url.isNotBlank()) Icon(Icons.Default.Fullscreen, "Zoom", Modifier.align(Alignment.BottomEnd).padding(8.dp).size(16.dp), tint = Color.White.copy(alpha = 0.8f))
            }
            if (frame.homeButton) Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 5.dp).size(24.dp).clip(CircleShape).background(Color(0xFF14110A)).border(2.dp, Color(0xFF3F3828), CircleShape))
            else if (frame.notch != Notch.NONE || frame == DeviceFrame.AND_FLAT) Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 2.dp).width(56.dp).height(3.dp).clip(CircleShape).background(Color(0xFF4A4433)))
        }
    }
}

@Composable
private fun RingtoneScreen(item: QueueItem) {
    val spin = rememberInfiniteTransition(label = "disc")
    val angle by spin.animateFloat(0f, 360f, infiniteRepeatable(tween(7000, easing = LinearEasing), RepeatMode.Restart), label = "angle")
    Column(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF2A2517), Color(0xFF0E0C07)))), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Box(Modifier.size(78.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.fillMaxSize().rotate(angle).clip(CircleShape).background(Brush.sweepGradient(listOf(BrandYellow, Color(0xFFFF8A00), BrandAmber, BrandYellow))))
            Box(Modifier.size(30.dp).clip(CircleShape).background(Color(0xFF14110A)), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.MusicNote, null, Modifier.size(18.dp), tint = BrandYellow)
            }
        }
        Spacer(Modifier.height(10.dp))
        Text(item.name.ifBlank { "Audio Track" }, color = Color.White, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 14.dp))
        Text("Ringtone Preview", color = BrandYellow, fontSize = 9.sp, lineHeight = 11.sp, letterSpacing = 1.sp, fontWeight = FontWeight.Bold)
    }
}

/** Muted looping video inside the phone screen; tap toggles play/pause. */
@Composable
private fun ScreenVideo(url: String) {
    val ctx = LocalContext.current
    val exo = remember(url) { ExoPlayer.Builder(ctx).build().apply { setMediaItem(MediaItem.fromUri(url)); repeatMode = Player.REPEAT_MODE_ALL; volume = 0f; prepare(); playWhenReady = true } }
    var playing by remember { mutableStateOf(true) }
    DisposableEffect(exo) {
        val l = object : Player.Listener { override fun onIsPlayingChanged(isPlaying: Boolean) { playing = isPlaying } }
        exo.addListener(l)
        onDispose { exo.removeListener(l); exo.release() }
    }
    Box(Modifier.fillMaxSize().clickable { if (exo.isPlaying) exo.pause() else exo.play() }) {
        AndroidView(factory = { PlayerView(it).apply { player = exo; useController = false; resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM } }, modifier = Modifier.fillMaxSize())
        if (!playing) Box(Modifier.align(Alignment.Center).size(48.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.3f)), contentAlignment = Alignment.Center) { Icon(Icons.Default.PlayArrow, null, tint = Color.White) }
    }
}

/** Full-screen focus view with pinch zoom + zoom buttons (like the web focus dialog). */
@Composable
private fun ZoomDialog(url: String, title: String, onClose: () -> Unit) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            AsyncImage(
                model = url, contentDescription = title, contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize()
                    .pointerInput(Unit) {
                        detectTransformGestures { _, pan, zoom, _ ->
                            scale = (scale * zoom).coerceIn(1f, 6f)
                            offset = if (scale <= 1f) Offset.Zero else offset + pan
                        }
                    }
                    .graphicsLayer { scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y }
            )
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, color = Color.White, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                ZoomBtn(Icons.Default.ZoomOut) { scale = (scale - 0.5f).coerceAtLeast(1f); if (scale <= 1f) offset = Offset.Zero }
                Spacer(Modifier.width(6.dp))
                Box(Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.15f)).clickable { scale = 1f; offset = Offset.Zero }.padding(horizontal = 10.dp, vertical = 7.dp)) {
                    Text("${(scale * 100).toInt()}%", color = Color.White, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.width(6.dp))
                ZoomBtn(Icons.Default.ZoomIn) { scale = (scale + 0.5f).coerceAtMost(6f) }
                Spacer(Modifier.width(6.dp))
                ZoomBtn(Icons.Default.Close, onClose)
            }
        }
    }
}

@Composable
private fun ZoomBtn(icon: ImageVector, onClick: () -> Unit) {
    Box(Modifier.size(34.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.15f)).clickable(onClick = onClick), contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(18.dp), tint = Color.White) }
}

@Composable
fun AudioPlayer(url: String) {
    val ctx = LocalContext.current
    val player = remember(url) { ExoPlayer.Builder(ctx).build().apply { setMediaItem(MediaItem.fromUri(url)); prepare() } }
    var playing by remember { mutableStateOf(false) }
    var pos by remember { mutableFloatStateOf(0f) }
    DisposableEffect(player) {
        val l = object : Player.Listener { override fun onIsPlayingChanged(isPlaying: Boolean) { playing = isPlaying } }
        player.addListener(l)
        onDispose { player.removeListener(l); player.release() }
    }
    LaunchedEffect(playing) { while (playing) { delay(200); val d = player.duration; pos = if (d > 0) player.currentPosition.toFloat() / d else 0f } }
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.surface).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(Brush.linearGradient(listOf(BrandYellow, BrandAmber))).clickable { if (playing) player.pause() else player.play() }, contentAlignment = Alignment.Center) {
            Icon(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, null, tint = BrandDark)
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(if (playing) "Playing ringtone preview" else "Play ringtone preview", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            LinearProgressIndicator(progress = { pos }, modifier = Modifier.fillMaxWidth().height(3.dp).clip(CircleShape), color = BrandAmber, trackColor = BrandAmber.copy(alpha = 0.2f))
        }
    }
}
