package com.zedge.contentstudio.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.core.UploadErrors
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.ui.MainViewModel

/**
 * "Failed uploads" section. Lists every queue row with status failed / error together with
 * the bot's error message, a human-readable hint, the failure time, and Requeue / Delete actions.
 * Used on the Dashboard (only when something failed) and on the Upload page (always).
 */
@Composable
fun FailedUploadsSection(
    vm: MainViewModel,
    failed: List<QueueItem>,
    accountLabel: String,
    hideWhenEmpty: Boolean = false,
    modifier: Modifier = Modifier,
) {
    if (failed.isEmpty() && hideWhenEmpty) return
    val danger = MaterialTheme.colorScheme.error
    val sorted = remember(failed) { failed.sortedWith(compareByDescending<QueueItem> { it.failedAt }.thenByDescending { it.id }) }

    SectionCard(
        title = "Failed uploads",
        subtitle = if (failed.isEmpty()) "No failed uploads in $accountLabel" else "${failed.size} item(s) failed in $accountLabel · tap a row for details",
        modifier = modifier,
        trailing = {
            Box(Modifier.clip(RoundedCornerShape(99.dp)).background(danger.copy(alpha = 0.14f)).padding(horizontal = 10.dp, vertical = 4.dp)) {
                Text(failed.size.toString(), color = danger, fontWeight = FontWeight.Bold, fontSize = 12.sp)
            }
        },
    ) {
        if (failed.isEmpty()) {
            EmptyState("Everything is healthy. Failed uploads will appear here with the reason.")
            return@SectionCard
        }

        // Bulk actions
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = { vm.requeueAllFailed() },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp),
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            ) { Icon(Icons.Default.Refresh, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Requeue all") }
            OutlinedButton(
                onClick = { vm.deleteAllFailed() },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = danger),
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            ) { Icon(Icons.Default.DeleteOutline, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Delete all") }
        }
        Spacer(Modifier.height(12.dp))

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            sorted.forEach { item -> FailedRow(item, onOpen = { vm.selectedItem.value = item }, onRequeue = { vm.requeue(item) }, onDelete = { vm.delete(item) }) }
        }
    }
}

@Composable
private fun FailedRow(item: QueueItem, onOpen: () -> Unit, onRequeue: () -> Unit, onDelete: () -> Unit) {
    val danger = MaterialTheme.colorScheme.error
    var expanded by remember(item.id) { mutableStateOf(false) }
    val hint = remember(item.error) { UploadErrors.explain(item.error) }

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(danger.copy(alpha = 0.05f))
            .border(1.dp, danger.copy(alpha = 0.25f), RoundedCornerShape(14.dp))
            .padding(10.dp)
    ) {
        Row(Modifier.fillMaxWidth().clickable(onClick = onOpen), verticalAlignment = Alignment.CenterVertically) {
            ItemThumb(item, Modifier.width(44.dp), ratio = 3f / 4f, corner = 10)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(item.displayTitle, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    TypeBadge(item.dayType)
                    StatusPill("FAILED", danger)
                    if (item.failedAt > 0) {
                        Icon(Icons.Default.Schedule, null, Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(RealTime.stampOf(item.failedAt), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }

        // Human hint
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.Top) {
            Icon(Icons.Default.Lightbulb, null, Modifier.size(14.dp).padding(top = 1.dp), tint = danger)
            Spacer(Modifier.width(6.dp))
            Text(hint, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = danger)
        }

        // Raw error from the bot
        if (item.error.isNotBlank()) {
            Spacer(Modifier.height(6.dp))
            Box(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surface).border(1.dp, danger.copy(alpha = 0.18f), RoundedCornerShape(10.dp)).padding(8.dp)
            ) {
                Text(
                    item.error,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 10.5.sp,
                    lineHeight = 14.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = if (expanded) Int.MAX_VALUE else 3,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (item.error.length > 120 || item.error.count { it == '\n' } > 2) {
                TextButton(onClick = { expanded = !expanded }, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)) {
                    Text(if (expanded) "Hide full error" else "Show full error", style = MaterialTheme.typography.labelSmall)
                }
            }
        }

        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = onRequeue, modifier = Modifier.weight(1f), shape = RoundedCornerShape(12.dp), contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp)) {
                Icon(Icons.Default.Refresh, null, Modifier.size(15.dp)); Spacer(Modifier.width(5.dp)); Text("Requeue")
            }
            OutlinedButton(onClick = onOpen, modifier = Modifier.weight(1f), shape = RoundedCornerShape(12.dp), contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp)) {
                Icon(Icons.Default.Warning, null, Modifier.size(15.dp)); Spacer(Modifier.width(5.dp)); Text("Details")
            }
            OutlinedButton(onClick = onDelete, modifier = Modifier.weight(1f), shape = RoundedCornerShape(12.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = danger), contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp)) {
                Icon(Icons.Default.DeleteOutline, null, Modifier.size(15.dp)); Spacer(Modifier.width(5.dp)); Text("Delete")
            }
        }
    }
}
