package com.zedge.contentstudio.domain

import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.data.UploadState
import java.time.LocalTime

/**
 * One predicted workflow run (upload attempt) for a calendar slot.
 * The workflow "gate" job picks ONE half-hour slot per 3-hour window using a deterministic hash of
 * date + window + account, then sleeps 0-14 random minutes. So the upload happens between
 * [start, end]. `profile` is the 0-based profile index the round-robin rotation will use.
 */
data class PlannedRun(
    val windowIdx: Int,
    val windowStart: LocalTime,
    val windowEnd: LocalTime,
    val start: LocalTime,
    val end: LocalTime,
    val profile: Int,          // -1 when unknown
    val profileKnown: Boolean, // false when uploadState has not loaded yet (estimate)
    val passed: Boolean,       // today only: window already over and this slot did not upload
    val live: Boolean,         // today only: we are inside the run window right now
    val isNext: Boolean,       // first run that has not happened yet
    val startMs: Long = 0L,    // epoch ms (Dhaka) of the gate slot
    val endMs: Long = 0L,      // startMs + max random delay
    val windowEndMs: Long = 0L,
    val exact: Boolean = false, // v23: user pinned an exact upload time for this slot (no random slot / delay)
) {
    val startLabel: String get() = RunSchedule.clock(start)
    val endLabel: String get() = RunSchedule.clock(end)
    /** "4:30 AM – 4:44 AM" for random slots, "4:30 AM (exact)" when the time is pinned. */
    val rangeLabel: String get() = if (exact) "$startLabel (exact)" else if (start == end) "~$startLabel" else "$startLabel \u2013 $endLabel"
    val profileLabel: String get() = if (profile < 0) "Profile ?" else "Profile #${profile + 1}" + (if (profileKnown) "" else " (est.)")
}

/** Gate health written by the workflow gate job (dashboardSettings/gate). */
data class GateHealth(
    val lastPing: Long?, val lastPingDhaka: String?, val lastDecision: String?,
    val lastRunDhaka: String?, val windowsUsed: List<Int>?, val runsToday: List<String>,
    // v13 cross-account: which windows really uploaded today + the time they ran
    val runWindows: Set<Int> = emptySet(), val runWindowTimes: Map<Int, String> = emptyMap(),
    val slotsUsed: List<SlotSpec>? = null,   // v23: slots the bot actually evaluated on its last ping
) {
    val minutesSincePing: Long? get() = lastPing?.let { (System.currentTimeMillis() - it) / 60000 }
}

/**
 * v23: one of the 3 daily upload slots of an account (Firebase dashboardSettings/schedule.slots[i]).
 * exact=false -> bot picks a random 30-min slot inside [hour, hour+3h) + 0-14 min (legacy behaviour).
 * exact=true  -> bot uploads at hour:minute sharp (Asia/Dhaka).
 */
/**
 * v23.1 upload slot. exact=true -> bot uploads at hour:minute sharp.
 * exact=false -> bot uploads at ONE random minute between [hour:minute, endHour:endMinute) (picked per day by hash).
 * Slots without a valid end (v23 schema) fall back to the classic 3 h window.
 */
data class SlotSpec(val hour: Int, val minute: Int = 0, val exact: Boolean = false, val endHour: Int = -1, val endMinute: Int = 0) {
    val minutesOfDay: Int get() = hour * 60 + minute
    val endMinutesOfDay: Int
        get() = when {
            exact -> minutesOfDay
            endHour in 0..23 && endMinute in 0..59 && endHour * 60 + endMinute > minutesOfDay -> endHour * 60 + endMinute
            else -> minOf(23 * 60 + 59, minutesOfDay + RunSchedule.WINDOW_HOURS * 60)
        }
    val label: String get() = RunSchedule.clock(LocalTime.of(hour, minute))
    val endLabel: String get() = RunSchedule.clock(LocalTime.of(endMinutesOfDay / 60, endMinutesOfDay % 60))
    val rangeLabel: String get() = if (exact) "$label (exact)" else "$label \u2013 $endLabel"
    val timeValue: String get() = "%02d:%02d".format(hour, minute)
    /** Same slot with the end normalised (what gets saved). */
    fun normalized(): SlotSpec = copy(endHour = endMinutesOfDay / 60, endMinute = endMinutesOfDay % 60)
    fun toJson(): org.json.JSONObject {
        val n = normalized()
        return org.json.JSONObject().put("hour", n.hour).put("minute", n.minute).put("exact", n.exact).put("endHour", n.endHour).put("endMinute", n.endMinute)
    }
    companion object {
        fun fromWindows(w: List<Int>): List<SlotSpec> = w.map { SlotSpec(it, 0, false).normalized() }
        fun parse(arr: org.json.JSONArray?): List<SlotSpec>? {
            if (arr == null) return null
            val out = (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val h = o.optInt("hour", -1); val m = o.optInt("minute", 0)
                if (h !in 0..23 || m !in 0..59) null
                else SlotSpec(h, m, o.optBoolean("exact", false), o.optInt("endHour", -1), o.optInt("endMinute", 0)).normalized()
            }
            return out.takeIf { it.isNotEmpty() }
        }
    }
}

/** Exact port of the workflow gate hash + profile rotation state manager. */
object RunSchedule {
    /** Validate a proposed schedule; null = OK, otherwise the error message. */
    fun validate(w: List<Int>): String? {
        if (w.size != 3) return "Need 3 windows"
        val s = w.sorted()
        for (i in s.indices) {
            if (s[i] !in 0..23) return "Hour out of range"
            if (i > 0 && s[i] - s[i - 1] < WINDOW_HOURS) return "Windows overlap - keep at least $WINDOW_HOURS h between start hours"
        }
        if (s.last() + WINDOW_HOURS > 24) return "Last window must end before midnight (start \u2264 9 PM)"
        return null
    }
    /** v23: validate 3 slots (exact or window) - same rules as the panel's validateSlots(). */
    fun validateSlots(sl: List<SlotSpec>): String? {
        if (sl.size != 3) return "Need 3 upload slots"
        for (x in sl) {
            if (x.hour !in 0..23) return "Hour out of range"
            if (x.minute !in 0..59) return "Minute out of range"
            if (!x.exact && x.endMinutesOfDay - x.minutesOfDay < SLOT_MIN) return "Window too short - keep at least $SLOT_MIN min between From and To"
        }
        val s = sl.sortedBy { it.minutesOfDay }
        for (i in 1 until s.size) {
            if (s[i].minutesOfDay - s[i - 1].endMinutesOfDay < SLOT_MIN) return "Slot $i and ${i + 1} overlap - keep at least $SLOT_MIN min between them"
        }
        return null
    }
    /** Bot's deterministic per-day random minute inside a window slot (same hash + modulo as the gate). */
    fun targetMinute(dateKey: String, windowIdx: Int, accountKey: String, spec: SlotSpec): Int {
        if (spec.exact) return spec.minutesOfDay
        val span = maxOf(1, spec.endMinutesOfDay - spec.minutesOfDay)
        return spec.minutesOfDay + (gateHash("$dateKey#$windowIdx#${accountKey.uppercase()}") % span.toLong()).toInt()
    }
    fun windowEndMinute(accountKey: String, windowIdx: Int): Int {
        val spec = slotFor(accountKey, windowIdx) ?: return windowsFor(accountKey)[windowIdx] * 60 + WINDOW_HOURS * 60
        return spec.endMinutesOfDay
    }
    fun hourLabel(h: Int): String { val hh = if (h % 12 == 0) 12 else h % 12; return "$hh:00 " + (if (h >= 12) "PM" else "AM") }

    /** Default window start hours (Asia/Dhaka) per account - same as DEFAULT_WINDOWS in each zedgeN.yml gate job. */
    val DEFAULT_WINDOWS: Map<String, List<Int>> = mapOf(
        "zedge1" to listOf(4, 10, 16),
        "zedge2" to listOf(5, 11, 17),
        "zedge3" to listOf(10, 16, 20),
        "zedge4" to listOf(11, 17, 21),
    )

    /** Live windows (Firebase dashboardSettings/schedule per account); falls back to DEFAULT_WINDOWS. */
    @Volatile var windows: Map<String, List<Int>> = DEFAULT_WINDOWS
    fun setWindows(key: String, w: List<Int>?) {
        val valid = w?.filter { it in 0..23 }?.takeIf { it.isNotEmpty() }
        windows = windows + (key to (valid ?: DEFAULT_WINDOWS.getValue(key)))
    }
    /** v23: live per-slot specs (exact minute + exact flag); hours are always mirrored into `windows`. */
    @Volatile var slots: Map<String, List<SlotSpec>> = DEFAULT_WINDOWS.mapValues { SlotSpec.fromWindows(it.value) }
    fun setSlots(key: String, sl: List<SlotSpec>?) {
        val valid = sl?.filter { it.hour in 0..23 && it.minute in 0..59 }?.takeIf { it.isNotEmpty() }
        val use = valid ?: SlotSpec.fromWindows(DEFAULT_WINDOWS.getValue(key))
        slots = slots + (key to use)
        setWindows(key, use.map { it.hour })
    }
    fun slotsFor(accountKey: String): List<SlotSpec> =
        slots[accountKey] ?: SlotSpec.fromWindows(windowsFor(accountKey))
    fun slotFor(accountKey: String, windowIdx: Int): SlotSpec? = slotsFor(accountKey).getOrNull(windowIdx)
    fun isExact(accountKey: String, windowIdx: Int): Boolean = slotFor(accountKey, windowIdx)?.exact == true
    const val WINDOW_HOURS = 3
    const val SLOT_MIN = 30
    const val MAX_DELAY_MIN = 14

    fun windowsFor(accountKey: String): List<Int> = windows[accountKey] ?: DEFAULT_WINDOWS[accountKey] ?: DEFAULT_WINDOWS.getValue("zedge1")

    /** JS: for (const c of seed) hash = (hash * 31 + c.charCodeAt(0)) >>> 0 */
    fun gateHash(seed: String): Long {
        var h = 0L
        for (ch in seed) h = (h * 31 + ch.code) and 0xFFFFFFFFL
        return h
    }

    fun chosenSlot(dateKey: String, windowIdx: Int, accountKey: String): Int {
        val slotsPerWindow = (WINDOW_HOURS * 60) / SLOT_MIN
        return (gateHash("$dateKey#$windowIdx#${accountKey.uppercase()}") % slotsPerWindow).toInt()
    }

    fun clock(t: LocalTime): String {
        val h12 = if (t.hour % 12 == 0) 12 else t.hour % 12
        return "%d:%02d %s".format(h12, t.minute, if (t.hour >= 12) "PM" else "AM")
    }

    private fun minutesOfDay(t: LocalTime): Int = t.hour * 60 + t.minute

    /** Time window only (no profile) - pure math, works for any account without its DB. */
    fun runTime(dateKey: String, windowIdx: Int, accountKey: String): Pair<LocalTime, LocalTime>? {
        val wins = windowsFor(accountKey)
        if (windowIdx !in wins.indices) return null
        // v23.1: the gate picks the exact minute (exact slot -> hour:minute; window slot -> hash-random minute inside From-To)
        // and sleeps until it, so the run starts at that minute - no extra random delay any more.
        val spec = slotFor(accountKey, windowIdx) ?: SlotSpec(wins[windowIdx], 0, false).normalized()
        val startMin = targetMinute(dateKey, windowIdx, accountKey, spec)
        val start = LocalTime.of((startMin / 60) % 24, startMin % 60)
        return start to start
    }

    /** Mutable rotation state (mirrors uploadState.lastUsedProfileIndex / profileUploadCounts). */
    private class Rotation(val total: Int, val limit: Int, var lastUsed: Int, val counts: HashMap<Int, Int>, val known: Boolean) {
        fun next(): Int {
            var n = (lastUsed + 1).mod(total)
            repeat(total) {
                if ((counts[n] ?: 0) < limit) return n
                n = (n + 1) % total
            }
            return -1
        }
        fun use(p: Int) { counts[p] = (counts[p] ?: 0) + 1; lastUsed = p }
        fun newDay() { counts.clear() }
    }

    private fun rotationFrom(state: UploadState?): Rotation {
        val today = RealTime.dhakaTodayString()
        val total = maxOf(1, state?.totalProfilesAvailable ?: 3)
        val counts = HashMap<Int, Int>()
        if (state != null && state.lastUploadDate == today) counts.putAll(state.profileUploadCounts)
        return Rotation(total, (ContentTypes.DAILY_LIMIT + total - 1) / total, state?.lastUsedProfileIndex ?: -1, counts, state != null)
    }

    /**
     * Attach a run (time + profile) to every slot of every planned day.
     * Today: the first `uploadedToday` windows are already consumed. Slots beyond the 3rd run
     * of a day (extra pinned files) get `null` - the workflow will not run for them that day.
     */
    fun annotate(days: List<PlannedDay>, state: UploadState?, accountKey: String, uploadedToday: Int): List<PlannedDay> {
        val rot = rotationFrom(state)
        val now = RealTime.dhakaNow().toLocalTime()
        val nowMin = minutesOfDay(now)
        var nextMarked = false
        return days.map { d ->
            if (!d.isToday) rot.newDay()
            val used = if (d.isToday) uploadedToday else 0
            val runs = d.slots.mapIndexed { sIdx, _ ->
                val w = used + sIdx
                if (w >= ContentTypes.DAILY_LIMIT) return@mapIndexed null
                val (start, end) = runTime(d.dateKey, w, accountKey) ?: return@mapIndexed null
                val wSpec = slotFor(accountKey, w)
                val wStart = if (wSpec != null) LocalTime.of(wSpec.hour, wSpec.minute) else LocalTime.of(windowsFor(accountKey)[w], 0)
                val wEndMin = maxOf(windowEndMinute(accountKey, w), minutesOfDay(start))
                val wEnd = LocalTime.of((wEndMin / 60) % 24, wEndMin % 60)
                val p = rot.next()
                if (p >= 0) rot.use(p)
                val passed = d.isToday && nowMin > wEndMin
                val live = d.isToday && nowMin >= minutesOfDay(start) && nowMin <= wEndMin
                val isNext = !nextMarked && !passed
                if (isNext) nextMarked = true
                PlannedRun(w, wStart, wEnd, start, end, p, rot.known, passed, live, isNext,
                    startMs = RealTime.dhakaEpochMs(d.date, minutesOfDay(start)), endMs = RealTime.dhakaEpochMs(d.date, minutesOfDay(end)), windowEndMs = RealTime.dhakaEpochMs(d.date, wEndMin),
                    exact = isExact(accountKey, w))
            }
            d.copy(runs = runs)
        }
    }

    /** Today's three run windows for one account (for the all-accounts strip). */
    data class TodayRun(val windowIdx: Int, val start: LocalTime, val end: LocalTime, val passed: Boolean, val live: Boolean,
                        val startMs: Long = 0L, val endMs: Long = 0L, val windowEndMs: Long = 0L, val exact: Boolean = false)

    fun todayRuns(accountKey: String): List<TodayRun> {
        val today = RealTime.dhakaDate(0)
        val dateKey = RealTime.key(today)   // YYYY-MM-DD - same seed format as the bot gate
        val nowMin = minutesOfDay(RealTime.dhakaNow().toLocalTime())
        return windowsFor(accountKey).indices.mapNotNull { w ->
            val (s, e) = runTime(dateKey, w, accountKey) ?: return@mapNotNull null
            val wEndMin = maxOf(windowEndMinute(accountKey, w), minutesOfDay(s))
            TodayRun(w, s, e, passed = nowMin > wEndMin, live = nowMin >= minutesOfDay(s) && nowMin <= wEndMin,
                startMs = RealTime.dhakaEpochMs(today, minutesOfDay(s)), endMs = RealTime.dhakaEpochMs(today, minutesOfDay(e)), windowEndMs = RealTime.dhakaEpochMs(today, wEndMin),
                exact = isExact(accountKey, w))
        }
    }
}
