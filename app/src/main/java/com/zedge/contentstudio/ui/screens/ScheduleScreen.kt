package com.zedge.contentstudio.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.util.lerp
import kotlin.math.absoluteValue
import androidx.compose.foundation.horizontalScroll
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Today
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.domain.PlannedDay
import com.zedge.contentstudio.domain.SpecialDays
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.components.EmptyState
import com.zedge.contentstudio.ui.components.IconDot
import com.zedge.contentstudio.ui.components.ItemThumb
import com.zedge.contentstudio.ui.components.StatTile
import com.zedge.contentstudio.ui.components.TypeBadge
import com.zedge.contentstudio.ui.components.TypePill
import com.zedge.contentstudio.ui.components.HolidayBanner
import com.zedge.contentstudio.ui.components.typeIcon
import com.zedge.contentstudio.ui.theme.BrandAmber
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn
import com.zedge.contentstudio.ui.theme.typeColor
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneOffset

// Planner card palette (light cards on the dark canvas, like the reference design)
private val PlannerCard = Color(0xFFFFFDF6)
private val PlannerCream = Color(0xFFFFF3C4)
private val PlannerMuted = Color(0xFF8A7B55)
private val PlannerOk = Color(0xFF1F8A4C)
private val PlannerWarn = Color(0xFF9A6B00)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ScheduleScreen(vm: MainViewModel) {
    val plan by vm.plan.collectAsStateWithLifecycle()
    val queueItems by vm.items.collectAsStateWithLifecycle()
    val synced by RealTime.synced.collectAsStateWithLifecycle()
    val sdStatus by vm.specialDays.status.collectAsStateWithLifecycle()
    val sdVersion by vm.specialDays.version.collectAsStateWithLifecycle()
    var pinTarget by remember { mutableStateOf<PlannedDay?>(null) }   // empty slot tapped -> pick a queued file
    var moveItem by remember { mutableStateOf<Pair<QueueItem, PlannedDay>?>(null) } // long-press -> move / unpin

    val days = plan.days
    val pageCount = rememberUpdatedState(days.size)
    val pager = rememberPagerState(initialPage = 0) { pageCount.value }
    val strip = rememberLazyListState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(pager.currentPage) { strip.animateScrollToItem(maxOf(0, pager.currentPage - 2)) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 8.dp, bottom = 24.dp)) {
        // Today summary
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatTile("Left today", "${plan.rule.remaining}", Modifier.weight(1f), BrandAmber, hint = ContentTypes.dayUi(plan.rule.type).label)
            StatTile("Uploaded today", "${plan.rule.uploadedToday} / ${ContentTypes.DAILY_LIMIT}", Modifier.weight(1f), Ok, hint = if (synced) "Live time" else "Device clock")
        }
        Spacer(Modifier.height(12.dp))

        // Stock per type - one horizontal strip of equal-size tiles, all text left-aligned
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("STOCK BY TYPE", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
            Text("min ${ContentTypes.MIN_STOCK_FOR_DAY} per day", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ContentTypes.TYPE_CYCLE.forEach { t ->
                val n = plan.buckets[t]?.size ?: 0
                val c = typeColor(t)
                val low = n < ContentTypes.MIN_STOCK_FOR_DAY
                Column(
                    Modifier.width(112.dp).clip(RoundedCornerShape(14.dp))
                        .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                        .border(1.dp, if (low) Warn.copy(alpha = 0.55f) else c.copy(alpha = 0.35f), RoundedCornerShape(14.dp))
                        .padding(10.dp)
                ) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        IconDot(typeIcon(t), c, c.copy(alpha = 0.16f), size = 26)
                        Spacer(Modifier.weight(1f))
                        Text(n.toString(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold, color = if (low) Warn else MaterialTheme.colorScheme.onSurface)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(ContentTypes.dayUi(t).short, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(if (low) "Low stock" else "Ready", style = MaterialTheme.typography.labelSmall, color = if (low) Warn else Ok)
                }
            }
        }
        val waiting = plan.waitingForStock
        if (waiting.isNotEmpty()) {
            Text(
                "Low stock (need ${ContentTypes.MIN_STOCK_FOR_DAY}): " + waiting.joinToString(", ") { "${ContentTypes.dayUi(it.first).short} ${it.second}" },
                style = MaterialTheme.typography.bodySmall, color = Warn, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
            )
        }
        Spacer(Modifier.height(14.dp))

        if (days.isEmpty()) {
            EmptyState("No planned days yet. Upload files to build the schedule.", Modifier.padding(horizontal = 16.dp))
        } else {
            // Date strip (syncs with the card pager)
            LazyRow(state = strip, contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                itemsIndexed(days) { i, d ->
                    val sel = pager.currentPage == i
                    val c = typeColor(d.dayType)
                    Column(
                        Modifier.width(46.dp).clip(RoundedCornerShape(14.dp))
                            .background(if (sel) BrandYellow else MaterialTheme.colorScheme.surfaceContainerHigh)
                            .then(if (d.isToday && !sel) Modifier.border(1.5.dp, BrandYellow, RoundedCornerShape(14.dp)) else Modifier)
                            .clickable { scope.launch { pager.animateScrollToPage(i) } }
                            .padding(vertical = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(d.date.dayOfWeek.name.take(3), style = MaterialTheme.typography.labelSmall, color = if (sel) BrandDark.copy(alpha = 0.7f) else if (d.isWeekend) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(d.date.dayOfMonth.toString(), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = if (sel) BrandDark else MaterialTheme.colorScheme.onSurface)
                        Spacer(Modifier.height(3.dp))
                        Box(Modifier.size(6.dp).clip(CircleShape).background(if (d.dayType.isBlank()) MaterialTheme.colorScheme.outline else if (sel) BrandDark else c))
                    }
                }
            }
            Spacer(Modifier.height(10.dp))

            // Current page label + jump to today
            val cur = days.getOrNull(pager.currentPage)
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(cur?.let { RealTime.longKey(it.dateKey) } ?: "", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                val todayIdx = days.indexOfFirst { it.isToday }
                if (todayIdx >= 0 && todayIdx != pager.currentPage) TextButton(onClick = { scope.launch { pager.animateScrollToPage(todayIdx) } }, contentPadding = PaddingValues(horizontal = 10.dp)) {
                    Icon(Icons.Default.Today, null, Modifier.size(16.dp)); Spacer(Modifier.width(4.dp)); Text("Today")
                }
            }
            Spacer(Modifier.height(6.dp))

            // Card pager - swipe between days, neighbours peek at the edges
            HorizontalPager(
                state = pager,
                contentPadding = PaddingValues(horizontal = 22.dp),
                pageSpacing = 12.dp,
                verticalAlignment = Alignment.Top,
                modifier = Modifier.fillMaxWidth().height(384.dp),
            ) { i ->
                val d = days[i]
                // Every card shares one fixed height; the non-focused neighbours shrink and fade a little
                val offset = ((pager.currentPage - i) + pager.currentPageOffsetFraction).absoluteValue.coerceIn(0f, 1f)
                DayCard(d, vm.specialDays,
                    Modifier.fillMaxSize().graphicsLayer {
                        val sc = lerp(0.94f, 1f, 1f - offset)
                        scaleX = sc; scaleY = sc
                        alpha = lerp(0.72f, 1f, 1f - offset)
                        transformOrigin = TransformOrigin(0.5f, 0f)
                    },
                    onItem = { vm.selectedItem.value = it },
                    onItemLong = { moveItem = it to d },
                    onEmpty = { pinTarget = d })
            }
        }

        // sdVersion is read here so day cards refresh when holiday feeds finish syncing
        Text("Special days: $sdStatus" + if (sdVersion > 0) " · synced" else "", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
        Spacer(Modifier.height(40.dp))
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
                        items(candidates) {
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

/**
 * One planner day, styled after the reference design: light card with yellow top edge (today = solid yellow),
 * holiday ribbon with flag + country (tap to cycle when several), date badge, type pill, content box, slot rows.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DayCard(d: PlannedDay, specialDays: SpecialDays, modifier: Modifier = Modifier, onItem: (QueueItem) -> Unit, onItemLong: (QueueItem) -> Unit, onEmpty: () -> Unit) {
    val today = d.isToday
    val special = specialDays.forDate(d.dateKey)
    val cardBg = if (today) BrandYellow else PlannerCard
    val ink = BrandDark
    val muted = if (today) BrandDark.copy(alpha = 0.65f) else PlannerMuted
    val rowBg = if (today) Color.White.copy(alpha = 0.55f) else PlannerCream
    val hasType = d.dayType.isNotBlank()
    val filled = d.slots.count { it != null }

    val cardShape = RoundedCornerShape(22.dp)
    Column(
        modifier
            .shadow(elevation = 18.dp, shape = cardShape, ambientColor = BrandYellow.copy(alpha = 0.35f), spotColor = Color.Black.copy(alpha = 0.6f))
            .clip(cardShape)
            .background(Brush.verticalGradient(listOf(cardBg, if (today) BrandAmber.copy(alpha = 0.9f).compositeOver(BrandYellow) else Color(0xFFFFF6DA))))
            .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.9f), Color.White.copy(alpha = 0.15f))), cardShape)
    ) {
        // ---- Holiday ribbon / top edge
        if (special.isNotEmpty()) {
            HolidayBanner(special, Modifier.fillMaxWidth())
        } else {
            Box(Modifier.fillMaxWidth().height(6.dp).background(if (today) BrandAmber else BrandYellow))
        }

        Column(Modifier.padding(14.dp)) {
            // ---- Header: date badge + weekday + type pill
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(44.dp).shadow(6.dp, RoundedCornerShape(13.dp), spotColor = BrandDark.copy(alpha = 0.45f)).clip(RoundedCornerShape(13.dp)).background(Brush.verticalGradient(listOf(if (today) Color(0xFF3A3320) else Color(0xFFFFE566), if (today) BrandDark else BrandAmber))), contentAlignment = Alignment.Center) {
                    Text(d.date.dayOfMonth.toString(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold, color = if (today) BrandYellow else BrandDark)
                }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(if (today) "TODAY" else d.date.dayOfWeek.name.take(3), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, letterSpacing = 0.8.sp, color = if (!today && d.isWeekend) MaterialTheme.colorScheme.error else ink)
                    Text(d.date.month.name.take(3), style = MaterialTheme.typography.labelSmall, letterSpacing = 0.8.sp, color = muted)
                }
                if (hasType) TypePill(d.dayType)
                else Text("$filled/${d.slotCount}", style = MaterialTheme.typography.labelMedium, color = muted)
            }
            Spacer(Modifier.height(12.dp))

            // ---- Content box
            Column(
                Modifier.fillMaxWidth()
                    .shadow(6.dp, RoundedCornerShape(14.dp), spotColor = BrandDark.copy(alpha = 0.35f))
                    .clip(RoundedCornerShape(14.dp))
                    .background(Brush.verticalGradient(listOf(Color.White.copy(alpha = if (today) 0.75f else 1f), rowBg)))
                    .border(1.dp, if (today) BrandDark.copy(alpha = 0.14f) else BrandYellow.copy(alpha = 0.6f), RoundedCornerShape(14.dp))
                    .padding(horizontal = 12.dp, vertical = 9.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if (today) "TODAY'S CONTENT" else "CONTENT", fontSize = 9.5.sp, lineHeight = 11.sp, letterSpacing = 1.sp, fontWeight = FontWeight.Bold, color = muted, modifier = Modifier.weight(1f))
                    Text("$filled/${d.slotCount}", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = if (d.slotCount > 0 && filled >= d.slotCount) PlannerOk else muted)
                }
                Text(if (hasType) ContentTypes.dayUi(d.dayType).label else "No type has ${ContentTypes.MIN_STOCK_FOR_DAY}+ files", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (d.switchedFrom != null) {
                    Text("${ContentTypes.dayUi(d.switchedFrom).short} skipped (< ${ContentTypes.MIN_STOCK_FOR_DAY} files)", style = MaterialTheme.typography.labelSmall, color = PlannerWarn, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Spacer(Modifier.height(10.dp))

            // ---- Slots
            if (d.slotCount == 0) {
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(PlannerOk.copy(alpha = if (today) 0.18f else 0.12f)).padding(horizontal = 12.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.CheckCircle, null, Modifier.size(18.dp), tint = PlannerOk)
                    Spacer(Modifier.width(8.dp))
                    Text("All uploads done for this day", color = PlannerOk, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelMedium)
                }
            } else {
                d.slots.forEachIndexed { i, it ->
                    if (i > 0) Spacer(Modifier.height(8.dp))
                    if (it == null) {
                        Row(
                            Modifier.fillMaxWidth().height(52.dp).clip(RoundedCornerShape(14.dp))
                                .background(BrandDark.copy(alpha = if (today) 0.06f else 0.035f))
                                .border(1.5.dp, BrandDark.copy(alpha = 0.18f), RoundedCornerShape(14.dp))
                                .clickable(onClick = onEmpty).padding(horizontal = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            IconDot(Icons.Default.Add, ink, BrandDark.copy(alpha = 0.08f))
                            Spacer(Modifier.width(10.dp))
                            Column {
                                Text("EMPTY SLOT", fontSize = 9.5.sp, lineHeight = 11.sp, letterSpacing = 0.8.sp, fontWeight = FontWeight.Bold, color = muted)
                                Text("Tap to pin a file", style = MaterialTheme.typography.bodySmall, color = ink)
                            }
                        }
                    } else {
                        val c = typeColor(it.dayType)
                        Row(
                            Modifier.fillMaxWidth().height(IntrinsicSize.Min)
                                .shadow(5.dp, RoundedCornerShape(14.dp), spotColor = BrandDark.copy(alpha = 0.4f))
                                .clip(RoundedCornerShape(14.dp))
                                .background(Brush.horizontalGradient(listOf(Color.White.copy(alpha = if (today) 0.8f else 1f), rowBg)))
                                .border(1.dp, Color.White.copy(alpha = 0.7f), RoundedCornerShape(14.dp))
                                .combinedClickable(onClick = { onItem(it) }, onLongClick = { onItemLong(it) }),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Box(Modifier.width(5.dp).fillMaxHeight().background(Brush.verticalGradient(listOf(if (today) BrandDark else BrandYellow, if (today) BrandDark.copy(alpha = 0.7f) else BrandAmber))))
                            Row(Modifier.weight(1f).padding(start = 10.dp, end = 10.dp, top = 9.dp, bottom = 9.dp), verticalAlignment = Alignment.CenterVertically) {
                                IconDot(typeIcon(it.dayType), BrandDark, c.copy(alpha = 0.35f))
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(ContentTypes.dayUi(it.dayType).short.uppercase(), fontSize = 9.5.sp, lineHeight = 11.sp, letterSpacing = 0.8.sp, fontWeight = FontWeight.Bold, color = muted)
                                    Text(it.displayTitle, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                }
                                if (it.isPinned) {
                                    Spacer(Modifier.width(6.dp))
                                    Icon(Icons.Default.PushPin, "Pinned", Modifier.size(15.dp), tint = ink.copy(alpha = 0.6f))
                                }
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
                if (item.isPinned) TextButton(onClick = onUnpin) { Icon(Icons.Default.Close, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.error); Spacer(Modifier.width(6.dp)); Text("Unpin (back to auto)", color = MaterialTheme.colorScheme.error) }
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
