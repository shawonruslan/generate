package com.zedge.contentstudio.domain

import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.ContentTypes.MIN_STOCK_FOR_DAY
import com.zedge.contentstudio.core.ContentTypes.TYPE_CYCLE
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.data.UploadState
import java.time.LocalDate

/** Today's rule (mirrors the workflow's uploadState handling). */
data class ScheduleRule(val type: String, val remaining: Int, val uploadedToday: Int)

data class PlannedDay(
    val index: Int,
    val date: LocalDate,
    val dateKey: String,
    val isToday: Boolean,
    val dayType: String,
    val switchedFrom: String?,
    val slotCount: Int,
    val slots: List<QueueItem?>,
    /** Predicted run (time + profile) per slot, parallel to `slots`; null = no run left that day. */
    val runs: List<PlannedRun?> = emptyList(),
) {
    fun runAt(i: Int): PlannedRun? = runs.getOrNull(i)
    val allEmpty: Boolean get() = slots.all { it == null }
    val isWeekend: Boolean get() = date.dayOfWeek.value >= 6
}

data class SchedulePlan(
    val rule: ScheduleRule,
    val days: List<PlannedDay>,
    val buckets: Map<String, List<QueueItem>>,
    val pinnedCount: Int,
    val queuedCount: Int,
) {
    /** Types that have some stock but not enough for a full day. */
    val waitingForStock: List<Pair<String, Int>>
        get() = TYPE_CYCLE.mapNotNull { t ->
            val n = buckets[t]?.size ?: 0
            if (n in 1 until MIN_STOCK_FOR_DAY) t to n else null
        }

    fun predictedDateFor(itemId: String): String? =
        days.firstOrNull { d -> d.slots.any { it?.id == itemId } }?.dateKey

    companion object {
        const val DAYS_PER_PAGE = 28
        val EMPTY = SchedulePlan(ScheduleRule("AUDIO", 3, 0), emptyList(), TYPE_CYCLE.associateWith { emptyList<QueueItem>() }, 0, 0)
    }
}

/**
 * Exact port of the dashboard's computeScheduleStats() + buildScheduleCalendar() day loop.
 * Rules:
 *  - Type rotation follows TYPE_CYCLE; a type gets a day only with >= 3 items in stock.
 *  - Types with < 3 items wait (shown in "Waiting for stock") until restocked or pinned.
 *  - A day's type is decided once and never switches mid-day.
 *  - Pinned items (scheduledDate) override; overdue pins run today.
 */
object SchedulePlanner {
    private const val MAX_DAYS = 700
    private const val MIN_DAYS = 28

    fun rule(state: UploadState?): ScheduleRule {
        val today = RealTime.dhakaTodayString()
        if (state == null) return ScheduleRule("AUDIO", 3, 0)
        return if (state.lastUploadDate == today) {
            val up = state.totalUploadsToday
            ScheduleRule(state.uploadDayType ?: "AUDIO", maxOf(0, 3 - up), up)
        } else {
            val prev = if (state.uploadDayType in TYPE_CYCLE) state.uploadDayType!! else TYPE_CYCLE.last()
            ScheduleRule(TYPE_CYCLE[(TYPE_CYCLE.indexOf(prev) + 1) % TYPE_CYCLE.size], 3, 0)
        }
    }

    fun build(items: List<QueueItem>, state: UploadState?, accountKey: String = "zedge1"): SchedulePlan {
        val queued = items.filter { it.isQueued }.sortedBy { it.createdAt }
        val buckets = LinkedHashMap<String, MutableList<QueueItem>>()
        TYPE_CYCLE.forEach { buckets[it] = ArrayList() }
        val todayKey = RealTime.key(RealTime.dhakaDate(0))
        val pinnedByDate = HashMap<String, ArrayDeque<QueueItem>>()
        var pinnedCount = 0
        for (i in queued) {
            val sd = i.scheduledDate
            if (sd != null) {
                val k = if (sd <= todayKey) todayKey else sd
                pinnedByDate.getOrPut(k) { ArrayDeque() }.addLast(i)
                pinnedCount++
                continue
            }
            buckets[i.dayType]?.add(i)
        }

        val rule = rule(state)
        var currentDayType = rule.type
        val typeIdx = HashMap<String, Int>().apply { TYPE_CYCLE.forEach { put(it, 0) } }
        fun remainingOf(t: String): Int = (buckets[t]?.size ?: 0) - (typeIdx[t] ?: 0)

        val todayStr = RealTime.dhakaTodayString()
        val lockedTodayType: String? =
            if (state != null && state.lastUploadDate == todayStr && state.dayTypeLockedDate == todayStr) state.uploadDayType else null

        val days = ArrayList<PlannedDay>()
        var dayIdx = 0
        while ((dayIdx < MIN_DAYS || TYPE_CYCLE.any { remainingOf(it) >= MIN_STOCK_FOR_DAY } || pinnedByDate.values.any { it.isNotEmpty() }) && dayIdx < MAX_DAYS) {
            if (dayIdx > 0) currentDayType = TYPE_CYCLE[(TYPE_CYCLE.indexOf(currentDayType) + 1) % TYPE_CYCLE.size]
            val slotLimit = if (dayIdx == 0) rule.remaining else 3
            val dayDate = RealTime.dhakaDate(dayIdx)
            val dayKey = RealTime.key(dayDate)
            val dayPinned = pinnedByDate[dayKey] ?: ArrayDeque()
            val slots = ArrayList<QueueItem?>()
            var switchedFrom: String? = null
            var dayLocked = dayIdx == 0 && lockedTodayType != null
            if (dayLocked && lockedTodayType != null) currentDayType = lockedTodayType

            for (s in 0 until slotLimit) {
                var allocated: QueueItem? = null
                if (dayPinned.isNotEmpty()) {
                    allocated = dayPinned.removeFirst()
                } else if (dayLocked) {
                    if (remainingOf(currentDayType) > 0) {
                        allocated = buckets.getValue(currentDayType)[typeIdx.getValue(currentDayType)]
                        typeIdx[currentDayType] = typeIdx.getValue(currentDayType) + 1
                    }
                } else {
                    var chosen: String? = null
                    if (remainingOf(currentDayType) >= MIN_STOCK_FOR_DAY) {
                        chosen = currentDayType
                    } else {
                        val startIdx = maxOf(0, TYPE_CYCLE.indexOf(currentDayType))
                        for (step in 1 until TYPE_CYCLE.size) {
                            val t = TYPE_CYCLE[(startIdx + step) % TYPE_CYCLE.size]
                            if (remainingOf(t) >= MIN_STOCK_FOR_DAY) { chosen = t; break }
                        }
                    }
                    if (chosen != null) {
                        if (chosen != currentDayType) { switchedFrom = currentDayType; currentDayType = chosen }
                        dayLocked = true
                        allocated = buckets.getValue(chosen)[typeIdx.getValue(chosen)]
                        typeIdx[chosen] = typeIdx.getValue(chosen) + 1
                    }
                }
                slots.add(allocated)
            }
            while (dayPinned.isNotEmpty()) slots.add(dayPinned.removeFirst())
            if (pinnedByDate[dayKey]?.isEmpty() == true) pinnedByDate.remove(dayKey)

            days.add(
                PlannedDay(
                    index = dayIdx, date = dayDate, dateKey = dayKey, isToday = dayIdx == 0,
                    dayType = currentDayType, switchedFrom = switchedFrom,
                    slotCount = maxOf(slotLimit, slots.size), slots = slots,
                )
            )
            dayIdx++
        }
        val withRuns = try { RunSchedule.annotate(days, state, accountKey, rule.uploadedToday) } catch (_: Exception) { days }
        return SchedulePlan(rule, withRuns, buckets, pinnedCount, queued.size)
    }

    fun typeLabel(t: String): String = ContentTypes.dayUi(t).label
}
