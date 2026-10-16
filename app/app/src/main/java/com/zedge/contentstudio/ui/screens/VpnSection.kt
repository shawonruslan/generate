package com.zedge.contentstudio.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.ChipRow
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.data.VpnProfile
import com.zedge.contentstudio.data.VpnRepo
import com.zedge.contentstudio.ui.GitHubViewModel
import com.zedge.contentstudio.ui.components.EmptyState
import com.zedge.contentstudio.ui.components.SectionCard
import com.zedge.contentstudio.ui.components.StatusPill
import com.zedge.contentstudio.ui.theme.Danger
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn

/**
 * v24 - VPN card of the GitHub Control page: per-account OpenVPN / WireGuard profiles, active profile,
 * mode, and the "Test" button that dispatches the account workflow in vpn_test mode.
 */
@Composable
fun VpnSection(vm: GitHubViewModel, openUrl: (String) -> Unit) {
    val account by vm.vpnAccount.collectAsStateWithLifecycle()
    val settings by vm.vpnSettings.collectAsStateWithLifecycle()
    val loading by vm.vpnLoading.collectAsStateWithLifecycle()
    val editing by vm.vpnEditing.collectAsStateWithLifecycle()

    var name by remember { mutableStateOf("") }
    var type by remember { mutableStateOf("openvpn") }
    var config by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var extra by remember { mutableStateOf("") }
    var certs by remember { mutableStateOf(mapOf<String, String>()) }
    var copyAll by remember { mutableStateOf(false) }
    var pendingCert by remember { mutableStateOf("") }

    LaunchedEffect(editing) {
        val p = editing
        name = p?.name ?: ""; type = p?.type ?: "openvpn"; config = p?.config ?: ""; user = p?.username ?: ""; pass = p?.password ?: ""; extra = p?.extra ?: ""
        certs = if (p == null) emptyMap() else mapOf("ca" to p.ca, "cert" to p.cert, "key" to p.key, "tlsAuth" to p.tlsAuth, "tlsCrypt" to p.tlsCrypt).filterValues { it.isNotBlank() }
    }
    val analysis = remember(config, type) { VpnRepo.analyze(config, type) }
    LaunchedEffect(analysis.type, config) { if (config.isNotBlank()) type = analysis.type }

    val pickConfig = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { u ->
        if (u != null) vm.readTextFile(u) { fileName, text -> config = text; if (name.isBlank()) name = fileName.substringBeforeLast('.') }
    }
    val pickCert = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { u ->
        if (u != null && pendingCert.isNotBlank()) vm.readTextFile(u) { _, text -> certs = certs + (pendingCert to text.trim()) }
    }

    val active = settings.active
    val last = settings.lastTest
    val pill = when {
        !settings.enabled -> "VPN OFF" to Warn
        else -> "${settings.mode.uppercase()} · ${active?.name ?: ""}" to Ok
    }

    SectionCard("VPN (OpenVPN / WireGuard) - ${account.uppercase()}", "Own exit IP for this account - profiles sync with the panel via Firebase", trailing = { StatusPill(pill.first, pill.second) }) {
        Text("Mode for real uploads", style = MaterialTheme.typography.labelMedium)
        ChipRow(listOf("none" to "Off (proxy / direct)", "openvpn" to "OpenVPN", "wireguard" to "WireGuard"), settings.mode, { vm.setVpnMode(it, settings.keepProxy) })
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(settings.keepProxy, { vm.setVpnMode(settings.mode, it) })
            Text("Keep the HTTP proxy inside the VPN (default: VPN replaces proxy)", style = MaterialTheme.typography.bodySmall)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { active?.let { vm.testVpn(it) } }, enabled = active != null && last?.busy != true) { Text("Test active profile") }
            OutlinedButton(onClick = { vm.refreshVpn() }) { Text("Refresh") }
            if (loading || last?.busy == true) CircularProgressIndicator(Modifier.width(18.dp).height(18.dp), strokeWidth = 2.dp)
        }

        // ---- last test result ----
        if (last != null) {
            Spacer(Modifier.height(8.dp))
            val color = when (last.status) { "ok" -> Ok; "fail" -> Danger; else -> Warn }
            val icon = when (last.status) { "ok" -> "✅"; "fail" -> "❌"; else -> "⏳" }
            Column(Modifier.fillMaxWidth().padding(4.dp)) {
                Text("$icon ${last.status.uppercase()} · ${last.profileName} (${last.type})", color = color, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
                Text(last.message, style = MaterialTheme.typography.bodySmall)
                if (last.ipBefore != null || last.ipAfter != null) Text("IP ${last.ipBefore?.ip ?: "?"} → ${last.ipAfter?.toString() ?: "?"}", style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
                val meta = listOfNotNull(last.zedgeOk?.let { if (it) "zedge.net reachable" else "zedge.net NOT reachable" }, if (last.durationMs > 0) "${last.durationMs / 1000}s" else null, if (last.at > 0) android.text.format.DateUtils.getRelativeTimeSpanString(last.at).toString() else null)
                if (meta.isNotEmpty()) Text(meta.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (last.runUrl.isNotBlank()) TextButton(onClick = { openUrl(last.runUrl) }) { Text("Open run") }
                if (last.status == "fail" && last.logTail.isNotBlank()) Text(last.logTail.takeLast(1200), style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        HorizontalDivider(Modifier.padding(vertical = 10.dp))
        Text("Saved profiles", style = MaterialTheme.typography.titleSmall)
        if (settings.profiles.isEmpty()) EmptyState("No profiles for ${Accounts.byKey(account).label} yet - add one below.")
        settings.profiles.forEach { p ->
            val isActive = p.id == settings.activeProfileId
            Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text((if (isActive) "⭐ " else "") + p.name, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    StatusPill(p.type, if (p.isWireGuard) Ok else Warn)
                    if (!p.isWireGuard) StatusPill(if (p.username.isNotBlank()) "user/pass" else "cert-only", MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = { vm.testVpn(p) }, enabled = last?.busy != true) { Text("Test") }
                    if (!isActive) TextButton(onClick = { vm.setVpnActive(p) }) { Text("Set active") }
                    TextButton(onClick = { vm.editVpn(p) }) { Text("Edit") }
                    TextButton(onClick = { vm.copyVpnToAll(p) }) { Text("Copy → all") }
                    TextButton(onClick = { vm.deleteVpn(p) }) { Text("Delete", color = Danger) }
                }
            }
        }

        HorizontalDivider(Modifier.padding(vertical = 10.dp))
        Text(if (editing == null) "New profile" else "Edit: ${editing!!.name}", style = MaterialTheme.typography.titleSmall)
        Spacer(Modifier.height(6.dp))
        OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("Profile name") }, singleLine = true)
        Spacer(Modifier.height(6.dp))
        ChipRow(listOf("openvpn" to "OpenVPN (.ovpn)", "wireguard" to "WireGuard (.conf)"), type, { type = it })
        OutlinedTextField(config, { config = it }, Modifier.fillMaxWidth().height(160.dp), label = { Text("Config (.ovpn / .conf text)") }, textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = { pickConfig.launch(arrayOf("*/*")) }) { Text("Load .ovpn / .conf") }
            if (analysis.hints.isNotEmpty()) Text(analysis.hints.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
        }
        if (type == "openvpn") {
            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(user, { user = it }, Modifier.weight(1f), label = { Text(if (analysis.needsAuth) "Username (required)" else "Username (optional)") }, singleLine = true)
                OutlinedTextField(pass, { pass = it }, Modifier.weight(1f), label = { Text("Password") }, singleLine = true, visualTransformation = PasswordVisualTransformation())
            }
            Spacer(Modifier.height(6.dp))
            Text("Separate certificate files (only if the .ovpn references ca / cert / key / tls-auth / tls-crypt files)", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                listOf("ca" to "CA", "cert" to "Cert", "key" to "Key", "tlsAuth" to "TLS-auth", "tlsCrypt" to "TLS-crypt").forEach { (k, label) ->
                    TextButton(onClick = { pendingCert = k; pickCert.launch(arrayOf("*/*")) }) { Text((if (certs[k].isNullOrBlank()) "" else "✅ ") + label) }
                }
                if (certs.isNotEmpty()) TextButton(onClick = { certs = emptyMap() }) { Text("Clear") }
            }
        }
        OutlinedTextField(extra, { extra = it }, Modifier.fillMaxWidth(), label = { Text("Extra config lines (optional)") }, textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(copyAll, { copyAll = it })
            Text("Also copy this profile to all 4 accounts", style = MaterialTheme.typography.bodySmall)
        }
        fun build(): VpnProfile = VpnProfile(
            editing?.id ?: VpnRepo.newId(), name.trim(), type, config.replace("\r", ""),
            if (type == "openvpn") user.trim() else "", if (type == "openvpn") pass else "",
            certs["ca"] ?: "", certs["cert"] ?: "", certs["key"] ?: "", certs["tlsAuth"] ?: "", certs["tlsCrypt"] ?: "",
            extra.replace("\r", ""), editing?.createdAt ?: 0L,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { vm.saveVpnProfile(build(), copyAll, test = false) }) { Text("Save") }
            OutlinedButton(onClick = { vm.saveVpnProfile(build(), copyAll, test = true) }) { Text("Save & Test") }
            TextButton(onClick = { vm.editVpn(null) }) { Text("New") }
        }
        Spacer(Modifier.height(4.dp))
        Text("Test runs the account workflow in vpn_test mode: connect → verify the public IP changed + zedge.net reachable → report here & Telegram → disconnect. No upload happens. Real runs abort if the VPN fails, so the runner IP is never exposed.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
