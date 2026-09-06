package com.zedge.contentstudio

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.ui.GitHubViewModel
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.components.ProgressCard
import com.zedge.contentstudio.ui.components.RequestDialog
import com.zedge.contentstudio.ui.screens.DistributeScreen
import com.zedge.contentstudio.ui.screens.GitHubScreen
import com.zedge.contentstudio.ui.screens.HomeScreen
import com.zedge.contentstudio.ui.screens.ItemDetailSheet
import com.zedge.contentstudio.ui.screens.PinManagerScreen
import com.zedge.contentstudio.ui.screens.ScheduleScreen
import com.zedge.contentstudio.ui.screens.UploadScreen
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.ContentStudioTheme
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

enum class Page(val title: String, val short: String) {
    HOME("Dashboard", "Home"), UPLOAD("Upload Center", "Upload"), SCHEDULE("Publishing Layout Planner", "Calendar"),
    PINS("Pin Manager", "Pins"), DISTRIBUTE("Multi-Account Distribution", "Distribute"), GITHUB("GitHub Control", "GitHub")
}

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()
    private val ghVm: GitHubViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, true)
        handleShare(intent)
        setContent { ContentStudioTheme { AppRoot(vm, ghVm) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
    }

    private fun handleShare(intent: Intent?) {
        if (intent == null) return
        val uris = ArrayList<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> (intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
        }
        if (uris.isNotEmpty()) vm.onSharedUris(uris)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot(vm: MainViewModel, ghVm: GitHubViewModel) {
    var page by rememberSaveable { mutableStateOf(Page.HOME) }
    val snack = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val activeKey by vm.activeKey.collectAsStateWithLifecycle()
    val connected by vm.connected.collectAsStateWithLifecycle()
    val dialog by vm.dialog.collectAsStateWithLifecycle()
    val ghDialog by ghVm.dialog.collectAsStateWithLifecycle()
    val progress by vm.progress.collectAsStateWithLifecycle()
    val selected by vm.selectedItem.collectAsStateWithLifecycle()
    val shared by vm.sharedUris.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { vm.messages.collectLatest { m -> snack.showSnackbar(m.text) } }
    LaunchedEffect(shared) { if (shared.isNotEmpty()) page = Page.UPLOAD }

    BackHandler(enabled = page != Page.HOME) { page = Page.HOME }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Content Studio", style = MaterialTheme.typography.titleLarge)
                        Text(page.title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = {
                    Box(Modifier.padding(start = 12.dp).size(38.dp).clip(CircleShape).background(BrandYellow), contentAlignment = Alignment.Center) {
                        Text("CS", color = BrandDark, fontWeight = FontWeight.ExtraBold)
                    }
                },
                actions = { AccountSwitcher(activeKey, connected) { vm.switchAccount(it) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                Page.entries.forEach { p ->
                    NavigationBarItem(
                        selected = page == p,
                        onClick = { page = p },
                        icon = {
                            Icon(
                                when (p) {
                                    Page.HOME -> Icons.Default.Dashboard; Page.UPLOAD -> Icons.Default.CloudUpload; Page.SCHEDULE -> Icons.Default.CalendarMonth
                                    Page.PINS -> Icons.Default.PushPin; Page.DISTRIBUTE -> Icons.Default.Hub; Page.GITHUB -> Icons.Default.Code
                                }, contentDescription = p.short
                            )
                        },
                        label = { Text(p.short) },
                    )
                }
            }
        },
        snackbarHost = { SnackbarHost(snack) },
        containerColor = MaterialTheme.colorScheme.background,
    ) { pad ->
        Box(Modifier.fillMaxSize().padding(pad)) {
            AnimatedContent(targetState = page, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "page") { p ->
                when (p) {
                    Page.HOME -> HomeScreen(vm, onOpenPage = { page = it })
                    Page.UPLOAD -> UploadScreen(vm)
                    Page.SCHEDULE -> ScheduleScreen(vm)
                    Page.PINS -> PinManagerScreen(vm)
                    Page.DISTRIBUTE -> DistributeScreen(vm)
                    Page.GITHUB -> GitHubScreen(ghVm)
                }
            }
            ProgressCard(progress, Modifier.align(Alignment.BottomCenter).padding(12.dp))
        }
    }

    RequestDialog(dialog)
    RequestDialog(ghDialog)
    selected?.let { item -> ItemDetailSheet(vm, item, onDismiss = { vm.selectedItem.value = null }) }
}

@Composable
fun AccountSwitcher(activeKey: String, connected: Boolean, onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box(Modifier.padding(end = 12.dp)) {
        Surface(shape = MaterialTheme.shapes.small, color = MaterialTheme.colorScheme.primaryContainer, modifier = Modifier.clickable { open = true }) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(if (connected) Ok else Warn))
                Spacer(Modifier.width(8.dp))
                Text(Accounts.byKey(activeKey).label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onPrimaryContainer)
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            Accounts.all.forEach { a ->
                DropdownMenuItem(
                    text = { Text(a.label + if (a.key == activeKey) "  ✓" else "") },
                    onClick = { open = false; onSelect(a.key) },
                )
            }
        }
    }
}

/** Horizontal chip selector reused by upload / distribute screens. */
@Composable
fun ChipRow(options: List<Pair<String, String>>, selected: String, onSelect: (String) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)) {
        options.forEach { (key, label) ->
            FilterChip(selected = selected == key, onClick = { onSelect(key) }, label = { Text(label) })
        }
    }
}
