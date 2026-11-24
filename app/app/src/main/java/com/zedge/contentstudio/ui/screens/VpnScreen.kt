package com.zedge.contentstudio.ui.screens

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.data.GhConfig
import com.zedge.contentstudio.data.VpnGithub
import com.zedge.contentstudio.ui.GitHubViewModel
import com.zedge.contentstudio.ui.components.SectionCard
import com.zedge.contentstudio.ui.components.StatusPill
import com.zedge.contentstudio.ui.theme.Danger
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn

/**
 * v24.1 - dedicated VPN page.
 * Top: the GitHub connection that this account's tests are dispatched with (shared with the GitHub page,
 * or its own owner / repo / token / workflow file). Below: profiles, mode, editor and the live test (VpnSection).
 */
@Composable
fun VpnScreen(vm: GitHubViewModel, activeKey: String) {
    val ctx = LocalContext.current
    fun openUrl(u: String) { runCatching { CustomTabsIntent.Builder().build().launchUrl(ctx, Uri.parse(u)) } }
    // Scope: always the account chosen in the top-bar switcher - every read/write below targets that account's Firebase only.
    LaunchedEffect(activeKey) { vm.selectVpnAccount(activeKey) }

    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            Text(
                "Working on ${activeKey.uppercase()} - the account selected in the top bar. Profiles, mode, GitHub connection and tests on this page are read from and saved to that account's Firebase only.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        item { VpnConnectionCard(vm) }
        item { VpnSection(vm, ::openUrl) }
    }
}

@Composable
private fun VpnConnectionCard(vm: GitHubViewModel) {
    val account by vm.vpnAccount.collectAsStateWithLifecycle()
    val settings by vm.vpnSettings.collectAsStateWithLifecycle()
    val checking by vm.vpnConnChecking.collectAsStateWithLifecycle()
    val global: GhConfig = vm.config()
    val saved = settings.github

    var link by remember { mutableStateOf("") }
    var owner by remember { mutableStateOf("") }
    var repo by remember { mutableStateOf("") }
    var branch by remember { mutableStateOf("") }
    var workflow by remember { mutableStateOf("") }
    var token by remember { mutableStateOf("") }
    LaunchedEffect(account, saved) {
        owner = saved?.owner ?: ""; repo = saved?.repo ?: ""; branch = saved?.branch ?: ""
        workflow = saved?.workflow ?: ""; token = saved?.token ?: ""
        link = if (owner.isNotBlank() && repo.isNotBlank()) "https://github.com/$owner/$repo" else ""
    }

    val effective = vm.vpnEffectiveGithub()
    val pill = when {
        effective == null -> "missing" to Danger
        checking -> "checking" to Warn
        else -> "ready" to Ok
    }

    SectionCard("GitHub connection - ${account.uppercase()}", "This account's own repo + token - Test / real runs of this account are dispatched here", trailing = { StatusPill(pill.first, pill.second) }) {
        Text(
            "${account.uppercase()} has its own GitHub account, repo and token. Enter them here - saved only in this account's Firebase and used for this account's Test / real runs.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(8.dp))
        run {
            OutlinedTextField(link, {
                link = it
                GitHubRepoLink.parse(it)?.let { (o, r) -> owner = o; repo = r }
            }, label = { Text("Repo link / path") }, placeholder = { Text("https://github.com/owner/repo") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(owner, { owner = it }, label = { Text("Owner") }, singleLine = true, modifier = Modifier.weight(1f))
                OutlinedTextField(repo, { repo = it }, label = { Text("Repository") }, singleLine = true, modifier = Modifier.weight(1f))
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(branch, { branch = it }, label = { Text("Branch") }, placeholder = { Text("main") }, singleLine = true, modifier = Modifier.weight(1f))
                OutlinedTextField(workflow, { workflow = it }, label = { Text("Workflow file") }, placeholder = { Text("$account.yml") }, singleLine = true, modifier = Modifier.weight(1f))
            }
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(token, { token = it }, label = { Text("Token (Actions + Contents read/write)") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
        }
        Spacer(Modifier.height(8.dp))
        Text(
            if (effective == null) "${account.uppercase()} has no GitHub connection yet - enter owner, repository, workflow file and token above, then Save. Test cannot run until then."
            else "${effective.first.owner}/${effective.first.repo} · ${effective.second} · ${effective.first.branchOrMain} · token ···${effective.first.token.takeLast(4)}",
            style = MaterialTheme.typography.bodySmall,
            color = if (effective == null) Danger else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { vm.saveVpnGithub(VpnGithub(false, owner.trim(), repo.trim(), branch.trim(), workflow.trim(), token.trim())) }) { Text("Save") }
            OutlinedButton(onClick = { vm.checkVpnGithub() }, enabled = effective != null && !checking) { Text("Check repo & workflow") }
        }
        Spacer(Modifier.height(6.dp))
        Text("Saved in this account's Firebase (dashboardSettings/vpn/github) - the web panel uses the same connection. The check verifies token, repo and that the workflow on GitHub is v24 (has the run_mode input).", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Accepts https://github.com/owner/repo, owner/repo or git@github.com:owner/repo.git */
object GitHubRepoLink {
    private val RX = Regex("(?:github\\.com/)?([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(?:[/?#]|$)")
    fun parse(raw: String): Pair<String, String>? {
        val s = raw.trim().removeSuffix(".git").removePrefix("git@github.com:")
        val m = RX.find(s) ?: return null
        return m.groupValues[1] to m.groupValues[2]
    }
}
