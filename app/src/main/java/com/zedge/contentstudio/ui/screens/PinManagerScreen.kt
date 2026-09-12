package com.zedge.contentstudio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn
import com.zedge.contentstudio.ui.theme.typeColor

@Composable
fun PinManagerScreen(vm: MainViewModel) {
    val queueItems by vm.items.collectAsStateWithLifecycle()
    val plan by vm.plan.collectAsStateWithLifecycle()
    var filter by rememberSaveable { mutableStateOf("ALL") }
    var search by rememberSaveable { mutableStateOf("") }
    val selectedIds = remember { mutableStateOf(setOf<String>()) }
    var pickFor by remember { mutableStateOf<List<QueueItem>?>(null) }  // items to (re)date via date picker
    var pickVerb by remember { mutableStateOf("") }

    val todayKey = RealTime.key(RealTime.dhakaDate())
    val queued = queueItems.filter { it.isQueued }
    val pinned = queued.filter { it.isPinned }.sortedWith(compareBy({ it.scheduledDate }, { it.createdAt }))
    val overdue = pinned.filter { (it.scheduledDate ?: "") < todayKey }
    val matches: (QueueItem) -> Boolean = { (filter == "ALL" || it.dayType == filter) && (search.isBlank() || it.displayTitle.contains(search, true) || it.name.contains(search, true)) }
    val unpinned = queued.filter { !it.isPinned }.filter(matches).sortedBy { it.createdAt }
    val groups = pinned.filter(matches).groupBy { it.scheduledDate ?: "" }

    LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile("Pinned files", pinned.size.toString(), Modifier.weight(1f), BrandAmber)
                StatTile("Overdue", overdue.size.toString(), Modifier.weight(1f), if (overdue.isEmpty()) Ok else Warn, hint = if (overdue.isEmpty()) "All on time" else "Shown today")
            }
        }
        item {
            OutlinedTextField(
                search, { search = it }, Modifier.fillMaxWidth(),
                placeholder = { Text("Search files") }, singleLine = true,
                leadingIcon = { Icon(Icons.Default.Search, null) },
                trailingIcon = { if (search.isNotBlank()) IconButton(onClick = { search = "" }) { Icon(Icons.Default.Close, "Clear") } },
                shape = MaterialTheme.shapes.medium,
            )
            Spacer(Modifier.height(8.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                (listOf("ALL") + ContentTypes.TYPE_CYCLE).forEach { t ->
                    val sel = filter == t
                    val c = if (t == "ALL") MaterialTheme.colorScheme.primary else typeColor(t)
                    Box(
                        Modifier.clip(CircleShape)
                            .background(if (sel) BrandYellow else MaterialTheme.colorScheme.surfaceVariant)
                            .clickable { filter = t }
                            .padding(horizontal = 12.dp, vertical = 6.dp)
                    ) {
                        Text(if (t == "ALL") "All" else ContentTypes.dayUi(t).short, color = if (sel) BrandDark else c, style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
        // Bulk actions
        item {
            val sel = selectedIds.value
            SectionCard("Bulk actions", if (sel.isEmpty()) "Tick files below to select" else "${sel.size} selected",
                trailing = { if (sel.isNotEmpty()) TextButton(onClick = { selectedIds.value = emptySet() }, contentPadding = PaddingValues(horizontal = 8.dp)) { Text("Clear") } }) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    OutlinedButton(enabled = sel.isNotEmpty(), onClick = { pickFor = queued.filter { it.id in sel }; pickVerb = "selected" }, contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)) { Text("Pin / re-date") }
                    OutlinedButton(enabled = sel.any { id -> pinned.any { it.id == id } }, onClick = { vm.bulkPin(pinned.filter { it.id in sel }, null, "selected"); selectedIds.value = emptySet() }, contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)) { Text("Unpin selected") }
                    OutlinedButton(enabled = overdue.isNotEmpty(), onClick = { vm.bulkPin(overdue, todayKey, "overdue") }, contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)) { Text("Overdue → today") }
                    OutlinedButton(enabled = pinned.isNotEmpty(), onClick = { vm.bulkPin(pinned, null, "all pinned") }, contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)) { Text("Unpin all") }
                }
            }
        }
        // Pinned grouped by date
        item { Text("Pinned files", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 2.dp, top = 4.dp)) }
        if (groups.isEmpty()) item { EmptyState("No pinned files yet. Pin from the planner or from the list below.") }
        groups.forEach { (dateKey, list) ->
            item {
                val isOverdue = dateKey < todayKey
                SectionCard(
                    RealTime.prettyKey(dateKey) + if (isOverdue) " · OVERDUE" else if (dateKey == todayKey) " · TODAY" else "",
                    "${list.size} file(s)" + if (isOverdue) " · shows today" else "",
                    trailing = { TextButton(onClick = { pickFor = list; pickVerb = RealTime.prettyKey(dateKey) }, contentPadding = PaddingValues(horizontal = 8.dp)) { Text("Move all") } }
                ) {
                    list.forEach { it -> PinRow(it, selectedIds, auto = null, onOpen = { vm.selectedItem.value = it }, onDate = { pickFor = listOf(it); pickVerb = it.displayTitle }, onUnpin = { vm.unpin(it) }) }
                }
            }
        }
        // Unpinned
        item { Text("Unpinned queue (auto rotation)", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 2.dp, top = 4.dp)) }
        if (unpinned.isEmpty()) item { EmptyState("Nothing matches.") }
        else item {
            SectionCard(null) {
                unpinned.forEach { it -> PinRow(it, selectedIds, auto = plan.predictedDateFor(it.id), onOpen = { vm.selectedItem.value = it }, onDate = { pickFor = listOf(it); pickVerb = it.displayTitle }, onUnpin = null) }
            }
        }
        item { Spacer(Modifier.height(56.dp)) }
    }

    pickFor?.let { list ->
        DateKeyPicker(initialKey = list.firstOrNull()?.scheduledDate ?: todayKey, onDismiss = { pickFor = null }) { key ->
            if (list.size == 1) vm.pin(list[0], key) else vm.bulkPin(list, key, pickVerb)
            pickFor = null; selectedIds.value = emptySet()
        }
    }
}

@Composable
private fun PinRow(item: QueueItem, selected: MutableState<Set<String>>, auto: String?, onOpen: () -> Unit, onDate: () -> Unit, onUnpin: (() -> Unit)?) {
    val checked = item.id in selected.value
    Row(
        Modifier.fillMaxWidth().clip(MaterialTheme.shapes.small)
            .background(if (checked) BrandYellow.copy(alpha = 0.10f) else MaterialTheme.colorScheme.surface)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(checked = checked, onCheckedChange = { c -> selected.value = if (c) selected.value + item.id else selected.value - item.id })
        ItemThumb(item, Modifier.width(40.dp).clickable(onClick = onOpen), ratio = 3f / 4f, corner = 8)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f).clickable(onClick = onOpen)) {
            Text(item.displayTitle, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(3.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                TypeBadge(item.dayType)
                Text(
                    when {
                        item.isPinned -> RealTime.prettyKey(item.scheduledDate)
                        auto != null -> "Auto · ${RealTime.prettyKey(auto)}"
                        else -> "Waiting for stock"
                    },
                    style = MaterialTheme.typography.labelSmall, color = if (item.isPinned) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
        IconButton(onClick = onDate, modifier = Modifier.size(36.dp)) {
            Icon(if (item.isPinned) Icons.Default.EditCalendar else Icons.Default.PushPin, if (item.isPinned) "Change date" else "Pin", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
        }
        if (onUnpin != null) IconButton(onClick = onUnpin, modifier = Modifier.size(36.dp)) {
            Icon(Icons.Default.Close, "Unpin", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.error)
        }
    }
}
