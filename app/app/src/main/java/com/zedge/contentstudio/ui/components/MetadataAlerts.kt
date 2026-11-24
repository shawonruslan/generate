package com.zedge.contentstudio.ui.components

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Label
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Warn

/**
 * v23 metadata guard - lists queued files that have no title / tags / category.
 * The upload bot skips these, so they must be fixed (tap -> detail sheet -> Publishing fields).
 * Also shows the bot's last report for the other accounts (dashboardSettings/metadataAlerts).
 */
@Composable
fun MetadataAlertSection(vm: MainViewModel, blocked: List<QueueItem>, activeKey: String, modifier: Modifier = Modifier) {
    val others = vm.metaAlerts.collectAsState().value.filter { (k, a) -> k != activeKey && (a?.count ?: 0) > 0 }
    if (blocked.isEmpty() && others.isEmpty()) return
    val cs = MaterialTheme.colorScheme
    var showAll by remember { mutableStateOf(false) }
    val label = Accounts.byKey(activeKey).label

    SectionCard(
        title = "Metadata missing",
        subtitle = if (blocked.isEmpty()) "All queued files in $label have metadata" else "${blocked.size} queued file(s) in $label will be SKIPPED by the bot until title, tags and category are set",
        modifier = modifier,
        trailing = {
            Box(Modifier.clip(RoundedCornerShape(99.dp)).background(BrandYellow).padding(horizontal = 10.dp, vertical = 4.dp)) {
                Text(blocked.size.toString(), color = BrandDark, fontWeight = FontWeight.Bold, fontSize = 12.sp)
            }
        },
    ) {
        val shown = if (showAll) blocked else blocked.take(5)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            shown.forEach { item ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                        .background(Warn.copy(alpha = 0.07f)).border(1.dp, Warn.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
                        .clickable { vm.selectedItem.value = item }.padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    ItemThumb(item, Modifier.width(40.dp), ratio = 3f / 4f, corner = 8)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(item.title.ifBlank { item.name.ifBlank { item.id } }, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = cs.onSurface)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Label, null, Modifier.size(12.dp), tint = Warn)
                            Spacer(Modifier.width(4.dp))
                            Text("missing: " + item.missingMetaFields.joinToString(", "), fontSize = 11.sp, color = Warn, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    Icon(Icons.Default.Edit, "Fix", Modifier.size(18.dp), tint = cs.onSurfaceVariant)
                }
            }
        }
        if (blocked.size > 5) {
            TextButton(onClick = { showAll = !showAll }) { Text(if (showAll) "Show less" else "Show all ${blocked.size}", fontSize = 12.sp) }
        }
        if (others.isNotEmpty()) {
            Spacer(Modifier.height(6.dp))
            Text(
                "Other accounts (bot report): " + others.entries.joinToString("  \u00b7  ") { (k, a) -> "${Accounts.byKey(k).label}: ${a?.count ?: 0}" },
                fontSize = 11.sp, lineHeight = 14.sp, color = cs.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(4.dp))
        Text("Tip: run generator.yml (mode: metadata) or edit the Publishing fields in the app / panel.", fontSize = 10.sp, lineHeight = 13.sp, color = cs.onSurfaceVariant)
    }
}

/** Small amber "No metadata" pill for queue rows / detail sheet. */
@Composable
fun NoMetaPill(item: QueueItem, modifier: Modifier = Modifier) {
    if (!item.isBlockedNoMeta) return
    StatusPill("No metadata", Warn, modifier)
}
