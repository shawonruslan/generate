package com.zedge.contentstudio.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
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
import java.awt.RenderingHints
import java.awt.geom.AffineTransform
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.util.concurrent.TimeUnit
import javax.imageio.IIOImage
import javax.imageio.ImageIO
import javax.imageio.ImageWriteParam

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
            val f = uri.toFile()
            if (!f.isFile) throw IOException("Cannot read ${uri.lastPathSegment ?: uri}")
            LocalFile(f.name, f.readBytes(), mimeFor(f.name))
        }

        fun fromFile(f: File): LocalFile = LocalFile(f.name, f.readBytes(), mimeFor(f.name))
    }
}

// v28.2: same uploader as the Android app (was missing in the desktop copy)
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

    /** Same as the dashboard's canvas resize: cover-scale, center crop, JPEG 0.92 (Java2D edition). */
    fun resizeToPortrait(bytes: ByteArray): ByteArray {
        var src: BufferedImage = ImageIO.read(ByteArrayInputStream(bytes)) ?: throw IOException("Unsupported image")
        src = applyExifRotation(bytes, src)
        val scale = maxOf(TARGET_W.toDouble() / src.width, TARGET_H.toDouble() / src.height)
        val nw = src.width * scale
        val nh = src.height * scale
        val dx = (TARGET_W - nw) / 2.0
        val dy = (TARGET_H - nh) / 2.0
        val out = BufferedImage(TARGET_W, TARGET_H, BufferedImage.TYPE_INT_RGB)
        val g = out.createGraphics()
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC)
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY)
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        g.color = java.awt.Color.BLACK
        g.fillRect(0, 0, TARGET_W, TARGET_H)
        g.drawImage(src, AffineTransform().apply { translate(dx, dy); scale(scale, scale) }, null)
        g.dispose()
        return encodeJpeg(out, 0.92f)
    }

    fun encodeJpeg(img: BufferedImage, quality: Float): ByteArray {
        val rgb = if (img.type == BufferedImage.TYPE_INT_RGB) img else BufferedImage(img.width, img.height, BufferedImage.TYPE_INT_RGB).also {
            val g = it.createGraphics(); g.color = java.awt.Color.BLACK; g.fillRect(0, 0, img.width, img.height); g.drawImage(img, 0, 0, null); g.dispose()
        }
        val writer = ImageIO.getImageWritersByFormatName("jpeg").next()
        val params = writer.defaultWriteParam.apply { compressionMode = ImageWriteParam.MODE_EXPLICIT; compressionQuality = quality }
        val bos = ByteArrayOutputStream()
        ImageIO.createImageOutputStream(bos).use { ios -> writer.output = ios; writer.write(null, IIOImage(rgb, null, null), params) }
        writer.dispose()
        return bos.toByteArray()
    }

    /** Minimal EXIF orientation reader (JPEG APP1 / TIFF IFD0 tag 0x0112) - no Android ExifInterface on desktop. */
    fun exifOrientation(bytes: ByteArray): Int {
        try {
            if (bytes.size < 4 || (bytes[0].toInt() and 0xFF) != 0xFF || (bytes[1].toInt() and 0xFF) != 0xD8) return 1
            var i = 2
            while (i + 4 <= bytes.size) {
                if ((bytes[i].toInt() and 0xFF) != 0xFF) return 1
                val marker = bytes[i + 1].toInt() and 0xFF
                val len = ((bytes[i + 2].toInt() and 0xFF) shl 8) or (bytes[i + 3].toInt() and 0xFF)
                if (marker == 0xE1 && i + 10 <= bytes.size && String(bytes, i + 4, 4, Charsets.US_ASCII) == "Exif") {
                    val t = i + 10 // TIFF header
                    val le = bytes[t] == 'I'.code.toByte()
                    fun u16(p: Int) = if (le) (bytes[p].toInt() and 0xFF) or ((bytes[p + 1].toInt() and 0xFF) shl 8) else ((bytes[p].toInt() and 0xFF) shl 8) or (bytes[p + 1].toInt() and 0xFF)
                    fun u32(p: Int) = if (le) (u16(p).toLong() or (u16(p + 2).toLong() shl 16)) else ((u16(p).toLong() shl 16) or u16(p + 2).toLong())
                    val ifd = t + u32(t + 4).toInt()
                    val n = u16(ifd)
                    for (k in 0 until n) {
                        val e = ifd + 2 + k * 12
                        if (e + 12 > bytes.size) break
                        if (u16(e) == 0x0112) return u16(e + 8)
                    }
                    return 1
                }
                if (marker == 0xDA) return 1
                i += 2 + len
            }
        } catch (_: Exception) {}
        return 1
    }

    private fun applyExifRotation(bytes: ByteArray, img: BufferedImage): BufferedImage {
        val deg = when (exifOrientation(bytes)) { 6 -> 90; 3 -> 180; 8 -> 270; else -> return img }
        val w = img.width; val h = img.height
        val out = if (deg == 180) BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB) else BufferedImage(h, w, BufferedImage.TYPE_INT_ARGB)
        val g = out.createGraphics()
        val at = AffineTransform()
        when (deg) {
            90 -> { at.translate(h.toDouble(), 0.0); at.rotate(Math.PI / 2) }
            180 -> { at.translate(w.toDouble(), h.toDouble()); at.rotate(Math.PI) }
            270 -> { at.translate(0.0, w.toDouble()); at.rotate(-Math.PI / 2) }
        }
        g.drawImage(img, at, null)
        g.dispose()
        return out
    }

    fun jpegName(name: String): String = name.replace(Regex("\\.[^.]+$"), "") + ".jpg"
}

/** Video frame capture on Windows uses ffmpeg (bundled next to the app, in %APPDATA%\ZedgeContentStudio\bin, or on PATH). */
object VideoUtils {
    /** Percentages of the duration used by the dashboard for thumbnail candidates. */
    val FRAME_POINTS = listOf(0.08, 0.28, 0.50, 0.72, 0.92)

    class Frame(val index: Int, val atMs: Long, val jpeg: ByteArray, val bitmap: Bitmap)

    fun ffmpegPath(): String? {
        val exe = if (System.getProperty("os.name").lowercase().contains("win")) "ffmpeg.exe" else "ffmpeg"
        val candidates = ArrayList<File>()
        System.getenv("FFMPEG_PATH")?.takeIf { it.isNotBlank() }?.let { candidates.add(File(it)) }
        candidates.add(File(android.content.Storage.baseDir, "bin/$exe"))
        System.getProperty("compose.application.resources.dir")?.let { candidates.add(File(it, exe)) }
        candidates.add(File(System.getProperty("user.dir"), exe))
        candidates.add(File(System.getProperty("user.dir"), "ffmpeg/$exe"))
        System.getenv("PATH")?.split(File.pathSeparator)?.forEach { candidates.add(File(it, exe)) }
        return candidates.firstOrNull { it.isFile }?.absolutePath
    }

    private fun run(cmd: List<String>, timeoutSec: Long = 60): Pair<Int, String> {
        val p = ProcessBuilder(cmd).redirectErrorStream(true).start()
        val text = p.inputStream.bufferedReader().readText()
        if (!p.waitFor(timeoutSec, TimeUnit.SECONDS)) { p.destroyForcibly(); return -1 to text }
        return p.exitValue() to text
    }

    fun durationMs(ffmpeg: String, file: File): Long {
        val (_, out) = run(listOf(ffmpeg, "-hide_banner", "-i", file.absolutePath))
        val m = Regex("Duration: (\\d+):(\\d+):(\\d+)\\.(\\d+)").find(out) ?: return 0L
        val (h, mi, s, frac) = m.destructured
        return ((h.toLong() * 3600 + mi.toLong() * 60 + s.toLong()) * 1000) + (frac.padEnd(3, '0').take(3).toLong())
    }

    suspend fun captureFrames(context: Context, file: LocalFile): List<Frame> = withContext(Dispatchers.IO) {
        val ffmpeg = ffmpegPath() ?: throw IOException(
            "ffmpeg.exe not found. Put ffmpeg.exe in %APPDATA%\\ZedgeContentStudio\\bin (or add it to PATH) to capture video frames.")
        val tmp = File.createTempFile("vid", ".bin", context.cacheDir)
        val outDir = File(context.cacheDir, "frames-" + System.nanoTime()).also { it.mkdirs() }
        try {
            tmp.writeBytes(file.bytes)
            val duration = durationMs(ffmpeg, tmp)
            val frames = ArrayList<Frame>()
            FRAME_POINTS.forEachIndexed { i, p ->
                val at = (duration * p).toLong()
                val out = File(outDir, "f$i.jpg")
                val sec = String.format(java.util.Locale.US, "%.3f", at / 1000.0)
                val (code, _) = run(listOf(ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-ss", sec, "-i", tmp.absolutePath, "-frames:v", "1", "-q:v", "2", out.absolutePath))
                if (code != 0 || !out.isFile || out.length() == 0L) return@forEachIndexed
                val jpeg = ImageUtils.resizeToPortrait(out.readBytes())
                frames.add(Frame(i, at, jpeg, BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, BitmapFactory.Options().apply { inSampleSize = 4 })!!))
            }
            frames
        } finally {
            tmp.delete()
            outDir.listFiles()?.forEach { it.delete() }
            outDir.delete()
        }
    }
}
