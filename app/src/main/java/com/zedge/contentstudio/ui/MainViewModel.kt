package com.zedge.contentstudio.ui

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.zedge.contentstudio.ContentStudioApp
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.ContentTypes
import com.zedge.contentstudio.core.NaturalOrder
import com.zedge.contentstudio.core.RealTime
import com.zedge.contentstudio.data.LocalFile
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.data.QueueRepository
import com.zedge.contentstudio.domain.GateHealth
import com.zedge.contentstudio.domain.RunSchedule
import com.zedge.contentstudio.data.UploadState
import com.zedge.contentstudio.data.VideoUtils
import com.zedge.contentstudio.domain.ImportUnit
import com.zedge.contentstudio.domain.SchedulePlan
import com.zedge.contentstudio.domain.SchedulePlanner
import com.zedge.contentstudio.domain.SpecialDays
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Snackbar message. */
data class UiMessage(val text: String, val kind: String = "info") // info | ok | warn | err

/** Modal dialog request rendered by the UI; resolves the suspended caller. */
class DialogRequest(
    val title: String,
    val message: String,
    val confirmLabel: String,
    val cancelLabel: String?,           // null -> alert (single button)
    val destructive: Boolean,
    private val result: CompletableDeferred<Boolean>,
) {
    fun confirm() = result.complete(true)
    fun cancel() = result.complete(false)
}

/** Smart archive import waiting for the user to confirm in the visual preview sheet. */
class ImportPreview(
    val plan: QueueRepository.SmartPlan,
    val distribute: Boolean,
    val targetLabel: String,
    val archiveNames: List<String>,
    private val result: CompletableDeferred<Boolean>,
) {
    fun confirm() = result.complete(true)
    fun cancel() = result.complete(false)
}

/** Long-running job feedback (progress card). */
data class JobProgress(val title: String, val detail: String, val current: Int, val total: Int) {
    val fraction: Float? get() = if (total > 0) current.toFloat() / total else null
}

/** Video waiting for the user to pick a cover frame (Live / Charging cards). */
class VideoDraft(val type: String, val file: LocalFile, val frames: List<VideoUtils.Frame>, val selected: Int)

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val application = app as ContentStudioApp
    val repo: QueueRepository = application.queueRepo
    val specialDays: SpecialDays = application.specialDays

    val activeKey: StateFlow<String> = repo.activeKey
    val items: StateFlow<List<QueueItem>> = repo.queue
    val uploadState: StateFlow<UploadState?> = repo.uploadState
    val connected: StateFlow<Boolean> = repo.connected
    val busy: StateFlow<Boolean> = repo.busy
    val schedules: StateFlow<Map<String, List<Int>>> = repo.schedules
    val scheduleSource: StateFlow<Map<String, String>> = repo.scheduleSource
    val gateHealth: StateFlow<Map<String, GateHealth?>> = repo.gateHealth

    fun saveSchedule(key: String, windows: List<Int>) {
        val err = RunSchedule.validate(windows)
        if (err != null) { toast(err, "error"); return }
        viewModelScope.launch {
            runCatching { repo.saveSchedule(key, windows) }
                .onSuccess { toast("${key.replace("zedge", "ZEDGE ")} schedule saved - bot uses it from the next ping", "ok") }
                .onFailure { toast("Save failed: ${it.message}", "error") }
        }
    }

    private val _messages = MutableSharedFlow<UiMessage>(extraBufferCapacity = 16)
    val messages: SharedFlow<UiMessage> = _messages
    val dialog = MutableStateFlow<DialogRequest?>(null)
    val importPreview = MutableStateFlow<ImportPreview?>(null)
    val progress = MutableStateFlow<JobProgress?>(null)
    val statusText = MutableStateFlow("")           // upload tab status line
    val distStatusText = MutableStateFlow("")       // distribute tab status line
    val videoDraft = MutableStateFlow<VideoDraft?>(null)
    val sharedUris = MutableStateFlow<List<Uri>>(emptyList())
    val selectedItem = MutableStateFlow<QueueItem?>(null)

    /** Calendar plan, recomputed whenever the queue, upload state, clock or holiday feed changes. */
    val plan: StateFlow<SchedulePlan> = combine(items, uploadState, activeKey, RealTime.tick, specialDays.version) { list, state, key, _, _ ->
        withContext(Dispatchers.Default) { SchedulePlanner.build(list, state, key) }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, SchedulePlan.EMPTY)

    init {
        viewModelScope.launch { runCatching { specialDays.syncAll() } }
        viewModelScope.launch { while (true) { delay(30_000); RealTime.bump() } }
    }

    // ------------------------------------------------------------------ helpers
    fun toast(text: String, kind: String = "info") { _messages.tryEmit(UiMessage(text, kind)) }

    suspend fun confirm(message: String, title: String = "Please confirm", confirmLabel: String = "Continue", destructive: Boolean = false): Boolean {
        val d = CompletableDeferred<Boolean>()
        dialog.value = DialogRequest(title, message, confirmLabel, "Cancel", destructive, d)
        val r = d.await(); dialog.value = null; return r
    }

    suspend fun alert(message: String, title: String = "Notice") {
        val d = CompletableDeferred<Boolean>()
        dialog.value = DialogRequest(title, message, "OK", null, false, d)
        d.await(); dialog.value = null
    }

    private suspend fun readFiles(uris: List<Uri>): List<LocalFile> {
        val out = ArrayList<LocalFile>()
        uris.forEachIndexed { i, u ->
            progress.value = JobProgress("Reading files", "${i + 1}/${uris.size}", i, uris.size)
            try { out.add(LocalFile.fromUri(getApplication(), u)) } catch (e: Exception) { toast("Could not read file: ${e.message}", "err") }
        }
        return out
    }

    private inline fun locked(block: () -> Unit) {
        if (!repo.tryLock()) { toast("Another upload is still running - wait for it to finish.", "warn"); return }
        block()
    }

    // ------------------------------------------------------------------ account
    fun switchAccount(key: String) {
        if (key == activeKey.value) return
        repo.connect(key)
        selectedItem.value = null
        toast("Switched to ${Accounts.byKey(key).label}")
    }

    // ------------------------------------------------------------------ upload tab
    /** Main upload: images -> wallpaper, mp3 -> ringtone, zip/rar -> smart import, video -> handled by Live/Charging cards. */
    fun uploadToQueue(uris: List<Uri>) = locked {
        viewModelScope.launch {
            try {
                val files = readFiles(uris)
                val archives = files.filter { it.isArchive }
                if (archives.isNotEmpty()) smartImport(archives, distribute = false, fallbackType = null, videoType = "LIVE_WALLPAPER")
                val media = files.filter { !it.isArchive }
                val videos = media.filter { it.isVideo }
                if (videos.isNotEmpty()) toast("${videos.size} video(s) skipped - use the Live Wallpaper / Charging Animation card.", "warn")
                val plain = media.filter { it.isImage || it.isAudio }
                var ok = 0
                plain.forEachIndexed { i, f ->
                    if (items.value.any { it.name == f.name } && !confirm("\"${f.name}\" is already in this queue. Add it again anyway?", "Duplicate file", "Add anyway")) return@forEachIndexed
                    try {
                        repo.uploadPlainFile(f) { progress.value = JobProgress("Uploading to ${activeKey.value.uppercase()}", it, i, plain.size) }
                        ok++
                    } catch (e: Exception) { toast("${f.name}: ${e.message}", "err") }
                }
                if (plain.isNotEmpty()) { statusText.value = "$ok/${plain.size} file(s) queued"; toast(statusText.value, if (ok == plain.size) "ok" else "warn") }
            } finally { progress.value = null; repo.unlock() }
        }
    }

    fun submitSet(type: String, slotUris: Map<String, Uri>) = locked {
        viewModelScope.launch {
            try {
                val meta = ContentTypes.SET_TYPES.getValue(type)
                val files = HashMap<String, LocalFile>()
                for (slot in meta.slots) {
                    val u = slotUris[slot] ?: run { toast("Please select all ${meta.slots.size} ${meta.short} images first.", "warn"); return@launch }
                    files[slot] = LocalFile.fromUri(getApplication(), u)
                }
                repo.submitSet(type, files) { progress.value = JobProgress("Uploading ${meta.label}", it, 0, 0) }
                toast("${meta.label} queued in ${activeKey.value.uppercase()}", "ok")
            } catch (e: Exception) { toast("Set upload failed: ${e.message}", "err") }
            finally { progress.value = null; repo.unlock() }
        }
    }

    /** Step 1 of video upload: read + capture 5 frames so the user can pick a cover. */
    fun prepareVideo(type: String, uri: Uri) {
        viewModelScope.launch {
            try {
                statusText.value = "Capturing 5 frames from video..."
                val f = LocalFile.fromUri(getApplication(), uri)
                if (!f.isVideo && !f.mime.startsWith("video/")) { toast("Only MP4 / MOV video files are allowed.", "err"); statusText.value = ""; return@launch }
                if (f.size > LocalFile.VIDEO_MAX_BYTES) { toast("Video must be 50 MB or smaller.", "err"); statusText.value = ""; return@launch }
                val frames = VideoUtils.captureFrames(getApplication(), f)
                if (frames.isEmpty()) { toast("Could not read video frames.", "err"); statusText.value = ""; return@launch }
                videoDraft.value = VideoDraft(type, f, frames, frames.size / 2)
                statusText.value = "${frames.size} frames captured - tap the best one for the cover."
            } catch (e: Exception) { toast("Video error: ${e.message}", "err"); statusText.value = "" }
        }
    }

    fun selectFrame(index: Int) {
        videoDraft.value = videoDraft.value?.let { VideoDraft(it.type, it.file, it.frames, index) }
        statusText.value = "Frame ${index + 1} selected as cover thumbnail."
    }

    fun cancelVideoDraft() { videoDraft.value = null; statusText.value = "" }

    fun submitVideoDraft() {
        val d = videoDraft.value ?: run { toast("Pick a video first.", "warn"); return }
        if (!repo.tryLock()) { toast("Another upload is still running - wait for it to finish.", "warn"); return }
        viewModelScope.launch {
            try {
                val meta = ContentTypes.VIDEO_TYPES.getValue(d.type)
                repo.submitVideo(d.type, d.file, d.frames[d.selected].jpeg) { progress.value = JobProgress("Uploading ${meta.label}", it, 0, 0) }
                toast("${meta.label} queued in ${activeKey.value.uppercase()}", "ok")
                videoDraft.value = null; statusText.value = ""
            } catch (e: Exception) { toast("Video upload failed: ${e.message}", "err") }
            finally { progress.value = null; repo.unlock() }
        }
    }

    // ------------------------------------------------------------------ smart archive import
    /** Caller must hold the upload lock. */
    private suspend fun smartImport(archives: List<LocalFile>, distribute: Boolean, fallbackType: String?, videoType: String) {
        val setStatus: (String) -> Unit = { if (distribute) distStatusText.value = it else statusText.value = it }
        val plan = repo.planSmartImport(archives, fallbackType) { setStatus(it); progress.value = JobProgress("Smart import", it, 0, 0) }
        progress.value = null
        if (plan.units.isEmpty()) {
            setStatus("Nothing usable found in the archive.")
            alert("Nothing to import." + (if (plan.problems.isNotEmpty()) "\n\n" + plan.problems.joinToString("\n") else ""))
            return
        }
        // Visual preview sheet: detected sets with thumbnails, singles, ringtones, videos, notes.
        val d = CompletableDeferred<Boolean>()
        importPreview.value = ImportPreview(plan, distribute, Accounts.byKey(activeKey.value).label, archives.map { it.name }, d)
        val go = try { d.await() } finally { importPreview.value = null }
        if (!go) { setStatus("Import cancelled."); return }
        val res = repo.runSmartImport(plan, distribute, videoType) { i, total, text ->
            setStatus(text); progress.value = JobProgress(if (distribute) "Distributing archive" else "Importing archive", text, i, total)
        }
        progress.value = null
        val summary = "${res.ok}/${res.total} item(s) queued" + (if (res.failed.isNotEmpty()) ", ${res.failed.size} failed" else "") + (if (!distribute) " - ${plan.summary}" else "")
        setStatus(summary); toast(summary, if (res.failed.isEmpty()) "ok" else "warn")
        if (res.failed.isNotEmpty()) alert("${res.failed.size} item(s) could not be uploaded:\n\n" + res.failed.joinToString("\n"), "Upload problems")
    }

    /** Smart Archive panel button (upload tab). */
    fun importArchives(uris: List<Uri>) = locked {
        viewModelScope.launch {
            try {
                val files = readFiles(uris).filter { it.isArchive }
                if (files.isEmpty()) { toast("Pick .zip or .rar archives.", "warn"); return@launch }
                smartImport(files, distribute = false, fallbackType = null, videoType = "LIVE_WALLPAPER")
            } finally { progress.value = null; repo.unlock() }
        }
    }

    // ------------------------------------------------------------------ multi-account distribution
    fun distribute(uris: List<Uri>, imageMode: String, videoType: String) = locked {
        viewModelScope.launch {
            try {
                val files = readFiles(uris)
                progress.value = null
                val archives = files.filter { it.isArchive }
                val loose = files.filter { !it.isArchive }
                if (archives.isNotEmpty()) smartImport(archives, distribute = true, fallbackType = imageMode.takeIf { ContentTypes.isSet(it) }, videoType = videoType)
                if (loose.isEmpty()) return@launch
                if (ContentTypes.isSet(imageMode)) distributeLooseSets(imageMode, loose) else distributeLooseFiles(loose, videoType)
            } finally { progress.value = null; repo.unlock() }
        }
    }

    private suspend fun distributeLooseFiles(files: List<LocalFile>, videoType: String) {
        val todo = ArrayList<LocalFile>()
        for (f in files) {
            if (repo.distPushedNames.contains(f.name) && !confirm("\"${f.name}\" was already distributed in this session. Distribute again anyway?", "Already distributed", "Distribute again")) continue
            todo.add(f)
        }
        if (todo.isEmpty()) { distStatusText.value = "Nothing to distribute."; return }
        val res = repo.distributeFiles(todo, videoType) { i, total, text -> distStatusText.value = text; progress.value = JobProgress("Distributing", text, i, total) }
        val s = "${res.ok}/${res.total} file(s) distributed across ZEDGE1 -> ZEDGE2 -> ZEDGE3 -> ZEDGE4" + (if (res.failed.isNotEmpty()) " - ${res.failed.size} failed" else "")
        distStatusText.value = s; toast(s, if (res.failed.isEmpty()) "ok" else "warn")
        if (res.failed.isNotEmpty()) alert(res.failed.joinToString("\n"), "Distribution problems")
    }

    private suspend fun distributeLooseSets(type: String, files: List<LocalFile>) {
        val meta = ContentTypes.SET_TYPES.getValue(type)
        val nonImages = files.filter { !it.isImage }
        if (nonImages.isNotEmpty()) { distStatusText.value = "Error: ${meta.label} mode accepts image files only - remove ${nonImages.size} non-image file(s) (MP3/video) and try again."; return }
        val size = meta.slots.size
        if (files.size % size != 0) {
            val r = files.size % size
            distStatusText.value = "Error: ${meta.label} needs $size images per set. You selected ${files.size} - that leaves $r extra. Select a multiple of $size (e.g. ${files.size - r} or ${files.size + size - r})."
            return
        }
        val sorted = files.sortedWith(compareBy(NaturalOrder) { it.name })
        val sets = sorted.chunked(size)
        val preview = sets.take(3).mapIndexed { idx, chunk ->
            val target = Accounts.distOrder[(repo.distPointer + idx) % Accounts.distOrder.size]
            "Set ${idx + 1} -> ${target.uppercase()}: " + chunk.joinToString(", ") { it.name }
        }
        val more = if (sets.size > 3) "\n\n...and ${sets.size - 3} more set(s)" else ""
        val msg = "${sets.size} ${meta.label}(s) will be created (grouped in name order - Zedge auto-assigns on upload):\n\n${preview.joinToString("\n")}$more\n\nContinue?"
        if (!confirm(msg, "Distribute sets", "Upload")) { distStatusText.value = "Set distribution cancelled - nothing was uploaded."; return }
        val groups = sets.map { chunk -> chunk.mapIndexed { j, f -> meta.slots[j] to f } }
        val res = repo.distributeSets(type, groups) { i, total, text -> distStatusText.value = text; progress.value = JobProgress("Distributing sets", text, i, total) }
        val s = "${res.ok}/${res.total} ${meta.label}(s) distributed" + (if (res.failed.isNotEmpty()) " - ${res.failed.size} failed" else "")
        distStatusText.value = s; toast(s, if (res.failed.isEmpty()) "ok" else "warn")
        if (res.failed.isNotEmpty()) alert(res.failed.joinToString("\n"), "Distribution problems")
    }

    // ------------------------------------------------------------------ item actions
    fun saveMetadata(item: QueueItem, title: String, tags: String, category: String, description: String, scheduledDate: String?) {
        viewModelScope.launch {
            try { repo.saveMetadata(item, title, tags, category, description, scheduledDate); toast("Saved \"${title.ifBlank { item.name }}\"", "ok") }
            catch (e: Exception) { toast("Save failed: ${e.message}", "err") }
        }
    }

    fun requeue(item: QueueItem) {
        viewModelScope.launch {
            try { repo.requeue(item); toast("Re-queued \"${item.displayTitle}\"", "ok") } catch (e: Exception) { toast("Requeue failed: ${e.message}", "err") }
        }
    }

    fun requeueAllFailed() {
        viewModelScope.launch {
            val failed = items.value.filter { it.isFailed }
            if (failed.isEmpty()) { toast("No failed uploads", "info"); return@launch }
            try { repo.requeueMany(failed.map { it.id }); toast("Re-queued ${failed.size} item(s)", "ok") }
            catch (e: Exception) { toast("Requeue failed: ${e.message}", "err") }
        }
    }

    fun deleteAllFailed() {
        viewModelScope.launch {
            val failed = items.value.filter { it.isFailed }
            if (failed.isEmpty()) { toast("No failed uploads", "info"); return@launch }
            if (!confirm("Permanently delete all ${failed.size} failed item(s) from ${Accounts.byKey(activeKey.value).label}?\n\nThis removes them from the queue AND deletes their files from R2 storage. This cannot be undone.", "Delete failed uploads", "Delete", destructive = true)) return@launch
            try { val res = repo.deleteMany(failed); if (selectedItem.value?.isFailed == true) selectedItem.value = null; toast(res.summary("failed item(s)"), if (res.ok) "ok" else "err") }
            catch (e: Exception) { toast("Delete failed: ${e.message}", "err") }
        }
    }

    /** Bulk delete every item matching a search / type filter ("remove all ringtones", etc.). */
    fun deleteMatching(matching: List<QueueItem>, plural: String, scope: String) {
        viewModelScope.launch {
            if (matching.isEmpty()) { toast("Nothing matches the current filter", "info"); return@launch }
            val account = Accounts.byKey(activeKey.value).label
            val uploaded = matching.count { it.status == "uploaded" }
            val note = if (uploaded > 0) "\n\n$uploaded of them are already uploaded to Zedge - they stay on Zedge, only the queue record + R2 file are removed." else ""
            if (!confirm("Permanently delete ${matching.size} $plural from $account?\n\nQueue rows AND their R2 files will be deleted.\nFilter: $scope$note\n\nThis cannot be undone.", "Delete all $plural", "Delete", destructive = true)) return@launch
            if (matching.size >= 25 && !confirm("Really delete ${matching.size} items? This is the second confirmation.", "Are you sure?", "Yes, delete", destructive = true)) return@launch
            try {
                val ids = matching.map { it.id }
                val res = repo.deleteMany(matching)
                if (selectedItem.value?.id in ids) selectedItem.value = null
                toast(res.summary("$plural from $account"), if (res.ok) "ok" else "err")
            } catch (e: Exception) { toast("Bulk delete failed: ${e.message}", "err") }
        }
    }

    fun delete(item: QueueItem) {
        viewModelScope.launch {
            if (!confirm("Permanently delete \"${item.name.ifBlank { item.id }}\"?\n\nThis removes it from the queue AND deletes its file(s) from R2 storage.", "Delete file", "Delete", destructive = true)) return@launch
            try { val res = repo.delete(item); if (selectedItem.value?.id == item.id) selectedItem.value = null; toast(res.summary(), if (res.ok) "ok" else "err") }
            catch (e: Exception) { toast("Delete failed: ${e.message}", "err") }
        }
    }

    fun pin(item: QueueItem, dateKey: String) {
        viewModelScope.launch {
            try { repo.pin(item.id, dateKey); toast("Pinned \"${item.displayTitle}\" -> ${RealTime.prettyKey(dateKey)}", "ok") }
            catch (e: Exception) { toast("Pin failed: ${e.message}", "err") }
        }
    }

    fun unpin(item: QueueItem, ask: Boolean = true) {
        viewModelScope.launch {
            if (ask && !confirm("Unpin \"${item.displayTitle}\"?\nIt will go back to the normal rotation (its own content-type day).", "Unpin", "Unpin")) return@launch
            try { repo.pin(item.id, null); toast("Unpinned \"${item.displayTitle}\"", "ok") } catch (e: Exception) { toast("Unpin failed: ${e.message}", "err") }
        }
    }

    /** Bulk unpin (dateKey == null) or re-date. */
    fun bulkPin(list: List<QueueItem>, dateKey: String?, verb: String) {
        viewModelScope.launch {
            if (list.isEmpty()) { toast("Nothing to do", "warn"); return@launch }
            val what = if (dateKey == null) "Unpin" else "Re-date to ${RealTime.prettyKey(dateKey)}"
            if (!confirm("$what ${list.size} file(s) ($verb)?" + (if (dateKey == null) "\nThey go back to their own content-type day." else ""), "Bulk update", what.substringBefore(' '))) return@launch
            try { repo.pinMany(list.map { it.id }, dateKey); toast("$what - ${list.size} file(s) updated", "ok") }
            catch (e: Exception) { toast("Bulk update failed: ${e.message}", "err") }
        }
    }

    val copyState = MutableStateFlow("idle") // idle | copying | done | failed
    fun copyToOtherAccounts(item: QueueItem) {
        viewModelScope.launch {
            copyState.value = "copying"
            try {
                val others = repo.copyToOtherAccounts(item)
                copyState.value = "done"
                toast("Copied to " + others.joinToString(" + ") { it.uppercase() }, "ok")
            } catch (e: Exception) { copyState.value = "failed"; toast("Copy failed: ${e.message}", "err") }
            delay(2500); copyState.value = "idle"
        }
    }

    // ------------------------------------------------------------------ share intent
    fun onSharedUris(uris: List<Uri>) { if (uris.isNotEmpty()) sharedUris.value = uris }
    fun consumeSharedUris(): List<Uri> { val u = sharedUris.value; sharedUris.value = emptyList(); return u }

    fun unitTitle(u: ImportUnit): String = u.title
}
