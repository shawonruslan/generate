package com.zedge.contentstudio.data

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import androidx.exifinterface.media.ExifInterface
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.Json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/** A file we are about to upload (from picker, share intent, or an extracted archive). */
class LocalFile(val name: String, val bytes: ByteArray, val mime: String) {
    val size: Long get() = bytes.size.toLong()
    val lower: String get() = name.lowercase()
    val isImage: Boolean get() = Regex("\\.(jpe?g|png|webp)$").containsMatchIn(lower)
    val isAudio: Boolean get() = lower.endsWith(".mp3")
    val isVideo: Boolean get() = Regex("\\.(mp4|mov)$").containsMatchIn(lower)
    val isArchive: Boolean get() = lower.endsWith(".zip") || lower.endsWith(".rar")
    val isJson: Boolean get() = lower.endsWith(".json")

    companion object {
        const val VIDEO_MAX_BYTES = 50L * 1024 * 1024

        fun mimeFor(name: String): String {
            val l = name.lowercase()
            return when {
                l.endsWith(".jpg") || l.endsWith(".jpeg") -> "image/jpeg"
                l.endsWith(".png") -> "image/png"
                l.endsWith(".webp") -> "image/webp"
                l.endsWith(".mp3") -> "audio/mpeg"
                l.endsWith(".mp4") -> "video/mp4"
                l.endsWith(".mov") -> "video/quicktime"
                l.endsWith(".zip") -> "application/zip"
                l.endsWith(".rar") -> "application/vnd.rar"
                else -> "application/octet-stream"
            }
        }

        suspend fun fromUri(context: Context, uri: Uri): LocalFile = withContext(Dispatchers.IO) {
            val cr: ContentResolver = context.contentResolver
            var name = uri.lastPathSegment ?: "file"
            cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) c.getString(idx)?.let { name = it }
                }
            }
            val bytes = cr.openInputStream(uri)?.use { it.readBytes() } ?: throw IOException("Cannot read $name")
            val mime = cr.getType(uri)?.takeIf { it != "application/octet-stream" } ?: mimeFor(name)
            LocalFile(name.substringAfterLast('/'), bytes, mime)
        }
    }
}

/** Cloudflare R2 worker gateway - identical protocol to the dashboard. */
class R2Uploader(private val http: OkHttpClient) {
    suspend fun upload(file: LocalFile, prefix: String): String = upload(file.bytes, file.name, file.mime, prefix)

    suspend fun upload(bytes: ByteArray, name: String, mime: String, prefix: String): String = withContext(Dispatchers.IO) {
        val cleaned = name.replace(Regex("[^a-zA-Z0-9.-]"), "_")
        val key = "$prefix/${System.currentTimeMillis()}_$cleaned"
        val req = Request.Builder()
            .url(Accounts.R2_WORKER_URL)
            .header("X-File-Name", key)
            .header("X-File-Type", mime)
            .post(bytes.toRequestBody(mime.toMediaType()))
            .build()
        http.newCall(req).execute().use { resp ->
            val body = resp.body?.string() ?: ""
            if (!resp.isSuccessful) throw IOException("R2 upload failed (${resp.code}) for $name")
            val url = try { JSONObject(body).optString("url") } catch (_: Exception) { "" }
            if (url.isBlank()) throw IOException("R2 returned no url for $name")
            url
        }
    }

    /** v19: HTTP 200/404 alone is NOT proof of deletion. Require a verified bucket receipt. */
    suspend fun delete(fileUrl: String): Boolean = withContext(Dispatchers.IO) {
        val key = keyFromUrl(fileUrl) ?: throw IOException("Invalid R2 URL; record retained")
        val payload = JSONObject().put("url", fileUrl).toString().toRequestBody("application/json; charset=utf-8".toMediaType())
        val req = Request.Builder().url(Accounts.R2_WORKER_URL)
            .header("X-R2-Delete-Protocol", "r2-delete-v1").header("Cache-Control", "no-store").delete(payload).build()
        http.newCall(req).execute().use { resp ->
            val text = resp.body?.string() ?: ""
            val receipt = try { JSONObject(text) } catch (_: Exception) { throw IOException("R2 HTTP ${resp.code}: unverified response. Deploy the v19 Worker.") }
            if (!resp.isSuccessful) throw IOException("R2 HTTP ${resp.code}: ${receipt.optString("error", "Delete failed")}")
            if (!receipt.optBoolean("ok") || !receipt.optBoolean("absent") || receipt.optString("deleteProtocol") != "r2-delete-v1" || receipt.optString("key") != key || receipt.optString("sourceUrl") != fileUrl)
                throw IOException("R2 deletion not verified. Deploy the v19 Worker with the correct bucket binding.")
            true
        }
    }

    companion object {
        /** Object key = URL path without the leading slash (percent-decoded), like the workflow does. */
        fun keyFromUrl(fileUrl: String): String? = try {
            val u = java.net.URI(fileUrl)
            if (u.scheme?.lowercase() !in setOf("http", "https") || u.host.isNullOrBlank()) null else u.path.trimStart('/').ifBlank { null }
        } catch (_: Exception) { null }

        private val URL_KEYS = setOf("fileUrl", "thumbUrl", "fileUrls", "files")

        /** Collect every http(s) URL stored under fileUrl / thumbUrl / fileUrls / files (set slots) in a queue row. */
        fun collectR2Urls(node: Any?, out: MutableSet<String>, underKey: Boolean = false) {
            when (val n = Json.norm(node)) {
                null -> {}
                is String -> if (underKey && n.startsWith("http", ignoreCase = true)) out.add(n)
                is org.json.JSONArray -> for (i in 0 until n.length()) collectR2Urls(n.opt(i), out, underKey)
                is JSONObject -> for (k in Json.keys(n)) collectR2Urls(n.opt(k), out, underKey || k in URL_KEYS)
                else -> {}
            }
        }
    }
}

object ImageUtils {
    const val TARGET_W = 1620
    const val TARGET_H = 2880

    /** Same as the dashboard's canvas resize: cover-scale, center crop, JPEG 0.92. */
    fun resizeToPortrait(bytes: ByteArray): ByteArray {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
        var sample = 1
        while (opts.outWidth / (sample * 2) >= TARGET_W && opts.outHeight / (sample * 2) >= TARGET_H) sample *= 2
        val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888 }
        var src = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOpts) ?: throw IOException("Unsupported image")
        src = applyExifRotation(bytes, src)

        val scale = maxOf(TARGET_W.toFloat() / src.width, TARGET_H.toFloat() / src.height)
        val nw = src.width * scale
        val nh = src.height * scale
        val dx = (TARGET_W - nw) / 2f
        val dy = (TARGET_H - nh) / 2f
        val out = Bitmap.createBitmap(TARGET_W, TARGET_H, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
        canvas.drawBitmap(src, null, android.graphics.RectF(dx, dy, dx + nw, dy + nh), paint)
        src.recycle()
        val bos = ByteArrayOutputStream()
        out.compress(Bitmap.CompressFormat.JPEG, 92, bos)
        out.recycle()
        return bos.toByteArray()
    }

    private fun applyExifRotation(bytes: ByteArray, bmp: Bitmap): Bitmap {
        val orientation = try {
            ExifInterface(bytes.inputStream()).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
        val m = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
            else -> return bmp
        }
        val r = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
        if (r !== bmp) bmp.recycle()
        return r
    }

    fun jpegName(name: String): String = name.replace(Regex("\\.[^.]+$"), "") + ".jpg"
}

object VideoUtils {
    /** Percentages of the duration used by the dashboard for thumbnail candidates. */
    val FRAME_POINTS = listOf(0.08, 0.28, 0.50, 0.72, 0.92)

    class Frame(val index: Int, val atMs: Long, val jpeg: ByteArray, val bitmap: Bitmap)

    /**
     * v28.4: robust frame capture.
     *  - keeps the real file extension so the extractor can sniff the container
     *  - falls back through CLOSEST_SYNC -> CLOSEST -> PREVIOUS_SYNC -> any frame
     *  - works when the container reports no duration (fixed offsets instead)
     *  - always releases the retriever
     */
    suspend fun captureFrames(context: Context, file: LocalFile): List<Frame> = withContext(Dispatchers.IO) {
        if (file.bytes.isEmpty()) throw IOException("Video file is empty or could not be read.")
        val ext = Regex("\\.[A-Za-z0-9]{2,4}$").find(file.lower)?.value ?: ".mp4"
        val tmp = File.createTempFile("vid", ext, context.cacheDir)
        val mr = MediaMetadataRetriever()
        try {
            tmp.writeBytes(file.bytes)
            mr.setDataSource(tmp.absolutePath)
            val duration = mr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val points: List<Long> = if (duration > 0L) {
                FRAME_POINTS.map { (duration * it).toLong().coerceIn(0L, (duration - 40L).coerceAtLeast(0L)) }
            } else {
                listOf(0L, 400L, 800L, 1200L, 1600L)
            }
            val frames = ArrayList<Frame>()
            points.forEachIndexed { i, at ->
                val bmp = grabFrame(mr, at)
                if (bmp != null) {
                    val jpeg = ImageUtils.resizeToPortrait(bitmapToBytes(bmp))
                    frames.add(Frame(i, at, jpeg, BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, BitmapFactory.Options().apply { inSampleSize = 4 })))
                    bmp.recycle()
                }
            }
            if (frames.isEmpty()) {
                val bmp = grabFrame(mr, 0L)
                    ?: throw IOException("No decodable frames in this video (unsupported codec or corrupt file).")
                val jpeg = ImageUtils.resizeToPortrait(bitmapToBytes(bmp))
                frames.add(Frame(0, 0L, jpeg, BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, BitmapFactory.Options().apply { inSampleSize = 4 })))
                bmp.recycle()
            }
            frames
        } finally {
            try { mr.release() } catch (_: Exception) {}
            tmp.delete()
        }
    }

    private fun grabFrame(mr: MediaMetadataRetriever, atMs: Long): Bitmap? {
        val us = atMs * 1000L
        val options = intArrayOf(
            MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            MediaMetadataRetriever.OPTION_CLOSEST,
            MediaMetadataRetriever.OPTION_PREVIOUS_SYNC,
            MediaMetadataRetriever.OPTION_NEXT_SYNC
        )
        for (opt in options) {
            val bmp = try { mr.getFrameAtTime(us, opt) } catch (_: Exception) { null }
            if (bmp != null) return bmp
        }
        return try { mr.frameAtTime } catch (_: Exception) { null }
    }

    private fun bitmapToBytes(b: Bitmap): ByteArray {
        val bos = ByteArrayOutputStream()
        b.compress(Bitmap.CompressFormat.JPEG, 95, bos)
        return bos.toByteArray()
    }
}
