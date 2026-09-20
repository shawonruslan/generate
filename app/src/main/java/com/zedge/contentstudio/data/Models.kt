package com.zedge.contentstudio.data

import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.Json
import org.json.JSONObject

/**
 * One row of wallpaperQueue. Keeps the raw JSON so "Copy to other accounts" can clone every field.
 */
class QueueItem(val id: String, val raw: JSONObject) {
    val name: String get() = raw.optString("name", "")
    val title: String get() = raw.optString("title", "")
    val tags: String get() = raw.optString("tags", "")
    val category: String get() = raw.optString("category", "")
    val description: String get() = raw.optString("description", "")
    val size: Long get() = raw.optLong("size", 0L)
    val status: String get() = raw.optString("status", "queued").ifBlank { "queued" }
    val createdAt: Long get() = raw.optLong("createdAt", 0L)
    val fileUrl: String get() = raw.optString("fileUrl", "")
    val thumbUrl: String get() = raw.optString("thumbUrl", "")
    val error: String get() = raw.optString("error", "")
    val failedAt: Long get() = raw.optLong("failedAt", 0L)

    /** Best-effort "added" time: createdAt, else the timestamp encoded in the Firebase push id. */
    val addedAtMs: Long get() = if (createdAt > 0L) createdAt else pushIdToMs(id)

    // Ringtone generator audio-processing audit trail (null when the row was not created by the generator)
    val autoProcess: Boolean? get() = if (raw.has("autoProcess") && !raw.isNull("autoProcess")) raw.optBoolean("autoProcess") else null
    val processed: Boolean get() = raw.optBoolean("processed", false)
    val processError: String get() = raw.optString("processError", "")
    val processing: JSONObject? get() = raw.optJSONObject("processing")
    /** One-line human summary of the processing result, or null when not applicable. */
    val processingSummary: String?
        get() {
            val ap = autoProcess ?: return null
            if (!ap) return "Auto-process was OFF - uploaded as generated"
            if (!processed) return "RAW audio - silence trim / volume boost FAILED: " + processError.ifBlank { "ffmpeg error" }
            val p = processing ?: return "Processed (silence trim + volume boost)"
            fun n(k: String): String {
                if (!p.has(k) || p.isNull(k)) return "-"
                val d = p.optDouble(k)
                return if (d == d.toLong().toDouble()) d.toLong().toString() else String.format(java.util.Locale.US, "%.2f", d)
            }
            return "${n("durationBefore")}s -> ${n("durationAfter")}s (trimmed ${n("trimmedSec")}s) | peak ${n("peakBeforeDb")} -> ${n("peakAfterDb")} dB | gain +${n("gainDb")} dB (boost ${n("boostPct")}%)"
        }

    /** Bot marks rows `failed` (upload error) or `error` (migration / invalid file). */
    val isFailed: Boolean get() = status == "failed" || status == "error"
    val distributedTo: String? get() = raw.optString("distributedTo", "").ifBlank { null }
    val importedFrom: String? get() = raw.optString("importedFrom", "").ifBlank { null }
    val scheduledDate: String? get() = Json.norm(raw.opt("scheduledDate"))?.toString()?.ifBlank { null }
    val isPinned: Boolean get() = scheduledDate != null
    val isQueued: Boolean get() = status == "queued"

    /**
     * v23 metadata guard - identical rule to zedgeN.yml / generator.yml / the web panel:
     * title + tags + category must all be non-empty, otherwise the upload bot SKIPS the file.
     */
    val missingMetaFields: List<String> get() = buildList {
        if (title.isBlank()) add("title")
        if (tags.isBlank() || tags.trim() == "[]") add("tags")
        if (category.isBlank()) add("category")
    }
    val hasMetadata: Boolean get() = missingMetaFields.isEmpty()
    /** Queued but blocked by the metadata guard - will never upload until fixed. */
    val isBlockedNoMeta: Boolean get() = isQueued && !hasMetadata

    val isMp3: Boolean get() = raw.optBoolean("isMp3", false) || name.lowercase().endsWith(".mp3")

    /** RINGTONE / WALLPAPER / WALLPAPER_24H / WALLPAPER_DUAL / WALLPAPER_BATTERY / LIVE_WALLPAPER / CHARGING_ANIMATION */
    val contentType: String
        get() {
            val ct = raw.optString("contentType", "")
            if (ct.isNotBlank()) return ct
            return if (isMp3) "RINGTONE" else "WALLPAPER"
        }

    /** Calendar day type (RINGTONE rows live on AUDIO days). */
    val dayType: String get() = if (contentType == "RINGTONE") "AUDIO" else contentType
    val isSetType: Boolean get() = ContentTypes.isSet(contentType)
    val isVideoType: Boolean get() = ContentTypes.isVideo(contentType)
    val slots: List<String> get() = ContentTypes.SET_TYPES[contentType]?.slots ?: emptyList()

    fun slotUrl(slot: String): String {
        val files = raw.optJSONObject("files") ?: return ""
        val f = Json.norm(files.opt(slot)) ?: return ""
        return if (f is JSONObject) f.optString("fileUrl", "") else f.toString()
    }

    val displayTitle: String get() = title.trim().ifBlank { name.ifBlank { "Unnamed" } }
    val tagList: List<String> get() = tags.split(',').map { it.trim() }.filter { it.isNotEmpty() }

    /** Best thumbnail for cards / lists. */
    val previewUrl: String
        get() = when {
            isMp3 -> ""
            isSetType -> slots.firstOrNull()?.let { slotUrl(it) }?.ifBlank { fileUrl } ?: fileUrl
            isVideoType -> thumbUrl
            else -> fileUrl
        }

    companion object {
        private const val PUSH_CHARS = "-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
        /** Firebase push ids encode their creation time (ms) in the first 8 characters. */
        fun pushIdToMs(id: String): Long {
            if (id.length < 8) return 0L
            var ts = 0L
            for (i in 0 until 8) {
                val idx = PUSH_CHARS.indexOf(id[i])
                if (idx < 0) return 0L
                ts = ts * 64 + idx
            }
            return ts
        }
        fun listFrom(data: Any?): List<QueueItem> {
            val o = data as? JSONObject ?: return emptyList()
            return Json.keys(o).mapNotNull { k ->
                val v = o.optJSONObject(k) ?: return@mapNotNull null
                QueueItem(k, v)
            }
        }
    }
}

/** The workflow's uploadState node. */
data class UploadState(
    val uploadDayType: String?,
    val lastUploadDate: String?,
    val totalUploadsToday: Int,
    val dayTypeLockedDate: String?,
    /** Profile rotation state written by the workflow (see getProfileState / updateProfileStateAfterUpload). */
    val lastUsedProfileIndex: Int = -1,
    val totalProfilesAvailable: Int = 3,
    val profileUploadCounts: Map<Int, Int> = emptyMap(),
) {
    companion object {
        fun from(data: Any?): UploadState? {
            val o = data as? JSONObject ?: return null
            val counts = HashMap<Int, Int>()
            val pc = o.opt("profileUploadCounts")
            if (pc is JSONObject) {
                for (k in pc.keys()) k.toIntOrNull()?.let { counts[it] = pc.optInt(k, 0) }
            } else if (pc is org.json.JSONArray) {
                for (i in 0 until pc.length()) counts[i] = pc.optInt(i, 0)
            }
            return UploadState(
                uploadDayType = o.optString("uploadDayType", "").ifBlank { null },
                lastUploadDate = o.optString("lastUploadDate", "").ifBlank { null },
                totalUploadsToday = o.optInt("totalUploadsToday", 0),
                dayTypeLockedDate = o.optString("dayTypeLockedDate", "").ifBlank { null },
                lastUsedProfileIndex = o.optInt("lastUsedProfileIndex", -1),
                totalProfilesAvailable = maxOf(1, o.optInt("totalProfilesAvailable", 3)),
                profileUploadCounts = counts,
            )
        }
    }
}

/** v25 Mix mode settings (dashboardSettings/variety) - shared by panel, app and the workflow. */
data class VarietyConfig(
    val enabled: Boolean = false,
    val strict: Boolean = false,
    val types: List<String> = ALL,
    val updatedAt: Long = 0L,
    val updatedBy: String? = null,
) {
    fun toJson(by: String = "app"): JSONObject {
        val arr = org.json.JSONArray(); types.forEach { arr.put(it) }
        return JSONObject().put("enabled", enabled).put("strict", strict).put("types", arr).put("updatedAt", System.currentTimeMillis()).put("updatedBy", by)
    }
    companion object {
        val ALL = listOf("RINGTONE", "WALLPAPER", "WALLPAPER_24H", "WALLPAPER_DUAL", "WALLPAPER_BATTERY", "LIVE_WALLPAPER", "CHARGING_ANIMATION")
        private val LABELS = mapOf(
            "RINGTONE" to "Ringtone", "WALLPAPER" to "Wallpaper", "WALLPAPER_24H" to "24H set", "WALLPAPER_DUAL" to "Dual set",
            "WALLPAPER_BATTERY" to "Battery set", "LIVE_WALLPAPER" to "Live wallpaper", "CHARGING_ANIMATION" to "Charging animation",
        )
        fun label(t: String): String = LABELS[t] ?: t
        /** Same rotation the workflow uses: start index = Dhaka day number % types.size */
        fun orderToday(types: List<String>): List<String> {
            if (types.isEmpty()) return emptyList()
            val dayNo = ((System.currentTimeMillis() + 6L * 3600_000L) / 86_400_000L).toInt()
            val s = dayNo % types.size
            return types.indices.map { types[(s + it) % types.size] }
        }
        fun from(data: Any?): VarietyConfig {
            val o = data as? JSONObject ?: return VarietyConfig()
            val arr = o.optJSONArray("types")
            var t = if (arr == null) emptyList() else (0 until arr.length()).mapNotNull { i -> arr.optString(i, "").uppercase().takeIf { it in ALL } }.distinct()
            if (t.isEmpty()) t = ALL
            return VarietyConfig(
                enabled = o.optBoolean("enabled", false),
                strict = o.optBoolean("strict", false),
                types = t,
                updatedAt = o.optLong("updatedAt", 0L),
                updatedBy = o.optString("updatedBy", "").ifBlank { null },
            )
        }
    }
}

/** uploadState/varietyUsed - which content types the bot already uploaded today (mix mode). */
data class VarietyUsed(val date: String?, val types: List<String>) {
    companion object {
        fun from(data: Any?): VarietyUsed? {
            val o = data as? JSONObject ?: return null
            val arr = o.optJSONArray("types")
            val t = if (arr == null) emptyList() else (0 until arr.length()).map { i -> arr.optString(i, "") }.filter { it.isNotBlank() }
            return VarietyUsed(o.optString("date", "").ifBlank { null }, t)
        }
    }
}


/** v26 Theme Studio - same JSON schema as the web panel (dashboardSettings/theme). */
data class ThemeConfig(
    val preset: String = "obsidian",
    val primary: String = "#7c5cff",
    val accent: String = "#22d3ee",
    val bg: String = "#070a14",
    val surface: String = "#111829",
    val text: String = "#e6ebff",
    val fontScale: Float = 1f,
    val radius: Float = 1f,
    val density: String = "comfortable",
    val updatedAt: Long = 0L,
    val updatedBy: String? = null,
    /** v27.8 per-element colours (same keys as the web panel Theme Studio "elements"). Missing key = Auto. */
    val elements: Map<String, String> = emptyMap(),
) {
    val isDark: Boolean get() = hexLuminance(bg) < 0.35

    fun element(key: String): String? = elements[key]

    fun withElement(key: String, hex: String?): ThemeConfig {
        val n = if (hex == null) "" else normHex(hex, "")
        val m = LinkedHashMap(elements)
        if (n.isEmpty()) m.remove(key) else m[key] = n
        return copy(elements = m)
    }

    fun sanitized(): ThemeConfig = copy(
        primary = normHex(primary, "#ffd400"),
        accent = normHex(accent, "#ffab00"),
        bg = normHex(bg, "#fffdf6"),
        surface = normHex(surface, "#ffffff"),
        text = normHex(text, "#211d12"),
        fontScale = fontScale.coerceIn(0.8f, 1.3f),
        radius = radius.coerceIn(0f, 1.6f),
        density = if (density == "compact") "compact" else "comfortable",
        elements = cleanElements(elements),
    )

    fun toJson(by: String = "app"): JSONObject = JSONObject()
        .put("preset", preset)
        .put("mode", if (isDark) "dark" else "light")
        .put("primary", primary).put("accent", accent).put("bg", bg).put("surface", surface).put("text", text)
        .put("fontScale", fontScale.toDouble()).put("radius", radius.toDouble()).put("density", density)
        .put("updatedAt", System.currentTimeMillis()).put("updatedBy", by).put("v271", 1)
        .put("elements", JSONObject().also { o -> elements.forEach { (k, v) -> o.put(k, v) } })

    fun matchesPreset(): Preset? = PRESETS.firstOrNull { it.primary == primary && it.accent == accent && it.bg == bg && it.surface == surface && it.text == text }

    fun withPreset(p: Preset): ThemeConfig = copy(preset = p.key, primary = p.primary, accent = p.accent, bg = p.bg, surface = p.surface, text = p.text)

    fun colorOf(key: String): String = when (key) {
        "primary" -> primary
        "accent" -> accent
        "bg" -> bg
        "surface" -> surface
        else -> text
    }

    fun withColor(key: String, hex: String): ThemeConfig {
        val c = when (key) {
            "primary" -> copy(primary = hex)
            "accent" -> copy(accent = hex)
            "bg" -> copy(bg = hex)
            "surface" -> copy(surface = hex)
            else -> copy(text = hex)
        }
        return c.copy(preset = c.matchesPreset()?.key ?: "custom")
    }

    data class Preset(val key: String, val name: String, val primary: String, val accent: String, val bg: String, val surface: String, val text: String)

    companion object {
        val PRESETS: List<Preset> = listOf(
            Preset("sunflower", "Sunflower", "#ffd400", "#ffab00", "#fffdf6", "#ffffff", "#211d12"),
            Preset("dark", "Dark Gold", "#ffd400", "#ffab00", "#0e0c08", "#181410", "#f7f1dc"),
            Preset("amoled", "AMOLED", "#ffd400", "#ffab00", "#000000", "#0c0c0c", "#f2f2f2"),
            Preset("ocean", "Ocean", "#2f80ed", "#56ccf2", "#f5f9ff", "#ffffff", "#0f1c2e"),
            Preset("midnight", "Midnight", "#4f8cff", "#7cc4ff", "#0a0f1e", "#121a2e", "#e6edff"),
            Preset("obsidian", "Obsidian Glass", "#7c5cff", "#22d3ee", "#070a14", "#111829", "#e6ebff"),
            Preset("aurora", "Aurora", "#34d399", "#60a5fa", "#06111f", "#0e1d31", "#e3f6ff"),
            Preset("ember", "Ember", "#fb7185", "#f59e0b", "#120a0f", "#1f121a", "#ffe9ee"),
            Preset("graphite", "Graphite", "#38bdf8", "#818cf8", "#0b0d12", "#151922", "#e5e7eb"),
            Preset("mint", "Mint", "#22c55e", "#10b981", "#f4fdf7", "#ffffff", "#0f2417"),
            Preset("rose", "Rose", "#ff5c8a", "#ff8fab", "#fff5f8", "#ffffff", "#2b1220"),
            Preset("violet", "Violet", "#a78bfa", "#c084fc", "#0f0a1e", "#1a1230", "#efe9ff"),
        )
        /** v27.8 element keys + labels (identical to the web panel Theme Studio). */
        val ELEMENT_KEYS: List<Pair<String, String>> = listOf(
            "header" to "Header / hero",
            "sidebar" to "Navigation bar",
            "card" to "Cards & panels",
            "button" to "Buttons",
            "ticker" to "Live ticker (web panel)",
            "badge" to "Badges & chips",
            "navActive" to "Active menu item",
        )

        fun cleanElements(m: Map<String, String>?): Map<String, String> {
            if (m == null) return emptyMap()
            val r = LinkedHashMap<String, String>()
            ELEMENT_KEYS.forEach { (k, _) -> val v = normHex(m[k], ""); if (v.isNotEmpty()) r[k] = v }
            return r
        }

        fun elementsFrom(o: JSONObject?): Map<String, String> {
            if (o == null) return emptyMap()
            val r = LinkedHashMap<String, String>()
            val keys = o.keys()
            while (keys.hasNext()) { val k = keys.next(); r[k] = o.optString(k, "") }
            return cleanElements(r)
        }

        private val HEX6 = Regex("^#[0-9a-f]{6}$")
        private val HEX3 = Regex("^#[0-9a-f]{3}$")

        fun normHex(s: String?, fallback: String): String {
            var h = (s ?: "").trim().lowercase()
            if (h.isNotEmpty() && h[0] != '#') h = "#" + h
            if (HEX3.matches(h)) h = "#" + h[1] + h[1] + h[2] + h[2] + h[3] + h[3]
            return if (HEX6.matches(h)) h else fallback
        }

        fun hexLuminance(hex: String): Double {
            val h = normHex(hex, "#ffffff")
            fun ch(i: Int): Double {
                val v = h.substring(i, i + 2).toInt(16) / 255.0
                return if (v <= 0.03928) v / 12.92 else Math.pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * ch(1) + 0.7152 * ch(3) + 0.0722 * ch(5)
        }

        fun from(data: Any?): ThemeConfig? {
            val o = data as? JSONObject ?: return null
            // v27.2: legacy yellow default saved by older panels is ignored -> app default (Obsidian)
            if (o.optString("preset", "") == "sunflower" && !o.has("v271")) return null
            return ThemeConfig(
                preset = o.optString("preset", "custom").ifBlank { "custom" },
                primary = o.optString("primary", ""),
                accent = o.optString("accent", ""),
                bg = o.optString("bg", ""),
                surface = o.optString("surface", ""),
                text = o.optString("text", ""),
                fontScale = o.optDouble("fontScale", 1.0).toFloat(),
                radius = o.optDouble("radius", 1.0).toFloat(),
                density = o.optString("density", "comfortable"),
                updatedAt = o.optLong("updatedAt", 0L),
                updatedBy = o.optString("updatedBy", "").ifBlank { null },
                elements = elementsFrom(o.optJSONObject("elements")),
            ).sanitized()
        }

        fun fromString(s: String?): ThemeConfig? = try {
            if (s.isNullOrBlank()) null else from(JSONObject(s))
        } catch (_: Exception) { null }
    }
}
