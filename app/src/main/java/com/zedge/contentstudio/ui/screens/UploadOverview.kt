package com.zedge.contentstudio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.domain.GateHealth
import com.zedge.contentstudio.domain.RunSchedule
import com.zedge.contentstudio.domain.SchedulePlan
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn
import kotlinx.coroutines.delay

/** v14: one reusable, theme-aware upload overview for Home and Planner. */
@Composable
internal fun TodayRunStrip(
    activeKey: String,
    plan: SchedulePlan,
    health: Map<String, GateHealth?>,
    modifier: Modifier = Modifier,
) {
    var now by remember { mutableStateOf(RealTime.now()) }
    LaunchedEffect(Unit) { while (true) { now = RealTime.now(); delay(1000L) } }
    val colors = MaterialTheme.colorScheme
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Today's uploads", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = colors.onSurface)
                Text("Dhaka · All ${Accounts.all.size} accounts", style = MaterialTheme.typography.labelSmall, color = colors.onSurfaceVariant)
            }
            Text("Swipe →", style = MaterialTheme.typography.labelSmall, color = colors.onSurfaceVariant)
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val cardWidth = minOf(300.dp, maxWidth - 16.dp)
            LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                itemsIndexed(Accounts.all, key = { _, account -> account.key }) { accountIndex, acc ->
                    val selected = acc.key == activeKey
                    val runs = RunSchedule.todayRuns(acc.key)
                    val g = health[acc.key]
                    val doneWindows = g?.runWindows ?: emptySet()
                    fun isDone(i: Int): Boolean = doneWindows.contains(i) || (selected && doneWindows.isEmpty() && i < plan.rule.uploadedToday)
                    val doneCount = runs.indices.count { isDone(it) }
                    val nextIndex = runs.indices.firstOrNull { !isDone(it) && now <= runs[it].windowEndMs }
                    val next = nextIndex?.let { runs[it] }
                    val shape = RoundedCornerShape(16.dp)
                    Column(
                        Modifier.width(cardWidth).clip(shape).background(colors.surfaceContainerHigh)
                            .border(1.dp, if (selected) BrandYellow else colors.outline.copy(alpha = 0.5f), shape)
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(30.dp).clip(RoundedCornerShape(9.dp)).background(if (selected) BrandYellow else colors.surfaceVariant), contentAlignment = Alignment.Center) {
                                Text((accountIndex + 1).toString().padStart(2, '0'), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = if (selected) BrandDark else colors.onSurfaceVariant)
                            }
                            Spacer(Modifier.width(8.dp))
                            Text(acc.label, modifier = Modifier.weight(1f), fontSize = 12.sp, fontWeight = FontWeight.ExtraBold, color = colors.onSurface)
                            Text("$doneCount / ${runs.size} done", fontSize = 11.sp, color = if (doneCount == runs.size) Ok else colors.onSurfaceVariant)
                        }
                        val phase = when {
                            next == null -> if (doneCount == runs.size) "All slots done" else "Windows ended"
                            now < next.startMs -> "Next slot in"
                            now <= next.endMs -> "Slot due · delay"
                            else -> "Catch-up left"
                        }
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(11.dp))
                                .background(if (selected) BrandYellow.copy(alpha = 0.12f) else colors.surface)
                                .padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(if (next == null) "TODAY" else phase.uppercase(), fontSize = 9.sp, lineHeight = 12.sp, letterSpacing = 0.4.sp, fontWeight = FontWeight.Bold, color = colors.onSurfaceVariant)
                                Spacer(Modifier.height(4.dp))
                                Text(next?.let { RunSchedule.clock(it.start) } ?: phase, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = colors.onSurface, maxLines = 2)
                            }
                            if (next != null) {
                                val target = when { now < next.startMs -> next.startMs; now <= next.endMs -> next.endMs; else -> next.windowEndMs }
                                OverviewClock(target - now, due = now >= next.startMs)
                            } else if (doneCount == runs.size) {
                                Text("✓", fontSize = 24.sp, color = Ok, modifier = Modifier.padding(start = 6.dp))
                            }
                        }
                        Column {
                            runs.forEachIndexed { i, r ->
                                if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(colors.outline.copy(alpha = 0.18f)))
                                val done = isDone(i)
                                val passed = !done && now > r.windowEndMs
                                val due = !done && !passed && now >= r.startMs
                                val tag = when { done -> "DONE"; passed -> "CLOSED"; due -> "DUE"; i == nextIndex -> "NEXT"; else -> "LATER" }
                                val tint = when { done -> Ok; due -> Warn; i == nextIndex -> colors.primary; else -> colors.onSurfaceVariant }
                                val slotIndex = i - maxOf(doneWindows.size, if (selected) plan.rule.uploadedToday else 0)
                                val day = plan.days.firstOrNull { it.isToday }
                                val item = if (selected && slotIndex >= 0) day?.slots?.getOrNull(slotIndex) else null
                                val profile = if (selected && slotIndex >= 0) day?.runAt(slotIndex)?.profileLabel else null
                                val detail = when {
                                    done -> "Uploaded" + (g?.runWindowTimes?.get(i)?.let { " $it" } ?: "")
                                    item != null -> item.displayTitle + (profile?.let { " · $it" } ?: "")
                                    passed -> "No run recorded in window"
                                    due -> "Awaiting run confirmation"
                                    selected && profile != null -> "Empty slot · $profile"
                                    else -> "Scheduled · Dhaka time"
                                }
                                Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Text(if (done) "✓" else (i + 1).toString().padStart(2, '0'), fontSize = 10.sp, color = if (done) Ok else colors.onSurfaceVariant, modifier = Modifier.width(22.dp))
                                    Column(Modifier.weight(1f).padding(end = 6.dp)) {
                                        Text(RunSchedule.clock(r.start), fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold, color = if (done) Ok else colors.onSurface)
                                        Text(detail, fontSize = 10.sp, lineHeight = 14.sp, color = colors.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    }
                                    Text(tag, fontSize = 8.sp, lineHeight = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.3.sp, color = tint,
                                        modifier = Modifier.clip(RoundedCornerShape(5.dp)).background(tint.copy(alpha = 0.12f)).padding(horizontal = 5.dp, vertical = 3.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
        Text("Scheduled times · 0–14 min delay · Catch-up enabled", fontSize = 10.sp, color = colors.onSurfaceVariant)
    }
}

@Composable
private fun OverviewClock(leftMs: Long, due: Boolean) {
    val seconds = (leftMs.coerceAtLeast(0L) / 1000L)
    val numbers = listOf(seconds / 3600L, (seconds / 60L) % 60L, seconds % 60L)
    val labels = listOf("HRS", "MIN", "SEC")
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.padding(start = 6.dp)) {
        numbers.forEachIndexed { i, n ->
            Column(
                Modifier.widthIn(min = 29.dp).clip(RoundedCornerShape(6.dp))
                    .background(if (due) Color(0xFF765520) else Color(0xFF292C28)).padding(horizontal = 3.dp, vertical = 5.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(n.toString().padStart(2, '0'), fontFamily = FontFamily.Monospace, fontSize = 16.sp, lineHeight = 19.sp, fontWeight = FontWeight.Bold, color = Color(0xFFFFFCEF))
                Text(labels[i], fontSize = 7.sp, lineHeight = 9.sp, letterSpacing = 0.4.sp, color = Color(0xFFD4D6BB))
            }
        }
    }
}
