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
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
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

enum class Page(val title: String, val short: String) {
    HOME("Dashboard", "Home"), UPLOAD("Upload", "Upload"), SCHEDULE("Planner", "Plan"),
    PINS("Pin Manager", "Pins"), DISTRIBUTE("Distribute", "Share"), GITHUB("GitHub", "GitHub")
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

    @Suppress("DEPRECATION")
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
                        Text(page.title, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("Content Studio", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = {
                    Box(Modifier.padding(start = 14.dp, end = 4.dp).size(32.dp).clip(CircleShape).background(BrandYellow), contentAlignment = Alignment.Center) {
                        Text("CS", color = BrandDark, fontWeight = FontWeight.ExtraBold, style = MaterialTheme.typography.labelMedium)
                    }
                },
                actions = { AccountSwitcher(activeKey, connected) { vm.switchAccount(it) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface, tonalElevation = 0.dp) {
                Page.entries.forEach { p ->
                    NavigationBarItem(
                        selected = page == p,
                        onClick = { page = p },
                        icon = {
                            Icon(
                                when (p) {
                                    Page.HOME -> Icons.Default.Dashboard; Page.UPLOAD -> Icons.Default.CloudUpload; Page.SCHEDULE -> Icons.Default.CalendarMonth
                                    Page.PINS -> Icons.Default.PushPin; Page.DISTRIBUTE -> Icons.Default.Hub; Page.GITHUB -> Icons.Default.Code
                                },
                                contentDescription = p.short,
                                modifier = Modifier.size(22.dp)
                            )
                        },
                        label = { Text(p.short, style = MaterialTheme.typography.labelSmall, maxLines = 1, softWrap = false) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = BrandDark,
                            selectedTextColor = MaterialTheme.colorScheme.primary,
                            indicatorColor = BrandYellow,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
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
        Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.clickable { open = true }) {
            Row(Modifier.padding(start = 10.dp, end = 12.dp, top = 7.dp, bottom = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(if (connected) Ok else Warn))
                Spacer(Modifier.width(7.dp))
                Text(Accounts.byKey(activeKey).label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurface)
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

/** Wrapping chip selector reused by upload / distribute / github screens. Chips flow to a new line instead of overflowing. */
@Composable
fun ChipRow(options: List<Pair<String, String>>, selected: String, onSelect: (String) -> Unit, modifier: Modifier = Modifier) {
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        options.forEach { (key, label) ->
            val on = selected == key
            FilterChip(
                selected = on,
                onClick = { onSelect(key) },
                label = { Text(label, style = MaterialTheme.typography.labelMedium, maxLines = 1) },
                shape = CircleShape,
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = BrandYellow,
                    selectedLabelColor = BrandDark,
                ),
            )
        }
    }
}

/** Small labelled section header used across screens. */
@Composable
fun SectionHeader(title: String, subtitle: String? = null, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(horizontal = 2.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        if (subtitle != null) {
            Spacer(Modifier.height(2.dp))
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
