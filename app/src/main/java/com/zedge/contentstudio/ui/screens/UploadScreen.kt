package com.zedge.contentstudio.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Collections
import androidx.compose.material.icons.filled.FolderZip
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.zedge.contentstudio.ChipRow
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.Fmt
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.components.EmptyState
import com.zedge.contentstudio.ui.components.QueueCard
import com.zedge.contentstudio.ui.components.SectionCard
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.typeColor

private val ALL_MEDIA_MIMES = arrayOf(
    "image/*", "audio/mpeg", "video/*",
    "application/zip", "application/x-zip-compressed",
    "application/vnd.rar", "application/x-rar-compressed", "application/octet-stream",
)
private val ARCHIVE_MIMES = arrayOf(
    "application/zip", "application/x-zip-compressed",
    "application/vnd.rar", "application/x-rar-compressed", "application/octet-stream",
)

/**
 * Tappable "drop zone" card used by the Upload Center and Multi-Account Distribution screens.
 * On Android there is no drag & drop from the file manager, so tapping opens the system picker.
 */
@Composable
fun DropZone(
    icon: @Composable () -> Unit,
    title: String,
    hint: String,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(16.dp)
    val alpha = if (enabled) 1f else 0.5f
    Box(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f))
            .border(1.5.dp, MaterialTheme.colorScheme.outlineVariant, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 22.dp, horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            icon()
            Spacer(Modifier.height(10.dp))
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = alpha),
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                hint,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = alpha),
                textAlign = TextAlign.Center,
            )
            if (!enabled) {
                Spacer(Modifier.height(6.dp))
                Text("Busy - another job is running", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

/** Upload Center: plain files, wallpaper sets, videos (Live / Charging) and smart ZIP/RAR import. */
@Composable
fun UploadScreen(vm: MainViewModel) {
    val busy by vm.busy.collectAsStateWithLifecycle()
    val status by vm.statusText.collectAsStateWithLifecycle()
    val activeKey by vm.activeKey.collectAsStateWithLifecycle()
    val items by vm.items.collectAsStateWithLifecycle()
    val draft by vm.videoDraft.collectAsStateWithLifecycle()
    val shared by vm.sharedUris.collectAsStateWithLifecycle()

    var setType by rememberSaveable { mutableStateOf("WALLPAPER_24H") }
    var videoType by rememberSaveable { mutableStateOf("LIVE_WALLPAPER") }
    val slotUris = remember { mutableStateMapOf<String, Uri>() }
    var pendingSlot by remember { mutableStateOf<String?>(null) }

    // Files shared from another app ("Import to Content Studio") land here.
    LaunchedEffect(shared) {
        if (shared.isNotEmpty()) {
            val uris = vm.consumeSharedUris()
            if (uris.isNotEmpty()) vm.uploadToQueue(uris)
        }
    }

    val pickMany = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) vm.uploadToQueue(uris)
    }
    val pickArchives = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) vm.importArchives(uris)
    }
    val pickSlot = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val slot = pendingSlot
        if (uri != null && slot != null) slotUris[slot] = uri
        pendingSlot = null
    }
    val pickVideo = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) vm.prepareVideo(videoType, uri)
    }

    val account = Accounts.byKey(activeKey).label
    val queued = items.filter { it.isQueued }

    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // ------------------------------------------------------------ 1. plain upload
        item {
            SectionCard(
                "Upload to $account",
                "Images become wallpapers, MP3 becomes ringtones, ZIP / RAR archives are smart-imported. Videos use the card below.",
            ) {
                DropZone(
                    icon = { Icon(Icons.Default.CloudUpload, null, Modifier.size(36.dp), tint = typeColor("WALLPAPER")) },
                    title = "Choose files",
                    hint = "JPG, PNG, WEBP, MP3, ZIP, RAR - multiple allowed",
                    enabled = !busy,
                ) { pickMany.launch(ALL_MEDIA_MIMES) }
                if (status.isNotBlank()) {
                    Spacer(Modifier.height(10.dp))
                    Text(
                        status,
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (status.startsWith("Error")) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }

        // ------------------------------------------------------------ 2. wallpaper sets
        item {
            val meta = ContentTypes.SET_TYPES.getValue(setType)
            SectionCard(
                "Wallpaper set",
                "Pick one image per slot. ${meta.label} needs ${meta.slots.size} images.",
            ) {
                ChipRow(ContentTypes.SET_TYPES.values.map { it.type to it.short }, setType) { t ->
                    if (t != setType) { setType = t; slotUris.clear() }
                }
                Spacer(Modifier.height(12.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(meta.slots) { slot ->
                        val uri = slotUris[slot]
                        val c = typeColor(setType)
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(
                                Modifier
                                    .width(84.dp)
                                    .aspectRatio(9f / 16f)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(c.copy(alpha = 0.12f))
                                    .border(1.dp, if (uri != null) c else MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(12.dp))
                                    .clickable(enabled = !busy) { pendingSlot = slot; pickSlot.launch(arrayOf("image/*")) },
                                contentAlignment = Alignment.Center,
                            ) {
                                if (uri != null) {
                                    AsyncImage(model = uri, contentDescription = slot, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                                } else {
                                    Icon(Icons.Default.Add, null, tint = c, modifier = Modifier.size(28.dp))
                                }
                            }
                            Spacer(Modifier.height(4.dp))
                            Text(slot.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { vm.submitSet(setType, slotUris.toMap()) },
                        enabled = !busy && slotUris.size == meta.slots.size,
                    ) {
                        Icon(Icons.Default.Collections, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Upload ${meta.short} set (${slotUris.size}/${meta.slots.size})")
                    }
                    OutlinedButton(onClick = { slotUris.clear() }, enabled = slotUris.isNotEmpty()) { Text("Clear") }
                }
            }
        }

        // ------------------------------------------------------------ 3. videos
        item {
            val meta = ContentTypes.VIDEO_TYPES.getValue(videoType)
            SectionCard(
                "Live Wallpaper / Charging Animation",
                "MP4 or MOV up to 50 MB. Five frames are captured - tap the one you want as the cover.",
            ) {
                ChipRow(ContentTypes.VIDEO_TYPES.values.map { it.type to it.label }, videoType) { t ->
                    if (t != videoType) { videoType = t; if (draft != null) vm.cancelVideoDraft() }
                }
                Spacer(Modifier.height(12.dp))
                val d = draft
                if (d == null) {
                    DropZone(
                        icon = { Icon(Icons.Default.Movie, null, Modifier.size(36.dp), tint = typeColor(videoType)) },
                        title = "Choose a video",
                        hint = "${meta.label} - MP4 / MOV, max 50 MB",
                        enabled = !busy,
                    ) { pickVideo.launch(arrayOf("video/mp4", "video/quicktime", "video/*")) }
                } else {
                    Text(
                        "${d.file.name}  (${Fmt.bytes(d.file.size)})",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(10.dp))
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        itemsIndexed(d.frames) { i, frame ->
                            val selected = i == d.selected
                            Box(
                                Modifier
                                    .width(84.dp)
                                    .aspectRatio(9f / 16f)
                                    .clip(RoundedCornerShape(12.dp))
                                    .border(if (selected) 3.dp else 1.dp, if (selected) BrandYellow else MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(12.dp))
                                    .clickable { vm.selectFrame(i) },
                            ) {
                                Image(
                                    bitmap = frame.bitmap.asImageBitmap(),
                                    contentDescription = "Frame ${i + 1}",
                                    modifier = Modifier.fillMaxSize(),
                                    contentScale = ContentScale.Crop,
                                )
                                if (selected) {
                                    Box(
                                        Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(BrandYellow).padding(vertical = 2.dp),
                                        contentAlignment = Alignment.Center,
                                    ) { Text("COVER", style = MaterialTheme.typography.labelSmall, color = BrandDark, fontWeight = FontWeight.Bold) }
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { vm.submitVideoDraft() }, enabled = !busy) { Text("Upload ${meta.label}") }
                        OutlinedButton(onClick = { vm.cancelVideoDraft() }, enabled = !busy) { Text("Cancel") }
                    }
                }
            }
        }

        // ------------------------------------------------------------ 4. smart archive import
        item {
            SectionCard(
                "Smart ZIP / RAR import",
                "Folders with 2 / 4 / 6 images become DUAL / 24H / BATTERY sets automatically. Loose images, MP3s and videos are imported as single items.",
            ) {
                DropZone(
                    icon = { Icon(Icons.Default.FolderZip, null, Modifier.size(36.dp), tint = typeColor("WALLPAPER_24H")) },
                    title = "Choose archives",
                    hint = ".zip or .rar - multiple allowed",
                    enabled = !busy,
                ) { pickArchives.launch(ARCHIVE_MIMES) }
            }
        }

        // ------------------------------------------------------------ 5. queue preview
        item {
            SectionCard("Queued in $account", "${queued.size} item(s) waiting - tap a card for details") {
                if (queued.isEmpty()) {
                    EmptyState("Nothing queued yet. Upload something above.")
                } else {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(queued.sortedByDescending { it.createdAt }.take(12), key = { it.id }) { item ->
                            QueueCard(item, onClick = { vm.selectedItem.value = item }, modifier = Modifier.width(132.dp))
                        }
                    }
                }
            }
        }

        item { Spacer(Modifier.height(72.dp)) }
    }
}
