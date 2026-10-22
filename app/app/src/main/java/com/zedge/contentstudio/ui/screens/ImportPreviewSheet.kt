package com.zedge.contentstudio.ui.screens

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.FolderZip
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.Fmt
import com.zedge.contentstudio.domain.ArchiveEntry
import com.zedge.contentstudio.domain.ImportUnit
import com.zedge.contentstudio.ui.ImportPreview
import com.zedge.contentstudio.ui.components.TypePill
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn
import com.zedge.contentstudio.ui.theme.typeColor

/**
 * Visual confirmation for Smart ZIP / RAR import (mirrors the web app's smart import summary,
 * but with real thumbnails): what was auto-detected, how the sets were built, and where it goes.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ImportPreviewSheet(preview: ImportPreview) {
    val plan = preview.plan
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val sets = plan.setUnits
    val files = plan.units.filterIsInstance<ImportUnit.File>()
    val images = files.filter { it.media == "image" }
    val audios = files.filter { it.media == "audio" }
    val videos = files.filter { it.media == "video" }
    val target = if (preview.distribute) Accounts.distOrder.joinToString(" → ") { it.uppercase() } else preview.targetLabel

    ModalBottomSheet(onDismissRequest = { preview.cancel() }, sheetState = sheet, containerColor = MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 24.dp)) {
            // header
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(BrandYellow), contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.FolderZip, null, Modifier.size(22.dp), tint = BrandDark)
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("Smart import detected", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("${plan.units.size} item(s) from ${preview.archiveNames.size} archive(s)", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(14.dp))

            // detection summary chips
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val perType = sets.groupBy { it.type }
                perType.forEach { (t, list) -> CountChip("${list.size} × ${list.first().meta.label}", typeColor(t)) }
                if (images.isNotEmpty()) CountChip("${images.size} wallpaper(s)", typeColor("WALLPAPER"))
                if (audios.isNotEmpty()) CountChip("${audios.size} ringtone(s)", typeColor("RINGTONE"))
                if (videos.isNotEmpty()) CountChip("${videos.size} video(s)", typeColor("LIVE_WALLPAPER"))
            }
            Spacer(Modifier.height(12.dp))

            // rule reminder
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh).padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Info, null, Modifier.size(16.dp), tint = BrandYellow)
                Spacer(Modifier.width(8.dp))
                Text("Folder with 2 images → Dual set · 4 → 24H set · 6 → Battery set. Slot picked from file names (morning / lock / low …) or file order. Other images → single wallpapers, MP3 → ringtone, MP4/MOV → video.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            // detected units
            LazyColumn(Modifier.heightIn(max = 380.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp), contentPadding = PaddingValues(bottom = 4.dp)) {
                items(sets, key = { it.hashCode() }) { s ->
                    Column(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainer)
                            .border(1.dp, typeColor(s.type).copy(alpha = 0.35f), RoundedCornerShape(14.dp))
                            .padding(10.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TypePill(s.type)
                            Spacer(Modifier.width(8.dp))
                            Text(s.label.ifBlank { s.archive }, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                            Text(if (s.byName) "by name" else "file order", style = MaterialTheme.typography.labelSmall, color = if (s.byName) Ok else Warn)
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            s.meta.slots.forEach { slot ->
                                val e = s.files[slot]
                                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                                    EntryThumb(e, Modifier.fillMaxWidth().aspectRatio(0.62f).clip(RoundedCornerShape(8.dp)))
                                    Spacer(Modifier.height(3.dp))
                                    Text(slot.uppercase(), fontSize = 8.5.sp, lineHeight = 10.sp, letterSpacing = 0.6.sp, fontWeight = FontWeight.Bold, color = typeColor(s.type), maxLines = 1)
                                    Text(e?.base ?: "-", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                            }
                        }
                    }
                }
                if (images.isNotEmpty()) item {
                    UnitGroup("Single wallpapers", typeColor("WALLPAPER")) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            images.take(6).forEach { EntryThumb(it.entry, Modifier.width(44.dp).height(70.dp).clip(RoundedCornerShape(8.dp))) }
                            if (images.size > 6) Box(Modifier.width(44.dp).height(70.dp).clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceContainerHighest), contentAlignment = Alignment.Center) {
                                Text("+${images.size - 6}", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
                if (audios.isNotEmpty()) item {
                    UnitGroup("Ringtones", typeColor("RINGTONE")) {
                        audios.take(5).forEach { FileLine(Icons.Default.MusicNote, it.entry, typeColor("RINGTONE")) }
                        if (audios.size > 5) Text("…and ${audios.size - 5} more", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (videos.isNotEmpty()) item {
                    UnitGroup("Videos", typeColor("LIVE_WALLPAPER")) {
                        videos.take(5).forEach { FileLine(Icons.Default.Videocam, it.entry, typeColor("LIVE_WALLPAPER")) }
                        if (videos.size > 5) Text("…and ${videos.size - 5} more", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (plan.notes.isNotEmpty() || plan.problems.isNotEmpty()) item {
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Warn.copy(alpha = 0.12f)).padding(10.dp)) {
                        plan.notes.forEach { n ->
                            Row(verticalAlignment = Alignment.Top) { Icon(Icons.Default.Info, null, Modifier.size(14.dp), tint = Warn); Spacer(Modifier.width(6.dp)); Text(n, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface) }
                        }
                        plan.problems.forEach { n ->
                            Row(verticalAlignment = Alignment.Top) { Icon(Icons.Default.Warning, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.error); Spacer(Modifier.width(6.dp)); Text(n, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error) }
                        }
                    }
                }
            }

            Spacer(Modifier.height(14.dp))
            // destination
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.CheckCircle, null, Modifier.size(16.dp), tint = Ok)
                Spacer(Modifier.width(6.dp))
                Text(
                    if (preview.distribute) "Round-robin: one set / file per account → $target" else "Everything goes to $target",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = { preview.confirm() },
                modifier = Modifier.fillMaxWidth().height(50.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = BrandYellow, contentColor = BrandDark),
            ) {
                Icon(Icons.Default.CloudUpload, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp))
                Text(if (preview.distribute) "Distribute ${plan.units.size} item(s)" else "Upload ${plan.units.size} item(s)", fontWeight = FontWeight.Bold)
            }
            TextButton(onClick = { preview.cancel() }, modifier = Modifier.fillMaxWidth()) { Text("Cancel") }
        }
    }
}

@Composable
private fun CountChip(text: String, color: Color) {
    Box(Modifier.clip(CircleShape).background(color.copy(alpha = 0.16f)).border(1.dp, color.copy(alpha = 0.45f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp)) {
        Text(text, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = color)
    }
}

@Composable
private fun UnitGroup(title: String, color: Color, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.surfaceContainer).border(1.dp, color.copy(alpha = 0.35f), RoundedCornerShape(14.dp)).padding(10.dp)) {
        Text(title.uppercase(), fontSize = 9.5.sp, lineHeight = 11.sp, letterSpacing = 1.sp, fontWeight = FontWeight.Bold, color = color)
        Spacer(Modifier.height(8.dp))
        content()
    }
}

@Composable
private fun FileLine(icon: androidx.compose.ui.graphics.vector.ImageVector, e: ArchiveEntry, color: Color) {
    Row(Modifier.padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(16.dp), tint = color)
        Spacer(Modifier.width(8.dp))
        Text(e.base, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Text(Fmt.bytes(e.size), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Small in-memory thumbnail decoded from the archive bytes (downsampled so big images stay cheap). */
@Composable
private fun EntryThumb(e: ArchiveEntry?, modifier: Modifier) {
    val bmp = remember(e) {
        if (e == null) null else try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(e.bytes, 0, e.bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / sample > 240 || bounds.outHeight / sample > 240) sample *= 2
            BitmapFactory.decodeByteArray(e.bytes, 0, e.bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
        } catch (_: Throwable) { null }
    }
    Box(modifier.background(MaterialTheme.colorScheme.surfaceContainerHighest), contentAlignment = Alignment.Center) {
        if (bmp != null) Image(bmp.asImageBitmap(), null, Modifier.matchParentSize(), contentScale = ContentScale.Crop)
        else Icon(Icons.Default.Warning, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
