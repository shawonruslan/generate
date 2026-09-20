package com.zedge.contentstudio.desktop

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.ByteArrayInputStream
import java.io.File
import java.net.URI
import java.util.concurrent.TimeUnit
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem

/** Ringtone preview player (MP3 via mp3spi -> PCM -> javax.sound). play/pause/release + progress 0..1. */
class Mp3Player(private val url: String) {
    private val _playing = MutableStateFlow(false)
    val playing: StateFlow<Boolean> = _playing
    private val _progress = MutableStateFlow(0f)
    val progress: StateFlow<Float> = _progress
    val error = MutableStateFlow<String?>(null)

    @Volatile private var paused = false
    @Volatile private var stopped = false
    private var thread: Thread? = null

    fun play() {
        val t = thread
        if (t == null || !t.isAlive) start() else { paused = false; _playing.value = true }
    }
    fun pause() { paused = true; _playing.value = false }
    fun release() { stopped = true; paused = false; _playing.value = false; thread?.interrupt() }

    private fun start() {
        stopped = false; paused = false; _playing.value = true
        thread = Thread({
            try { loop() } catch (e: InterruptedException) { } catch (e: Exception) { error.value = e.message ?: "playback failed" }
            _playing.value = false
        }, "mp3-preview").apply { isDaemon = true; start() }
    }

    private fun fetch(): ByteArray {
        val lower = url.lowercase()
        if (lower.startsWith("http://") || lower.startsWith("https://")) {
            val http = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build()
            http.newCall(Request.Builder().url(url).build()).execute().use { r -> return r.body?.bytes() ?: ByteArray(0) }
        }
        val f = if (lower.startsWith("file:")) File(URI(url)) else File(url)
        return f.readBytes()
    }

    private fun loop() {
        val bytes = fetch()
        val durationUs: Long = runCatching {
            val ff = AudioSystem.getAudioFileFormat(ByteArrayInputStream(bytes))
            (ff.properties()["duration"] as? Long) ?: -1L
        }.getOrDefault(-1L)
        val src = AudioSystem.getAudioInputStream(ByteArrayInputStream(bytes))
        val base = src.format
        val rate = if (base.sampleRate > 0) base.sampleRate else 44100f
        val ch = if (base.channels > 0) base.channels else 2
        val fmt = AudioFormat(AudioFormat.Encoding.PCM_SIGNED, rate, 16, ch, ch * 2, rate, false)
        val pcm = AudioSystem.getAudioInputStream(fmt, src)
        val line = AudioSystem.getSourceDataLine(fmt)
        line.open(fmt)
        line.start()
        val buf = ByteArray(8192)
        var written = 0L
        val totalPcm = if (durationUs > 0) (durationUs / 1_000_000.0 * rate * ch * 2).toLong() else -1L
        try {
            while (!stopped) {
                if (paused) { Thread.sleep(40); continue }
                val n = pcm.read(buf)
                if (n < 0) break
                line.write(buf, 0, n)
                written += n
                if (totalPcm > 0) _progress.value = (written.toFloat() / totalPcm).coerceIn(0f, 1f)
            }
            if (!stopped) { line.drain(); _progress.value = 1f }
        } finally {
            runCatching { line.stop(); line.close(); pcm.close(); src.close() }
        }
    }
}
