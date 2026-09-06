package com.zedge.contentstudio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.width
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.Page
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.components.QueueCard
import com.zedge.contentstudio.ui.components.SectionCard
import com.zedge.contentstudio.ui.components.StatTile
import com.zedge.contentstudio.ui.components.TypeBadge
import com.zedge.contentstudio.ui.theme.BrandAmber
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.typeColor

@Composable
fun HomeScreen(vm: MainViewModel, onOpenPage: (Page) -> Unit) {
    val items by vm.items.collectAsStateWithLifecycle()
    val plan by vm.plan.collectAsStateWithLifecycle()
    val active by vm.activeKey.collectAsStateWithLifecycle()
    val synced by RealTime.synced.collectAsStateWithLifecycle()
    val queued = items.filter { it.isQueued }
    fun count(t: String) = queued.count { it.dayType == t }

    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            // Hero banner
            Box(Modifier.fillMaxWidth().clip(MaterialTheme.shapes.large).background(Brush.linearGradient(listOf(BrandYellow, BrandAmber))).padding(18.dp)) {
                Column {
                    Text("Zedge Automation", style = MaterialTheme.typography.labelSmall, color = BrandDark.copy(alpha = 0.7f))
                    Text("Content Studio", style = MaterialTheme.typography.headlineSmall, color = BrandDark)
                    Spacer(Modifier.height(6.dp))
                    val today = plan.days.firstOrNull()
                    Text(
                        if (today == null) "Loading schedule..." else if (today.slotCount == 0) "All uploads done for today 🎉" else "Today: ${ContentTypes.dayUi(today.dayType).label} · ${today.slotCount} slot(s) left",
                        style = MaterialTheme.typography.bodyMedium, color = BrandDark
                    )
                    Text("${Accounts.byKey(active).label} · ${if (synced) "Real time synced" else "Device clock"} · ${RealTime.prettyKey(RealTime.key(RealTime.dhakaDate()))}", style = MaterialTheme.typography.bodySmall, color = BrandDark.copy(alpha = 0.75f))
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { onOpenPage(Page.UPLOAD) }) { Text("Upload") }
                        OutlinedButton(onClick = { onOpenPage(Page.SCHEDULE) }) { Text("Calendar") }
                    }
                }
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile("Active DB", Accounts.byKey(active).label, Modifier.weight(1f))
                StatTile("Total queued", queued.size.toString(), Modifier.weight(1f), accent = BrandAmber)
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile("Ringtones", count("AUDIO").toString(), Modifier.weight(1f), typeColor("AUDIO"))
                StatTile("Wallpapers", count("WALLPAPER").toString(), Modifier.weight(1f), typeColor("WALLPAPER"))
                StatTile("24H sets", count("WALLPAPER_24H").toString(), Modifier.weight(1f), typeColor("WALLPAPER_24H"))
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile("Dual sets", count("WALLPAPER_DUAL").toString(), Modifier.weight(1f), typeColor("WALLPAPER_DUAL"))
                StatTile("Battery", count("WALLPAPER_BATTERY").toString(), Modifier.weight(1f), typeColor("WALLPAPER_BATTERY"))
                StatTile("Live", count("LIVE_WALLPAPER").toString(), Modifier.weight(1f), typeColor("LIVE_WALLPAPER"))
                StatTile("Charging", count("CHARGING_ANIMATION").toString(), Modifier.weight(1f), typeColor("CHARGING_ANIMATION"))
            }
        }
        item {
            SectionCard("Upcoming days", "Next 7 days from the publishing planner") {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(plan.days.take(7)) { d ->
                        Column(Modifier.width(96.dp).clip(MaterialTheme.shapes.small).background(MaterialTheme.colorScheme.surfaceVariant).padding(10.dp)) {
                            Text(if (d.isToday) "TODAY" else d.date.dayOfWeek.name.take(3), style = MaterialTheme.typography.labelSmall, color = if (d.isToday) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(d.date.dayOfMonth.toString(), style = MaterialTheme.typography.titleLarge)
                            Spacer(Modifier.height(6.dp))
                            TypeBadge(d.dayType)
                            Spacer(Modifier.height(6.dp))
                            Text("${d.slots.count { it != null }}/${d.slotCount}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
        item {
            SectionCard("Recent uploads", "Latest 4 items in ${Accounts.byKey(active).label}", trailing = { OutlinedButton(onClick = { onOpenPage(Page.UPLOAD) }) { Text("See all") } }) {
                val recent = items.sortedByDescending { it.createdAt }.take(4)
                if (recent.isEmpty()) Text("No uploads yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                else Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    recent.forEach { it -> QueueCard(it, onClick = { vm.selectedItem.value = it }, modifier = Modifier.weight(1f)) }
                }
            }
        }
        item { Spacer(Modifier.height(60.dp)) }
    }
}
