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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.components.EmptyState
import com.zedge.contentstudio.ui.components.ItemThumb
import com.zedge.contentstudio.ui.components.SectionCard
import com.zedge.contentstudio.ui.components.StatTile
import com.zedge.contentstudio.ui.components.TypeBadge
import com.zedge.contentstudio.ui.theme.BrandAmber
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn

@Composable
fun PinManagerScreen(vm: MainViewModel) {
    val items by vm.items.collectAsStateWithLifecycle()
    val plan by vm.plan.collectAsStateWithLifecycle()
    val active by vm.activeKey.collectAsStateWithLifecycle()
    var filter by rememberSaveable { mutableStateOf("ALL") }
    var search by rememberSaveable { mutableStateOf("") }
    val selectedIds = remember { mutableStateOf(setOf<String>()) }
    var pickFor by remember { mutableStateOf<List<QueueItem>?>(null) }  // items to (re)date via date picker
    var pickVerb by remember { mutableStateOf("") }

    val todayKey = RealTime.key(RealTime.dhakaDate())
    val queued = items.filter { it.isQueued }
    val pinned = queued.filter { it.isPinned }.sortedWith(compareBy({ it.scheduledDate }, { it.createdAt }))
    val overdue = pinned.filter { (it.scheduledDate ?: "") < todayKey }
    val matches: (QueueItem) -> Boolean = { (filter == "ALL" || it.dayType == filter) && (search.isBlank() || it.displayTitle.contains(search, true) || it.name.contains(search, true)) }
    val unpinned = queued.filter { !it.isPinned }.filter(matches).sortedBy { it.createdAt }
    val groups = pinned.filter(matches).groupBy { it.scheduledDate ?: "" }

    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile("Account", Accounts.byKey(active).label, Modifier.weight(1f))
                StatTile("Pinned", pinned.size.toString(), Modifier.weight(1f), BrandAmber)
                StatTile("Overdue", overdue.size.toString(), Modifier.weight(1f), if (overdue.isEmpty()) Ok else Warn, hint = if (overdue.isEmpty()) null else "shown today")
            }
        }
        item {
            OutlinedTextField(search, { search = it }, Modifier.fillMaxWidth(), placeholder = { Text("Search files") }, singleLine = true)
            Spacer(Modifier.height(8.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                items(listOf("ALL") + ContentTypes.TYPE_CYCLE) { t ->
                    val sel = filter == t
                    Box(Modifier.clip(RoundedCornerShape(999.dp)).background(if (sel) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant).clickable { filter = t }.padding(horizontal = 12.dp, vertical = 6.dp)) {
                        Text(if (t == "ALL") "All" else ContentTypes.dayUi(t).short, color = if (sel) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
        // Bulk actions
        item {
            val sel = selectedIds.value
            SectionCard("Bulk actions", if (sel.isEmpty()) "Tick files below" else "${sel.size} selected") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(enabled = sel.isNotEmpty(), onClick = { pickFor = queued.filter { it.id in sel }; pickVerb = "selected" }) { Text("Pin / re-date") }
                    OutlinedButton(enabled = sel.any { id -> pinned.any { it.id == id } }, onClick = { vm.bulkPin(pinned.filter { it.id in sel }, null, "selected"); selectedIds.value = emptySet() }) { Text("Unpin") }
                    TextButton(enabled = sel.isNotEmpty(), onClick = { selectedIds.value = emptySet() }) { Text("Clear") }
                }
                Spacer(Modifier.height(6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(enabled = overdue.isNotEmpty(), onClick = { vm.bulkPin(overdue, todayKey, "overdue") }) { Text("Overdue → today") }
                    OutlinedButton(enabled = pinned.isNotEmpty(), onClick = { vm.bulkPin(pinned, null, "all pinned") }) { Text("Unpin all") }
                }
            }
        }
        // Pinned grouped by date
        item { Text("Pinned files", style = MaterialTheme.typography.titleMedium) }
        if (groups.isEmpty()) item { EmptyState("No pinned files. Pin from the calendar or from the list below.") }
        groups.forEach { (dateKey, list) ->
            item {
                val isOverdue = dateKey < todayKey
                SectionCard(RealTime.prettyKey(dateKey) + if (isOverdue) "  · OVERDUE (shows today)" else if (dateKey == todayKey) "  · TODAY" else "", "${list.size} file(s)",
                    trailing = { TextButton(onClick = { pickFor = list; pickVerb = RealTime.prettyKey(dateKey) }) { Text("Move all") } }) {
                    list.forEach { it -> PinRow(it, selectedIds, auto = null, onOpen = { vm.selectedItem.value = it }, onDate = { pickFor = listOf(it); pickVerb = it.displayTitle }, onUnpin = { vm.unpin(it) }) }
                }
            }
        }
        // Unpinned
        item { Spacer(Modifier.height(4.dp)); Text("Unpinned queue (auto rotation)", style = MaterialTheme.typography.titleMedium) }
        if (unpinned.isEmpty()) item { EmptyState("Nothing matches.") }
        else item {
            SectionCard(null) {
                unpinned.forEach { it -> PinRow(it, selectedIds, auto = plan.predictedDateFor(it.id), onOpen = { vm.selectedItem.value = it }, onDate = { pickFor = listOf(it); pickVerb = it.displayTitle }, onUnpin = null) }
            }
        }
        item { Spacer(Modifier.height(72.dp)) }
    }

    pickFor?.let { list ->
        DateKeyPicker(initialKey = list.firstOrNull()?.scheduledDate ?: todayKey, onDismiss = { pickFor = null }) { key ->
            if (list.size == 1) vm.pin(list[0], key) else vm.bulkPin(list, key, pickVerb)
            pickFor = null; selectedIds.value = emptySet()
        }
    }
}

@Composable
private fun PinRow(item: QueueItem, selected: androidx.compose.runtime.MutableState<Set<String>>, auto: String?, onOpen: () -> Unit, onDate: () -> Unit, onUnpin: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Checkbox(checked = item.id in selected.value, onCheckedChange = { c -> selected.value = if (c) selected.value + item.id else selected.value - item.id })
        ItemThumb(item, Modifier.width(34.dp).clickable(onClick = onOpen), corner = 6)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f).clickable(onClick = onOpen)) {
            Text(item.displayTitle, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                TypeBadge(item.dayType)
                Text(
                    when {
                        item.isPinned -> "Pinned: ${RealTime.prettyKey(item.scheduledDate)}"
                        auto != null -> "Auto: ${RealTime.prettyKey(auto)}"
                        else -> "Auto: waiting for stock (${ContentTypes.MIN_STOCK_FOR_DAY} needed)"
                    },
                    style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
        TextButton(onClick = onDate) { Text(if (item.isPinned) "Date" else "Pin") }
        if (onUnpin != null) TextButton(onClick = onUnpin) { Text("Unpin", color = MaterialTheme.colorScheme.error) }
    }
}
