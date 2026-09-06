package com.zedge.contentstudio.data

import android.util.Log
import com.zedge.contentstudio.core.Json
import com.zedge.contentstudio.core.RealTime
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import kotlin.coroutines.coroutineContext

private const val TAG = "FirebaseRtdb"
private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()

/**
 * Firebase Realtime Database over the REST API - no google-services.json, no SDK.
 * Behaves exactly like the unauthenticated web SDK the dashboard uses.
 */
class FirebaseRtdb(private val http: OkHttpClient, val baseUrl: String) {

    private fun url(path: String, query: String = ""): String {
        val p = path.trim('/')
        return if (p.isEmpty()) "$baseUrl/.json$query" else "$baseUrl/$p.json$query"
    }

    private suspend fun exec(req: Request): String = withContext(Dispatchers.IO) {
        http.newCall(req).execute().use { resp ->
            captureServerTime(resp.header("Date"), resp.sentRequestAtMillis, resp.receivedResponseAtMillis)
            val body = resp.body?.string() ?: ""
            if (!resp.isSuccessful) {
                var msg = ""
                try { msg = JSONObject(body).optString("error") } catch (_: Exception) {}
                throw IOException("Firebase ${resp.code}: ${msg.ifBlank { resp.message }}")
            }
            body
        }
    }

    suspend fun get(path: String, shallow: Boolean = false): Any? =
        Json.parse(exec(Request.Builder().url(url(path, if (shallow) "?shallow=true" else "")).get().build()))

    suspend fun set(path: String, value: Any?) {
        val body = (value?.toString() ?: "null").toRequestBody(JSON_MEDIA)
        exec(Request.Builder().url(url(path)).put(body).build())
    }

    suspend fun update(path: String, patch: JSONObject) {
        exec(Request.Builder().url(url(path)).patch(patch.toString().toRequestBody(JSON_MEDIA)).build())
    }

    /** Like SDK push()+set(): returns the generated key. */
    suspend fun push(path: String, value: JSONObject): String {
        val res = exec(Request.Builder().url(url(path)).post(value.toString().toRequestBody(JSON_MEDIA)).build())
        return JSONObject(res).optString("name")
    }

    suspend fun delete(path: String) {
        exec(Request.Builder().url(url(path)).delete().build())
    }

    /** Lightweight request used only to read the server Date header. */
    suspend fun syncClock() {
        try { get("uploadState/lastUploadDate") } catch (e: Exception) { Log.w(TAG, "clock sync failed: ${e.message}") }
    }

    fun stream(path: String): RtdbStream = RtdbStream(http, url(path))

    companion object {
        fun serverTimestamp(): JSONObject = JSONObject().put(".sv", "timestamp")

        private val rfc1123 = DateTimeFormatter.RFC_1123_DATE_TIME
        fun captureServerTime(dateHeader: String?, t0: Long, t1: Long) {
            if (dateHeader.isNullOrBlank()) return
            try {
                val ms = ZonedDateTime.parse(dateHeader, rfc1123).toInstant().toEpochMilli() + 500 // header has 1s resolution
                RealTime.applyServerTime(ms, t0, t1)
            } catch (_: Exception) {}
        }

        fun streamingClient(base: OkHttpClient): OkHttpClient =
            base.newBuilder().readTimeout(0, TimeUnit.MILLISECONDS).build()
    }
}

/** One realtime value emitted by a stream; version guarantees StateFlow emits on every change. */
data class RtdbSnapshot(val version: Long, val data: Any?, val ready: Boolean)

/**
 * Server-Sent-Events listener for a database path (equivalent of onValue()).
 * Keeps a local mirror of the subtree and applies put/patch events.
 */
class RtdbStream(base: OkHttpClient, private val url: String) {
    private val client = FirebaseRtdb.streamingClient(base)
    private val _snapshot = MutableStateFlow(RtdbSnapshot(0, null, false))
    val snapshot: StateFlow<RtdbSnapshot> = _snapshot
    private var root: Any? = null
    private var version = 0L

    fun launchIn(scope: CoroutineScope): Job = scope.launch(Dispatchers.IO) {
        var backoff = 1000L
        while (isActive) {
            val call = client.newCall(
                Request.Builder().url(url).header("Accept", "text/event-stream").header("Cache-Control", "no-cache").build()
            )
            val handle = coroutineContext.job.invokeOnCompletion { call.cancel() }
            try {
                call.execute().use { resp ->
                    if (!resp.isSuccessful) throw IOException("stream HTTP ${resp.code}")
                    FirebaseRtdb.captureServerTime(resp.header("Date"), resp.sentRequestAtMillis, resp.receivedResponseAtMillis)
                    backoff = 1000L
                    val source = resp.body!!.source()
                    var event = ""
                    val data = StringBuilder()
                    while (isActive) {
                        val line = source.readUtf8Line() ?: break
                        when {
                            line.isEmpty() -> {
                                if (event.isNotEmpty()) handle(event, data.toString())
                                event = ""; data.setLength(0)
                            }
                            line.startsWith("event:") -> event = line.substring(6).trim()
                            line.startsWith("data:") -> {
                                if (data.isNotEmpty()) data.append('\n')
                                data.append(line.substring(5).trim())
                            }
                        }
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (isActive) Log.w(TAG, "stream dropped ($url): ${e.message}")
            } finally {
                handle.dispose()
            }
            if (!isActive) break
            delay(backoff)
            backoff = minOf(backoff * 2, 30_000L)
        }
    }

    private fun handle(event: String, data: String) {
        when (event) {
            "put" -> {
                val o = JSONObject(data)
                root = setAt(root, segments(o.optString("path", "/")), Json.norm(o.opt("data")))
                publish()
            }
            "patch" -> {
                val o = JSONObject(data)
                val base = segments(o.optString("path", "/"))
                val d = o.optJSONObject("data")
                if (d != null) for (k in Json.keys(d)) root = setAt(root, base + k, Json.norm(d.opt(k)))
                publish()
            }
            "cancel", "auth_revoked" -> throw IOException("stream $event")
            else -> {} // keep-alive
        }
    }

    private fun publish() {
        version++
        _snapshot.value = RtdbSnapshot(version, root, true)
    }

    private fun segments(path: String): List<String> = path.split('/').filter { it.isNotEmpty() }

    private fun setAt(node: Any?, segs: List<String>, value: Any?): Any? {
        if (segs.isEmpty()) return value
        val obj = (node as? JSONObject) ?: JSONObject()
        val head = segs[0]
        val child = setAt(Json.norm(obj.opt(head)), segs.drop(1), value)
        if (child == null) obj.remove(head) else obj.put(head, child)
        return if (obj.length() == 0) null else obj
    }
}
