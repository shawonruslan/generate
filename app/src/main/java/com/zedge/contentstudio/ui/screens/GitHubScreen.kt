package com.zedge.contentstudio.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.InsertDriveFile
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.ChipRow
import com.zedge.contentstudio.core.Fmt
import com.zedge.contentstudio.data.GitHubRepo
import com.zedge.contentstudio.ui.GitHubViewModel
import com.zedge.contentstudio.ui.components.EmptyState
import com.zedge.contentstudio.ui.components.SectionCard
import com.zedge.contentstudio.ui.components.StatusPill
import com.zedge.contentstudio.ui.theme.Danger
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn

@Composable
fun GitHubScreen(vm: GitHubViewModel) {
    val ctx = LocalContext.current
    val cfg by vm.config.collectAsStateWithLifecycle()
    val connStatus by vm.connectionStatus.collectAsStateWithLifecycle()
    val sessionRaw by vm.sessionRaw.collectAsStateWithLifecycle()
    val sessionStatus by vm.sessionStatus.collectAsStateWithLifecycle()
    val runs by vm.runs.collectAsStateWithLifecycle()
    val runsLoading by vm.runsLoading.collectAsStateWithLifecycle()
    val path by vm.path.collectAsStateWithLifecycle()
    val entries by vm.entries.collectAsStateWithLifecycle()
    val filesLoading by vm.filesLoading.collectAsStateWithLifecycle()
    val log by vm.log.collectAsStateWithLifecycle()
    val triggering by vm.triggering.collectAsStateWithLifecycle()

    var owner by remember { mutableStateOf(cfg.owner) }
    var repo by remember { mutableStateOf(cfg.repo) }
    var branch by remember { mutableStateOf(cfg.branch) }
    var token by remember { mutableStateOf(cfg.token) }
    LaunchedEffect(cfg) { owner = cfg.owner; repo = cfg.repo; branch = cfg.branch; token = cfg.token }
    var sessionText by remember { mutableStateOf("") }
    LaunchedEffect(sessionRaw) { sessionText = if (sessionRaw.length > 4000) sessionRaw.take(4000) + "…" else sessionRaw }

    val rgCount by vm.rgCount.collectAsStateWithLifecycle(); val rgLength by vm.rgLength.collectAsStateWithLifecycle()
    val rgAuto by vm.rgAutoProcess.collectAsStateWithLifecycle(); val rgVolume by vm.rgVolume.collectAsStateWithLifecycle()
    val rgSilence by vm.rgSilence.collectAsStateWithLifecycle(); val rgPad by vm.rgPad.collectAsStateWithLifecycle()
    val rgTarget by vm.rgTarget.collectAsStateWithLifecycle(); val rgAttach by vm.rgAttachSession.collectAsStateWithLifecycle()
    val mdPath by vm.mdQueuePath.collectAsStateWithLifecycle(); val mdAttach by vm.mdAttachSession.collectAsStateWithLifecycle()

    val pickSession = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { u -> if (u != null) vm.loadSessionFromFile(u) }
    val pickPush = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { us -> if (us.isNotEmpty()) vm.pushFiles(us) }
    fun openUrl(u: String) { runCatching { CustomTabsIntent.Builder().build().launchUrl(ctx, Uri.parse(u)) } }

    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // Connection
        item {
            SectionCard("Connection", "Settings sync to the database so every device shares them", trailing = { StatusPill(if (cfg.ready) "READY" else "INCOMPLETE", if (cfg.ready) Ok else Warn) }) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(owner, { owner = it }, Modifier.weight(1f), label = { Text("Owner") }, singleLine = true)
                    OutlinedTextField(repo, { repo = it }, Modifier.weight(1f), label = { Text("Repo") }, singleLine = true)
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(branch, { branch = it }, Modifier.weight(0.6f), label = { Text("Branch") }, singleLine = true, placeholder = { Text("main") })
                    OutlinedTextField(token, { token = it }, Modifier.weight(1.4f), label = { Text("Token (repo + workflow scope)") }, singleLine = true, visualTransformation = PasswordVisualTransformation())
                }
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { vm.saveConfig(owner, repo, branch, token) }) { Text("Save") }
                    OutlinedButton(onClick = { vm.testConnection() }, enabled = cfg.ready) { Text("Test") }
                }
                Spacer(Modifier.height(6.dp))
                Text(connStatus, style = MaterialTheme.typography.bodySmall, color = if (connStatus.startsWith("Connected")) Ok else if (connStatus.startsWith("Failed")) Danger else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        // Gemini session
        item {
            SectionCard("Gemini session", "Cookie export JSON used by the generator workflows") {
                OutlinedTextField(sessionText, { sessionText = it }, Modifier.fillMaxWidth().height(120.dp), label = { Text("Session JSON") }, textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace))
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { vm.saveSession(if (sessionText.endsWith("…")) sessionRaw else sessionText) }) { Text("Save") }
                    OutlinedButton(onClick = { pickSession.launch(arrayOf("application/json", "text/plain", "*/*")) }) { Text("Load file") }
                    TextButton(onClick = { sessionText = ""; vm.saveSession("") }) { Text("Clear") }
                }
                Spacer(Modifier.height(6.dp))
                Text(sessionStatus, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        // Ringtone generator
        item {
            SectionCard("Ringtone Generator", GitHubRepo.GENERATOR_WORKFLOW) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(rgCount, { vm.rgCount.value = it }, Modifier.weight(1f), label = { Text("Count") }, singleLine = true)
                    OutlinedTextField(rgLength, { vm.rgLength.value = it }, Modifier.weight(1f), label = { Text("Length (s)") }, singleLine = true)
                    OutlinedTextField(rgVolume, { vm.rgVolume.value = it }, Modifier.weight(1f), label = { Text("Volume %") }, singleLine = true)
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(rgSilence, { vm.rgSilence.value = it }, Modifier.weight(1f), label = { Text("Silence thr.") }, singleLine = true)
                    OutlinedTextField(rgPad, { vm.rgPad.value = it }, Modifier.weight(1f), label = { Text("Pad (ms)") }, singleLine = true)
                }
                Spacer(Modifier.height(8.dp))
                Text("Auto process", style = MaterialTheme.typography.labelLarge)
                ChipRow(listOf("true" to "Yes", "false" to "No"), rgAuto, { vm.rgAutoProcess.value = it })
                Spacer(Modifier.height(8.dp))
                Text("Target account", style = MaterialTheme.typography.labelLarge)
                ChipRow(GitHubRepo.TARGET_ACCOUNTS.map { it to it.uppercase().replace("_", " ") }, rgTarget, { vm.rgTarget.value = it })
                Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(rgAttach, { vm.rgAttachSession.value = it }); Text("Attach saved Gemini session") }
                Button(onClick = { vm.triggerRingtone() }, enabled = triggering == null && cfg.ready) { Text(if (triggering == "Ringtone Generator") "Triggering…" else "Run Ringtone Generator") }
            }
        }
        // Metadata generator
        item {
            SectionCard("Metadata Generator", "mode = metadata") {
                OutlinedTextField(mdPath, { vm.mdQueuePath.value = it }, Modifier.fillMaxWidth(), label = { Text("Image queue path") }, singleLine = true)
                Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(mdAttach, { vm.mdAttachSession.value = it }); Text("Attach saved Gemini session") }
                Button(onClick = { vm.triggerMetadata() }, enabled = triggering == null && cfg.ready) { Text(if (triggering == "Metadata Generator") "Triggering…" else "Run Metadata Generator") }
            }
        }
        // Runs
        item {
            SectionCard("Workflow runs", "Latest 20", trailing = {
                Row {
                    TextButton(onClick = { vm.loadRuns() }, enabled = cfg.ready) { Text("Refresh") }
                    TextButton(onClick = { vm.cleanRuns() }, enabled = cfg.ready && !runsLoading) { Text("Clean", color = Danger) }
                }
            }) {
                if (runsLoading) Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)); Text("Working…") }
                if (runs.isEmpty() && !runsLoading) EmptyState(if (cfg.ready) "No runs yet." else "Save a connection to load runs.")
                runs.forEach { r ->
                    val color = when { r.status != "completed" -> Warn; r.conclusion == "success" -> Ok; r.conclusion == "cancelled" || r.conclusion == "skipped" -> MaterialTheme.colorScheme.onSurfaceVariant; else -> Danger }
                    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(10.dp).clip(CircleShape).background(color))
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text("#${r.runNumber} · ${r.name}", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("${r.status}${if (!r.conclusion.isNullOrBlank()) " · ${r.conclusion}" else ""} · ${r.event} · ${r.branch} · ${r.createdAt.replace('T', ' ').removeSuffix("Z")}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        IconButton(onClick = { openUrl(r.htmlUrl) }) { Icon(Icons.Default.OpenInNew, "Open") }
                        IconButton(onClick = { vm.deleteRun(r) }) { Icon(Icons.Default.Delete, "Delete", tint = Danger) }
                    }
                }
            }
        }
        // Repo browser
        item {
            SectionCard("Repository files", "/${path}", trailing = {
                Row {
                    TextButton(onClick = { vm.goUp() }, enabled = path.isNotBlank()) { Text("Up") }
                    TextButton(onClick = { vm.listPath(path) }, enabled = cfg.ready) { Text("Refresh") }
                }
            }) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { pickPush.launch(arrayOf("*/*")) }, enabled = cfg.ready) { Text("Push files here") }
                }
                Spacer(Modifier.height(8.dp))
                if (filesLoading) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                if (entries.isEmpty() && !filesLoading) EmptyState(if (cfg.ready) "Empty folder." else "Save a connection to browse.")
                entries.forEach { e ->
                    Row(Modifier.fillMaxWidth().clickable(enabled = e.type == "dir") { vm.listPath(e.path) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (e.type == "dir") Icons.Default.Folder else Icons.Default.InsertDriveFile, null, tint = if (e.type == "dir") MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(e.name, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (e.type != "dir") Text(Fmt.bytes(e.size), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (e.htmlUrl.isNotBlank()) IconButton(onClick = { openUrl(e.htmlUrl) }) { Icon(Icons.Default.OpenInNew, "Open") }
                        if (e.type != "dir") IconButton(onClick = { vm.deleteFile(e) }) { Icon(Icons.Default.Delete, "Delete", tint = Danger) }
                    }
                }
            }
        }
        // Log
        item {
            SectionCard("Activity log", trailing = { TextButton(onClick = { vm.clearLog() }) { Text("Clear") } }) {
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Color(0xFF1B1B1B)).padding(10.dp)) {
                    if (log.isEmpty()) Text("No activity yet.", color = Color(0xFF9E9E9E), fontFamily = FontFamily.Monospace, fontSize = 11.sp)
                    log.take(60).forEach { l ->
                        Text("[${l.time}] ${l.text}", color = when (l.kind) { "ok" -> Color(0xFF7ED957); "err" -> Color(0xFFFF7B72); else -> Color(0xFFE6E6E6) }, fontFamily = FontFamily.Monospace, fontSize = 11.sp)
                    }
                }
            }
        }
        item { Spacer(Modifier.height(72.dp)) }
    }
}
