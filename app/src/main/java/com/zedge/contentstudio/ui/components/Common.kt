package com.zedge.contentstudio.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.ui.DialogRequest
import com.zedge.contentstudio.ui.JobProgress
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.typeColor

/** Section card with an optional title row. */
@Composable
fun SectionCard(
    title: String? = null,
    subtitle: String? = null,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 14.dp)) {
            if (title != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (subtitle != null) {
                            Spacer(Modifier.height(2.dp))
                            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 3, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    if (trailing != null) {
                        Spacer(Modifier.width(8.dp))
                        trailing()
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
            content()
        }
    }
}

/** KPI tile. Designed for 2 per row: big number on top, full label (never truncated) below. */
@Composable
fun StatTile(label: String, value: String, modifier: Modifier = Modifier, accent: Color = MaterialTheme.colorScheme.primary, hint: String? = null) {
    Card(
        modifier = modifier,
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).clip(CircleShape).background(accent))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(value, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (hint != null) Text(hint, style = MaterialTheme.typography.labelSmall, color = accent, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** Colored content-type pill ("24H", "DUAL", "AUDIO" ...). */
@Composable
fun TypeBadge(type: String?, modifier: Modifier = Modifier, long: Boolean = false) {
    val ui = ContentTypes.dayUi(if (type == "RINGTONE") "AUDIO" else type)
    val c = typeColor(ui.type)
    Box(
        modifier
            .clip(CircleShape)
            .background(c.copy(alpha = 0.16f))
            .border(1.dp, c.copy(alpha = 0.45f), CircleShape)
            .padding(horizontal = 8.dp, vertical = 3.dp)
    ) {
        Text(if (long) ui.label else ui.short, color = c, fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.4.sp, maxLines = 1)
    }
}

@Composable
fun StatusPill(text: String, color: Color, modifier: Modifier = Modifier) {
    Box(modifier.clip(CircleShape).background(color.copy(alpha = 0.16f)).padding(horizontal = 8.dp, vertical = 3.dp)) {
        Text(text, color = color, fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1)
    }
}

/** Portrait thumbnail with type-aware fallback (music icon for ringtones, play icon for videos). */
@Composable
fun ItemThumb(item: QueueItem, modifier: Modifier = Modifier, ratio: Float = 9f / 16f, corner: Int = 12) {
    val c = typeColor(item.dayType)
    Box(modifier.aspectRatio(ratio).clip(RoundedCornerShape(corner.dp)).background(Brush.verticalGradient(listOf(c.copy(alpha = 0.35f), c.copy(alpha = 0.75f))))) {
        val url = item.previewUrl
        if (url.isNotBlank()) {
            AsyncImage(model = url, contentDescription = item.displayTitle, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
        if (item.isMp3) Icon(Icons.Default.MusicNote, null, tint = Color.White, modifier = Modifier.align(Alignment.Center).size(28.dp))
        if (item.isVideoType) Icon(Icons.Default.PlayCircle, null, tint = Color.White.copy(alpha = 0.9f), modifier = Modifier.align(Alignment.Center).size(28.dp))
        if (item.isPinned) {
            Box(Modifier.align(Alignment.TopEnd).padding(5.dp).clip(CircleShape).background(BrandYellow).padding(3.dp)) {
                Icon(Icons.Default.PushPin, null, tint = BrandDark, modifier = Modifier.size(11.dp))
            }
        }
        if (item.isSetType) {
            Box(Modifier.align(Alignment.BottomStart).padding(5.dp).clip(RoundedCornerShape(6.dp)).background(Color.Black.copy(alpha = 0.55f)).padding(horizontal = 6.dp, vertical = 2.dp)) {
                Text("${item.slots.size} img", color = Color.White, fontSize = 9.sp, lineHeight = 11.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** Compact queue card (grid). */
@Composable
fun QueueCard(item: QueueItem, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier.clickable(onClick = onClick),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(8.dp)) {
            ItemThumb(item, Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            Text(item.displayTitle, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                TypeBadge(item.dayType)
                val st = item.status
                StatusPill(st.uppercase(), when (st) { "queued" -> MaterialTheme.colorScheme.primary; "uploaded", "done" -> Ok; "error", "failed" -> MaterialTheme.colorScheme.error; else -> MaterialTheme.colorScheme.onSurfaceVariant })
            }
        }
    }
}

/** Horizontal list row for a queue item: thumb + 2-line title + badges. Used by Home & Pins. */
@Composable
fun QueueRow(item: QueueItem, subtitle: String? = null, onClick: () -> Unit, modifier: Modifier = Modifier, trailing: (@Composable () -> Unit)? = null) {
    Row(
        modifier.fillMaxWidth().clip(MaterialTheme.shapes.medium).clickable(onClick = onClick).padding(horizontal = 4.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ItemThumb(item, Modifier.width(44.dp), ratio = 3f / 4f, corner = 10)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(item.displayTitle, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                TypeBadge(item.dayType)
                if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (trailing != null) {
            Spacer(Modifier.width(8.dp))
            trailing()
        }
    }
}

/** Renders a DialogRequest (confirm or alert). */
@Composable
fun RequestDialog(req: DialogRequest?) {
    if (req == null) return
    AlertDialog(
        onDismissRequest = { req.cancel() },
        title = { Text(req.title) },
        text = { Text(req.message, style = MaterialTheme.typography.bodyMedium) },
        confirmButton = {
            if (req.destructive) TextButton(onClick = { req.confirm() }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(req.confirmLabel) }
            else TextButton(onClick = { req.confirm() }) { Text(req.confirmLabel) }
        },
        dismissButton = if (req.cancelLabel != null) ({ TextButton(onClick = { req.cancel() }) { Text(req.cancelLabel) } }) else null,
    )
}

/** Floating progress card shown while an upload / import job runs. */
@Composable
fun ProgressCard(p: JobProgress?, modifier: Modifier = Modifier) {
    if (p == null) return
    Card(modifier = modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium, colors = CardDefaults.cardColors(containerColor = BrandYellow)) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.5.dp, color = BrandDark)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(p.title, style = MaterialTheme.typography.titleSmall, color = BrandDark)
                Text(p.detail, style = MaterialTheme.typography.bodySmall, color = BrandDark.copy(alpha = 0.8f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(6.dp))
                val f = p.fraction
                if (f != null) LinearProgressIndicator(progress = { f }, modifier = Modifier.fillMaxWidth(), color = BrandDark, trackColor = BrandDark.copy(alpha = 0.2f))
                else LinearProgressIndicator(modifier = Modifier.fillMaxWidth(), color = BrandDark, trackColor = BrandDark.copy(alpha = 0.2f))
            }
        }
    }
}

@Composable
fun EmptyState(text: String, modifier: Modifier = Modifier) {
    Box(
        modifier.fillMaxWidth().clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)).padding(20.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

@Composable
fun PagerBar(page: Int, pages: Int, onPrev: () -> Unit, onNext: () -> Unit, label: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        FilledTonalIconButton(onClick = onPrev, enabled = page > 0, modifier = Modifier.size(36.dp)) { Icon(Icons.Default.ChevronLeft, "Previous") }
        Text(label, Modifier.weight(1f), textAlign = TextAlign.Center, style = MaterialTheme.typography.labelLarge)
        FilledTonalIconButton(onClick = onNext, enabled = page < pages - 1, modifier = Modifier.size(36.dp)) { Icon(Icons.Default.ChevronRight, "Next") }
    }
}
