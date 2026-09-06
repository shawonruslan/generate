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
) {
    companion object {
        fun from(data: Any?): UploadState? {
            val o = data as? JSONObject ?: return null
            return UploadState(
                uploadDayType = o.optString("uploadDayType", "").ifBlank { null },
                lastUploadDate = o.optString("lastUploadDate", "").ifBlank { null },
                totalUploadsToday = o.optInt("totalUploadsToday", 0),
                dayTypeLockedDate = o.optString("dayTypeLockedDate", "").ifBlank { null },
            )
        }
    }
}
