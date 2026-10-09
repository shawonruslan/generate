package com.zedge.contentstudio.ui.screens

import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material.icons.filled.ErrorOutline
import com.zedge.contentstudio.ui.components.typeIcon
import com.zedge.contentstudio.ui.components.DhakaClock
import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.Page
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.components.EmptyState
import com.zedge.contentstudio.ui.components.FailedUploadsSection
import com.zedge.contentstudio.ui.components.MetadataAlertSection
import com.zedge.contentstudio.ui.components.QueueRow
import com.zedge.contentstudio.ui.components.SectionCard
import com.zedge.contentstudio.ui.components.StatTile
import com.zedge.contentstudio.ui.components.TypeBadge
import com.zedge.contentstudio.ui.theme.BrandAmber
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn
import com.zedge.contentstudio.ui.theme.typeColor
import com.zedge.contentstudio.ui.theme.BrandHeader
import com.zedge.contentstudio.ui.theme.BrandHeaderEnd
import com.zedge.contentstudio.ui.theme.BrandOnHeader
import com.zedge.contentstudio.ui.theme.BrandBadge
import com.zedge.contentstudio.ui.theme.BrandOnBadge

@Composable
fun HomeScreen(vm: MainViewModel, onOpenPage: (Page) -> Unit) {
    val queueItems by vm.items.collectAsStateWithLifecycle()
    val plan by vm.plan.collectAsStateWithLifecycle()
    val uploadHealth by vm.gateHealth.collectAsStateWithLifecycle()
    val active by vm.activeKey.collectAsStateWithLifecycle()
    val synced by RealTime.synced.collectAsStateWithLifecycle()
    val queued = queueItems.filter { it.isQueued }
    val failed = queueItems.filter { it.isFailed }
    val noMeta = queued.filter { !it.hasMetadata }   // v23 metadata guard
    fun count(t: String) = queued.count { it.dayType == t }

    LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // Hero: today at a glance
        item {
            val today = plan.days.firstOrNull()
            Box(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.large).background(Brush.linearGradient(listOf(BrandHeader, BrandHeaderEnd, BrandHeader))).padding(horizontal = 16.dp, vertical = 16.dp)) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("TODAY", style = MaterialTheme.typography.labelSmall, color = BrandOnHeader.copy(alpha = 0.7f))
                        Spacer(Modifier.width(6.dp))
                        Text(RealTime.prettyKey(RealTime.key(RealTime.dhakaDate())), style = MaterialTheme.typography.labelSmall, color = BrandOnHeader.copy(alpha = 0.7f))
                        Spacer(Modifier.weight(1f))
                        Box(Modifier.size(7.dp).clip(CircleShape).background(if (synced) BrandOnHeader else Color(0xFF7A1E1E)))
                        Spacer(Modifier.width(5.dp))
                        Text(if (synced) "Live time" else "Device time", style = MaterialTheme.typography.labelSmall, color = BrandOnHeader.copy(alpha = 0.7f))
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        when {
                            today == null -> "Loading schedule…"
                            today.slotCount == 0 -> "All done for today"
                            else -> "${today.slotCount} ${ContentTypes.dayUi(today.dayType).label} left"
                        },
                        style = MaterialTheme.typography.headlineSmall, color = BrandOnHeader, maxLines = 2, overflow = TextOverflow.Ellipsis
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${Accounts.byKey(active).label} · ${queued.size} queued", style = MaterialTheme.typography.bodyMedium, color = BrandOnHeader.copy(alpha = 0.8f), modifier = Modifier.weight(1f))
                        DhakaClock(color = BrandOnHeader)
                    }
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { onOpenPage(Page.UPLOAD) }, colors = ButtonDefaults.buttonColors(containerColor = BrandOnHeader, contentColor = BrandHeader), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) {
                            Icon(Icons.Default.CloudUpload, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Upload")
                        }
                        Button(onClick = { onOpenPage(Page.SCHEDULE) }, colors = ButtonDefaults.buttonColors(containerColor = BrandOnHeader.copy(alpha = 0.12f), contentColor = BrandOnHeader), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) {
                            Icon(Icons.Default.CalendarMonth, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Planner")
                        }
                    }
                }
            }
        }

        // v14 Home upload overview — shared with the Planner.
        item { TodayRunStrip(active, plan, uploadHealth) }

        // Queue by type — 2 per row, full labels
        item {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Queue by type", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 2.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile("Ringtones", count("AUDIO").toString(), Modifier.weight(1f), typeColor("AUDIO"), icon = typeIcon("AUDIO"))
                    StatTile("Wallpapers", count("WALLPAPER").toString(), Modifier.weight(1f), typeColor("WALLPAPER"), icon = typeIcon("WALLPAPER"))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile("24H sets", count("WALLPAPER_24H").toString(), Modifier.weight(1f), typeColor("WALLPAPER_24H"), icon = typeIcon("WALLPAPER_24H"))
                    StatTile("Dual sets", count("WALLPAPER_DUAL").toString(), Modifier.weight(1f), typeColor("WALLPAPER_DUAL"), icon = typeIcon("WALLPAPER_DUAL"))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile("Battery sets", count("WALLPAPER_BATTERY").toString(), Modifier.weight(1f), typeColor("WALLPAPER_BATTERY"), icon = typeIcon("WALLPAPER_BATTERY"))
                    StatTile("Live wallpapers", count("LIVE_WALLPAPER").toString(), Modifier.weight(1f), typeColor("LIVE_WALLPAPER"), icon = typeIcon("LIVE_WALLPAPER"))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile("Charging animations", count("CHARGING_ANIMATION").toString(), Modifier.weight(1f), typeColor("CHARGING_ANIMATION"), icon = typeIcon("CHARGING_ANIMATION"))
                    StatTile("Pinned", queued.count { it.isPinned }.toString(), Modifier.weight(1f), BrandAmber, icon = Icons.Default.PushPin)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile("Failed uploads", failed.size.toString(), Modifier.weight(1f), MaterialTheme.colorScheme.error, hint = if (failed.isNotEmpty()) "Needs attention" else null, icon = Icons.Default.ErrorOutline)
                    StatTile("No metadata", noMeta.size.toString(), Modifier.weight(1f), Warn, hint = if (noMeta.isNotEmpty()) "Bot skips these" else null, icon = Icons.Default.WarningAmber)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile("Total in queue", queueItems.size.toString(), Modifier.weight(1f), BrandDark, icon = Icons.Default.Inventory2) // v27.9 icons
                }
            }
        }

        // v23: files without metadata (bot skips them) - always above failed uploads
        item { MetadataAlertSection(vm, noMeta, active) }

        // Failed uploads (shown only when something went wrong)
        if (failed.isNotEmpty()) {
            item { FailedUploadsSection(vm, failed, Accounts.byKey(active).label, hideWhenEmpty = true) }
        }

        // Next 7 days
        item {
            SectionCard("Next 7 days", trailing = { TextButton(onClick = { onOpenPage(Page.SCHEDULE) }, contentPadding = PaddingValues(horizontal = 8.dp)) { Text("Planner"); Icon(Icons.Default.ChevronRight, null, Modifier.size(16.dp)) } }) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(plan.days.take(7)) { d ->
                        val filled = d.slots.count { it != null }
                        val full = d.slotCount > 0 && filled >= d.slotCount
                        Column(
                            Modifier.width(78.dp).clip(MaterialTheme.shapes.small)
                                .background(if (d.isToday) BrandBadge else MaterialTheme.colorScheme.surfaceVariant)
                                .clickable { onOpenPage(Page.SCHEDULE) }
                                .padding(horizontal = 8.dp, vertical = 10.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            val fg = if (d.isToday) BrandOnBadge else MaterialTheme.colorScheme.onSurface
                            Text(if (d.isToday) "TODAY" else d.date.dayOfWeek.name.take(3), style = MaterialTheme.typography.labelSmall, color = if (d.isToday) BrandOnBadge else MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(d.date.dayOfMonth.toString(), style = MaterialTheme.typography.titleLarge, color = fg)
                            Spacer(Modifier.height(6.dp))
                            TypeBadge(d.dayType)
                            Spacer(Modifier.height(6.dp))
                            Text("$filled/${d.slotCount}", style = MaterialTheme.typography.labelMedium, color = if (full) Ok else if (filled == 0) Warn else fg, textAlign = TextAlign.Center)
                        }
                    }
                }
            }
        }

        // Quick actions
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                QuickAction("Pins", Icons.Default.PushPin, Modifier.weight(1f)) { onOpenPage(Page.PINS) }
                QuickAction("Distribute", Icons.Default.Hub, Modifier.weight(1f)) { onOpenPage(Page.DISTRIBUTE) }
                QuickAction("Planner", Icons.Default.CalendarMonth, Modifier.weight(1f)) { onOpenPage(Page.SCHEDULE) }
            }
        }

        // Recent uploads
        item {
            SectionCard("Recent uploads", Accounts.byKey(active).label, trailing = { TextButton(onClick = { onOpenPage(Page.UPLOAD) }, contentPadding = PaddingValues(horizontal = 8.dp)) { Text("See all") } }) {
                val recent = queueItems.sortedByDescending { it.createdAt }.take(5)
                if (recent.isEmpty()) EmptyState("No uploads yet. Tap Upload to add files.")
                else recent.forEach { it -> QueueRow(it, subtitle = it.status.uppercase(), onClick = { vm.selectedItem.value = it }) }
            }
        }
        item { Spacer(Modifier.height(56.dp)) }
    }
}

@Composable
private fun QuickAction(label: String, icon: ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(
        modifier.clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surface).clickable(onClick = onClick).padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(BrandYellow.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
            Icon(icon, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
        }
        Spacer(Modifier.height(6.dp))
        Text(label, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}
