package com.zedge.contentstudio.core

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong

// ---------------------------------------------------------------------------
// Accounts (the four Zedge automation Firebase projects)
// ---------------------------------------------------------------------------
data class Account(val key: String, val label: String, val databaseUrl: String)

object Accounts {
    val all: List<Account> = listOf(
        Account("zedge1", "ZEDGE1", "https://shimul-zedge1-default-rtdb.asia-southeast1.firebasedatabase.app"), // <-- CONFIG
        Account("zedge2", "ZEDGE2", "https://shimul-zedge-2-default-rtdb.asia-southeast1.firebasedatabase.app"), // <-- CONFIG
        Account("zedge3", "ZEDGE3", "https://shimul-zedge3-default-rtdb.firebaseio.com"), // <-- CONFIG
        Account("zedge4", "ZEDGE4", "https://shimul-zedge-4-default-rtdb.firebaseio.com"), // <-- CONFIG
    )
    val keys: List<String> = all.map { it.key }
    /** Round-robin order used by Multi-Account Distribution. */
    val distOrder: List<String> = keys
    fun byKey(key: String): Account = all.firstOrNull { it.key == key } ?: all[0]
    fun isValid(key: String?): Boolean = key != null && all.any { it.key == key }

    const val R2_WORKER_URL = "https://shimul.shawonhawladar.workers.dev" // <-- CONFIG: your Cloudflare R2 worker URL
    const val QUEUE_PATH = "wallpaperQueue"
    const val STATE_PATH = "uploadState"
    const val GH_SETTINGS_PATH = "dashboardSettings/ghPanel"
}

// ---------------------------------------------------------------------------
// Content types (mirrors the dashboard + workflow constants)
// ---------------------------------------------------------------------------
data class SetMeta(val type: String, val slots: List<String>, val label: String, val short: String, val prefix: String)
data class VideoMeta(val type: String, val label: String, val short: String, val prefix: String)
data class DayTypeUi(val type: String, val title: String, val label: String, val short: String)

object ContentTypes {
    const val DAILY_LIMIT = 3
    const val MIN_STOCK_FOR_DAY = 3

    val TYPE_CYCLE = listOf(
        "AUDIO", "WALLPAPER", "WALLPAPER_24H", "WALLPAPER_DUAL", "WALLPAPER_BATTERY", "LIVE_WALLPAPER", "CHARGING_ANIMATION"
    )
    val SLOTS_24H = listOf("morning", "afternoon", "evening", "night")

    val SET_TYPES: Map<String, SetMeta> = linkedMapOf(
        "WALLPAPER_24H" to SetMeta("WALLPAPER_24H", SLOTS_24H, "24H Wallpaper Set", "24H", "24h"),
        "WALLPAPER_DUAL" to SetMeta("WALLPAPER_DUAL", listOf("lock", "home"), "Dual Wallpaper Set", "DUAL", "dual"),
        "WALLPAPER_BATTERY" to SetMeta(
            "WALLPAPER_BATTERY", listOf("critical", "low", "mid", "high", "full", "charging"),
            "Battery Wallpaper Set", "BATTERY", "battery"
        ),
    )
    val VIDEO_TYPES: Map<String, VideoMeta> = linkedMapOf(
        "LIVE_WALLPAPER" to VideoMeta("LIVE_WALLPAPER", "Live Wallpaper", "LIVE", "live"),
        "CHARGING_ANIMATION" to VideoMeta("CHARGING_ANIMATION", "Charging Animation", "CHARGE", "charging"),
    )
    val DAY_TYPE_UI: Map<String, DayTypeUi> = linkedMapOf(
        "AUDIO" to DayTypeUi("AUDIO", "Audio Day", "Ringtone", "Ringtone day"),
        "WALLPAPER" to DayTypeUi("WALLPAPER", "Wallpaper Day", "Wallpaper", "Wallpaper day"),
        "WALLPAPER_24H" to DayTypeUi("WALLPAPER_24H", "24H Wallpaper Day", "24H Set", "24H set day"),
        "WALLPAPER_DUAL" to DayTypeUi("WALLPAPER_DUAL", "Dual Wallpaper Day", "Dual Set", "Dual set day"),
        "WALLPAPER_BATTERY" to DayTypeUi("WALLPAPER_BATTERY", "Battery Wallpaper Day", "Battery", "Battery set day"),
        "LIVE_WALLPAPER" to DayTypeUi("LIVE_WALLPAPER", "Live Wallpaper Day", "Live Video", "Live wallpaper day"),
        "CHARGING_ANIMATION" to DayTypeUi("CHARGING_ANIMATION", "Charging Animation Day", "Charging", "Charging animation day"),
    )
    /** Smart import: number of images in a folder decides the set type. */
    val COUNT_TO_SET_TYPE: Map<Int, String> = mapOf(2 to "WALLPAPER_DUAL", 4 to "WALLPAPER_24H", 6 to "WALLPAPER_BATTERY")

    val SLOT_WORDS: Map<String, List<String>> = mapOf(
        "morning" to listOf("morning", "morn", "dawn", "sunrise", "am"),
        "afternoon" to listOf("afternoon", "noon", "midday", "day"),
        "evening" to listOf("evening", "sunset", "dusk", "eve"),
        "night" to listOf("night", "midnight", "dark"),
        "lock" to listOf("lock", "lockscreen", "ls"),
        "home" to listOf("home", "homescreen", "hs"),
        "critical" to listOf("critical", "crit", "empty"),
        "low" to listOf("low"),
        "mid" to listOf("mid", "medium", "half"),
        "high" to listOf("high"),
        "full" to listOf("full", "100"),
        "charging" to listOf("charging", "charge", "chg"),
    )

    fun dayUi(type: String?): DayTypeUi = DAY_TYPE_UI[type] ?: DAY_TYPE_UI.getValue("WALLPAPER")
    fun isSet(type: String?): Boolean = type != null && SET_TYPES.containsKey(type)
    fun isVideo(type: String?): Boolean = type != null && VIDEO_TYPES.containsKey(type)
    fun nextInCycle(type: String): String {
        val idx = TYPE_CYCLE.indexOf(type)
        val prev = if (idx < 0) TYPE_CYCLE.size - 1 else idx
        return TYPE_CYCLE[(prev + 1) % TYPE_CYCLE.size]
    }
}

// ---------------------------------------------------------------------------
// Real time (server-synced clock) + Dhaka date helpers
// ---------------------------------------------------------------------------
object RealTime {
    val DHAKA: ZoneId = ZoneId.of("Asia/Dhaka")
    private val offsetMs = AtomicLong(0)
    private val _synced = MutableStateFlow(false)
    val synced: StateFlow<Boolean> = _synced
    private val _tick = MutableStateFlow(0L)
    /** Bumps whenever the offset changes, so calendars can rebuild. */
    val tick: StateFlow<Long> = _tick

    fun now(): Long = System.currentTimeMillis() + offsetMs.get()

    /** Periodic nudge (every 30 s) so "today" rolls over at midnight without a restart. */
    fun bump() { _tick.value = _tick.value + 1 }

    fun applyServerTime(serverMs: Long, t0: Long, t1: Long) {
        offsetMs.set(serverMs - (t0 + t1) / 2)
        _synced.value = true
        _tick.value = _tick.value + 1
    }

    fun dhakaNow(): LocalDateTime = Instant.ofEpochMilli(now()).atZone(DHAKA).toLocalDateTime()
    /** Epoch ms of `minutesOfDay` on the given Dhaka calendar day. */
    fun dhakaEpochMs(day: LocalDate, minutesOfDay: Int): Long =
        day.atStartOfDay(DHAKA).toInstant().toEpochMilli() + minutesOfDay * 60_000L
    fun dhakaDate(offsetDays: Int = 0): LocalDate = dhakaNow().toLocalDate().plusDays(offsetDays.toLong())

    /** "YYYY-MM-DD" key used for pins and calendar days. */
    fun key(d: LocalDate): String = d.toString()
    fun parseKey(key: String?): LocalDate? = try { if (key.isNullOrBlank()) null else LocalDate.parse(key) } catch (_: Exception) { null }

    /** Workflow-compatible "M/D/YYYY" string (matches JS toLocaleString en-US). */
    fun dhakaTodayString(): String {
        val d = dhakaDate(0)
        return "${d.monthValue}/${d.dayOfMonth}/${d.year}"
    }

    private val stampFmt = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm", Locale.UK)
    /** "06/09/2026 17:59" - same as the dashboard's en-GB stamp for generated set names. */
    fun stamp(): String = LocalDateTime.now().format(stampFmt)
    private val failedFmt = DateTimeFormatter.ofPattern("dd MMM yyyy, HH:mm", Locale.UK)
    /** Epoch millis -> "08 Sept 2026, 00:34" in Dhaka time. */
    fun stampOf(ms: Long): String = if (ms <= 0L) "-" else Instant.ofEpochMilli(ms).atZone(DHAKA).toLocalDateTime().format(failedFmt)

    private val prettyFmt = DateTimeFormatter.ofPattern("EEE, dd MMM yyyy", Locale.UK)
    fun prettyKey(key: String?): String = parseKey(key)?.format(prettyFmt) ?: (key ?: "-")
    private val longFmt = DateTimeFormatter.ofPattern("EEEE, MMMM d, yyyy", Locale.US)
    fun longKey(key: String?): String = parseKey(key)?.format(longFmt) ?: (key ?: "-")

    fun relDayLabel(key: String, today: String): String {
        if (key < today) return "overdue - runs today"
        if (key == today) return "today"
        val a = parseKey(key) ?: return ""
        val b = parseKey(today) ?: return ""
        val diff = a.toEpochDay() - b.toEpochDay()
        return if (diff == 1L) "tomorrow" else "in $diff days"
    }
}

// ---------------------------------------------------------------------------
// Misc helpers
// ---------------------------------------------------------------------------
object Fmt {
    fun bytes(bytes: Long): String {
        if (bytes <= 0L) return "0 B"
        val sizes = arrayOf("B", "KB", "MB")
        val i = minOf((Math.log(bytes.toDouble()) / Math.log(1024.0)).toInt(), 2)
        return String.format(Locale.US, "%.2f %s", bytes / Math.pow(1024.0, i.toDouble()), sizes[i])
    }
}

/** Natural (numeric-aware, case-insensitive) comparator, like Intl.Collator numeric. */
object NaturalOrder : Comparator<String> {
    private val chunk = Regex("\\d+|\\D+")
    override fun compare(a: String, b: String): Int {
        val ca = chunk.findAll(a).map { it.value }.toList()
        val cb = chunk.findAll(b).map { it.value }.toList()
        var i = 0
        while (i < ca.size && i < cb.size) {
            val x = ca[i]; val y = cb[i]
            val c = if (x[0].isDigit() && y[0].isDigit()) {
                val xt = x.trimStart('0'); val yt = y.trimStart('0')
                if (xt.length != yt.length) xt.length.compareTo(yt.length) else xt.compareTo(yt)
            } else x.compareTo(y, ignoreCase = true)
            if (c != 0) return c
            i++
        }
        return ca.size.compareTo(cb.size)
    }
}

object Json {
    /** org.json NULL -> Kotlin null. */
    fun norm(v: Any?): Any? = if (v == null || v === JSONObject.NULL) null else v

    fun parse(text: String): Any? {
        val t = text.trim()
        if (t.isEmpty() || t == "null") return null
        return norm(org.json.JSONTokener(t).nextValue())
    }

    fun deepCopy(o: JSONObject): JSONObject = JSONObject(o.toString())

    fun obj(vararg pairs: Pair<String, Any?>): JSONObject {
        val o = JSONObject()
        for ((k, v) in pairs) o.put(k, v ?: JSONObject.NULL)
        return o
    }

    fun keys(o: JSONObject): List<String> = o.keys().asSequence().toList()

    fun asStringList(a: JSONArray?): List<String> =
        if (a == null) emptyList() else (0 until a.length()).map { a.optString(it) }
}

/** Turns the bot's raw Playwright / runtime error text into a short, human-readable hint. */
object UploadErrors {
    fun explain(raw: String?): String {
        val e = raw?.trim().orEmpty()
        val l = e.lowercase()
        if (e.isEmpty()) return "No error message was recorded for this item."
        if (l.contains("profile-list")) {
            val idx = Regex("""\.nth\((\d+)\)""").find(e)?.groupValues?.getOrNull(1)?.toIntOrNull()
            return if (idx != null)
                "Profile #${idx + 1} does not exist on this Zedge account. The workflow was run with a higher \"total_profiles\" than the account really has - re-run it with the correct profile count."
            else "Could not find the profile card on the Zedge Profiles page. Make sure the account has an approved profile and \"total_profiles\" matches."
        }
        if (l.contains("stale processing claim")) return "The bot crashed repeatedly while processing this item (stale claim). Requeue to try again."
        if (l.contains("from r2") && (l.contains("download") || l.contains("http 404"))) return "Source file is missing in R2 storage - probably deleted after another account uploaded it (shared copy). Upload the file again."
        if (l.contains("missing both fileurl")) return "This queue entry has no file attached. Delete it and upload the file again."
        if (l.contains("login") || l.contains("sign in") || l.contains("password") || l.contains("credential")) return "Zedge login failed - check the email / password inputs of the workflow."
        if (l.contains("captcha") || l.contains("verify you are human")) return "Zedge showed a captcha / bot check. Try later or with another proxy / user-agent."
        if (l.contains("daily limit") || l.contains("limit reached")) return "Zedge daily upload limit reached for this account. It will work again tomorrow."
        if (l.contains("proxy") || l.contains("err_tunnel") || l.contains("econnrefused") || l.contains("net::err")) return "Network / proxy problem while reaching Zedge. Check proxy settings and re-run."
        if (l.contains("file too large") || l.contains("exceeds") || l.contains("too big")) return "Zedge rejected the file size. Compress the file and upload again."
        if (l.contains("unsupported") || l.contains("invalid file") || l.contains("format")) return "Zedge rejected the file format. Check the file type for this content type."
        if (l.contains("waiting for locator") || l.contains("waitfor") || l.contains("timeout")) {
            val loc = Regex("""locator\(([^)]*)\)""").find(e)?.groupValues?.getOrNull(1)?.take(80)
            return "Timed out waiting for a page element" + (if (loc != null) " ($loc)" else "") + ". Zedge may have changed its layout or loaded slowly - requeue and try again."
        }
        return "Upload failed with a technical error - see the raw message below. Requeue to retry."
    }
}
