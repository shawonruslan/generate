package com.zedge.contentstudio.ui

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.zedge.contentstudio.ContentStudioApp
import com.zedge.contentstudio.data.GhConfig
import com.zedge.contentstudio.data.GhEntry
import com.zedge.contentstudio.data.GhRun
import com.zedge.contentstudio.data.GitHubRepo
import com.zedge.contentstudio.data.LocalFile
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.data.VpnGithub
import com.zedge.contentstudio.data.VpnProfile
import com.zedge.contentstudio.data.VpnRepo
import com.zedge.contentstudio.data.VpnSettings
import kotlinx.coroutines.Job
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class LogLine(val time: String, val text: String, val kind: String) // "" | ok | err

/** GitHub Control page state: connection, session, generators, runs, repo browser, log. */
class GitHubViewModel(app: Application) : AndroidViewModel(app) {
    private val gh: GitHubRepo = (app as ContentStudioApp).gitHub

    val config = MutableStateFlow(gh.config)
    val sessionRaw = MutableStateFlow(gh.session)
    val connectionStatus = MutableStateFlow("Not tested")
    val sessionStatus = MutableStateFlow(sessionSummary(gh.session))
    val runs = MutableStateFlow<List<GhRun>>(emptyList())
    val runsLoading = MutableStateFlow(false)
    val path = MutableStateFlow("")
    val entries = MutableStateFlow<List<GhEntry>>(emptyList())
    val filesLoading = MutableStateFlow(false)
    val log = MutableStateFlow<List<LogLine>>(emptyList())
    val dialog = MutableStateFlow<DialogRequest?>(null)
    val triggering = MutableStateFlow<String?>(null)

    // ---- v24 VPN ----
    private val vpn: VpnRepo = (app as ContentStudioApp).vpn
    val vpnAccount = MutableStateFlow("zedge1")
    val vpnSettings = MutableStateFlow(VpnSettings())
    val vpnLoading = MutableStateFlow(false)
    val vpnEditing = MutableStateFlow<VpnProfile?>(null)
    val vpnConnChecking = MutableStateFlow(false)
    private var vpnPoll: Job? = null

    // Ringtone generator form (defaults identical to the dashboard)
    val rgCount = MutableStateFlow("10"); val rgLength = MutableStateFlow("5"); val rgAutoProcess = MutableStateFlow("true")
    val rgVolume = MutableStateFlow("200"); val rgSilence = MutableStateFlow("0.02"); val rgPad = MutableStateFlow("100")
    val rgTarget = MutableStateFlow("zedge_2"); val rgAttachSession = MutableStateFlow(true)
    // Metadata generator form
    val mdQueuePath = MutableStateFlow("wallpaperQueue"); val mdAttachSession = MutableStateFlow(true)

    private val tf = SimpleDateFormat("HH:mm:ss", Locale.UK)
    fun logLine(text: String, kind: String = "") { log.value = (listOf(LogLine(tf.format(Date()), text, kind)) + log.value).take(200) }
    fun clearLog() { log.value = emptyList() }

    init {
        viewModelScope.launch {
            try {
                if (gh.syncFromCloud()) {
                    config.value = gh.config; sessionRaw.value = gh.session; sessionStatus.value = sessionSummary(gh.session)
                    logLine("Settings restored from database (cloud sync).", "ok")
                }
            } catch (e: Exception) { logLine("DB settings load failed: ${e.message}", "err") }
            if (gh.config.ready) { loadRuns(); listPath("") }
            refreshVpn()
        }
    }

    private suspend fun confirm(message: String, title: String, label: String, destructive: Boolean = true): Boolean {
        val d = CompletableDeferred<Boolean>()
        dialog.value = DialogRequest(title, message, label, "Cancel", destructive, d)
        val r = d.await(); dialog.value = null; return r
    }

    // ---- v24 VPN ----
    fun selectVpnAccount(key: String) { vpnAccount.value = key; vpnEditing.value = null; refreshVpn() }
    fun editVpn(p: VpnProfile?) { vpnEditing.value = p }

    fun refreshVpn() {
        viewModelScope.launch {
            vpnLoading.value = true
            try { vpnSettings.value = vpn.load(vpnAccount.value); if (vpnSettings.value.lastTest?.busy == true) startVpnPoll() }
            catch (e: Exception) { logLine("VPN settings load failed (${vpnAccount.value}): ${e.message}", "err") }
            finally { vpnLoading.value = false }
        }
    }

    /** FirebaseRtdb is REST-only, so while a test is queued/running we poll lastTest every 10 s (max 15 min). */
    private fun startVpnPoll() {
        if (vpnPoll?.isActive == true) return
        vpnPoll = viewModelScope.launch {
            val key = vpnAccount.value
            repeat(90) {
                delay(10_000)
                if (vpnAccount.value != key) return@launch
                val s = runCatching { vpn.load(key) }.getOrNull() ?: return@repeat
                vpnSettings.value = s
                val t = s.lastTest
                if (t == null || !t.busy) {
                    if (t != null) logLine("VPN test ${if (t.status == "ok") "OK" else "FAILED"} (${t.profileName}): ${t.message}", if (t.status == "ok") "ok" else "err")
                    return@launch
                }
            }
        }
    }

    fun saveVpnProfile(p: VpnProfile, copyAll: Boolean, test: Boolean) {
        viewModelScope.launch {
            try {
                VpnRepo.validate(p)
                val targets = if (copyAll) Accounts.keys else listOf(vpnAccount.value)
                vpn.saveProfile(targets, p)
                logLine("VPN profile \"${p.name}\" saved to ${targets.joinToString { it.uppercase() }}.", "ok")
                vpnEditing.value = p
                refreshVpn()
                if (test) testVpn(p)
            } catch (e: Exception) { logLine("VPN profile save failed: ${e.message}", "err") }
        }
    }

    fun setVpnActive(p: VpnProfile) {
        viewModelScope.launch {
            try { vpn.setActive(vpnAccount.value, p); logLine("${vpnAccount.value.uppercase()}: active VPN profile -> ${p.name} (${p.type} enabled for real runs)", "ok"); refreshVpn() }
            catch (e: Exception) { logLine("VPN: ${e.message}", "err") }
        }
    }

    fun setVpnMode(mode: String, keepProxy: Boolean) {
        viewModelScope.launch {
            val s = vpnSettings.value
            if (mode != "none") {
                val act = s.active ?: run { logLine("Pick an active profile first (Set active on a saved profile).", "err"); return@launch }
                if (act.type != mode) { logLine("Active profile \"${act.name}\" is ${act.type} - choose the matching mode or set another profile active.", "err"); return@launch }
            }
            try { vpn.setMode(vpnAccount.value, mode, keepProxy); logLine("${vpnAccount.value.uppercase()}: VPN mode = $mode${if (keepProxy) " (proxy kept inside VPN)" else ""}", "ok"); refreshVpn() }
            catch (e: Exception) { logLine("VPN: ${e.message}", "err") }
        }
    }

    fun deleteVpn(p: VpnProfile) {
        viewModelScope.launch {
            if (!confirm("Delete VPN profile \"${p.name}\" from ${vpnAccount.value.uppercase()}?", "Delete profile", "Delete")) return@launch
            try { vpn.deleteProfile(vpnAccount.value, p.id); if (vpnEditing.value?.id == p.id) vpnEditing.value = null; logLine("VPN profile \"${p.name}\" deleted."); refreshVpn() }
            catch (e: Exception) { logLine("VPN: ${e.message}", "err") }
        }
    }

    fun copyVpnToAll(p: VpnProfile) {
        viewModelScope.launch {
            try { vpn.copyToAll(vpnAccount.value, p); logLine("VPN profile \"${p.name}\" copied to all accounts.", "ok") }
            catch (e: Exception) { logLine("VPN: ${e.message}", "err") }
        }
    }

    fun config(): GhConfig = gh.config
    fun vpnEffectiveGithub(): Pair<GhConfig, String>? = vpn.effectiveGithub(vpnAccount.value, vpnSettings.value)
    fun saveVpnGithub(g: VpnGithub) {
        viewModelScope.launch {
            if (g.owner.isBlank() || g.repo.isBlank() || g.token.isBlank()) { logLine("Owner, repository and token are required.", "err"); return@launch }
            try { vpn.saveGithub(vpnAccount.value, g); logLine("VPN GitHub connection saved for ${vpnAccount.value.uppercase()} (${g.owner}/${g.repo} @ ${g.workflow.ifBlank { vpnAccount.value + ".yml" }}).", "ok"); refreshVpn() }
            catch (e: Exception) { logLine("Save failed: ${e.message}", "err") }
        }
    }
    fun checkVpnGithub() {
        viewModelScope.launch {
            vpnConnChecking.value = true
            try { logLine("VPN connection check: " + vpn.check(vpnAccount.value, vpnSettings.value), "ok") }
            catch (e: Exception) { logLine("VPN connection check failed: ${e.message}", "err") }
            finally { vpnConnChecking.value = false }
        }
    }

    fun testVpn(p: VpnProfile) {
        viewModelScope.launch {
            val key = vpnAccount.value
            val eff = vpn.effectiveGithub(key, vpnSettings.value)
            if (eff == null) { logLine("GitHub connection for ${key.uppercase()} is missing - VPN page > GitHub connection.", "err"); return@launch }
            try {
                vpn.test(key, p, vpnSettings.value)
                logLine("VPN test for ${key.uppercase()} (${p.name}) triggered via ${eff.first.owner}/${eff.first.repo} ${eff.second} - live status on the VPN page & Telegram.", "ok")
                refreshVpn(); startVpnPoll(); loadRuns()
            } catch (e: Exception) {
                logLine("VPN test trigger failed: ${e.message}. Check the workflow file name in the Connection card and that the yml on GitHub is v24 (run_mode input).", "err")
                refreshVpn()
            }
        }
    }

    /** Reads a picked document as UTF-8 text (for .ovpn / .conf / certificate files). */
    fun readTextFile(uri: Uri, onText: (String, String) -> Unit) {
        viewModelScope.launch {
            try { val f = LocalFile.fromUri(getApplication<Application>(), uri); onText(f.name, String(f.bytes, Charsets.UTF_8).replace("\r", "")) }
            catch (e: Exception) { logLine("File read failed: ${e.message}", "err") }
        }
    }

    private fun sessionSummary(raw: String): String {
        if (raw.isBlank()) return "No session saved"
        return try { val i = gh.sessionInfo(raw); "Saved: ${i.cookies} cookies (${i.format}), ${raw.length / 1024} KB" } catch (_: Exception) { "Saved (unparsed)" }
    }

    // ---- connection ----
    fun saveConfig(owner: String, repo: String, branch: String, token: String, workflows: Map<String, String> = config.value.workflows) {
        viewModelScope.launch {
            val cfg = GhConfig(owner.trim(), repo.trim(), branch.trim().ifBlank { "main" }, token.trim(), workflows.mapValues { it.value.trim() }.filterValues { it.isNotBlank() })
            gh.saveConfig(cfg); config.value = cfg
            logLine("Connection settings saved${if (cfg.ready) "" else " (incomplete - owner / repo / token needed)"}.", if (cfg.ready) "ok" else "err")
            if (cfg.ready) { loadRuns(); listPath(path.value) }
        }
    }

    fun testConnection() {
        viewModelScope.launch {
            connectionStatus.value = "Testing..."
            try { connectionStatus.value = gh.testConnection(); logLine(connectionStatus.value, "ok") }
            catch (e: Exception) { connectionStatus.value = "Failed: ${e.message}"; logLine("Connection test failed: ${e.message}", "err") }
        }
    }

    // ---- session ----
    fun saveSession(raw: String) {
        viewModelScope.launch {
            try {
                val info = gh.saveSession(raw)
                sessionRaw.value = gh.session
                if (info == null) { sessionStatus.value = "No session saved"; logLine("Gemini session cleared.", "ok"); return@launch }
                sessionStatus.value = sessionSummary(gh.session)
                logLine("Session saved: ${info.cookies} cookies (${info.format}).", "ok")
                if (raw.length > 60000) logLine("Warning: session JSON is over 60 KB - workflow_dispatch may reject it. Export a cookies-only JSON instead.", "err")
            } catch (e: Exception) { sessionStatus.value = "Invalid JSON"; logLine("Session JSON invalid: ${e.message}", "err") }
        }
    }

    fun loadSessionFromFile(uri: Uri) {
        viewModelScope.launch {
            try { val f = LocalFile.fromUri(getApplication(), uri); saveSession(String(f.bytes)) }
            catch (e: Exception) { logLine("Could not read session file: ${e.message}", "err") }
        }
    }

    // ---- workflow triggers ----
    private fun trigger(label: String, inputs: Map<String, String>) {
        viewModelScope.launch {
            if (!gh.config.ready) { logLine("Configure owner / repo / token first (Connection card).", "err"); return@launch }
            triggering.value = label
            try {
                gh.dispatch(GitHubRepo.GENERATOR_WORKFLOW, inputs)
                logLine("$label triggered on ${gh.config.branchOrMain} - run appears in a few seconds.", "ok")
                delay(8000); loadRuns()
            } catch (e: Exception) { logLine("$label trigger failed: ${e.message}", "err") }
            finally { triggering.value = null }
        }
    }

    fun triggerRingtone() = trigger("Ringtone Generator", gh.ringtoneInputs(rgCount.value, rgLength.value, rgAutoProcess.value, rgVolume.value, rgSilence.value, rgPad.value, rgTarget.value, rgAttachSession.value))
    fun triggerMetadata() = trigger("Metadata Generator", gh.metadataInputs(mdQueuePath.value, mdAttachSession.value))

    // ---- runs ----
    fun loadRuns() {
        viewModelScope.launch {
            if (!gh.config.ready) return@launch
            runsLoading.value = true
            try { runs.value = gh.listRuns() } catch (e: Exception) { logLine("Runs load failed: ${e.message}", "err") }
            finally { runsLoading.value = false }
        }
    }

    fun deleteRun(run: GhRun) {
        viewModelScope.launch {
            if (!confirm("Delete run #${run.runNumber} (${run.name}) from history?", "Delete run", "Delete")) return@launch
            try { gh.deleteRun(run.id); logLine("Run #${run.runNumber} deleted.", "ok"); loadRuns() } catch (e: Exception) { logLine("Delete failed: ${e.message}", "err") }
        }
    }

    fun cleanRuns() {
        viewModelScope.launch {
            if (!gh.config.ready) { logLine("Configure owner / repo / token first.", "err"); return@launch }
            if (!confirm("Delete ALL completed workflow runs from the Actions history? Queued / running runs are kept. This cannot be undone.", "Clean run history", "Delete all")) return@launch
            runsLoading.value = true
            logLine("Cleaning completed run history...")
            try {
                val (deleted, failed) = gh.cleanCompletedRuns { logLine("... $it runs deleted so far") }
                logLine("Run history clean complete: $deleted deleted${if (failed > 0) ", $failed failed" else ""}.", "ok")
            } catch (e: Exception) { logLine("Clean stopped: ${e.message}", "err") }
            finally { runsLoading.value = false; loadRuns() }
        }
    }

    // ---- repo browser ----
    fun listPath(p: String) {
        viewModelScope.launch {
            if (!gh.config.ready) return@launch
            filesLoading.value = true
            try { entries.value = gh.listPath(p); path.value = p } catch (e: Exception) { logLine("List failed: ${e.message}", "err") }
            finally { filesLoading.value = false }
        }
    }

    fun goUp() { val p = path.value; listPath(if (p.contains('/')) p.substringBeforeLast('/') else "") }

    fun deleteFile(e: GhEntry) {
        viewModelScope.launch {
            if (!confirm("Delete \"${e.path}\" from the repo? This creates a commit on ${gh.config.branchOrMain}.", "Delete file", "Delete")) return@launch
            try { gh.deleteFile(e); logLine("Deleted ${e.path}.", "ok"); listPath(path.value) } catch (ex: Exception) { logLine("Delete failed: ${ex.message}", "err") }
        }
    }

    fun pushFiles(uris: List<Uri>) {
        viewModelScope.launch {
            if (!gh.config.ready) { logLine("Configure owner / repo / token first.", "err"); return@launch }
            for (u in uris) {
                try {
                    val f = LocalFile.fromUri(getApplication(), u)
                    val target = (if (path.value.isBlank()) "" else "${path.value}/") + f.name
                    logLine("Pushing $target (${"%.1f".format(f.size / 1024.0)} KB)...")
                    val line = gh.pushFile(path.value, f)
                    logLine(line, if (line.startsWith("Skipped")) "err" else "ok")
                } catch (e: Exception) { logLine("Push failed: ${e.message}", "err") }
            }
            listPath(path.value)
        }
    }
}
