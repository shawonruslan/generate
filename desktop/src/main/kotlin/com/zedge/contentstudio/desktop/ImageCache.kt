package com.zedge.contentstudio.desktop

import android.content.Storage
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import okhttp3.OkHttpClient
import okhttp3.Request
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.io.File
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import javax.imageio.ImageIO

/**
 * v30.6 PERF - memory (byte-budgeted LRU) + disk cache for remote thumbnails / previews.
 *
 * - Decodes with ImageIO source subsampling, so a 1620x2880 wallpaper never becomes a full-size ARGB bitmap in RAM.
 * - Every cached bitmap is capped at [MAX_SIDE] px - plenty for the 300 dp cards and the phone mockup on a 2x screen.
 * - At most [DECODE_PARALLELISM] decodes run at once, so a 35-item grid no longer causes a memory spike + GC storm.
 * - The memory cache is limited by bytes ([MAX_BYTES]) instead of "240 entries".
 *
 * Before v30.6 every thumbnail was decoded at up to 2200 px and up to 240 of them (~10 MB each) were kept inside a
 * 1 GB heap: the app froze, stuttered and the garbage collector ran non-stop.
 */
object ImageCache {
    const val MAX_SIDE = 1100
    private const val MAX_BYTES = 160L * 1024 * 1024
    private const val DECODE_PARALLELISM = 2
    private val http = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val gate = Semaphore(DECODE_PARALLELISM)
    private var memBytes = 0L
    private val mem = LinkedHashMap<String, ImageBitmap>(64, 0.75f, true)
    private val inFlight = ConcurrentHashMap<String, Deferred<ImageBitmap?>>()
    private val diskDir: File by lazy { File(Storage.cacheDir, "images").also { it.mkdirs() } }

    private fun bytesOf(b: ImageBitmap): Long = b.width.toLong() * b.height.toLong() * 4L

    private fun put(key: String, bmp: ImageBitmap) {
        synchronized(mem) {
            mem.remove(key)?.let { memBytes -= bytesOf(it) }
            mem[key] = bmp
            memBytes += bytesOf(bmp)
            val it = mem.entries.iterator()
            while (memBytes > MAX_BYTES && mem.size > 1 && it.hasNext()) {
                val e = it.next()
                if (e.key == key) continue
                memBytes -= bytesOf(e.value)
                it.remove()
            }
        }
    }

    fun peek(key: String): ImageBitmap? = synchronized(mem) { mem[key] }

    suspend fun load(key: String): ImageBitmap? {
        peek(key)?.let { return it }
        val d = inFlight.getOrPut(key) {
            scope.async {
                try {
                    val bmp = gate.withPermit { runCatching { decode(fetch(key)) }.getOrNull() }
                    if (bmp != null) put(key, bmp)
                    bmp
                } finally {
                    inFlight.remove(key)
                }
            }
        }
        return d.await()
    }

    private fun fetch(key: String): ByteArray? {
        val lower = key.lowercase()
        if (lower.startsWith("http://") || lower.startsWith("https://")) {
            val f = File(diskDir, sha1(key))
            if (f.isFile && f.length() > 0) return f.readBytes()
            http.newCall(Request.Builder().url(key).get().build()).execute().use { resp ->
                if (!resp.isSuccessful) return null
                val bytes = resp.body?.bytes() ?: return null
                runCatching { f.writeBytes(bytes) }
                return bytes
            }
        }
        val file = if (lower.startsWith("file:")) runCatching { File(URI(key)) }.getOrElse { File(key.removePrefix("file:")) } else File(key)
        return if (file.isFile) file.readBytes() else null
    }

    private fun decode(bytes: ByteArray?): ImageBitmap? {
        if (bytes == null) return null
        val img = readSubsampled(bytes) ?: ImageIO.read(ByteArrayInputStream(bytes)) ?: return null
        val side = maxOf(img.width, img.height)
        val out = if (side > MAX_SIDE) {
            val s = MAX_SIDE.toDouble() / side
            BitmapFactory.scale(img, maxOf(1, (img.width * s).toInt()), maxOf(1, (img.height * s).toInt()))
        } else img
        return out.toComposeImageBitmap()
    }

    /** Reads the image already reduced by an integer factor, so the full-resolution pixels never exist in memory. */
    private fun readSubsampled(bytes: ByteArray): BufferedImage? {
        return runCatching {
            ImageIO.createImageInputStream(ByteArrayInputStream(bytes)).use { iis ->
                val readers = ImageIO.getImageReaders(iis)
                if (!readers.hasNext()) return@use null
                val reader = readers.next()
                try {
                    reader.setInput(iis, true, true)
                    val w = reader.getWidth(0)
                    val h = reader.getHeight(0)
                    val factor = maxOf(1, maxOf(w, h) / MAX_SIDE)
                    val p = reader.defaultReadParam
                    if (factor > 1) p.setSourceSubsampling(factor, factor, 0, 0)
                    reader.read(0, p)
                } finally {
                    reader.dispose()
                }
            }
        }.getOrNull()
    }

    private fun sha1(s: String): String = MessageDigest.getInstance("SHA-1").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    fun clearDisk() { runCatching { diskDir.listFiles()?.forEach { it.delete() } } }

    fun clearMemory() { synchronized(mem) { mem.clear(); memBytes = 0L } }
}
