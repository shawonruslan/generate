package com.zedge.contentstudio.data

import android.content.Context
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.Fmt
import com.zedge.contentstudio.core.Json
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.domain.ArchiveClassifier
import com.zedge.contentstudio.domain.ArchiveReader
import com.zedge.contentstudio.domain.ImportUnit
import com.zedge.contentstudio.domain.SetUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import org.json.JSONObject
import org.json.JSONArray
import com.zedge.contentstudio.domain.GateHealth
import com.zedge.contentstudio.domain.RunSchedule
import java.util.concurrent.TimeUnit

/** Progress callback text for long uploads. */
typealias Progress = (String) -> Unit

/**
 * All queue mutations for every account. One instance per app (see ContentStudioApp).
 * Mirrors the dashboard's Firebase writes key for key (same paths, same payload fields).
 */
class QueueRepository(private val context: Context) {
    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(300, TimeUnit.SECONDS)
        .build()

    private val dbs: Map<String, FirebaseRtdb> = Accounts.all.associate { it.key to FirebaseRtdb(http, it.databaseUrl) }
    fun db(key: String): FirebaseRtdb = dbs.getValue(key)
    val r2 = R2Uploader(http)

    private val prefs = context.getSharedPreferences("content_studio", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // ---- active account + realtime streams ----
    private val _activeKey = MutableStateFlow(prefs.getString("activeProject", "zedge1").let { if (Accounts.isValid(it)) it!! else "zedge1" })
    val activeKey: StateFlow<String> = _activeKey

    private var connectionJob: Job? = null

    private val _queue = MutableStateFlow<List<QueueItem>>(emptyList())
    val queue: StateFlow<List<QueueItem>> = _queue
    private val _uploadState = MutableStateFlow<UploadState?>(null)
    val uploadState: StateFlow<UploadState?> = _uploadState
    private val _connected = MutableStateFlow(false)
    val connected: StateFlow<Boolean> = _connected

    /** Global upload lock (one long job at a time) - same as the dashboard's acquireUploadLock(). */
    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy
    fun tryLock(): Boolean { if (_busy.value) return false; _busy.value = true; return true }
    fun unlock() { _busy.value = false }

    /** Round-robin pointer for Multi-Account Distribution (session scoped, like the web). */
    var distPointer = 0
    val distPushedNames = HashSet<String>()

    // ---- v9: live upload schedule + gate health for every account ----
    private val _schedules = MutableStateFlow(RunSchedule.DEFAULT_WINDOWS)
    val schedules: StateFlow<Map<String, List<Int>>> = _schedules
    private val _scheduleSource = MutableStateFlow<Map<String, String>>(emptyMap())   // key -> "firebase" | "default"
    val scheduleSource: StateFlow<Map<String, String>> = _scheduleSource
    private val _gateHealth = MutableStateFlow<Map<String, GateHealth?>>(emptyMap())
    val gateHealth: StateFlow<Map<String, GateHealth?>> = _gateHealth

    init {
        connect(_activeKey.value)
        for (acc in Accounts.all) subscribeSchedule(acc.key)
    }

    private fun subscribeSchedule(key: String) {
        val d = db(key)
        scope.launch {
            val sch = d.stream("dashboardSettings/schedule")
            val gate = d.stream("dashboardSettings/gate")
            sch.launchIn(this)
            gate.launchIn(this)
            launch {
                sch.snapshot.collect { snap ->
                    if (!snap.ready) return@collect
                    val obj = snap.data as? JSONObject
                    val arr = obj?.optJSONArray("windows")
                    val w = arr?.let { a -> (0 until a.length()).mapNotNull { i -> a.optInt(i, -1).takeIf { it in 0..23 } } }?.takeIf { it.isNotEmpty() }
                    RunSchedule.setWindows(key, w)
                    _schedules.value = RunSchedule.windows
                    _scheduleSource.value = _scheduleSource.value + (key to (if (w != null) "firebase" else "default"))
                    RealTime.bump()   // re-plan the calendar with the new windows
                }
            }
            launch {
                gate.snapshot.collect { snap ->
                    if (!snap.ready) return@collect
                    _gateHealth.value = _gateHealth.value + (key to parseGate(snap.data as? JSONObject))
                }
            }
        }
    }

    private fun parseGate(o: JSONObject?): GateHealth? {
        if (o == null) return null
        val today = RealTime.key(RealTime.dhakaDate(0))   // gate writes YYYY-MM-DD
        val runsObj = o.optJSONObject("runs")?.optJSONObject(today)
        val runs = runsObj?.let { r -> Json.keys(r).sortedBy { it.toIntOrNull() ?: 0 }.map { k ->
            val e = r.optJSONObject(k)
            "W${(k.toIntOrNull() ?: 0) + 1} ${e?.optString("dhaka") ?: ""}" + (if (e?.optBoolean("catchUp") == true) " (catch-up)" else "")
        } } ?: emptyList()
        val wu = o.optJSONArray("windowsUsed")?.let { a -> (0 until a.length()).map { a.optInt(it) } }
        // v13 cross-account: window index -> real run time, so every account shows true status
        val doneW = mutableSetOf<Int>()
        val doneT = mutableMapOf<Int, String>()
        runsObj?.let { r ->
            Json.keys(r).forEach { k ->
                val idx = k.toIntOrNull() ?: return@forEach
                doneW.add(idx)
                val e = r.optJSONObject(k)
                val t = e?.optString("dhaka")?.takeIf { it.isNotBlank() }
                if (t != null) doneT[idx] = t.trim().substringAfterLast(' ') + (if (e.optBoolean("catchUp")) " (catch-up)" else "")
            }
        }
        return GateHealth(
            lastPing = o.optLong("lastPing", 0L).takeIf { it > 0 },
            lastPingDhaka = o.optString("lastPingDhaka").takeIf { it.isNotBlank() },
            lastDecision = o.optString("lastDecision").takeIf { it.isNotBlank() },
            lastRunDhaka = o.optString("lastRunDhaka").takeIf { it.isNotBlank() },
            windowsUsed = wu, runsToday = runs, runWindows = doneW, runWindowTimes = doneT,
        )
    }

    /** Save a new upload schedule for one account (same payload as the dashboard). */
    suspend fun saveSchedule(key: String, windows: List<Int>) {
        val arr = JSONArray(); windows.sorted().forEach { arr.put(it) }
        db(key).set("dashboardSettings/schedule", Json.obj("windows" to arr, "updatedAt" to System.currentTimeMillis(), "updatedBy" to "app"))
    }

    fun connect(key: String) {
        val k = if (Accounts.isValid(key)) key else "zedge1"
        connectionJob?.cancel()
        _connected.value = false
        _queue.value = emptyList()
        _uploadState.value = null
        _activeKey.value = k
        prefs.edit().putString("activeProject", k).apply()
        val d = db(k)
        connectionJob = scope.launch {
            val qs = d.stream(Accounts.QUEUE_PATH)
            val ss = d.stream(Accounts.STATE_PATH)
            qs.launchIn(this)
            ss.launchIn(this)
            launch { qs.snapshot.collect { snap -> if (snap.ready) { _queue.value = QueueItem.listFrom(snap.data); _connected.value = true } } }
            launch { ss.snapshot.collect { snap -> if (snap.ready) _uploadState.value = UploadState.from(snap.data) } }
            launch { d.syncClock() }
        }
    }

    // ---- helpers ----
    private fun basePayload(): JSONObject = Json.obj(
        "title" to "", "tags" to "", "category" to "", "description" to "",
        "status" to "queued", "createdAt" to FirebaseRtdb.serverTimestamp()
    )

    private fun merge(vararg parts: JSONObject): JSONObject {
        val o = JSONObject()
        for (p in parts) for (k in Json.keys(p)) o.put(k, p.opt(k))
        return o
    }

    private suspend fun pushQueue(dbKey: String, payload: JSONObject): String = db(dbKey).push(Accounts.QUEUE_PATH, payload)

    // ---- 1. Plain queue upload (images -> 1620x2880 JPEG, mp3 -> ringtone) ----
    suspend fun uploadPlainFile(file: LocalFile, dbKey: String = activeKey.value, progress: Progress = {}) {
        val isAudio = file.mime == "audio/mpeg" || file.isAudio
        val payload: JSONObject
        if (isAudio) {
            progress("Uploading ringtone ${file.name}...")
            val url = r2.upload(file, dbKey)
            payload = Json.obj("name" to file.name, "type" to file.mime.ifBlank { "audio/mpeg" }, "size" to file.size, "isMp3" to true, "contentType" to "RINGTONE", "fileUrl" to url)
        } else {
            progress("Resizing ${file.name}...")
            val resized = withContext(Dispatchers.Default) { ImageUtils.resizeToPortrait(file.bytes) }
            progress("Uploading ${file.name}...")
            val url = r2.upload(resized, file.name, "image/jpeg", dbKey)
            payload = Json.obj("name" to file.name, "type" to "image/jpeg", "size" to resized.size, "width" to 1620, "height" to 2880, "isMp3" to false, "contentType" to "WALLPAPER", "fileUrl" to url)
        }
        pushQueue(dbKey, merge(payload, basePayload()))
    }

    // ---- 2. Manual set upload (24H / Dual / Battery slot pickers) ----
    suspend fun submitSet(type: String, slotFiles: Map<String, LocalFile>, dbKey: String = activeKey.value, progress: Progress = {}) {
        val meta = ContentTypes.SET_TYPES.getValue(type)
        val files = JSONObject()
        var total = 0L
        for (slot in meta.slots) {
            val f = slotFiles[slot] ?: throw IllegalStateException("Missing $slot image")
            progress("Resizing & uploading $slot image...")
            val resized = withContext(Dispatchers.Default) { ImageUtils.resizeToPortrait(f.bytes) }
            files.put(slot, r2.upload(resized, "${meta.prefix}_${slot}_${f.name}", "image/jpeg", "$dbKey/${meta.prefix}"))
            total += resized.size
        }
        val payload = Json.obj(
            "name" to "${meta.label} ${RealTime.stamp()}", "type" to "image/jpeg", "size" to total, "isMp3" to false,
            "contentType" to type, "files" to files, "fileUrl" to files.optString(meta.slots[0])
        )
        pushQueue(dbKey, merge(payload, basePayload()))
    }

    // ---- 3. Video (Live wallpaper / Charging animation) with chosen cover frame ----
    suspend fun submitVideo(type: String, file: LocalFile, thumbJpeg: ByteArray, dbKey: String = activeKey.value, progress: Progress = {}) {
        val meta = ContentTypes.VIDEO_TYPES.getValue(type)
        if (file.size > LocalFile.VIDEO_MAX_BYTES) throw IllegalStateException("Video must be 50 MB or smaller")
        progress("Uploading video ${file.name}...")
        val videoUrl = r2.upload(file.bytes, "${meta.prefix}_${file.name}", file.mime.ifBlank { "video/mp4" }, "$dbKey/${meta.prefix}")
        progress("Uploading cover thumbnail...")
        val thumbUrl = r2.upload(thumbJpeg, "${meta.prefix}_thumb_${file.name}.jpg", "image/jpeg", "$dbKey/${meta.prefix}")
        val payload = Json.obj(
            "name" to file.name, "type" to file.mime.ifBlank { "video/mp4" }, "size" to file.size, "isMp3" to false,
            "contentType" to type, "fileUrl" to videoUrl, "thumbUrl" to thumbUrl
        )
        pushQueue(dbKey, merge(payload, basePayload()))
    }

    // ---- 4. Distribution payload for a single media file ----
    suspend fun buildDistributionPayload(file: LocalFile, dbKey: String, videoType: String, progress: Progress): JSONObject {
        if (file.mime == "audio/mpeg" || file.isAudio) {
            val url = r2.upload(file, dbKey)
            return Json.obj("name" to file.name, "type" to file.mime.ifBlank { "audio/mpeg" }, "size" to file.size, "isMp3" to true, "contentType" to "RINGTONE", "fileUrl" to url)
        }
        if (file.mime.startsWith("video/") || file.isVideo) {
            val vType = if (videoType == "CHARGING_ANIMATION") "CHARGING_ANIMATION" else "LIVE_WALLPAPER"
            val vMeta = ContentTypes.VIDEO_TYPES.getValue(vType)
            progress("Capturing cover thumbnail from ${file.name}...")
            val frames = VideoUtils.captureFrames(context, file)
            if (frames.isEmpty()) throw IllegalStateException("Could not read video ${file.name}")
            val thumb = frames[frames.size / 2].jpeg
            progress("Uploading ${vMeta.label} ${file.name} -> ${dbKey.uppercase()}...")
            val url = r2.upload(file.bytes, "${vMeta.prefix}_${file.name}", file.mime.ifBlank { "video/mp4" }, "$dbKey/${vMeta.prefix}")
            val thumbUrl = r2.upload(thumb, "${vMeta.prefix}_thumb_${file.name}.jpg", "image/jpeg", "$dbKey/${vMeta.prefix}")
            return Json.obj("name" to file.name, "type" to file.mime.ifBlank { "video/mp4" }, "size" to file.size, "isMp3" to false, "contentType" to vType, "fileUrl" to url, "thumbUrl" to thumbUrl)
        }
        val resized = withContext(Dispatchers.Default) { ImageUtils.resizeToPortrait(file.bytes) }
        val url = r2.upload(resized, file.name, "image/jpeg", dbKey)
        return Json.obj("name" to file.name, "type" to "image/jpeg", "size" to resized.size, "width" to 1620, "height" to 2880, "isMp3" to false, "contentType" to "WALLPAPER", "fileUrl" to url)
    }

    /** Upload a detected set's slot images and return its queue payload. */
    suspend fun buildSetPayload(unit: SetUnit, dbKey: String, onSlot: (String) -> Unit): JSONObject {
        val meta = unit.meta
        val urls = JSONObject()
        var total = 0L
        for (slot in meta.slots) {
            onSlot(slot)
            val entry = unit.files.getValue(slot)
            val resized = withContext(Dispatchers.Default) { ImageUtils.resizeToPortrait(entry.bytes) }
            urls.put(slot, r2.upload(resized, "${meta.prefix}_${slot}_${entry.base}", "image/jpeg", "$dbKey/${meta.prefix}"))
            total += resized.size
        }
        return Json.obj(
            "name" to if (unit.label.isNotBlank()) "${meta.label} - ${unit.label}" else "${meta.label} ${RealTime.stamp()}",
            "type" to "image/jpeg", "size" to total, "isMp3" to false, "contentType" to unit.type, "files" to urls, "fileUrl" to urls.optString(meta.slots[0])
        )
    }

    // ---- 5. Smart archive import (mode queue | distribute) ----
    class SmartPlan(val units: List<ImportUnit>, val notes: List<String>, val problems: List<String>) {
        val setUnits: List<SetUnit> get() = units.filterIsInstance<ImportUnit.Set>().map { it.set }
        val summary: String get() = ArchiveClassifier.describe(units)
    }

    suspend fun planSmartImport(archives: List<LocalFile>, fallbackType: String? = null, progress: Progress = {}): SmartPlan {
        val units = ArrayList<ImportUnit>()
        val notes = ArrayList<String>()
        val problems = ArrayList<String>()
        for (af in archives) {
            progress("Reading ${af.name} (${Fmt.bytes(af.size)})...")
            val entries = try { ArchiveReader.read(af) } catch (e: Exception) { problems.add("${af.name}: ${e.message}"); continue }
            val r = ArchiveClassifier.classify(entries, af.name, fallbackType)
            if (r.mediaCount == 0) problems.add("${af.name}: no images / mp3 / videos inside")
            units.addAll(r.units); notes.addAll(r.notes)
        }
        return SmartPlan(units, notes, problems)
    }

    class ImportResult(val ok: Int, val total: Int, val failed: List<String>)

    suspend fun runSmartImport(plan: SmartPlan, distribute: Boolean, videoType: String, progress: (Int, Int, String) -> Unit): ImportResult {
        var ok = 0
        val failed = ArrayList<String>()
        val total = plan.units.size
        plan.units.forEachIndexed { i, u ->
            val dbKey = if (distribute) Accounts.distOrder[distPointer % Accounts.distOrder.size] else activeKey.value
            val title = u.title
            val dest = if (distribute) " -> ${dbKey.uppercase()}" else ""
            try {
                val payload = when (u) {
                    is ImportUnit.Set -> buildSetPayload(u.set, dbKey) { slot -> progress(i, total, "${i + 1}/$total $title - $slot: uploading$dest") }
                    is ImportUnit.File -> {
                        progress(i, total, "${i + 1}/$total $title: uploading$dest")
                        buildDistributionPayload(u.entry.toLocalFile(), dbKey, videoType) { progress(i, total, it) }
                    }
                }
                val archive = when (u) { is ImportUnit.Set -> u.set.archive; is ImportUnit.File -> u.entry.archive }
                val extra = Json.obj("importedFrom" to archive.ifBlank { null })
                if (distribute) extra.put("distributedTo", dbKey)
                pushQueue(dbKey, merge(payload, basePayload(), extra))
                ok++
                if (distribute) { distPointer++; distPushedNames.add(title) }
            } catch (e: Exception) {
                failed.add("$title: ${e.message}")
            }
        }
        return ImportResult(ok, total, failed)
    }

    // ---- 6. Multi-account distribution of loose files ----
    suspend fun distributeFiles(files: List<LocalFile>, videoType: String, progress: (Int, Int, String) -> Unit): ImportResult {
        var ok = 0
        val failed = ArrayList<String>()
        files.forEachIndexed { i, f ->
            val dbKey = Accounts.distOrder[distPointer % Accounts.distOrder.size]
            try {
                progress(i, files.size, "${i + 1}/${files.size} ${f.name} -> ${dbKey.uppercase()}")
                val payload = buildDistributionPayload(f, dbKey, videoType) { progress(i, files.size, it) }
                pushQueue(dbKey, merge(payload, basePayload(), Json.obj("distributedTo" to dbKey)))
                ok++; distPointer++; distPushedNames.add(f.name)
            } catch (e: Exception) { failed.add("${f.name}: ${e.message}") }
        }
        return ImportResult(ok, files.size, failed)
    }

    /** Set-mode distribution: loose images grouped N at a time in natural name order. */
    suspend fun distributeSets(type: String, groups: List<List<Pair<String, LocalFile>>>, progress: (Int, Int, String) -> Unit): ImportResult {
        val meta = ContentTypes.SET_TYPES.getValue(type)
        var ok = 0
        val failed = ArrayList<String>()
        groups.forEachIndexed { sIdx, chunk ->
            val dbKey = Accounts.distOrder[distPointer % Accounts.distOrder.size]
            try {
                val filesMap = JSONObject()
                var total = 0L
                chunk.forEachIndexed { j, (slot, f) ->
                    progress(sIdx, groups.size, "${meta.short} set ${sIdx + 1}/${groups.size}: uploading image ${j + 1}/${meta.slots.size} ($slot: ${f.name}) -> ${dbKey.uppercase()}")
                    val resized = withContext(Dispatchers.Default) { ImageUtils.resizeToPortrait(f.bytes) }
                    filesMap.put(slot, r2.upload(resized, "${meta.prefix}_${slot}_${f.name}", "image/jpeg", "$dbKey/${meta.prefix}"))
                    total += resized.size
                }
                val payload = Json.obj(
                    "name" to "${meta.label} ${RealTime.stamp()}", "type" to "image/jpeg", "size" to total, "isMp3" to false,
                    "contentType" to type, "importedFrom" to null, "files" to filesMap, "fileUrl" to filesMap.optString(meta.slots[0]),
                    "distributedTo" to dbKey
                )
                pushQueue(dbKey, merge(payload, basePayload()))
                ok++; distPointer++
            } catch (e: Exception) { failed.add("Set ${sIdx + 1}: ${e.message}") }
        }
        return ImportResult(ok, groups.size, failed)
    }

    // ---- 7. Item edits ----
    suspend fun saveMetadata(item: QueueItem, title: String, tags: String, category: String, description: String, scheduledDate: String?) {
        val patch = Json.obj(
            "title" to title.trim(), "tags" to tags.trim(), "category" to category.trim().uppercase(), "description" to description.trim(),
            "scheduledDate" to scheduledDate?.takeIf { it.isNotBlank() }
        )
        db(activeKey.value).update("${Accounts.QUEUE_PATH}/${item.id}", patch)
    }

    suspend fun requeue(item: QueueItem) = requeueMany(listOf(item.id))

    /** Multi-path update: put failed rows back in the queue and clear the failure fields (same as the dashboard). */
    suspend fun requeueMany(ids: Collection<String>) {
        if (ids.isEmpty()) return
        val account = activeKey.value
        val fresh = Json.norm(db(account).get(Accounts.QUEUE_PATH)) as? JSONObject
        if (ids.any { !fresh?.optJSONObject(it)?.optString("deleteState").isNullOrBlank() })
            throw java.io.IOException("Deletion pending/incomplete. Retry Delete, not Requeue.")
        val patch = JSONObject()
        for (id in ids) {
            patch.put("${Accounts.QUEUE_PATH}/$id/status", "queued")
            patch.put("${Accounts.QUEUE_PATH}/$id/error", JSONObject.NULL)
            patch.put("${Accounts.QUEUE_PATH}/$id/failedAt", JSONObject.NULL)
            patch.put("${Accounts.QUEUE_PATH}/$id/processingAt", JSONObject.NULL)
            patch.put("${Accounts.QUEUE_PATH}/$id/requeuedAt", FirebaseRtdb.serverTimestamp())
        }
        db(account).update("", patch)
    }

    /** v19: verified R2 deletion before removing any Firebase record. */
    data class PurgeResult(val rows: Int, val files: Int, val kept: Int, val failed: Int, val verifyFailed: Boolean,
        val retained: Int = 0, val detail: String = "", val deletedIds: Set<String> = emptySet()) {
        val ok: Boolean get() = failed == 0 && !verifyFailed && retained == 0 && kept == 0
        fun summary(what: String = "item(s)"): String = "Deleted $rows $what · $files R2 object(s) verified absent" +
            (if (retained > 0) " · $retained record(s) kept — retry/review required" else "") +
            (if (kept > 0) " · $kept shared/in-use or invalid item(s) blocked" else "") +
            (if (detail.isNotBlank()) " · $detail" else "")
    }
    private val purgeMutex = kotlinx.coroutines.sync.Mutex()

    suspend fun purge(items: Collection<QueueItem>, onProgress: (String, Int, Int) -> Unit = { _, _, _ -> }): PurgeResult {
        val account = activeKey.value
        if (items.isEmpty()) return PurgeResult(0, 0, 0, 0, false)
        onProgress("Checking all account queues…", 0, 0)
        return purgeMutex.withLock {
            val ids = items.map { it.id }.toSet()
            val snapshots = LinkedHashMap<String, JSONObject>()
            try {
                for (key in Accounts.keys) snapshots[key] = Json.norm(db(key).get(Accounts.QUEUE_PATH)) as? JSONObject ?: JSONObject()
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                return@withLock PurgeResult(0, 0, 0, 0, true, ids.size, "Could not verify all account queues. Nothing deleted: ${e.message}")
            }
            val rows = LinkedHashMap<String, JSONObject>()
            val refs = LinkedHashMap<String, Set<String>>()
            val urls = LinkedHashMap<String, String>()
            val outside = HashSet<String>()
            val blocked = LinkedHashMap<String, String>()
            fun keysOf(row: Any?): Set<String> {
                val found = LinkedHashSet<String>(); R2Uploader.collectR2Urls(row, found)
                return found.map { url ->
                    val key = R2Uploader.keyFromUrl(url) ?: throw java.io.IOException("Invalid R2 media URL; record retained")
                    urls[key] = url; key
                }.toSet()
            }
            try {
                for ((key, q) in snapshots) for (id in Json.keys(q)) {
                    val row = q.optJSONObject(id) ?: continue
                    if (key == account && id in ids) { rows[id] = row; refs[id] = keysOf(row) }
                    else outside.addAll(keysOf(row))
                }
            } catch (e: Exception) {
                return@withLock PurgeResult(0, 0, 0, 0, true, ids.size, "Media references could not be verified: ${e.message}")
            }
            for ((id, row) in rows) {
                val keys = refs.getValue(id)
                if (keys.isEmpty()) blocked[id] = "No stored R2 URL. Record retained for manual review."
                if (row.optString("status") == "processing") blocked[id] = "Upload is processing. Wait before deleting."
                if (keys.any { it in outside }) blocked[id] = "File shared by another retained queue item. Remove its other references first."
            }
            var changed = true
            while (changed) {
                changed = false
                val protectedKeys = outside.toMutableSet()
                for (id in blocked.keys) protectedKeys.addAll(refs[id].orEmpty())
                for ((id, keys) in refs) if (id !in blocked && keys.any { it in protectedKeys }) { blocked[id] = "Shares a file with a retained item."; changed = true }
            }
            val eligible = rows.keys.filter { it !in blocked }
            if (eligible.isEmpty()) return@withLock PurgeResult(0, 0, blocked.size, 0, false, rows.size, blocked.values.firstOrNull() ?: "")
            onProgress("Reserving ${eligible.size} record(s) in Firebase…", 0, 0)
            for (chunk in eligible.chunked(200)) {
                val patch = JSONObject()
                for (id in chunk) {
                    patch.put("${Accounts.QUEUE_PATH}/$id/status", "deleting")
                    patch.put("${Accounts.QUEUE_PATH}/$id/deleteState", "pending")
                    patch.put("${Accounts.QUEUE_PATH}/$id/deleteError", JSONObject.NULL)
                    patch.put("${Accounts.QUEUE_PATH}/$id/deleteRequestedAt", FirebaseRtdb.serverTimestamp())
                }
                db(account).update("", patch)
            }
            val candidates = eligible.flatMap { refs.getValue(it) }.toSet()
            val doneFiles = java.util.concurrent.atomic.AtomicInteger(0)
            onProgress("Deleting ${candidates.size} file(s) from R2 (verified)…", 0, candidates.size)
            val outcomes: Map<String, String?> = coroutineScope {
                val sem = Semaphore(6)
                candidates.map { key -> async(Dispatchers.IO) {
                    sem.withPermit {
                        val error: String? = try { if (!r2.delete(urls.getValue(key))) "R2 deletion not verified" else null }
                        catch (e: Exception) { if (e is kotlinx.coroutines.CancellationException) throw e; e.message ?: "R2 deletion failed" }
                        val n = doneFiles.incrementAndGet()
                        onProgress((if (error == null) "✓ " else "✗ ") + key.substringAfterLast('/') + " · $n/${candidates.size}", n, candidates.size)
                        key to error
                    }
                } }.awaitAll().toMap()
            }
            onProgress("Verifying queue and removing records…", candidates.size, candidates.size)
            val verified = outcomes.values.count { it == null }
            val failures = outcomes.size - verified
            val latest = try { Json.norm(db(account).get(Accounts.QUEUE_PATH)) as? JSONObject ?: JSONObject() }
            catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                return@withLock PurgeResult(0, verified, blocked.size, failures, true, rows.size, "Final Firebase check failed; retry Delete. ${e.message}")
            }
            val deleted = LinkedHashSet<String>()
            var detail = blocked.values.firstOrNull() ?: ""
            var verifyFailed = false
            for (chunk in eligible.chunked(200)) {
                val patch = JSONObject(); val removal = ArrayList<String>()
                for (id in chunk) {
                    val row = latest.optJSONObject(id) ?: continue
                    val expected = refs.getValue(id)
                    var error = expected.mapNotNull { outcomes[it] }.firstOrNull()
                    val current = try { keysOf(row) } catch (_: Exception) { emptySet<String>() }
                    if (current != expected || row.optString("deleteState") != "pending") error = "Record changed while deleting. Review and retry Delete."
                    if (error == null) { patch.put("${Accounts.QUEUE_PATH}/$id", JSONObject.NULL); removal.add(id) }
                    else {
                        patch.put("${Accounts.QUEUE_PATH}/$id/status", "failed")
                        patch.put("${Accounts.QUEUE_PATH}/$id/deleteState", "incomplete")
                        patch.put("${Accounts.QUEUE_PATH}/$id/deleteError", error)
                        patch.put("${Accounts.QUEUE_PATH}/$id/error", "Deletion incomplete — retry Delete, not Requeue. $error")
                        patch.put("${Accounts.QUEUE_PATH}/$id/failedAt", FirebaseRtdb.serverTimestamp())
                        if (detail.isBlank()) detail = error
                    }
                }
                try { if (patch.length() > 0) db(account).update("", patch); deleted.addAll(removal) }
                catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    verifyFailed = true; detail = "Firebase cleanup failed. Retry Delete. ${e.message}"; break
                }
            }
            PurgeResult(deleted.size, verified, blocked.size, failures, verifyFailed, rows.size - deleted.size, detail, deleted)
        }
    }

    suspend fun deleteMany(items: Collection<QueueItem>, onProgress: (String, Int, Int) -> Unit = { _, _, _ -> }): PurgeResult = purge(items, onProgress)

    suspend fun delete(item: QueueItem, onProgress: (String, Int, Int) -> Unit = { _, _, _ -> }): PurgeResult = purge(listOf(item), onProgress)

    suspend fun pin(itemId: String, dateKey: String?) =
        db(activeKey.value).update("${Accounts.QUEUE_PATH}/$itemId", Json.obj("scheduledDate" to dateKey))

    /** Multi-path update, like the dashboard's bulk unpin / re-date. */
    suspend fun pinMany(ids: Collection<String>, dateKey: String?) {
        if (ids.isEmpty()) return
        val patch = JSONObject()
        for (id in ids) patch.put("${Accounts.QUEUE_PATH}/$id/scheduledDate", dateKey ?: JSONObject.NULL)
        db(activeKey.value).update("", patch)
    }

    suspend fun copyToOtherAccounts(item: QueueItem): List<String> {
        val others = Accounts.distOrder.filter { it != activeKey.value }
        for (key in others) {
            val copy = Json.deepCopy(item.raw)
            copy.remove("id")
            copy.put("status", "queued")
            copy.put("createdAt", FirebaseRtdb.serverTimestamp())
            copy.put("distributedTo", key)
            pushQueue(key, copy)
        }
        return others
    }
}
