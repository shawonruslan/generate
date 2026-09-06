package com.zedge.contentstudio.domain

import android.content.Context
import android.util.Log
import com.zedge.contentstudio.core.RealTime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

/** One chip on a calendar day. */
data class SpecialDay(val name: String, val icon: String, val kind: String, val slug: String, val countries: MutableList<String>?) {
    val label: String get() = if (countries != null && countries.size == 1) "$name (${countries[0]})" else name
}

/**
 * Special-days engine: built-in world days + live public-holiday feeds
 * (Nager.Date for EU/Americas/Asia, Google Calendar for IN/BD). 7-day disk cache.
 */
class SpecialDays(private val context: Context, private val http: OkHttpClient) {

    private val byDate = HashMap<String, MutableList<SpecialDay>>()
    private val builtYears = HashSet<Int>()
    private val triedFeeds = HashSet<String>()
    private val onlineCountries = LinkedHashSet<String>()
    private val _version = MutableStateFlow(0)
    val version: StateFlow<Int> = _version
    private val _status = MutableStateFlow("Built-in days only")
    val status: StateFlow<String> = _status
    private val prefs = context.getSharedPreferences("special_days_cache", Context.MODE_PRIVATE)

    fun forDate(key: String): List<SpecialDay> = byDate[key] ?: emptyList()

    @Synchronized
    private fun add(dateKey: String, name: String, icon: String, kind: String, country: String?) {
        if (dateKey.isBlank() || name.isBlank()) return
        val list = byDate.getOrPut(dateKey) { ArrayList() }
        val slug = name.lowercase().replace(Regex("[^a-z]"), "")
        val existing = list.firstOrNull { e ->
            e.slug == slug || (slug.length >= 6 && e.slug.length >= 6 && (e.slug.contains(slug) || slug.contains(e.slug)))
        }
        if (existing != null) {
            if (country != null && existing.countries != null && !existing.countries.contains(country)) existing.countries.add(country)
            return
        }
        list.add(SpecialDay(name, icon.ifBlank { "star" }, kind.ifBlank { "global" }, slug, if (country != null) mutableListOf(country) else null))
    }

    fun buildBuiltin(year: Int) {
        if (!builtYears.add(year)) return
        for (w in WORLD_DAYS) add(LocalDate.of(year, w.month, w.day).toString(), w.name, w.icon, "global", null)
        fun nth(month: Int, dow: DayOfWeek, n: Int): LocalDate =
            LocalDate.of(year, month, 1).with(TemporalAdjusters.dayOfWeekInMonth(n, dow))
        add(nth(5, DayOfWeek.SUNDAY, 2).toString(), "Mother's Day", "heart", "global", null)
        add(nth(6, DayOfWeek.SUNDAY, 3).toString(), "Father's Day", "user-tie", "global", null)
        add(nth(8, DayOfWeek.SUNDAY, 1).toString(), "Friendship Day", "user-group", "global", null)
        add(nth(10, DayOfWeek.FRIDAY, 1).toString(), "World Smile Day", "face-smile", "global", null)
        val thanksgiving = nth(11, DayOfWeek.THURSDAY, 4)
        add(thanksgiving.plusDays(1).toString(), "Black Friday", "tags", "global", null)
        add(thanksgiving.plusDays(4).toString(), "Cyber Monday", "laptop", "global", null)
        _version.value++
    }

    /** Loads built-in days for y..y+2 immediately, then merges every online feed in parallel. */
    suspend fun syncAll() {
        val y = RealTime.dhakaDate().year
        val years = listOf(y, y + 1, y + 2)
        years.forEach { buildBuiltin(it) }
        var merged = 0
        coroutineScope {
            val jobs = ArrayList<kotlinx.coroutines.Deferred<Boolean>>()
            for (year in years) {
                for (cc in ALL_NAGER) jobs += async(Dispatchers.IO) { runCatching { fetchNager(year, cc) }.getOrElse { false } }
                for ((cc, cal) in GOOGLE_CALENDARS) jobs += async(Dispatchers.IO) { runCatching { fetchGoogle(year, cc, cal) }.getOrElse { false } }
            }
            merged = jobs.awaitAll().count { it }
        }
        _status.value = if (merged > 0) "Live holidays synced - ${onlineCountries.size} countries" else "Built-in days only (feeds offline)"
        _version.value++
    }

    private fun cached(key: String): JSONArray? {
        val raw = prefs.getString(key, null) ?: return null
        return try {
            val o = JSONObject(raw)
            if (System.currentTimeMillis() - o.optLong("at") < CACHE_MS) o.optJSONArray("rows") else null
        } catch (_: Exception) { null }
    }

    private fun store(key: String, rows: JSONArray) {
        prefs.edit().putString(key, JSONObject().put("at", System.currentTimeMillis()).put("rows", rows).toString()).apply()
    }

    private suspend fun fetchNager(year: Int, country: String): Boolean {
        val feedKey = "${year}_$country"
        synchronized(triedFeeds) { if (!triedFeeds.add(feedKey)) return false }
        var rows = cached("nager_$feedKey")
        if (rows == null) {
            val body = httpGet("https://date.nager.at/api/v3/PublicHolidays/$year/$country")
            val arr = JSONArray(body)
            rows = JSONArray()
            for (i in 0 until arr.length()) {
                val h = arr.optJSONObject(i) ?: continue
                if (h.optString("date").isBlank() || (h.has("global") && !h.optBoolean("global", true))) continue
                rows.put(JSONObject().put("date", h.optString("date")).put("name", h.optString("name").ifBlank { h.optString("localName") }))
            }
            store("nager_$feedKey", rows)
        }
        applyRows(rows, country)
        return true
    }

    private suspend fun fetchGoogle(year: Int, country: String, calendarId: String): Boolean {
        val feedKey = "google_${year}_$country"
        synchronized(triedFeeds) { if (!triedFeeds.add(feedKey)) return false }
        var rows = cached(feedKey)
        if (rows == null) {
            val url = GOOGLE_CAL_BASE + URLEncoder.encode(calendarId, "UTF-8") + "/events" +
                "?key=$GOOGLE_API_KEY&timeMin=$year-01-01T00:00:00Z&timeMax=${year + 1}-01-01T00:00:00Z" +
                "&singleEvents=true&orderBy=startTime&maxResults=2500"
            val data = JSONObject(httpGet(url))
            val items = data.optJSONArray("items") ?: JSONArray()
            rows = JSONArray()
            for (i in 0 until items.length()) {
                val ev = items.optJSONObject(i) ?: continue
                val start = ev.optJSONObject("start")
                val raw = start?.optString("date")?.ifBlank { start.optString("dateTime").take(10) } ?: ""
                if (raw.isNotBlank()) rows.put(JSONObject().put("date", raw).put("name", ev.optString("summary").ifBlank { "Public holiday" }))
            }
            store(feedKey, rows)
        }
        applyRows(rows, country)
        return true
    }

    private fun applyRows(rows: JSONArray, country: String) {
        for (i in 0 until rows.length()) {
            val h = rows.optJSONObject(i) ?: continue
            add(h.optString("date"), h.optString("name"), iconFor(h.optString("name")), "holiday", country)
        }
        synchronized(onlineCountries) { onlineCountries.add(country) }
    }

    private suspend fun httpGet(url: String): String = withContext(Dispatchers.IO) {
        http.newCall(Request.Builder().url(url).header("Cache-Control", "no-store").build()).execute().use { r ->
            if (!r.isSuccessful) throw IllegalStateException("HTTP ${r.code} $url")
            r.body?.string() ?: ""
        }
    }

    companion object {
        private const val CACHE_MS = 7L * 24 * 60 * 60 * 1000
        const val GOOGLE_CAL_BASE = "https://" + "www.googleapis.com/calendar/v3/calendars/"
        const val GOOGLE_API_KEY = "AIzaSyAnNeYfEYF6Z41r-QBo2q8eWKaP-CBPlnc"
        val EUROPE = listOf("GB", "IE", "DE", "FR", "ES", "PT", "IT", "NL", "BE", "CH", "AT", "SE", "NO", "DK", "FI", "PL", "CZ", "GR", "RU", "UA")
        val AMERICAS = listOf("US", "CA", "MX", "BR", "AR", "CL", "CO", "PE")
        val ASIA = listOf("JP", "KR", "CN", "HK", "SG", "VN", "ID", "KZ")
        val ALL_NAGER = EUROPE + AMERICAS + ASIA
        val GOOGLE_CALENDARS = mapOf(
            "IN" to "en.indian.official#holiday@group.v.calendar.google.com",
            "BD" to "en.bd.official#holiday@group.v.calendar.google.com",
        )

        data class WorldDay(val month: Int, val day: Int, val name: String, val icon: String)
        val WORLD_DAYS = listOf(
            WorldDay(1, 1, "New Year's Day", "champagne"),
            WorldDay(2, 9, "Pizza Day", "pizza"),
            WorldDay(2, 14, "Valentine's Day", "heart"),
            WorldDay(3, 8, "Women's Day", "venus"),
            WorldDay(3, 20, "Day of Happiness / Spring Begins", "face-smile"),
            WorldDay(4, 1, "April Fools' Day", "face-grin"),
            WorldDay(4, 15, "World Art Day", "palette"),
            WorldDay(4, 22, "Earth Day", "earth"),
            WorldDay(5, 4, "Star Wars Day", "jedi"),
            WorldDay(5, 21, "International Tea Day", "mug-hot"),
            WorldDay(6, 5, "World Environment Day", "leaf"),
            WorldDay(6, 8, "World Oceans Day", "water"),
            WorldDay(6, 21, "World Music Day / Summer Begins", "music"),
            WorldDay(7, 7, "World Chocolate Day", "cookie"),
            WorldDay(7, 17, "World Emoji Day", "face-laugh"),
            WorldDay(7, 30, "Intl Friendship Day", "user-group"),
            WorldDay(8, 8, "International Cat Day", "cat"),
            WorldDay(8, 19, "World Photography Day", "camera"),
            WorldDay(8, 26, "International Dog Day", "dog"),
            WorldDay(9, 21, "Day of Peace", "dove"),
            WorldDay(9, 22, "Autumn Begins", "wind"),
            WorldDay(10, 1, "International Coffee Day", "mug-saucer"),
            WorldDay(10, 4, "World Animal Day", "paw"),
            WorldDay(10, 5, "World Teachers' Day", "chalkboard"),
            WorldDay(10, 10, "World Mental Health Day", "brain"),
            WorldDay(10, 31, "Halloween", "ghost"),
            WorldDay(11, 13, "World Kindness Day", "hand-heart"),
            WorldDay(11, 14, "Children's Day", "child"),
            WorldDay(11, 19, "Intl Men's Day", "mars"),
            WorldDay(12, 21, "Winter Begins", "snowflake"),
            WorldDay(12, 24, "Christmas Eve", "sleigh"),
            WorldDay(12, 25, "Christmas", "gifts"),
            WorldDay(12, 31, "New Year's Eve", "champagne"),
        )

        fun iconFor(name: String): String {
            val n = name.lowercase()
            return when {
                "christmas" in n -> "gifts"
                "thanksgiving" in n -> "drumstick"
                "independence" in n -> "flag"
                "new year" in n -> "champagne"
                "labor" in n || "labour" in n || "worker" in n -> "hammer"
                "memorial" in n || "veteran" in n || "armistice" in n -> "medal"
                "luther" in n -> "dove"
                "easter" in n || "good friday" in n -> "egg"
                "halloween" in n -> "ghost"
                "boxing" in n -> "box-open"
                else -> "landmark"
            }
        }

        /** Emoji for a chip icon key (Compose has no FontAwesome). */
        fun emoji(icon: String): String = when (icon) {
            "champagne" -> "🥂"; "pizza" -> "🍕"; "heart" -> "❤️"; "venus" -> "♀️"; "face-smile" -> "😊"
            "face-grin" -> "😂"; "palette" -> "🎨"; "earth" -> "🌍"; "jedi" -> "⚔️"; "mug-hot" -> "🍵"
            "leaf" -> "🍃"; "water" -> "🌊"; "music" -> "🎵"; "cookie" -> "🍫"; "face-laugh" -> "😆"
            "user-group" -> "👥"; "cat" -> "🐱"; "camera" -> "📷"; "dog" -> "🐶"; "dove" -> "🕊️"
            "wind" -> "🍂"; "mug-saucer" -> "☕"; "paw" -> "🐾"; "chalkboard" -> "👩‍🏫"; "brain" -> "🧠"
            "ghost" -> "👻"; "hand-heart" -> "🤝"; "child" -> "🧒"; "mars" -> "♂️"; "snowflake" -> "❄️"
            "sleigh" -> "🛷"; "gifts" -> "🎁"; "user-tie" -> "👔"; "tags" -> "🏷️"; "laptop" -> "💻"
            "drumstick" -> "🍗"; "flag" -> "🚩"; "hammer" -> "🔨"; "medal" -> "🎖️"; "egg" -> "🥚"
            "box-open" -> "📦"; "landmark" -> "🏛️"
            else -> "⭐"
        }
    }
}
