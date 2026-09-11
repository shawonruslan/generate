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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.ui.text.style.TextDecoration
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.domain.PlannedRun
import com.zedge.contentstudio.domain.RunSchedule
import com.zedge.contentstudio.domain.SchedulePlan
import com.zedge.contentstudio.ui.theme.Danger
import androidx.compose.material.icons.filled.Today
import androidx.compose.material3.AlertDialog
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import kotlinx.coroutines.delay
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.material.icons.filled.HourglassEmpty
import com.zedge.contentstudio.ui.components.SectionCard
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
private val PlannerInfo = Color(0xFF0B7FB5)

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

        // Exact run times today - all four accounts (pure math, mirrors the workflow gate hash)
        val activeKey by vm.activeKey.collectAsStateWithLifecycle()
        TodayRunStrip(activeKey, plan)
        Spacer(Modifier.height(12.dp))

        // v9: edit upload windows (saved to Firebase, read by the bot) + cron health
        ScheduleSettingsCard(vm, activeKey)
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
                    if (i > 0) Spacer(Modifier.height(10.dp))
                    SlotCard(index = i, item = it, run = d.runAt(i), hasRunInfo = d.runs.isNotEmpty(), today = today, onItem = onItem, onItemLong = onItemLong, onEmpty = onEmpty)
                }
            }
        }
    }
}

// ---------------- v12: professional slot cards (same design as the web panel) ----------------
private data class SlotTone(val c1: Color, val c2: Color, val soft: Color, val ink: Color)
private fun slotTone(type: String?): SlotTone = when (if (type == "RINGTONE") "AUDIO" else type) {
    "AUDIO" -> SlotTone(Color(0xFFFF9F1A), Color(0xFFE05D00), Color(0xFFFFF1E0), Color(0xFFB4520A))
    "WALLPAPER" -> SlotTone(Color(0xFFFFE14D), Color(0xFFF2B400), Color(0xFFFFF8D6), Color(0xFF8A6A00))
    else -> SlotTone(Color(0xFFFFCF5C), Color(0xFFC98A00), Color(0xFFFFF3C4), Color(0xFF7A5A00))
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SlotCard(index: Int, item: QueueItem?, run: PlannedRun?, hasRunInfo: Boolean, today: Boolean, onItem: (QueueItem) -> Unit, onItemLong: (QueueItem) -> Unit, onEmpty: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    val passed = hasRunInfo && run?.passed == true
    val live = hasRunInfo && run?.live == true
    val isNext = hasRunInfo && run?.isNext == true && !live
    val ringColor = when {
        live -> Color(0xFFFF8A00)
        isNext -> Color(0xFF22C55E)
        item == null -> if (today) BrandDark.copy(alpha = 0.35f) else Color(0xFFE3D9BF)
        else -> if (today) BrandDark.copy(alpha = 0.14f) else Color(0xFFEFE6CC)
    }
    val ringW = if (live || isNext) 2.dp else 1.dp
    val tone = slotTone(item?.dayType)
    val cardAlpha = if (passed) 0.72f else 1f
    val glow = when { live -> Color(0xFFFF8A00); isNext -> Color(0xFF22C55E); else -> BrandDark }
    val base = Modifier.fillMaxWidth()
        .graphicsLayer { this.alpha = cardAlpha }
        .shadow(if (live) 10.dp else 5.dp, shape, spotColor = glow.copy(alpha = 0.45f))
        .clip(shape)
        .background(if (item == null) (if (today) Color.White.copy(alpha = 0.28f) else Color(0xFFFFFCF5)) else Color.White)
        .border(ringW, ringColor, shape)
    val clickMod = if (item == null) base.clickable(onClick = onEmpty) else base.combinedClickable(onClick = { onItem(item) }, onLongClick = { onItemLong(item) })
    Row(clickMod.height(IntrinsicSize.Min)) {
        if (item != null) Box(Modifier.width(4.dp).fillMaxHeight().background(Brush.verticalGradient(listOf(tone.c1, tone.c2))))
        Column(Modifier.weight(1f)) {
            // ---- header band: type chip + SLOT n
            Row(
                Modifier.fillMaxWidth()
                    .then(if (item == null) Modifier else Modifier.background(Brush.verticalGradient(listOf(Color(0xFFFFFDF6), Color(0xFFFFF8E6)))))
                    .padding(start = 10.dp, end = 8.dp, top = 5.dp, bottom = 5.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (item == null) SlotChip(Icons.Default.Add, "EMPTY SLOT", Color(0xFFF3F0E6), Color(0xFF8A7B55))
                else SlotChip(typeIcon(item.dayType), ContentTypes.dayUi(item.dayType).label.uppercase(), tone.soft, tone.ink)
                Spacer(Modifier.width(6.dp))
                Text("SLOT ${index + 1}", fontSize = 9.sp, lineHeight = 11.sp, letterSpacing = 0.8.sp, fontWeight = FontWeight.ExtraBold, color = Color(0xFFB3A57F))
                Spacer(Modifier.weight(1f))
                if (hasRunInfo && run != null) RunStatusBadge(run)   // v12c compact
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(if (item == null) Color(0xFFEAE2CA) else Color(0xFFF4ECD6)))
            // ---- body
            Column(Modifier.fillMaxWidth().padding(start = 10.dp, end = 8.dp, top = 6.dp, bottom = 7.dp)) {
                if (item != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (item.isPinned) {
                            Icon(Icons.Default.PushPin, "Pinned", Modifier.size(11.dp), tint = Color(0xFFA89E85))
                            Spacer(Modifier.width(4.dp))
                        }
                        Text(item.displayTitle, fontSize = 13.sp, lineHeight = 17.sp, fontWeight = FontWeight.ExtraBold, color = BrandDark, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                } else {
                    Text("Tap to pin a file", fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold, color = if (today) Color(0xFF6B5510) else Color(0xFFA89E85))
                }
                if (hasRunInfo) RunMetaRow(run)
            }
        }
    }
}

@Composable
private fun SlotChip(icon: ImageVector, text: String, bg: Color, fg: Color) {
    Row(Modifier.clip(CircleShape).background(bg).padding(horizontal = 9.dp, vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(10.dp), tint = fg)
        Spacer(Modifier.width(4.dp))
        Text(text, fontSize = 9.sp, lineHeight = 11.sp, letterSpacing = 0.6.sp, fontWeight = FontWeight.ExtraBold, color = fg, maxLines = 1)
    }
}

@Composable
private fun MetaPill(icon: ImageVector, text: String, fg: Color, bg: Color, border: Color, strike: Boolean = false) {
    val shape = RoundedCornerShape(8.dp)
    Row(Modifier.clip(shape).background(bg).border(1.dp, border, shape).padding(horizontal = 8.dp, vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(10.dp), tint = fg.copy(alpha = 0.8f))
        Spacer(Modifier.width(4.dp))
        Text(text, fontSize = 10.5.sp, lineHeight = 13.sp, fontWeight = FontWeight.Bold, color = fg, maxLines = 1, overflow = TextOverflow.Ellipsis, textDecoration = if (strike) TextDecoration.LineThrough else TextDecoration.None)
    }
}

@Composable
private fun StatusBadge(text: String, icon: ImageVector?, bg: Brush, fg: Color, pulse: Boolean = false) {
    var on by remember { mutableStateOf(true) }
    if (pulse) LaunchedEffect(Unit) { while (true) { delay(700L); on = !on } }
    Row(Modifier.graphicsLayer { alpha = if (pulse && !on) 0.55f else 1f }.clip(CircleShape).background(bg).padding(horizontal = 8.dp, vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) {
            Icon(icon, null, Modifier.size(9.dp), tint = fg)
            Spacer(Modifier.width(3.dp))
        }
        Text(text, fontSize = 8.5.sp, lineHeight = 10.sp, letterSpacing = 0.5.sp, fontWeight = FontWeight.ExtraBold, color = fg, maxLines = 1)
    }
}

@Composable
private fun RunStatusBadge(run: PlannedRun) {
    when {
        run.passed -> StatusBadge("PASSED", Icons.Default.Check, SolidColor(Color(0xFFEFE6CC)), Color(0xFF8A6D00))
        run.live -> StatusBadge("RUNNING", Icons.Default.Bolt, Brush.linearGradient(listOf(Color(0xFFFF9F1A), Color(0xFFE05D00))), Color.White, pulse = true)
        run.isNext -> StatusBadge("NEXT UP", Icons.Default.SkipNext, Brush.linearGradient(listOf(Color(0xFF22C55E), Color(0xFF15803D))), Color.White)
        else -> StatusBadge("SCHEDULED", null, SolidColor(Color(0xFFF3F0E6)), Color(0xFF8A7B55))
    }
}

/** v12c compact: one row = time pill + profile pill + inline flip-clock (status badge lives in the header). */
@Composable
private fun RunMetaRow(run: PlannedRun?) {
    Spacer(Modifier.height(5.dp))
    if (run == null) {
        val shape = RoundedCornerShape(8.dp)
        Row(Modifier.fillMaxWidth().clip(shape).background(Color(0xFFFFF0F0)).border(1.dp, Color(0xFFFFD6D6), shape).padding(horizontal = 8.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("No run slot left this day (max 3) - rolls to next day", fontSize = 10.sp, lineHeight = 13.sp, fontWeight = FontWeight.Bold, color = Danger, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        return
    }
    val timeTxt = "${run.startLabel} \u2013 ${run.endLabel}"
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        if (run.passed) MetaPill(Icons.Default.Schedule, timeTxt, Color(0xFFA89E85), Color(0xFFF5F2EA), Color(0xFFEAE4D3), strike = true)
        else MetaPill(Icons.Default.Schedule, timeTxt, Color(0xFF0B6FA0), Color(0xFFEAF6FC), Color(0xFFD3EBF6))
        MetaPill(Icons.Default.Person, run.profileLabel, Color(0xFF5C5138), Color(0xFFF7F3E8), Color(0xFFEFE6CC))
    }
    if (!run.passed && run.startMs > 0L) {
        Spacer(Modifier.height(4.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            RunCountdown(run.startMs, run.endMs, run.windowEndMs, compact = true, inline = true)
        }
    }
}

/** Countdown look shared by the slot footer band and the compact today-strip timer. */
private data class CdLook(val state: String, val label: String, val icon: ImageVector, val top: Color, val bottom: Color, val digit: Color, val labelColor: Color, val left: Long, val pulse: Boolean = false)
private fun cdLook(now: Long, startMs: Long, endMs: Long, windowEndMs: Long): CdLook = when {
    now < startMs -> {
        val left = startMs - now
        if (left <= 15 * 60_000L) CdLook("soon", "UPLOAD IN", Icons.Default.HourglassEmpty, Color(0xFF0F5F3A), Color(0xFF073B24), Color(0xFFB6FFD2), Ok, left)
        else CdLook("wait", "UPLOAD IN", Icons.Default.HourglassEmpty, Color(0xFF1B2430), Color(0xFF0F151D), Color(0xFF7FE3FF), PlannerInfo, left)
    }
    now <= endMs -> CdLook("live", "UPLOADING NOW", Icons.Default.Bolt, Color(0xFFFF8A00), Color(0xFFC85C00), Color(0xFFFFF7E6), Color(0xFFC85C00), endMs - now, pulse = true)
    now <= windowEndMs -> CdLook("catch", "CATCH-UP CLOSES IN", Icons.Default.Sync, Color(0xFF6B4A00), Color(0xFF3D2A00), Color(0xFFFFD66B), Color(0xFF8A4B00), windowEndMs - now)
    else -> CdLook("passed", "WINDOW PASSED", Icons.Default.Schedule, Color(0xFFD9D3C2), Color(0xFFC4BDA9), Color(0xFF6F6650), PlannerMuted, 0L)
}

@Composable
private fun FlipBlocks(look: CdLook, blink: Boolean, compact: Boolean) {
    var sec = (look.left / 1000).coerceAtLeast(0)
    val days = sec / 86400; sec -= days * 86400
    val hrs = sec / 3600; sec -= hrs * 3600
    val mins = sec / 60; sec -= mins * 60
    Row(verticalAlignment = Alignment.Top) {
        if (days > 0) {
            FlipBlock(days, "DAYS", look.top, look.bottom, look.digit, compact)
            FlipSep(look.labelColor, blink, compact)
        }
        FlipBlock(hrs, "HRS", look.top, look.bottom, look.digit, compact)
        FlipSep(look.labelColor, blink, compact)
        FlipBlock(mins, "MIN", look.top, look.bottom, look.digit, compact)
        FlipSep(look.labelColor, blink, compact)
        FlipBlock(sec, "SEC", look.top, look.bottom, look.digit, compact)
    }
}

/** v11: flip-clock style countdown (compact variant used in the today strip). */
@Composable
private fun RunCountdown(startMs: Long, endMs: Long, windowEndMs: Long, compact: Boolean = false, inline: Boolean = false) {
    var now by remember { mutableStateOf(RealTime.now()) }
    LaunchedEffect(startMs) {
        while (true) { now = RealTime.now(); delay(1000L - (now % 1000L)) }
    }
    val look = cdLook(now, startMs, endMs, windowEndMs)
    val blink = (now / 500) % 2 == 0L
    if (inline) {
        if (look.left <= 0L) return
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(look.icon, null, Modifier.size(11.dp), tint = look.labelColor.copy(alpha = if (look.pulse && !blink) 0.35f else 1f))
            Spacer(Modifier.width(4.dp))
            FlipBlocks(look, blink, compact = true)
        }
        return
    }
    Column(horizontalAlignment = if (compact) Alignment.End else Alignment.Start) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(look.icon, null, Modifier.size(if (compact) 10.dp else 11.dp), tint = look.labelColor.copy(alpha = if (look.pulse && !blink) 0.35f else 1f))
            Spacer(Modifier.width(3.dp))
            Text(look.label, fontSize = if (compact) 8.sp else 9.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp, color = look.labelColor)
        }
        if (look.left > 0L) {
            Spacer(Modifier.height(2.dp))
            FlipBlocks(look, blink, compact)
        }
    }
}

@Composable
private fun FlipBlock(value: Long, unit: String, top: Color, bottom: Color, digit: Color, compact: Boolean) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .widthIn(min = if (compact) 26.dp else 34.dp)
            .clip(RoundedCornerShape(if (compact) 5.dp else 7.dp))
            .background(Brush.verticalGradient(listOf(top, bottom)))
            .padding(horizontal = if (compact) 4.dp else 5.dp, vertical = if (compact) 2.dp else 3.dp)
    ) {
        Text("%02d".format(value), fontSize = if (compact) 12.sp else 16.sp, lineHeight = if (compact) 14.sp else 18.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace, color = digit, maxLines = 1)
        Text(unit, fontSize = if (compact) 6.5.sp else 7.5.sp, lineHeight = 9.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 1.sp, color = digit.copy(alpha = 0.7f), maxLines = 1)
    }
}

@Composable
private fun FlipSep(color: Color, blink: Boolean, compact: Boolean) {
    Text(":", fontSize = if (compact) 12.sp else 16.sp, lineHeight = if (compact) 18.sp else 24.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace,
        color = color.copy(alpha = if (blink) 1f else 0.25f), modifier = Modifier.padding(horizontal = 2.dp))
}

private fun fmtCountdown(ms: Long): String {
    var s = (ms / 1000).coerceAtLeast(0)
    val d = s / 86400; s -= d * 86400
    val h = s / 3600; s -= h * 3600
    val m = s / 60; s -= m * 60
    val core = "%02d:%02d:%02d".format(h, m, s)
    return if (d > 0) "${d}d $core" else core
}

/** Today's exact upload times for every account (the active one is highlighted). */
@Composable
private fun ScheduleSettingsCard(vm: MainViewModel, activeKey: String) {
    val schedules by vm.schedules.collectAsStateWithLifecycle()
    val sources by vm.scheduleSource.collectAsStateWithLifecycle()
    val health by vm.gateHealth.collectAsStateWithLifecycle()
    val tick by RealTime.tick.collectAsStateWithLifecycle()
    SectionCard(title = "Upload schedule & cron health", subtitle = "3 windows/day per account. Bot reads these from Firebase - set every cron-job.org job to  0,30 * * * *  (Asia/Dhaka)") {
        Accounts.all.forEach { acc ->
            val live = schedules[acc.key] ?: RunSchedule.DEFAULT_WINDOWS.getValue(acc.key)
            var draft by remember(acc.key, live) { mutableStateOf(live) }
            val dirty = draft != live
            val err = RunSchedule.validate(draft)
            val g = health[acc.key]
            val isActive = acc.key == activeKey
            // v12d settings: theme-aware account card (works on dark + light)
            val cs = MaterialTheme.colorScheme
            val shape = RoundedCornerShape(14.dp)
            Column(
                Modifier.fillMaxWidth().padding(vertical = 5.dp).clip(shape)
                    .background(if (isActive) BrandYellow.copy(alpha = 0.10f).compositeOver(cs.surfaceContainerHigh) else cs.surfaceContainerHigh)
                    .border(if (isActive) 1.5.dp else 1.dp, if (isActive) BrandYellow else cs.outline.copy(alpha = 0.5f), shape)
                    .padding(10.dp)
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(acc.label, fontWeight = FontWeight.ExtraBold, fontSize = 13.sp, color = cs.onSurface)
                    if (isActive) {
                        Spacer(Modifier.width(6.dp))
                        Text("ACTIVE", fontSize = 8.sp, lineHeight = 10.sp, letterSpacing = 0.8.sp, fontWeight = FontWeight.Black, color = BrandDark,
                            modifier = Modifier.clip(RoundedCornerShape(999.dp)).background(BrandYellow).padding(horizontal = 6.dp, vertical = 2.dp))
                    }
                    Spacer(Modifier.weight(1f))
                    Text(if (sources[acc.key] == "firebase") "saved in Firebase" else "default (yml)", fontSize = 10.sp, color = cs.onSurfaceVariant)
                }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    draft.forEachIndexed { i, h ->
                        var open by remember { mutableStateOf(false) }
                        Box(Modifier.weight(1f)) {
                            Column(
                                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(cs.surfaceContainerHighest)
                                    .border(1.dp, cs.outline.copy(alpha = 0.6f), RoundedCornerShape(10.dp))
                                    .clickable { open = true }.padding(horizontal = 8.dp, vertical = 6.dp)
                            ) {
                                Text("WINDOW ${i + 1}", fontSize = 8.sp, lineHeight = 10.sp, letterSpacing = 0.8.sp, fontWeight = FontWeight.Bold, color = cs.onSurfaceVariant)
                                Text(RunSchedule.hourLabel(h), fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.ExtraBold, color = BrandYellow, maxLines = 1)
                                Text("to " + RunSchedule.hourLabel((h + RunSchedule.WINDOW_HOURS) % 24), fontSize = 10.sp, lineHeight = 12.sp, color = cs.onSurfaceVariant, maxLines = 1)
                            }
                            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                                (0..21).forEach { hh ->
                                    DropdownMenuItem(text = { Text(RunSchedule.hourLabel(hh), fontSize = 12.sp) }, onClick = {
                                        draft = draft.toMutableList().also { it[i] = hh }; open = false
                                    })
                                }
                            }
                        }
                    }
                }
                if (err != null) Text(err, fontSize = 11.sp, color = Danger, modifier = Modifier.padding(top = 6.dp))
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { vm.saveSchedule(acc.key, draft.sorted()) }, enabled = dirty && err == null, contentPadding = PaddingValues(horizontal = 14.dp, vertical = 4.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = BrandYellow, contentColor = BrandDark, disabledContainerColor = cs.surfaceContainerHighest, disabledContentColor = cs.onSurfaceVariant.copy(alpha = 0.5f))) {
                        Text(if (dirty) "Save schedule" else "Saved", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                    OutlinedButton(onClick = { draft = RunSchedule.DEFAULT_WINDOWS.getValue(acc.key) }, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = cs.onSurface)) {
                        Text("Default", fontSize = 12.sp)
                    }
                }
                // cron health (tick keeps "x min ago" fresh)
                val ago = remember(tick, g) { g?.minutesSincePing }
                val (pingColor, pingText) = when {
                    g == null || ago == null -> Danger to "no ping yet - check cron-job.org"
                    ago <= 45 -> Ok to "$ago min ago (${g.lastPingDhaka ?: ""})"
                    ago <= 120 -> Warn to "$ago min ago - a ping was missed"
                    else -> Danger to "${ago / 60} h ago - cron-job.org ping missing!"
                }
                Spacer(Modifier.height(8.dp))
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(cs.surfaceContainerLow).padding(horizontal = 10.dp, vertical = 7.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    HealthLine("Cron ping", pingText, pingColor, cs.onSurfaceVariant)
                    HealthLine("Last decision", (g?.lastDecision ?: "-") + (g?.lastRunDhaka?.let { "  \u00b7  last run $it" } ?: ""), cs.onSurface, cs.onSurfaceVariant)
                    HealthLine("Runs today", g?.runsToday?.takeIf { it.isNotEmpty() }?.joinToString("  \u00b7  ") ?: "none yet", cs.onSurface, cs.onSurfaceVariant)
                    if (g?.windowsUsed != null && g.windowsUsed != live) {
                        Text("Bot last used ${g.windowsUsed} - it picks up the new schedule on its next ping.", fontSize = 10.sp, lineHeight = 13.sp, color = Warn)
                    }
                }
            }
        }
    }
}

@Composable
private fun HealthLine(label: String, value: String, valueColor: Color, labelColor: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(6.dp).clip(CircleShape).background(valueColor))
        Spacer(Modifier.width(6.dp))
        Text("$label: ", fontSize = 11.sp, lineHeight = 14.sp, color = labelColor)
        Text(value, fontSize = 11.sp, lineHeight = 14.sp, color = valueColor, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun TodayRunStrip(activeKey: String, plan: SchedulePlan) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("TODAY'S UPLOAD TIMES", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
            Text("slot + 0-14 min delay", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Accounts.all.forEach { acc ->
                val isActive = acc.key == activeKey
                val runs = RunSchedule.todayRuns(acc.key)
                Column(
                    Modifier.width(150.dp).clip(RoundedCornerShape(14.dp))
                        .background(if (isActive) BrandYellow.copy(alpha = 0.25f) else MaterialTheme.colorScheme.surfaceContainerHigh)
                        .border(1.dp, if (isActive) BrandYellow else MaterialTheme.colorScheme.outline.copy(alpha = 0.4f), RoundedCornerShape(14.dp))
                        .padding(10.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(acc.label, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                        if (isActive) Text("active", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Spacer(Modifier.height(6.dp))
                    runs.forEachIndexed { i, r ->
                        // For the active account we also know the file + profile from the plan
                        val slotIdx = i - plan.rule.uploadedToday
                        val todayDay = plan.days.firstOrNull { it.isToday }
                        val item = if (isActive && slotIdx >= 0) todayDay?.slots?.getOrNull(slotIdx) else null
                        val pr = if (isActive && slotIdx >= 0) todayDay?.runAt(slotIdx) else null
                        val done = isActive && i < plan.rule.uploadedToday
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("${i + 1}.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.width(4.dp))
                            Text(
                                RunSchedule.clock(r.start),
                                style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
                                color = when { done -> Ok; r.passed -> MaterialTheme.colorScheme.onSurfaceVariant; r.live -> Ok; else -> PlannerInfo },
                                textDecoration = if (r.passed && !done) TextDecoration.LineThrough else null,
                            )
                            if (done) { Spacer(Modifier.width(4.dp)); Icon(Icons.Default.CheckCircle, null, Modifier.size(12.dp), tint = Ok) }
                            if (!done && !r.passed && r.startMs > 0L) { Spacer(Modifier.weight(1f)); RunCountdown(r.startMs, r.endMs, r.windowEndMs, compact = true) }
                        }
                        if (isActive) {
                            Text(
                                when {
                                    done -> "uploaded"
                                    item != null -> "${item.displayTitle} · ${pr?.profileLabel ?: ""}"
                                    pr != null -> "empty slot · ${pr.profileLabel}"
                                    else -> "-"
                                },
                                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            )
                        }
                        if (i < runs.lastIndex) Spacer(Modifier.height(4.dp))
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
