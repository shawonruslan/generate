package com.zedge.contentstudio.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.domain.PlannedDay
import com.zedge.contentstudio.domain.PlannedRun
import com.zedge.contentstudio.domain.SpecialDays
import com.zedge.contentstudio.ui.components.HolidayBanner
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn
import kotlinx.coroutines.delay

/** v15: content-sized calendar cards, accessible contrast and persistent timer units. */
@Composable
fun DayCard(d: PlannedDay, specialDays: SpecialDays, modifier: Modifier = Modifier, onItem: (QueueItem) -> Unit, onItemLong: (QueueItem) -> Unit, onEmpty: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    var now by remember { mutableStateOf(RealTime.now()) }
    LaunchedEffect(d.dateKey) { while (true) { now = RealTime.now(); delay(1000L) } }
    val special = specialDays.forDate(d.dateKey)
    val shape = RoundedCornerShape(18.dp)
    val filled = d.slots.count { it != null }
    // v16 raised golden cards
    val dark = colors.surface.luminance() < 0.5f
    val top = if (dark) (if (d.isToday) Color(0xFF514014) else Color(0xFF352B16)) else (if (d.isToday) Color(0xFFFFE779) else Color(0xFFFFF1B6))
    val bottom = if (dark) Color(0xFF241F14) else Color(0xFFFFFCED)
    Column(modifier.shadow(if (d.isToday) 10.dp else 6.dp, shape, clip = false, spotColor = Color(0xFF9A6D00).copy(alpha = 0.45f)).clip(shape)
        .background(Brush.verticalGradient(listOf(top, bottom))).border(1.dp, if (d.isToday) BrandYellow else BrandYellow.copy(alpha = 0.35f), shape)) {
        Box(Modifier.fillMaxWidth().height(3.dp).background(Brush.horizontalGradient(listOf(BrandYellow.copy(alpha = 0.3f), BrandYellow, BrandYellow.copy(alpha = 0.3f)))))
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(43.dp).shadow(3.dp, RoundedCornerShape(12.dp)).clip(RoundedCornerShape(12.dp)).background(Brush.linearGradient(listOf(Color(0xFFFFEB76), BrandYellow))), contentAlignment = Alignment.Center) {
                    Text(d.date.dayOfMonth.toString(), fontSize = 22.sp, fontWeight = FontWeight.Bold, color = BrandDark)
                }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(if (d.isToday) "TODAY" else d.date.dayOfWeek.name.take(3), fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp, color = colors.onSurface)
                    Text("${d.date.month.name.take(3)} ${d.date.year} · DHAKA", fontSize = 10.sp, color = colors.onSurfaceVariant)
                }
                Text("$filled / ${d.slotCount}\nfiles planned", fontSize = 10.sp, lineHeight = 14.sp, color = if (filled > 0 && filled == d.slotCount) Ok else colors.onSurfaceVariant)
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(ContentTypes.dayUi(d.dayType).label, fontSize = 13.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), color = colors.onSurface)
                Text("0–14 min delay", fontSize = 10.sp, color = colors.onSurfaceVariant)
            }
            if (d.switchedFrom != null) Text("${ContentTypes.dayUi(d.switchedFrom).short}: waiting for 3 files", fontSize = 10.sp, color = colors.onSurfaceVariant)
            if (special.isNotEmpty()) HolidayBanner(special, Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)))
            if (d.slotCount == 0) {
                Text("✓ All uploads done for today", modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Ok.copy(alpha = 0.12f)).padding(16.dp), color = Ok, fontWeight = FontWeight.Bold)
            } else {
                d.slots.forEachIndexed { i, item ->
                    PlannerSlot(i, item, d.runAt(i), d.runs.isNotEmpty(), now, onItem, onItemLong, onEmpty)
                }
                Text("Tap a file to view · Hold to move / unpin", fontSize = 10.sp, lineHeight = 14.sp, color = colors.onSurfaceVariant)
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PlannerSlot(index: Int, item: QueueItem?, run: PlannedRun?, hasRuns: Boolean, now: Long, onItem: (QueueItem) -> Unit, onItemLong: (QueueItem) -> Unit, onEmpty: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    val past = run != null && run.windowEndMs > 0 && now > run.windowEndMs
    val due = run != null && now >= run.startMs && !past
    val next = run?.isNext == true && !past && !due
    val tint = when { item == null -> colors.onSurfaceVariant; due -> Warn; next -> Ok; else -> colors.onSurfaceVariant }
    val status = when { item == null -> "EMPTY"; run == null && hasRuns -> "NO RUN"; past -> "CLOSED"; due -> "DUE"; next -> "NEXT"; else -> "PLANNED" }
    val shape = RoundedCornerShape(12.dp)
    val base = Modifier.fillMaxWidth().shadow(3.dp, shape, clip = false, spotColor = Color(0xFF886300).copy(alpha = 0.3f)).clip(shape).background(Brush.verticalGradient(listOf(colors.surface, if (colors.surface.luminance() < 0.5f) Color(0xFF2D2514) else Color(0xFFFFFEF5))))
        .border(1.dp, if (due || next) tint.copy(alpha = 0.7f) else BrandYellow.copy(alpha = 0.3f), shape)
    val action = if (item == null) base.clickable(onClickLabel = "Choose a file for this day", onClick = onEmpty)
        else base.combinedClickable(onClickLabel = "View file", onLongClickLabel = "Move or unpin file", onClick = { onItem(item) }, onLongClick = { onItemLong(item) })
    // v18 consistent slot typography and timer-footer sizing; no maximum-height clip.
    Column(action.heightIn(min = 178.dp)) {
        Column(Modifier.padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("SLOT ${(index + 1).toString().padStart(2, '0')}", fontSize = 10.sp, letterSpacing = 0.6.sp, fontWeight = FontWeight.Bold, color = colors.onSurfaceVariant, modifier = Modifier.weight(1f))
                if (item?.isPinned == true) Text("PINNED  ·  ", fontSize = 9.sp, color = colors.onSurfaceVariant)
                Text(status, fontSize = 9.sp, fontWeight = FontWeight.Bold, color = tint, modifier = Modifier.clip(RoundedCornerShape(5.dp)).background(tint.copy(alpha = 0.1f)).padding(horizontal = 6.dp, vertical = 3.dp))
            }
            Text(item?.displayTitle ?: "+ Choose a file", fontSize = 14.sp, lineHeight = 19.sp, fontWeight = FontWeight.Bold, color = colors.onSurface, minLines = 2)
            if (run != null) {
                Text("${run.startLabel} – ${run.endLabel}", fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium, color = colors.onSurface)
                Text("${run.profileLabel} · Dhaka", fontSize = 11.sp, lineHeight = 14.sp, color = colors.onSurfaceVariant)
            } else if (hasRuns) {
                Text("Daily limit reached · Move this file to another day", fontSize = 11.sp, lineHeight = 15.sp, color = colors.onSurfaceVariant)
            }
        }
        if (run != null && item != null && run.startMs > 0L) PlannerSlotClock(run, now)
        else if (item == null) Text("Tap to pin a queued file to this day", fontSize = 10.sp, color = colors.onSurfaceVariant, modifier = Modifier.padding(start = 12.dp, end = 12.dp, bottom = 10.dp))
    }
}

@Composable
private fun PlannerSlotClock(run: PlannedRun, now: Long) {
    val colors = MaterialTheme.colorScheme
    val closed = now > run.windowEndMs
    val due = now >= run.startMs
    val target = when { !due -> run.startMs; now <= run.endMs -> run.endMs; else -> run.windowEndMs }
    val seconds = ((target - now).coerceAtLeast(0L) / 1000L)
    val days = seconds / 86400L
    val label = when { closed -> "Window closed"; !due -> "Scheduled in"; now <= run.endMs -> "Slot due"; else -> "Catch-up left" }
    Row(Modifier.fillMaxWidth().heightIn(min = 57.dp).background(Brush.horizontalGradient(listOf(BrandYellow.copy(alpha = 0.14f), BrandYellow.copy(alpha = 0.04f)))).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 6.dp)) {
            Text(label, fontSize = 10.sp, lineHeight = 13.sp, fontWeight = FontWeight.Medium, color = colors.onSurfaceVariant)
            if (days > 0L) Text("$days ${if (days == 1L) "day" else "days"} +", fontSize = 10.sp, color = colors.onSurfaceVariant)
            if (due && !closed) Text("Awaiting run", fontSize = 9.sp, color = colors.onSurfaceVariant)
        }
        if (!closed) {
            val values = listOf((seconds / 3600L) % 24L, (seconds / 60L) % 60L, seconds % 60L)
            val units = listOf("HRS", "MIN", "SEC")
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                values.forEachIndexed { i, value ->
                    Column(Modifier.widthIn(min = 31.dp).clip(RoundedCornerShape(6.dp)).background(if (due) Color(0xFF765520) else Color(0xFF35290E)).padding(horizontal = 4.dp, vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(value.toString().padStart(2, '0'), fontSize = 16.sp, lineHeight = 19.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, color = Color(0xFFFFE77B))
                        Text(units[i], fontSize = 8.sp, lineHeight = 10.sp, color = Color(0xFFCCB979))
                    }
                }
            }
        }
    }
}
