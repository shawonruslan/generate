package com.zedge.contentstudio.data

import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.Json
import org.json.JSONObject

/**
 * v24 - VPN (OpenVPN / WireGuard) profiles per Zedge account.
 * Storage mirrors the web panel + vpn.mjs:  dashboardSettings/vpn/{mode, activeProfileId, keepProxy, profiles/<id>, lastTest, lastRun}
 */
data class VpnProfile(
    val id: String,
    val name: String = "",
    val type: String = "openvpn",          // openvpn | wireguard
    val config: String = "",               // .ovpn or WireGuard .conf text
    val username: String = "",
    val password: String = "",
    val ca: String = "", val cert: String = "", val key: String = "", val tlsAuth: String = "", val tlsCrypt: String = "",
    val extra: String = "",
    val createdAt: Long = 0L,
    val updatedAt: Long = 0L,
) {
    val isWireGuard: Boolean get() = type == "wireguard"
    fun toJson(): JSONObject = Json.obj(
        "id" to id, "name" to name, "type" to type, "config" to config, "username" to username, "password" to password,
        "ca" to ca, "cert" to cert, "key" to key, "tlsAuth" to tlsAuth, "tlsCrypt" to tlsCrypt, "extra" to extra,
        "createdAt" to (if (createdAt > 0) createdAt else System.currentTimeMillis()), "updatedAt" to System.currentTimeMillis(),
    )
    companion object {
        fun from(id: String, o: JSONObject): VpnProfile = VpnProfile(
            id, o.optString("name"), if (o.optString("type") == "wireguard") "wireguard" else "openvpn", o.optString("config"),
            o.optString("username"), o.optString("password"), o.optString("ca"), o.optString("cert"), o.optString("key"),
            o.optString("tlsAuth"), o.optString("tlsCrypt"), o.optString("extra"), o.optLong("createdAt"), o.optLong("updatedAt"),
        )
    }
}

data class VpnIp(val ip: String, val place: String) {
    override fun toString(): String = if (place.isBlank()) ip else "$ip ($place)"
    companion object {
        fun from(o: JSONObject?): VpnIp? {
            if (o == null) return null
            val ip = o.optString("ip"); if (ip.isBlank()) return null
            return VpnIp(ip, listOf(o.optString("city"), o.optString("country")).filter { it.isNotBlank() }.joinToString(", "))
        }
    }
}

data class VpnResult(
    val status: String,                    // queued | running | ok | fail
    val stage: String = "",
    val message: String = "",
    val detail: String = "",
    val profileId: String = "",
    val profileName: String = "",
    val type: String = "",
    val ipBefore: VpnIp? = null,
    val ipAfter: VpnIp? = null,
    val zedgeOk: Boolean? = null,
    val durationMs: Long = 0L,
    val at: Long = 0L,
    val runUrl: String = "",
    val logTail: String = "",
) {
    val busy: Boolean get() = status == "queued" || status == "running"
    companion object {
        fun from(o: JSONObject?): VpnResult? {
            if (o == null) return null
            return VpnResult(
                o.optString("status"), o.optString("stage"), o.optString("message"), o.optString("detail"), o.optString("profileId"), o.optString("profileName"), o.optString("type"),
                VpnIp.from(o.optJSONObject("ipBefore")), VpnIp.from(o.optJSONObject("ipAfter")),
                if (o.has("zedgeOk") && !o.isNull("zedgeOk")) o.optBoolean("zedgeOk") else null,
                o.optLong("durationMs"), o.optLong("at"), o.optString("runUrl"), o.optString("logTail"),
            )
        }
    }
}

/** v24.1: per-account GitHub connection used to dispatch this account's workflow (panel + app share it). */
data class VpnGithub(
    val useGlobal: Boolean = true, val owner: String = "", val repo: String = "", val branch: String = "",
    val workflow: String = "", val token: String = "", val updatedAt: Long = 0,
) {
    /** Each Zedge account has its own GitHub account / repo / token. */
    val ownReady: Boolean get() = owner.isNotBlank() && repo.isNotBlank() && token.isNotBlank()
    fun toJson(): JSONObject = Json.obj("useGlobal" to false, "owner" to owner, "repo" to repo, "branch" to branch.ifBlank { "main" }, "workflow" to workflow, "token" to token, "updatedAt" to System.currentTimeMillis())
    companion object {
        fun from(o: JSONObject?): VpnGithub? = o?.let {
            VpnGithub(false, it.optString("owner"), it.optString("repo"), it.optString("branch"), it.optString("workflow"), it.optString("token"), it.optLong("updatedAt"))
        }
    }
}

data class VpnSettings(
    val mode: String = "none",             // none | openvpn | wireguard
    val activeProfileId: String = "",
    val keepProxy: Boolean = false,
    val profiles: List<VpnProfile> = emptyList(),
    val lastTest: VpnResult? = null,
    val lastRun: VpnResult? = null,
    val github: VpnGithub? = null,
) {
    val active: VpnProfile? get() = profiles.firstOrNull { it.id == activeProfileId }
    val enabled: Boolean get() = mode != "none" && active != null
}

data class VpnAnalysis(val type: String, val needsAuth: Boolean, val externalFiles: List<String>, val hints: List<String>)

class VpnRepo(private val dbOf: (String) -> FirebaseRtdb, private val gitHub: GitHubRepo) {

    suspend fun load(accountKey: String): VpnSettings {
        val raw = dbOf(accountKey).get(Accounts.VPN_PATH) as? JSONObject ?: return VpnSettings()
        val profiles = raw.optJSONObject("profiles")?.let { p -> p.keys().asSequence().mapNotNull { id -> p.optJSONObject(id)?.let { VpnProfile.from(id, it) } }.toList() } ?: emptyList()
        return VpnSettings(
            raw.optString("mode", "none").ifBlank { "none" }, raw.optString("activeProfileId"), raw.optBoolean("keepProxy", false),
            profiles.sortedBy { it.name.lowercase() }, VpnResult.from(raw.optJSONObject("lastTest")), VpnResult.from(raw.optJSONObject("lastRun")),
            VpnGithub.from(raw.optJSONObject("github")),
        )
    }

    /** Saves (creates or overwrites) the profile in each given account database. */
    suspend fun saveProfile(accountKeys: List<String>, profile: VpnProfile) {
        val json = profile.toJson()
        accountKeys.forEach { dbOf(it).set("${Accounts.VPN_PATH}/profiles/${profile.id}", json) }
    }

    suspend fun deleteProfile(accountKey: String, id: String) {
        val cur = load(accountKey)
        val patch = JSONObject().put("profiles/$id", JSONObject.NULL).put("updatedAt", System.currentTimeMillis())
        if (cur.activeProfileId == id) { patch.put("activeProfileId", ""); patch.put("mode", "none") }
        dbOf(accountKey).update(Accounts.VPN_PATH, patch)
    }

    /** Set active -> mode switches to the profile's type so real runs use it immediately. */
    suspend fun setActive(accountKey: String, profile: VpnProfile) {
        dbOf(accountKey).update(Accounts.VPN_PATH, Json.obj("activeProfileId" to profile.id, "mode" to profile.type, "updatedAt" to System.currentTimeMillis()))
    }

    suspend fun setMode(accountKey: String, mode: String, keepProxy: Boolean) {
        dbOf(accountKey).update(Accounts.VPN_PATH, Json.obj("mode" to mode, "keepProxy" to keepProxy, "updatedAt" to System.currentTimeMillis()))
    }

    suspend fun copyToAll(fromKey: String, profile: VpnProfile) = saveProfile(Accounts.keys.filter { it != fromKey }, profile)

    /**
     * Test = dispatch the account's own workflow with run_mode=vpn_test. The yml skips the automation, connects the
     * tunnel, verifies the IP change + zedge.net and writes the result to dashboardSettings/vpn/lastTest.
     */
    suspend fun saveGithub(accountKey: String, g: VpnGithub) {
        dbOf(accountKey).update(Accounts.VPN_PATH, Json.obj("github" to g.toJson()))
    }

    /** Effective (config, workflowFile) used to dispatch this account's workflow, or null when nothing is configured. */
    fun effectiveGithub(accountKey: String, settings: VpnSettings?): Pair<GhConfig, String>? {
        val own = settings?.github
        // No fallback to the shared GitHub page: the connection must be set for this account.
        if (own != null && own.ownReady) return GhConfig(own.owner, own.repo, own.branch.ifBlank { "main" }, own.token) to own.workflow.ifBlank { "$accountKey.yml" }
        return null
    }

    suspend fun check(accountKey: String, settings: VpnSettings?): String {
        val (cfg, wf) = effectiveGithub(accountKey, settings) ?: throw IllegalStateException("GitHub connection for ${accountKey.uppercase()} is not configured")
        return gitHub.checkWorkflow(cfg, wf)
    }

    suspend fun test(accountKey: String, profile: VpnProfile, settings: VpnSettings? = null) {
        val db = dbOf(accountKey)
        val (cfg, wf) = effectiveGithub(accountKey, settings) ?: throw IllegalStateException("GitHub connection for ${accountKey.uppercase()} is not configured (VPN page > GitHub connection)")
        db.update("${Accounts.VPN_PATH}/lastTest", Json.obj(
            "status" to "queued", "stage" to "dispatch", "message" to "Workflow dispatched - waiting for the runner...",
            "profileId" to profile.id, "profileName" to profile.name, "type" to profile.type, "at" to System.currentTimeMillis(), "account" to accountKey,
            "repo" to "${cfg.owner}/${cfg.repo}", "workflow" to wf, "runUrl" to "",
        ))
        try {
            gitHub.dispatchWith(cfg, wf, mapOf("run_mode" to "vpn_test", "vpn_profile" to profile.id, "os" to "windows-latest"))
        } catch (e: Exception) {
            runCatching { db.update("${Accounts.VPN_PATH}/lastTest", Json.obj("status" to "fail", "stage" to "dispatch", "message" to "Trigger failed: ${e.message}", "at" to System.currentTimeMillis())) }
            throw e
        }
    }

    companion object {
        fun newId(): String = "vpn_" + java.lang.Long.toString(System.currentTimeMillis(), 36) + (1000..9999).random()

        private val EXTERNAL = listOf("ca", "cert", "key", "tls-auth", "tls-crypt", "pkcs12", "tls-crypt-v2")
        val EXTERNAL_FIELD = mapOf("ca" to "ca", "cert" to "cert", "key" to "key", "tls-auth" to "tlsAuth", "tls-crypt" to "tlsCrypt")

        /** Same heuristics as the web panel: detects type, auth requirement and external file references. */
        fun analyze(raw: String, fallbackType: String): VpnAnalysis {
            val t = raw.replace("\r", "")
            if (t.isBlank()) return VpnAnalysis(fallbackType, false, emptyList(), emptyList())
            val m = RegexOption.MULTILINE; val i = RegexOption.IGNORE_CASE
            if (Regex("^\\s*\\[Interface\\]", setOf(m, i)).containsMatchIn(t) && Regex("^\\s*\\[Peer\\]", setOf(m, i)).containsMatchIn(t)) {
                val hints = mutableListOf<String>()
                if (!Regex("^\\s*PrivateKey\\s*=", setOf(m, i)).containsMatchIn(t)) hints += "missing PrivateKey"
                if (!Regex("^\\s*Endpoint\\s*=", setOf(m, i)).containsMatchIn(t)) hints += "missing Endpoint"
                if (!Regex("AllowedIPs\\s*=.*0\\.0\\.0\\.0/0", setOf(i)).containsMatchIn(t)) hints += "AllowedIPs lacks 0.0.0.0/0 - IP will not change for all traffic"
                if (hints.isEmpty()) hints += "WireGuard config looks complete"
                return VpnAnalysis("wireguard", false, emptyList(), hints)
            }
            val hints = mutableListOf<String>()
            if (!Regex("^\\s*remote\\s+", setOf(m, i)).containsMatchIn(t) && !t.contains("<connection>", true)) hints += "no 'remote' line - not a client .ovpn?"
            val needsAuth = Regex("^\\s*auth-user-pass\\b", setOf(m, i)).containsMatchIn(t)
            val ext = EXTERNAL.filter { d ->
                val mm = Regex("^\\s*${Regex.escape(d)}\\s+([^\\s#]+)", setOf(m, i)).find(t)
                mm != null && mm.groupValues[1] != "[inline]" && !Regex("<${Regex.escape(d)}>[\\s\\S]*?</${Regex.escape(d)}>", setOf(i)).containsMatchIn(t)
            }
            hints += if (needsAuth) "needs username + password (auth-user-pass)" else "certificate-only login - no username/password needed"
            if (ext.isNotEmpty()) hints += "references external file(s): ${ext.joinToString()} - upload them" else if (t.contains("<ca>", true)) hints += "certificates inline - nothing else to upload"
            if (!Regex("^\\s*redirect-gateway", setOf(m, i)).containsMatchIn(t)) hints += "no redirect-gateway (fine if the server pushes it; the test verifies the IP change)"
            return VpnAnalysis("openvpn", needsAuth, ext, hints)
        }

        /** Throws IllegalArgumentException with a user-facing message when the profile cannot work. */
        fun validate(p: VpnProfile) {
            require(p.name.isNotBlank()) { "Profile name is required." }
            require(p.config.isNotBlank()) { "Paste or pick the config file first." }
            val a = analyze(p.config, p.type)
            require(a.type == p.type) { "The config looks like ${a.type} but type is set to ${p.type}." }
            if (p.type == "openvpn") {
                require(!(a.needsAuth && p.username.isBlank())) { "This .ovpn uses auth-user-pass - enter username and password." }
                val missing = a.externalFiles.filter { d -> val f = EXTERNAL_FIELD[d]; f == null || fieldValue(p, f).isBlank() }
                require(missing.isEmpty()) { "Upload the referenced file(s): ${missing.joinToString()} (or use an .ovpn with inline certificates)." }
            }
        }

        private fun fieldValue(p: VpnProfile, f: String): String = when (f) { "ca" -> p.ca; "cert" -> p.cert; "key" -> p.key; "tlsAuth" -> p.tlsAuth; "tlsCrypt" -> p.tlsCrypt; else -> "" }
    }
}
