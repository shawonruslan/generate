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
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.ByteArrayInputStream
import java.io.File
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import javax.imageio.ImageIO

/** Memory (LRU) + disk cache for remote thumbnails / previews. Local files are read directly. */
object ImageCache {
    private const val MAX_ENTRIES = 240
    private const val MAX_SIDE = 2200
    private val http = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mem = object : LinkedHashMap<String, ImageBitmap>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ImageBitmap>?): Boolean = size > MAX_ENTRIES
    }
    private val inFlight = ConcurrentHashMap<String, Deferred<ImageBitmap?>>()
    private val diskDir: File by lazy { File(Storage.cacheDir, "images").also { it.mkdirs() } }

    fun peek(key: String): ImageBitmap? = synchronized(mem) { mem[key] }

    suspend fun load(key: String): ImageBitmap? {
        peek(key)?.let { return it }
        val d = inFlight.getOrPut(key) {
            scope.async {
                val bmp = runCatching { decode(fetch(key)) }.getOrNull()
                if (bmp != null) synchronized(mem) { mem[key] = bmp }
                inFlight.remove(key)
                bmp
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
        var img = ImageIO.read(ByteArrayInputStream(bytes)) ?: return null
        val side = maxOf(img.width, img.height)
        if (side > MAX_SIDE) {
            val s = MAX_SIDE.toDouble() / side
            img = BitmapFactory.scale(img, maxOf(1, (img.width * s).toInt()), maxOf(1, (img.height * s).toInt()))
        }
        return img.toComposeImageBitmap()
    }

    private fun sha1(s: String): String = MessageDigest.getInstance("SHA-1").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    fun clearDisk() { runCatching { diskDir.listFiles()?.forEach { it.delete() } } }
}
