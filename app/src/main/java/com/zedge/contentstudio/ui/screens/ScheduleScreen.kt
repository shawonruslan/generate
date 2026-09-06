package com.zedge.contentstudio.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.domain.PlannedDay
import com.zedge.contentstudio.domain.SchedulePlan
import com.zedge.contentstudio.domain.SpecialDays
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.components.ItemThumb
import com.zedge.contentstudio.ui.components.PagerBar
import com.zedge.contentstudio.ui.components.StatTile
import com.zedge.contentstudio.ui.components.TypeBadge
import com.zedge.contentstudio.ui.theme.BrandAmber
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn
import com.zedge.contentstudio.ui.theme.typeColor
import java.time.Instant
import java.time.ZoneOffset

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ScheduleScreen(vm: MainViewModel) {
    val plan by vm.plan.collectAsStateWithLifecycle()
    val queueItems by vm.items.collectAsStateWithLifecycle()
    val synced by RealTime.synced.collectAsStateWithLifecycle()
    val sdStatus by vm.specialDays.status.collectAsStateWithLifecycle()
    val sdVersion by vm.specialDays.version.collectAsStateWithLifecycle()
    var page by rememberSaveable { mutableStateOf(0) }
    var pinTarget by remember { mutableStateOf<PlannedDay?>(null) }   // empty slot tapped -> pick a queued file
    var moveItem by remember { mutableStateOf<Pair<QueueItem, PlannedDay>?>(null) } // long-press -> move / unpin

    val totalPages = maxOf(1, (plan.days.size + SchedulePlan.DAYS_PER_PAGE - 1) / SchedulePlan.DAYS_PER_PAGE)
    if (page >= totalPages) page = totalPages - 1
    val visible = plan.days.drop(page * SchedulePlan.DAYS_PER_PAGE).take(SchedulePlan.DAYS_PER_PAGE)

    LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Today summary
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile("Left today", "${plan.rule.remaining}", Modifier.weight(1f), BrandAmber, hint = ContentTypes.dayUi(plan.rule.type).label)
                StatTile("Uploaded today", "${plan.rule.uploadedToday} / ${ContentTypes.DAILY_LIMIT}", Modifier.weight(1f), Ok, hint = if (synced) "Live time ✓" else "Device clock")
            }
        }
        // Stock per type (compact chips)
        item {
            Column {
                Text("Stock by type", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 2.dp, bottom = 6.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    ContentTypes.TYPE_CYCLE.forEach { t ->
                        val n = plan.buckets[t]?.size ?: 0
                        val c = typeColor(t)
                        Row(Modifier.clip(CircleShape).background(c.copy(alpha = 0.14f)).border(1.dp, c.copy(alpha = 0.4f), CircleShape).padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(ContentTypes.dayUi(t).short, style = MaterialTheme.typography.labelSmall, color = c, fontWeight = FontWeight.Bold)
                            Spacer(Modifier.width(6.dp))
                            Text(n.toString(), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.Bold)
                        }
                    }
                }
                val waiting = plan.waitingForStock
                if (waiting.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Low stock (need ${ContentTypes.MIN_STOCK_FOR_DAY}): " + waiting.joinToString(", ") { "${ContentTypes.dayUi(it.first).short} ${it.second}" },
                        style = MaterialTheme.typography.bodySmall, color = Warn
                    )
                }
                // sdVersion is read here so day cards refresh when holiday feeds finish syncing
                Text("Special days: $sdStatus" + if (sdVersion > 0) "" else "", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
            }
        }
        item { PagerBar(page, totalPages, onPrev = { page-- }, onNext = { page++ }, label = if (visible.isEmpty()) "" else "${RealTime.prettyKey(visible.first().dateKey)} → ${RealTime.prettyKey(visible.last().dateKey)}") }

        // One full-width day card per row — readable titles
        items(visible) { d ->
            DayCard(d, vm.specialDays, Modifier.fillMaxWidth(),
                onItem = { vm.selectedItem.value = it },
                onItemLong = { moveItem = it to d },
                onEmpty = { pinTarget = d })
        }
        item { Spacer(Modifier.height(56.dp)) }
    }

    // --- Pick a file to pin into an empty slot ---
    pinTarget?.let { day ->
        var q by remember { mutableStateOf("") }
        val candidates = queueItems.filter { it.isQueued && !it.isPinned }.filter { q.isBlank() || it.displayTitle.contains(q, true) }.sortedBy { it.createdAt }
        AlertDialog(
            onDismissRequest = { pinTarget = null },
            title = { Text("Pin to ${RealTime.prettyKey(day.dateKey)}", style = MaterialTheme.typography.titleMedium) },
            text = {
                Column {
                    Text("Day type: ${ContentTypes.dayUi(day.dayType).label}. Pinning overrides the rotation.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(q, { q = it }, Modifier.fillMaxWidth(), placeholder = { Text("Search") }, singleLine = true)
                    Spacer(Modifier.height(8.dp))
                    LazyColumn(Modifier.height(320.dp)) {
                        items(candidates) { it ->
                            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { vm.pin(it, day.dateKey); pinTarget = null }.padding(vertical = 6.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                ItemThumb(it, Modifier.width(38.dp), ratio = 3f / 4f, corner = 8)
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(it.displayTitle, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium)
                                    val auto = plan.predictedDateFor(it.id)
                                    Text(if (auto != null) "Auto: ${RealTime.prettyKey(auto)}" else "Auto: waiting for stock", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Spacer(Modifier.width(6.dp))
                                TypeBadge(it.dayType)
                            }
                        }
                        if (candidates.isEmpty()) item { Text("No unpinned queued files.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { pinTarget = null }) { Text("Close") } },
        )
    }

    // --- Long press on a slot: move to another date / unpin ---
    moveItem?.let { (item, day) ->
        MoveDialog(item, day, onDismiss = { moveItem = null },
            onMove = { key -> vm.pin(item, key); moveItem = null },
            onUnpin = { vm.unpin(item); moveItem = null })
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DayCard(d: PlannedDay, specialDays: SpecialDays, modifier: Modifier = Modifier, onItem: (QueueItem) -> Unit, onItemLong: (QueueItem) -> Unit, onEmpty: () -> Unit) {
    val c = typeColor(d.dayType)
    val special = specialDays.forDate(d.dateKey)
    val filled = d.slots.count { it != null }
    Card(
        modifier = modifier,
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(if (d.isToday) 2.dp else 1.dp, if (d.isToday) BrandYellow else MaterialTheme.colorScheme.outlineVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(Modifier.padding(12.dp)) {
            // Date column
            Column(Modifier.width(48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(if (d.isToday) BrandYellow else MaterialTheme.colorScheme.surfaceVariant),
                    contentAlignment = Alignment.Center
                ) {
                    Text(d.date.dayOfMonth.toString(), style = MaterialTheme.typography.titleLarge, color = if (d.isToday) BrandDark else MaterialTheme.colorScheme.onSurface)
                }
                Spacer(Modifier.height(4.dp))
                Text(if (d.isToday) "TODAY" else d.date.dayOfWeek.name.take(3), style = MaterialTheme.typography.labelSmall, color = if (d.isToday) MaterialTheme.colorScheme.primary else if (d.isWeekend) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                Text(d.date.month.name.take(3), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.width(12.dp))
            // Content column
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if (d.dayType.isBlank()) "No type" else ContentTypes.dayUi(d.dayType).label, style = MaterialTheme.typography.titleSmall, color = c, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(6.dp))
                    Text("$filled/${d.slotCount}", style = MaterialTheme.typography.labelMedium, color = if (d.slotCount > 0 && filled >= d.slotCount) Ok else MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (d.switchedFrom != null) {
                    Text("${ContentTypes.dayUi(d.switchedFrom).short} skipped (< ${ContentTypes.MIN_STOCK_FOR_DAY} files)", style = MaterialTheme.typography.labelSmall, color = Warn, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (special.isNotEmpty()) {
                    Spacer(Modifier.height(4.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        special.take(3).forEach { s ->
                            Box(Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant).padding(horizontal = 7.dp, vertical = 2.dp)) {
                                Text("${SpecialDays.emoji(s.icon)} ${s.label}", fontSize = 10.sp, lineHeight = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                if (d.slotCount == 0) {
                    Box(Modifier.fillMaxWidth().height(40.dp).clip(RoundedCornerShape(10.dp)).background(Ok.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
                        Text("All uploads done \uD83C\uDF89", color = Ok, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelMedium)
                    }
                } else {
                    d.slots.forEachIndexed { i, it ->
                        if (i > 0) Spacer(Modifier.height(6.dp))
                        if (it == null) {
                            Row(
                                Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(10.dp))
                                    .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(10.dp))
                                    .clickable(onClick = onEmpty).padding(horizontal = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(Icons.Default.Add, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                Spacer(Modifier.width(8.dp))
                                Text("Empty slot · tap to pin", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        } else {
                            Row(
                                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surfaceVariant)
                                    .combinedClickable(onClick = { onItem(it) }, onLongClick = { onItemLong(it) }).padding(6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                ItemThumb(it, Modifier.width(36.dp), ratio = 3f / 4f, corner = 8)
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(it.displayTitle, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    Spacer(Modifier.height(3.dp))
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        TypeBadge(it.dayType)
                                        if (it.isPinned) Row(verticalAlignment = Alignment.CenterVertically) {
                                            Icon(Icons.Default.PushPin, null, Modifier.size(11.dp), tint = MaterialTheme.colorScheme.primary)
                                            Spacer(Modifier.width(2.dp))
                                            Text("Pinned", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                                        }
                                    }
                                }
                                if (it.isPinned) Icon(Icons.Default.Close, "Unpin", Modifier.size(18.dp).clickable { onItemLong(it) }, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MoveDialog(item: QueueItem, day: PlannedDay, onDismiss: () -> Unit, onMove: (String) -> Unit, onUnpin: () -> Unit) {
    var showPicker by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(item.displayTitle, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium) },
        text = {
            Column {
                Text(if (item.isPinned) "Pinned to ${RealTime.prettyKey(item.scheduledDate ?: day.dateKey)}" else "Auto-scheduled for ${RealTime.prettyKey(day.dateKey)} (${ContentTypes.dayUi(item.dayType).label} rotation)", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(10.dp))
                TextButton(onClick = { showPicker = true }) { Text("Pin / move to another date…") }
                TextButton(onClick = { onMove(day.dateKey) }) { Text("Pin here (${RealTime.prettyKey(day.dateKey)})") }
                if (item.isPinned) TextButton(onClick = onUnpin) { Text("Unpin (back to auto)", color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
    if (showPicker) {
        DateKeyPicker(initialKey = item.scheduledDate ?: day.dateKey, onDismiss = { showPicker = false }, onPick = { showPicker = false; onMove(it) })
    }
}

/** Material date picker that returns a YYYY-MM-DD key (Dhaka calendar day). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateKeyPicker(initialKey: String?, onDismiss: () -> Unit, onPick: (String) -> Unit) {
    val initial = (initialKey?.let { RealTime.parseKey(it) } ?: RealTime.dhakaDate()).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli()
    val state = rememberDatePickerState(initialSelectedDateMillis = initial)
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                val ms = state.selectedDateMillis ?: return@TextButton
                onPick(RealTime.key(Instant.ofEpochMilli(ms).atZone(ZoneOffset.UTC).toLocalDate()))
            }) { Text("Pin") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    ) { DatePicker(state = state) }
}
