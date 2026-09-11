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
) {
    val startLabel: String get() = RunSchedule.clock(start)
    val endLabel: String get() = RunSchedule.clock(end)
    val profileLabel: String get() = if (profile < 0) "Profile ?" else "Profile #${profile + 1}" + (if (profileKnown) "" else " (est.)")
}

/** Gate health written by the workflow gate job (dashboardSettings/gate). */
data class GateHealth(
    val lastPing: Long?, val lastPingDhaka: String?, val lastDecision: String?,
    val lastRunDhaka: String?, val windowsUsed: List<Int>?, val runsToday: List<String>,
    // v13 cross-account: which windows really uploaded today + the time they ran
    val runWindows: Set<Int> = emptySet(), val runWindowTimes: Map<Int, String> = emptyMap(),
) {
    val minutesSincePing: Long? get() = lastPing?.let { (System.currentTimeMillis() - it) / 60000 }
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
        val startMin = wins[windowIdx] * 60 + chosenSlot(dateKey, windowIdx, accountKey) * SLOT_MIN
        val start = LocalTime.of((startMin / 60) % 24, startMin % 60)
        return start to start.plusMinutes(MAX_DELAY_MIN.toLong())
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
                val wStart = LocalTime.of(windowsFor(accountKey)[w], 0)
                val wEndMin = windowsFor(accountKey)[w] * 60 + WINDOW_HOURS * 60
                val wEnd = LocalTime.of((wEndMin / 60) % 24, wEndMin % 60)
                val p = rot.next()
                if (p >= 0) rot.use(p)
                val passed = d.isToday && nowMin > wEndMin
                val live = d.isToday && nowMin >= minutesOfDay(start) && nowMin <= wEndMin
                val isNext = !nextMarked && !passed
                if (isNext) nextMarked = true
                PlannedRun(w, wStart, wEnd, start, end, p, rot.known, passed, live, isNext,
                    startMs = RealTime.dhakaEpochMs(d.date, minutesOfDay(start)), endMs = RealTime.dhakaEpochMs(d.date, minutesOfDay(end)), windowEndMs = RealTime.dhakaEpochMs(d.date, wEndMin))
            }
            d.copy(runs = runs)
        }
    }

    /** Today's three run windows for one account (for the all-accounts strip). */
    data class TodayRun(val windowIdx: Int, val start: LocalTime, val end: LocalTime, val passed: Boolean, val live: Boolean,
                        val startMs: Long = 0L, val endMs: Long = 0L, val windowEndMs: Long = 0L)

    fun todayRuns(accountKey: String): List<TodayRun> {
        val today = RealTime.dhakaDate(0)
        val dateKey = RealTime.key(today)   // YYYY-MM-DD - same seed format as the bot gate
        val nowMin = minutesOfDay(RealTime.dhakaNow().toLocalTime())
        return windowsFor(accountKey).indices.mapNotNull { w ->
            val (s, e) = runTime(dateKey, w, accountKey) ?: return@mapNotNull null
            val wEndMin = windowsFor(accountKey)[w] * 60 + WINDOW_HOURS * 60
            TodayRun(w, s, e, passed = nowMin > wEndMin, live = nowMin >= minutesOfDay(s) && nowMin <= wEndMin,
                startMs = RealTime.dhakaEpochMs(today, minutesOfDay(s)), endMs = RealTime.dhakaEpochMs(today, minutesOfDay(e)), windowEndMs = RealTime.dhakaEpochMs(today, wEndMin))
        }
    }
}
