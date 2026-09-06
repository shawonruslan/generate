package com.zedge.contentstudio.ui.screens

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

@Composable
fun HomeScreen(vm: MainViewModel, onOpenPage: (Page) -> Unit) {
    val queueItems by vm.items.collectAsStateWithLifecycle()
    val plan by vm.plan.collectAsStateWithLifecycle()
    val active by vm.activeKey.collectAsStateWithLifecycle()
    val synced by RealTime.synced.collectAsStateWithLifecycle()
    val queued = queueItems.filter { it.isQueued }
    fun count(t: String) = queued.count { it.dayType == t }

    LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // Hero: today at a glance
        item {
            val today = plan.days.firstOrNull()
            Box(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.large).background(Brush.linearGradient(listOf(BrandYellow, BrandAmber))).padding(horizontal = 16.dp, vertical = 16.dp)) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("TODAY", style = MaterialTheme.typography.labelSmall, color = BrandDark.copy(alpha = 0.7f))
                        Spacer(Modifier.width(6.dp))
                        Text(RealTime.prettyKey(RealTime.key(RealTime.dhakaDate())), style = MaterialTheme.typography.labelSmall, color = BrandDark.copy(alpha = 0.7f))
                        Spacer(Modifier.weight(1f))
                        Box(Modifier.size(7.dp).clip(CircleShape).background(if (synced) BrandDark else Color(0xFF7A1E1E)))
                        Spacer(Modifier.width(5.dp))
                        Text(if (synced) "Live time" else "Device time", style = MaterialTheme.typography.labelSmall, color = BrandDark.copy(alpha = 0.7f))
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        when {
                            today == null -> "Loading schedule…"
                            today.slotCount == 0 -> "All done for today"
                            else -> "${today.slotCount} ${ContentTypes.dayUi(today.dayType).label} left"
                        },
                        style = MaterialTheme.typography.headlineSmall, color = BrandDark, maxLines = 2, overflow = TextOverflow.Ellipsis
                    )
                    Text("${Accounts.byKey(active).label} · ${queued.size} queued", style = MaterialTheme.typography.bodyMedium, color = BrandDark.copy(alpha = 0.8f))
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { onOpenPage(Page.UPLOAD) }, colors = ButtonDefaults.buttonColors(containerColor = BrandDark, contentColor = BrandYellow), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) {
                            Icon(Icons.Default.CloudUpload, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Upload")
                        }
                        Button(onClick = { onOpenPage(Page.SCHEDULE) }, colors = ButtonDefaults.buttonColors(containerColor = BrandDark.copy(alpha = 0.12f), contentColor = BrandDark), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) {
                            Icon(Icons.Default.CalendarMonth, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Planner")
                        }
                    }
                }
            }
        }

        // Queue by type — 2 per row, full labels
        item {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Queue by type", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 2.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile("Ringtones", count("AUDIO").toString(), Modifier.weight(1f), typeColor("AUDIO"))
                    StatTile("Wallpapers", count("WALLPAPER").toString(), Modifier.weight(1f), typeColor("WALLPAPER"))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile("24H sets", count("WALLPAPER_24H").toString(), Modifier.weight(1f), typeColor("WALLPAPER_24H"))
                    StatTile("Dual sets", count("WALLPAPER_DUAL").toString(), Modifier.weight(1f), typeColor("WALLPAPER_DUAL"))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile("Battery sets", count("WALLPAPER_BATTERY").toString(), Modifier.weight(1f), typeColor("WALLPAPER_BATTERY"))
                    StatTile("Live wallpapers", count("LIVE_WALLPAPER").toString(), Modifier.weight(1f), typeColor("LIVE_WALLPAPER"))
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile("Charging animations", count("CHARGING_ANIMATION").toString(), Modifier.weight(1f), typeColor("CHARGING_ANIMATION"))
                    StatTile("Pinned", queued.count { it.isPinned }.toString(), Modifier.weight(1f), BrandAmber)
                }
            }
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
                                .background(if (d.isToday) BrandYellow else MaterialTheme.colorScheme.surfaceVariant)
                                .clickable { onOpenPage(Page.SCHEDULE) }
                                .padding(horizontal = 8.dp, vertical = 10.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            val fg = if (d.isToday) BrandDark else MaterialTheme.colorScheme.onSurface
                            Text(if (d.isToday) "TODAY" else d.date.dayOfWeek.name.take(3), style = MaterialTheme.typography.labelSmall, color = if (d.isToday) BrandDark else MaterialTheme.colorScheme.onSurfaceVariant)
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
