package com.zedge.contentstudio.data

import android.content.Context
import android.util.Base64
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.Json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URLEncoder

data class GhConfig(val owner: String = "", val repo: String = "", val branch: String = "main", val token: String = "") {
    val ready: Boolean get() = owner.isNotBlank() && repo.isNotBlank() && token.isNotBlank()
    val branchOrMain: String get() = branch.ifBlank { "main" }
    fun toJson(): String = Json.obj("owner" to owner, "repo" to repo, "branch" to branchOrMain, "token" to token).toString()
    companion object {
        fun parse(raw: String?): GhConfig {
            if (raw.isNullOrBlank()) return GhConfig()
            return try {
                val o = JSONObject(raw)
                GhConfig(o.optString("owner"), o.optString("repo"), o.optString("branch", "main").ifBlank { "main" }, o.optString("token"))
            } catch (_: Exception) { GhConfig() }
        }
    }
}

data class GhRun(val id: Long, val name: String, val status: String, val conclusion: String?, val event: String, val branch: String, val createdAt: String, val htmlUrl: String, val runNumber: Long)
data class GhEntry(val name: String, val path: String, val type: String, val size: Long, val sha: String, val htmlUrl: String)
data class SessionInfo(val cookies: Int, val format: String)

/**
 * GitHub Control panel backend: connection config + Gemini session (local + cloud-synced to
 * dashboardSettings/ghPanel on ZEDGE1), workflow dispatch, runs list/clean, repo file browser.
 */
class GitHubRepo(context: Context, private val http: OkHttpClient, private val zedge1: FirebaseRtdb) {
    private val prefs = context.getSharedPreferences("gh_panel", Context.MODE_PRIVATE)

    var config: GhConfig
        get() = GhConfig.parse(prefs.getString("cfg", null))
        private set(v) { prefs.edit().putString("cfg", v.toJson()).apply() }
    var session: String
        get() = prefs.getString("session", "") ?: ""
        private set(v) { prefs.edit().putString("session", v).apply() }
    private var cfgTs: Long
        get() = prefs.getLong("cfgTs", 0L)
        set(v) { prefs.edit().putLong("cfgTs", v).apply() }
    private var sessionTs: Long
        get() = prefs.getLong("sessionTs", 0L)
        set(v) { prefs.edit().putLong("sessionTs", v).apply() }

    // ---- settings + cloud sync ----
    suspend fun saveConfig(cfg: GhConfig) {
        val ts = System.currentTimeMillis()
        config = cfg; cfgTs = ts
        runCatching { zedge1.update(Accounts.GH_SETTINGS_PATH, Json.obj("cfg" to cfg.toJson(), "cfgUpdatedAt" to ts)) }
    }

    /** Returns cookie info, or throws if the JSON is invalid. Empty string clears the session. */
    suspend fun saveSession(raw: String): SessionInfo? {
        val ts = System.currentTimeMillis()
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            session = ""; sessionTs = ts
            runCatching { zedge1.update(Accounts.GH_SETTINGS_PATH, Json.obj("session" to "", "sessionUpdatedAt" to ts)) }
            return null
        }
        val info = sessionInfo(trimmed) // throws on invalid JSON
        session = trimmed; sessionTs = ts
        runCatching { zedge1.update(Accounts.GH_SETTINGS_PATH, Json.obj("session" to trimmed, "sessionUpdatedAt" to ts)) }
        return info
    }

    fun sessionInfo(raw: String): SessionInfo {
        val parsed = Json.parse(raw)
        return when {
            parsed is JSONArray -> SessionInfo(parsed.length(), "cookie array")
            parsed is JSONObject && parsed.optJSONArray("cookies") != null -> SessionInfo(parsed.optJSONArray("cookies")!!.length(), "storageState")
            else -> SessionInfo(0, "unknown object")
        }
    }

    /** Newer-timestamp-wins merge with the cloud copy; returns true if local settings changed. */
    suspend fun syncFromCloud(): Boolean {
        val data = (zedge1.get(Accounts.GH_SETTINGS_PATH) as? JSONObject) ?: JSONObject()
        val localCfg = prefs.getString("cfg", "") ?: ""
        val localSes = session
        val dbCfgTs = data.optLong("cfgUpdatedAt", 0L)
        val dbSesTs = data.optLong("sessionUpdatedAt", 0L)
        var applied = false
        val dbCfg = data.optString("cfg", "")
        if (dbCfg.isNotBlank() && dbCfgTs >= cfgTs) {
            if (dbCfg != localCfg) applied = true
            prefs.edit().putString("cfg", dbCfg).apply(); cfgTs = dbCfgTs
        } else if (localCfg.isNotBlank() && cfgTs > dbCfgTs) {
            runCatching { zedge1.update(Accounts.GH_SETTINGS_PATH, Json.obj("cfg" to localCfg, "cfgUpdatedAt" to cfgTs)) }
        }
        if (data.has("session") && Json.norm(data.opt("session")) is String && dbSesTs >= sessionTs) {
            val s = data.optString("session", "")
            if (s != localSes) applied = true
            session = s; sessionTs = dbSesTs
        } else if (localSes.isNotBlank() && sessionTs > dbSesTs) {
            runCatching { zedge1.update(Accounts.GH_SETTINGS_PATH, Json.obj("session" to localSes, "sessionUpdatedAt" to sessionTs)) }
        }
        return applied
    }

    // ---- REST ----
    private suspend fun api(path: String, method: String = "GET", body: JSONObject? = null): Any? = withContext(Dispatchers.IO) {
        val cfg = config
        if (!cfg.ready) throw IOException("GitHub connection not configured (owner / repo / token)")
        val b = Request.Builder().url(GH_API + path)
            .header("Authorization", "Bearer ${cfg.token}")
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28")
        val rb = body?.toString()?.toRequestBody("application/json".toMediaType())
        when (method) {
            "GET" -> b.get()
            "DELETE" -> b.delete(rb)
            "POST" -> b.post(rb ?: "".toRequestBody(null))
            "PUT" -> b.put(rb ?: "".toRequestBody(null))
        }
        http.newCall(b.build()).execute().use { resp ->
            val text = resp.body?.string() ?: ""
            if (!resp.isSuccessful) {
                var detail = ""
                try { detail = JSONObject(text).optString("message") } catch (_: Exception) {}
                throw IOException("GitHub API ${resp.code}: ${detail.ifBlank { resp.message }}")
            }
            if (resp.code == 204 || text.isBlank()) null else Json.parse(text)
        }
    }

    private fun repoPath(): String = "/repos/${config.owner}/${config.repo}"
    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
    private fun encPath(p: String): String = p.split('/').joinToString("/") { enc(it) }

    suspend fun testConnection(): String {
        val repo = api(repoPath()) as JSONObject
        val wfs = api("${repoPath()}/actions/workflows?per_page=50") as JSONObject
        return "Connected: ${repo.optString("full_name")} (${if (repo.optBoolean("private")) "private" else "public"}) - ${wfs.optInt("total_count")} workflows"
    }

    suspend fun dispatch(workflowFile: String, inputs: Map<String, String>) {
        val body = Json.obj("ref" to config.branchOrMain, "inputs" to JSONObject(inputs))
        api("${repoPath()}/actions/workflows/${enc(workflowFile)}/dispatches", "POST", body)
    }

    /** generator.yml inputs for the ringtone generator card (defaults identical to the dashboard form). */
    fun ringtoneInputs(count: String, length: String, autoProcess: String, volume: String, silence: String, pad: String, target: String, attachSession: Boolean): Map<String, String> {
        val m = linkedMapOf(
            "auto_generate_count" to count.ifBlank { "10" },
            "length_seconds" to length.ifBlank { "5" },
            "auto_process" to autoProcess.ifBlank { "true" },
            "volume_boost_pct" to volume.ifBlank { "200" },
            "silence_threshold" to silence.ifBlank { "0.02" },
            "pad_ms" to pad.ifBlank { "100" },
            "target_account" to target.ifBlank { "zedge_2" },
        )
        if (attachSession && session.isNotBlank()) m["gemini_session"] = session
        return m
    }

    fun metadataInputs(queuePath: String, attachSession: Boolean): Map<String, String> {
        val m = linkedMapOf("mode" to "metadata", "image_queue_path" to queuePath.ifBlank { "wallpaperQueue" })
        if (attachSession && session.isNotBlank()) m["gemini_session"] = session
        return m
    }

    suspend fun listRuns(): List<GhRun> {
        val data = api("${repoPath()}/actions/runs?per_page=20") as JSONObject
        val arr = data.optJSONArray("workflow_runs") ?: JSONArray()
        return (0 until arr.length()).map { i ->
            val r = arr.getJSONObject(i)
            GhRun(
                r.optLong("id"), r.optString("name").ifBlank { r.optString("display_title") }, r.optString("status"),
                Json.norm(r.opt("conclusion"))?.toString(), r.optString("event"), r.optString("head_branch"),
                r.optString("created_at"), r.optString("html_url"), r.optLong("run_number")
            )
        }
    }

    suspend fun deleteRun(id: Long) { api("${repoPath()}/actions/runs/$id", "DELETE") }

    /** Deletes every completed run (queued / running are kept). Returns deleted/failed counts. */
    suspend fun cleanCompletedRuns(onProgress: (Int) -> Unit): Pair<Int, Int> {
        var deleted = 0; var failed = 0
        for (round in 0 until 30) {
            val data = api("${repoPath()}/actions/runs?status=completed&per_page=100&page=1") as JSONObject
            val runs = data.optJSONArray("workflow_runs") ?: JSONArray()
            if (runs.length() == 0) break
            var roundDeleted = 0
            for (i in 0 until runs.length()) {
                try { deleteRun(runs.getJSONObject(i).optLong("id")); deleted++; roundDeleted++; if (deleted % 10 == 0) onProgress(deleted) }
                catch (_: Exception) { failed++ }
            }
            if (roundDeleted == 0) break
        }
        return deleted to failed
    }

    suspend fun listPath(path: String): List<GhEntry> {
        val p = if (path.isBlank()) "" else "/" + encPath(path)
        val res = api("${repoPath()}/contents$p?ref=${enc(config.branchOrMain)}")
        val arr = res as? JSONArray ?: return emptyList()
        val out = (0 until arr.length()).map { i ->
            val e = arr.getJSONObject(i)
            GhEntry(e.optString("name"), e.optString("path"), e.optString("type"), e.optLong("size"), e.optString("sha"), e.optString("html_url"))
        }
        return out.sortedWith(compareBy({ if (it.type == "dir") 0 else 1 }, { it.name.lowercase() }))
    }

    suspend fun deleteFile(entry: GhEntry) {
        api("${repoPath()}/contents/${encPath(entry.path)}", "DELETE",
            Json.obj("message" to "chore: delete ${entry.path} (dashboard repo clean)", "sha" to entry.sha, "branch" to config.branchOrMain))
    }

    /** Returns log line. */
    suspend fun pushFile(dir: String, file: LocalFile): String {
        if (file.size > 25L * 1024 * 1024) return "Skipped ${file.name} - over 25 MB (too large for the contents API)."
        val target = (if (dir.isBlank()) "" else "$dir/") + file.name
        val content = Base64.encodeToString(file.bytes, Base64.NO_WRAP)
        var sha: String? = null
        try {
            val existing = api("${repoPath()}/contents/${encPath(target)}?ref=${enc(config.branchOrMain)}")
            if (existing is JSONObject && existing.optString("sha").isNotBlank()) sha = existing.optString("sha")
        } catch (_: Exception) {}
        val body = Json.obj("message" to (if (sha != null) "update: " else "add: ") + "$target (pushed from dashboard)", "content" to content, "branch" to config.branchOrMain)
        if (sha != null) body.put("sha", sha)
        api("${repoPath()}/contents/${encPath(target)}", "PUT", body)
        return "Pushed $target ${if (sha != null) "(updated existing)" else "(new file)"}."
    }

    companion object {
        const val GH_API = "https://api.github.com"
        const val GENERATOR_WORKFLOW = "generator.yml"
        val TARGET_ACCOUNTS = listOf("zedge_1", "zedge_2", "zedge_3")
    }
}
