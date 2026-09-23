package com.zedge.contentstudio

import com.zedge.contentstudio.ui.theme.BrandAmber
import com.zedge.contentstudio.ui.components.AuroraBackground
import com.zedge.contentstudio.ui.components.BrandLogo
import androidx.compose.animation.scaleIn
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import com.zedge.contentstudio.core.MetaNotifier
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.core.tween
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
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import com.zedge.contentstudio.ui.components.FloatingNavBar
import com.zedge.contentstudio.ui.components.ProgressCard
import com.zedge.contentstudio.ui.components.RequestDialog
import com.zedge.contentstudio.ui.screens.DistributeScreen
import com.zedge.contentstudio.ui.screens.GitHubScreen
import com.zedge.contentstudio.ui.screens.HomeScreen
import com.zedge.contentstudio.ui.screens.ImportPreviewSheet
import com.zedge.contentstudio.ui.screens.ItemDetailSheet
import com.zedge.contentstudio.ui.screens.PinManagerScreen
import com.zedge.contentstudio.ui.screens.ScheduleScreen
import com.zedge.contentstudio.ui.screens.UploadScreen
import com.zedge.contentstudio.ui.screens.VpnScreen
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.ContentStudioTheme
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn
import kotlinx.coroutines.flow.collectLatest
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material3.IconButton
import com.zedge.contentstudio.ui.screens.ThemeSheet
import com.zedge.contentstudio.ui.theme.BrandHeader
import com.zedge.contentstudio.ui.theme.BrandHeaderEnd
import com.zedge.contentstudio.ui.theme.BrandOnHeader
import com.zedge.contentstudio.ui.theme.BrandNavActive
import com.zedge.contentstudio.ui.theme.BrandOnNavActive

enum class Page(val title: String, val short: String) {
    HOME("Dashboard", "Home"), UPLOAD("Upload", "Upload"), SCHEDULE("Planner", "Plan"),
    PINS("Pin Manager", "Pins"), DISTRIBUTE("Distribute", "Share"), GITHUB("GitHub", "GitHub"), VPN("VPN", "VPN")
}

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()
    private val ghVm: GitHubViewModel by viewModels()

    // v23: runtime permission for metadata-guard notifications (Android 13+)
    private val notifPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, true)
        handleShare(intent)
        if (android.os.Build.VERSION.SDK_INT >= 33 && !MetaNotifier.canPost(this)) {
            notifPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
        setContent {
            // v26: theme follows the active account (Firebase dashboardSettings/theme) + live preview from Theme Studio
            val themeKey by vm.activeKey.collectAsStateWithLifecycle()
            val themes by vm.theme.collectAsStateWithLifecycle()
            val themePreview by vm.themePreview.collectAsStateWithLifecycle()
            ContentStudioTheme(themePreview ?: themes[themeKey]) { AppRoot(vm, ghVm) }
        }
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
    var showTheme by rememberSaveable { mutableStateOf(false) }
    val snack = remember { SnackbarHostState() }
    val activeKey by vm.activeKey.collectAsStateWithLifecycle()
    val connected by vm.connected.collectAsStateWithLifecycle()
    val dialog by vm.dialog.collectAsStateWithLifecycle()
    val importPreview by vm.importPreview.collectAsStateWithLifecycle()
    val ghDialog by ghVm.dialog.collectAsStateWithLifecycle()
    val progress by vm.progress.collectAsStateWithLifecycle()
    val selected by vm.selectedItem.collectAsStateWithLifecycle()
    val shared by vm.sharedUris.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { vm.messages.collectLatest { m -> snack.showSnackbar(m.text) } }
    LaunchedEffect(shared) { if (shared.isNotEmpty()) page = Page.UPLOAD }

    BackHandler(enabled = page != Page.HOME) { page = Page.HOME }
    if (showTheme) ThemeSheet(vm, activeKey) { showTheme = false }

    // v27 Glass UI: animated aurora backdrop behind the whole app
    AuroraBackground {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(page.title, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("Meta Hawladar · Glass", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = {
                    // v27.10 brand logo - re-colours live with the Theme Studio (surface / text / primary)
                    BrandLogo(size = 34.dp, modifier = Modifier.padding(start = 14.dp, end = 4.dp))
                },
                actions = {
                    IconButton(onClick = { showTheme = true }) { Icon(Icons.Default.Palette, contentDescription = "Theme Studio", tint = MaterialTheme.colorScheme.onSurface) }
                    AccountSwitcher(activeKey, connected) { vm.switchAccount(it) }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
            )
        },
        bottomBar = { FloatingNavBar(current = page, onSelect = { page = it }) },
        snackbarHost = { SnackbarHost(snack) },
        containerColor = Color.Transparent,
    ) { pad ->
        Box(Modifier.fillMaxSize().padding(pad)) {
            AnimatedContent(
                targetState = page,
                transitionSpec = {
                    val forward = targetState.ordinal >= initialState.ordinal
                    (slideInHorizontally(tween(260)) { if (forward) it / 5 else -it / 5 } + fadeIn(tween(260)) + scaleIn(tween(260), initialScale = 0.96f)) togetherWith
                        (slideOutHorizontally(tween(200)) { if (forward) -it / 5 else it / 5 } + fadeOut(tween(200)))
                },
                label = "page",
            ) { p ->
                when (p) {
                    Page.HOME -> HomeScreen(vm, onOpenPage = { page = it })
                    Page.UPLOAD -> UploadScreen(vm)
                    Page.SCHEDULE -> ScheduleScreen(vm)
                    Page.PINS -> PinManagerScreen(vm)
                    Page.DISTRIBUTE -> DistributeScreen(vm)
                    Page.GITHUB -> GitHubScreen(ghVm)
                    Page.VPN -> VpnScreen(ghVm, activeKey)
                }
            }
            ProgressCard(progress, Modifier.align(Alignment.BottomCenter).padding(12.dp))
        }
    }
    }

    RequestDialog(dialog)
    importPreview?.let { ImportPreviewSheet(it) }
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
                    text = { Text(a.label, fontWeight = if (a.key == activeKey) FontWeight.Bold else FontWeight.Normal) },
                    trailingIcon = { if (a.key == activeKey) Icon(Icons.Default.Check, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary) },
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
                    selectedContainerColor = BrandNavActive,
                    selectedLabelColor = BrandOnNavActive,
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
