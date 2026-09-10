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
