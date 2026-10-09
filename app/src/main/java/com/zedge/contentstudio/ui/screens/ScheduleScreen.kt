package com.zedge.contentstudio.ui.screens

import androidx.compose.material.icons.filled.HourglassBottom
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
import com.zedge.contentstudio.domain.GateHealth
import com.zedge.contentstudio.domain.PlannedRun
import com.zedge.contentstudio.domain.RunSchedule
import com.zedge.contentstudio.domain.SlotSpec
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import com.zedge.contentstudio.domain.SchedulePlan
import com.zedge.contentstudio.ui.theme.Danger
import androidx.compose.material.icons.filled.Today
import androidx.compose.material3.AlertDialog
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material.icons.filled.ArrowForward
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
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Switch
import com.zedge.contentstudio.data.VarietyConfig
import com.zedge.contentstudio.ui.theme.ThemeState
import com.zedge.contentstudio.ui.theme.mixColor

// v27.8 planner palette follows Theme Studio - readable on light AND dark themes (no more cream-on-dark)
private val PlannerCard: Color get() = ThemeState.palette.card
private val PlannerCream: Color get() = mixColor(ThemeState.palette.card, ThemeState.palette.primary, 0.16f)
private val PlannerMuted: Color get() = ThemeState.palette.muted
private val PlannerOk: Color get() = if (ThemeState.palette.isDark) Color(0xFF4ADE80) else Color(0xFF1F8A4C)
private val PlannerWarn: Color get() = if (ThemeState.palette.isDark) Color(0xFFFBBF24) else Color(0xFF9A6B00)
private val PlannerInfo: Color get() = if (ThemeState.palette.isDark) Color(0xFF7FD4FF) else Color(0xFF0B7FB5)
private val PlannerSoft: Color get() = mixColor(ThemeState.palette.card, ThemeState.palette.text, 0.07f)
private val PlannerLine: Color get() = ThemeState.palette.line
private fun readable(c: Color): Color = if (ThemeState.palette.isDark) mixColor(c, Color.White, 0.45f) else c
private fun softOf(c: Color): Color = mixColor(ThemeState.palette.card, c, if (ThemeState.palette.isDark) 0.22f else 0.14f)

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
            StatTile("Left today", "${plan.rule.remaining}", Modifier.weight(1f), BrandAmber, hint = ContentTypes.dayUi(plan.rule.type).label, icon = Icons.Default.HourglassBottom) // v27.9 icons
            StatTile("Uploaded today", "${plan.rule.uploadedToday} / ${ContentTypes.DAILY_LIMIT}", Modifier.weight(1f), Ok, hint = if (synced) "Live time" else "Device clock", icon = Icons.Default.CheckCircle)
        }
        Spacer(Modifier.height(12.dp))

        // v16 schedule overview first: visible above the calendar.
        Text("All accounts, queue & schedule settings", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
        // Exact run times today - all four accounts (pure math, mirrors the workflow gate hash)
        val activeKey by vm.activeKey.collectAsStateWithLifecycle()
        val stripHealth by vm.gateHealth.collectAsStateWithLifecycle()   // v13 cross-account
        TodayRunStrip(activeKey, plan, stripHealth, Modifier.padding(horizontal = 16.dp))
        Spacer(Modifier.height(12.dp))

        // v9: edit upload windows (saved to Firebase, read by the bot) + cron health
        ScheduleSettingsCard(vm, activeKey)
        Spacer(Modifier.height(12.dp))

        // v25: Mix mode - 3 slots = 3 different content types (dashboardSettings/variety)
        MixModeCard(vm, activeKey)
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



        Text("Schedule calendar", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp))
        Text("Dhaka time · Estimated slots · Swipe to change day", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
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
                if (todayIdx >= 0) TextButton(onClick = { scope.launch { pager.animateScrollToPage(todayIdx) } }, contentPadding = PaddingValues(horizontal = 10.dp)) {
                    Icon(Icons.Default.Today, null, Modifier.size(16.dp)); Spacer(Modifier.width(4.dp)); Text("Today")
                }
            }
            Spacer(Modifier.height(6.dp))

            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp).shadow(3.dp, RoundedCornerShape(14.dp)).clip(RoundedCornerShape(14.dp)).background(BrandYellow.copy(alpha = 0.14f)).border(1.dp, BrandYellow.copy(alpha = 0.35f), RoundedCornerShape(14.dp)).padding(horizontal = 4.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                TextButton(enabled = pager.currentPage > 0, onClick = { scope.launch { pager.animateScrollToPage((pager.currentPage - 1).coerceAtLeast(0)) } }) { Text("← Previous") }
                Text("${pager.currentPage + 1} / ${days.size} days", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(enabled = pager.currentPage < days.lastIndex, onClick = { scope.launch { pager.animateScrollToPage((pager.currentPage + 1).coerceAtMost(days.lastIndex)) } }) { Text("Next →") }
            }

            // Card pager - swipe between days, neighbours peek at the edges
            HorizontalPager(
                state = pager,
                contentPadding = PaddingValues(horizontal = 22.dp),
                pageSpacing = 12.dp,
                verticalAlignment = Alignment.Top,
                modifier = Modifier.fillMaxWidth(),   // v13b slot height: no fixed 384.dp clip
            ) { i ->
                val d = days[i]
                // v13b slot height: cards size to their own content, so all 3 slots are always visible
                val offset = ((pager.currentPage - i) + pager.currentPageOffsetFraction).absoluteValue.coerceIn(0f, 1f)
                DayCard(d, vm.specialDays,
                    Modifier.fillMaxWidth().graphicsLayer {
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
// ---------------- v12: professional slot cards (same design as the web panel) ----------------
private data class SlotTone(val c1: Color, val c2: Color, val soft: Color, val ink: Color)
private fun slotTone(type: String?): SlotTone = when (if (type == "RINGTONE") "AUDIO" else type) {
    "AUDIO" -> SlotTone(Color(0xFFFF9F1A), Color(0xFFE05D00), softOf(Color(0xFFFF9F1A)), readable(Color(0xFFB4520A)))
    "WALLPAPER" -> SlotTone(Color(0xFFFFE14D), Color(0xFFF2B400), softOf(Color(0xFFF2B400)), readable(Color(0xFF8A6A00)))
    else -> SlotTone(BrandYellow, BrandAmber, softOf(BrandYellow), readable(mixColor(BrandYellow, Color.Black, 0.45f)))
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
        run.passed -> StatusBadge("PASSED", Icons.Default.Check, SolidColor(PlannerSoft), PlannerMuted)
        run.live -> StatusBadge("RUNNING", Icons.Default.Bolt, Brush.linearGradient(listOf(Color(0xFFFF9F1A), Color(0xFFE05D00))), Color.White, pulse = true)
        run.isNext -> StatusBadge("NEXT UP", Icons.Default.SkipNext, Brush.linearGradient(listOf(Color(0xFF22C55E), Color(0xFF15803D))), Color.White)
        else -> StatusBadge("SCHEDULED", null, SolidColor(PlannerSoft), PlannerMuted)
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
    val timeTxt = run.rangeLabel
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        if (run.passed) MetaPill(Icons.Default.Schedule, timeTxt, PlannerMuted, PlannerSoft, PlannerLine, strike = true)
        else MetaPill(Icons.Default.Schedule, timeTxt, PlannerInfo, mixColor(PlannerCard, PlannerInfo, 0.14f), PlannerInfo.copy(alpha = 0.35f))
        MetaPill(Icons.Default.Person, run.profileLabel, ThemeState.palette.text.copy(alpha = 0.85f), PlannerSoft, PlannerLine)
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
    else -> CdLook("passed", "WINDOW PASSED", Icons.Default.Schedule, PlannerSoft, mixColor(PlannerCard, ThemeState.palette.text, 0.12f), PlannerMuted, PlannerMuted, 0L)
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
    val slotMap by vm.slots.collectAsStateWithLifecycle()
    SectionCard(title = "Upload schedule & cron health", subtitle = "3 uploads/day per account \u00b7 Window = random inside 3 h, Exact = that minute sharp (Dhaka). Keep cron-job.org at 0,30 * * * *") {
        Accounts.all.forEach { acc ->
            val live = slotMap[acc.key] ?: SlotSpec.fromWindows(schedules[acc.key] ?: RunSchedule.DEFAULT_WINDOWS.getValue(acc.key))
            var draft by remember(acc.key, live) { mutableStateOf(live) }
            var pickIdx by remember(acc.key) { mutableStateOf(-1) }
            var pickField by remember { mutableStateOf(0) }   // 0 = start/exact, 1 = window end
            val dirty = draft != live
            val err = RunSchedule.validateSlots(draft)
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
                // v23.1 stacked slot tiles (Window = random inside 3 h, Exact = sharp minute)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    draft.forEachIndexed { i, sl ->
                        SlotTile(
                            index = i, slot = sl,
                            onMode = { exact -> if (exact != sl.exact) draft = draft.toMutableList().also {
                                val e = minOf(23 * 60 + 59, sl.minutesOfDay + RunSchedule.WINDOW_HOURS * 60)
                                it[i] = if (exact) sl.copy(exact = true, endHour = sl.hour, endMinute = sl.minute) else sl.copy(exact = false, endHour = e / 60, endMinute = e % 60)
                            } },
                            onPickTime = { field -> pickIdx = i; pickField = field },
                        )
                    }
                }
                if (pickIdx in draft.indices) {
                    // v23.1 time picker (Asia/Dhaka): field 0 = start / exact time, 1 = window end
                    val cur = draft[pickIdx]
                    val isEnd = pickField == 1
                    val initMin = if (isEnd) cur.endMinutesOfDay else cur.minutesOfDay
                    val tp = rememberTimePickerState(initialHour = initMin / 60, initialMinute = initMin % 60, is24Hour = false)
                    val title = when { cur.exact -> "Slot ${pickIdx + 1} - exact upload time"; isEnd -> "Slot ${pickIdx + 1} - window ends"; else -> "Slot ${pickIdx + 1} - window starts" }
                    val hint = when { cur.exact -> "The bot uploads at this minute sharp."; isEnd -> "The bot picks one random minute before this time."; else -> "The bot picks one random minute after this time." }
                    AlertDialog(
                        onDismissRequest = { pickIdx = -1 },
                        title = { Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold) },
                        text = { Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) { TimePicker(state = tp); Text("Time is Asia/Dhaka. $hint", fontSize = 11.sp, color = cs.onSurfaceVariant) } },
                        confirmButton = {
                            TextButton(onClick = {
                                val idx = pickIdx
                                draft = draft.toMutableList().also {
                                    val o = it[idx]
                                    it[idx] = if (isEnd) o.copy(endHour = tp.hour, endMinute = tp.minute)
                                    else if (o.exact) o.copy(hour = tp.hour, minute = tp.minute, endHour = tp.hour, endMinute = tp.minute)
                                    else {
                                        val len = o.endMinutesOfDay - o.minutesOfDay
                                        val e = minOf(23 * 60 + 59, tp.hour * 60 + tp.minute + len)   // keep the window length when moving From
                                        o.copy(hour = tp.hour, minute = tp.minute, endHour = e / 60, endMinute = e % 60)
                                    }
                                }
                                pickIdx = -1
                            }) { Text("Set") }
                        },
                        dismissButton = { TextButton(onClick = { pickIdx = -1 }) { Text("Cancel") } },
                    )
                }
                if (err != null) Text(err, fontSize = 11.sp, color = Danger, modifier = Modifier.padding(top = 6.dp))
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { vm.saveSchedule(acc.key, draft.sortedBy { it.minutesOfDay }) }, enabled = dirty && err == null, contentPadding = PaddingValues(horizontal = 14.dp, vertical = 4.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = BrandYellow, contentColor = BrandDark, disabledContainerColor = cs.surfaceContainerHighest, disabledContentColor = cs.onSurfaceVariant.copy(alpha = 0.5f))) {
                        Text(if (dirty) "Save schedule" else "Saved", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                    OutlinedButton(onClick = { draft = SlotSpec.fromWindows(RunSchedule.DEFAULT_WINDOWS.getValue(acc.key)) }, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
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
                    if (g?.windowsUsed != null && g.windowsUsed != live.map { it.hour }) {
                        Text("Bot last used ${g.windowsUsed} - it picks up the new schedule on its next ping.", fontSize = 10.sp, lineHeight = 13.sp, color = Warn)
                    }
                    if (g?.slotsUsed != null) {
                        HealthLine("Bot slots", g.slotsUsed.mapIndexed { i, s -> "S${i + 1} ${s.label}" + (if (s.exact) " (exact)" else " (random)") }.joinToString("  \u00b7  "), cs.onSurface, cs.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun SlotTile(index: Int, slot: SlotSpec, onMode: (Boolean) -> Unit, onPickTime: (Int) -> Unit) {
    val cs = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(12.dp)
    Column(
        Modifier.fillMaxWidth().clip(shape)
            .background(if (slot.exact) BrandYellow.copy(alpha = 0.08f).compositeOver(cs.surfaceContainerHighest) else cs.surfaceContainerHighest)
            .border(1.dp, if (slot.exact) BrandYellow else cs.outline.copy(alpha = 0.5f), shape)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("SLOT ${index + 1}", fontSize = 10.sp, lineHeight = 12.sp, letterSpacing = 1.sp, fontWeight = FontWeight.ExtraBold, color = cs.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            SegmentedToggle(exact = slot.exact, onMode = onMode)
        }
        // v23.1 value fields: exact -> one time; window -> From / To
        if (slot.exact) {
            TimeField(label = null, value = slot.label, modifier = Modifier.fillMaxWidth()) { onPickTime(0) }
        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TimeField(label = "FROM", value = slot.label, modifier = Modifier.weight(1f)) { onPickTime(0) }
                Icon(Icons.Default.ArrowForward, null, Modifier.size(16.dp).padding(bottom = 12.dp), tint = cs.onSurfaceVariant)
                TimeField(label = "TO", value = slot.endLabel, modifier = Modifier.weight(1f)) { onPickTime(1) }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(if (slot.exact) Icons.Default.GpsFixed else Icons.Default.Shuffle, null, Modifier.size(12.dp), tint = if (slot.exact) BrandAmber else cs.onSurfaceVariant)
            Spacer(Modifier.width(6.dp))
            Text(
                if (slot.exact) "Uploads at ${slot.label} sharp (Dhaka)"
                else "Random minute between ${slot.label} \u2013 ${slot.endLabel}",
                fontSize = 11.sp, lineHeight = 14.sp, color = cs.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun TimeField(label: String?, value: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        if (label != null) Text(label, fontSize = 9.sp, lineHeight = 11.sp, letterSpacing = 1.sp, fontWeight = FontWeight.ExtraBold, color = cs.onSurfaceVariant)
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(cs.surface)
                .border(1.dp, cs.outline.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
                .clickable(onClick = onClick)
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(value, fontSize = if (label == null) 17.sp else 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.ExtraBold, color = cs.onSurface, maxLines = 1)
            Spacer(Modifier.weight(1f))
            Icon(Icons.Default.Schedule, null, Modifier.size(18.dp), tint = cs.onSurfaceVariant)
        }
    }
}

@Composable
private fun SegmentedToggle(exact: Boolean, onMode: (Boolean) -> Unit) {
    val cs = MaterialTheme.colorScheme
    Row(Modifier.clip(RoundedCornerShape(999.dp)).background(cs.surfaceContainerHigh).border(1.dp, cs.outline.copy(alpha = 0.4f), RoundedCornerShape(999.dp)).padding(2.dp)) {
        listOf("Window" to false, "Exact" to true).forEach { (label, isExact) ->
            val on = exact == isExact
            Text(
                label, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Bold,
                color = if (on) BrandYellow else cs.onSurfaceVariant,
                modifier = Modifier.clip(RoundedCornerShape(999.dp)).background(if (on) BrandDark else Color.Transparent)
                    .clickable { onMode(isExact) }.padding(horizontal = 11.dp, vertical = 5.dp),
            )
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

/** v25 Mix mode: when ON the account's 3 daily slots upload 3 DIFFERENT content types (bot reads dashboardSettings/variety). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MixModeCard(vm: MainViewModel, activeKey: String) {
    val cfgMap by vm.variety.collectAsStateWithLifecycle()
    val usedMap by vm.varietyUsed.collectAsStateWithLifecycle()
    SectionCard(
        title = "Mix mode — 3 slots, 3 different types",
        subtitle = "OFF = normal rotation (one content type per day). ON = every daily slot uploads a different content type; order rotates daily, empty types are skipped, pinned items always win. Saved per account in Firebase.",
    ) {
        Accounts.all.forEach { acc ->
            val live = cfgMap[acc.key] ?: VarietyConfig()
            var draft by remember(acc.key, live) { mutableStateOf(live) }
            val dirty = draft != live
            val used = usedMap[acc.key]
            val usedToday = if (used != null && used.date == RealTime.dhakaTodayString()) used.types else emptyList()
            val isActive = acc.key == activeKey
            Column(
                Modifier.fillMaxWidth().padding(bottom = 10.dp)
                    .border(1.dp, if (isActive) BrandYellow else MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(14.dp))
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(acc.key.replace("zedge", "ZEDGE ") + (if (isActive) "  · active" else ""), fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleSmall)
                        Text(
                            if (draft.enabled) "Mix mode ON" else "OFF — normal day-type rotation",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (draft.enabled) Ok else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(checked = draft.enabled, onCheckedChange = { draft = draft.copy(enabled = it) })
                }
                if (draft.enabled) {
                    Text("Content types to mix (min 2; only types with queued files are used)", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        VarietyConfig.ALL.forEach { t ->
                            val on = t in draft.types
                            FilterChip(
                                selected = on,
                                onClick = { draft = draft.copy(types = VarietyConfig.ALL.filter { x -> if (x == t) !on else x in draft.types }) },
                                label = { Text(VarietyConfig.label(t), style = MaterialTheme.typography.labelSmall) },
                            )
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { draft = draft.copy(strict = !draft.strict) }) {
                        Checkbox(checked = draft.strict, onCheckedChange = { draft = draft.copy(strict = it) })
                        Text("Strict: prefer a different type for every slot (repeats only when no other type has stock - a slot is never left empty)", style = MaterialTheme.typography.bodySmall)
                    }
                    val order = VarietyConfig.orderToday(draft.types)
                    Text("Order today: " + order.joinToString(" › ") { VarietyConfig.label(it) }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Uploaded today: " + (if (usedToday.isEmpty()) "-" else usedToday.joinToString(", ") { VarietyConfig.label(it) }), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { vm.saveVariety(acc.key, draft) }, enabled = dirty) { Text(if (dirty) "Save to Firebase" else "Saved") }
                    OutlinedButton(onClick = { draft = live }, enabled = dirty) { Text("Reset") }
                }
            }
        }
    }
}
