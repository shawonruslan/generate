package com.zedge.contentstudio

import androidx.compose.ui.graphics.toArgb
import com.zedge.contentstudio.ui.theme.ThemeState
import com.zedge.contentstudio.ui.components.MhLogoMark
import com.zedge.contentstudio.ui.screens.ThemeStudioScreen

import android.net.Uri
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPlacement
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zedge.contentstudio.core.Accounts
import com.zedge.contentstudio.core.MetaNotifier
import com.zedge.contentstudio.desktop.AppIcon
import com.zedge.contentstudio.desktop.DesktopNotifier
import com.zedge.contentstudio.desktop.NotificationCenter
import com.zedge.contentstudio.desktop.fileDropTarget
import com.zedge.contentstudio.ui.GitHubViewModel
import com.zedge.contentstudio.ui.MainViewModel
import com.zedge.contentstudio.ui.components.AuroraBackground
import com.zedge.contentstudio.ui.components.DhakaClock
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
import com.zedge.contentstudio.ui.screens.ThemeSheet
import com.zedge.contentstudio.ui.screens.UploadScreen
import com.zedge.contentstudio.ui.screens.VpnScreen
import com.zedge.contentstudio.ui.theme.BrandAmber
import com.zedge.contentstudio.ui.theme.BrandDark
import com.zedge.contentstudio.ui.theme.BrandHeader
import com.zedge.contentstudio.ui.theme.BrandHeaderEnd
import com.zedge.contentstudio.ui.theme.BrandNavActive
import com.zedge.contentstudio.ui.theme.BrandOnHeader
import com.zedge.contentstudio.ui.theme.BrandOnNavActive
import com.zedge.contentstudio.ui.theme.BrandYellow
import com.zedge.contentstudio.ui.theme.ContentStudioTheme
import com.zedge.contentstudio.ui.theme.Ok
import com.zedge.contentstudio.ui.theme.Warn
import java.awt.Dimension
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.swing.UIManager
import kotlinx.coroutines.flow.collectLatest

enum class Page(val title: String, val short: String) {
    HOME("Dashboard", "Home"), UPLOAD("Upload", "Upload"), SCHEDULE("Planner", "Plan"),
    PINS("Pin Manager", "Pins"), DISTRIBUTE("Distribute", "Share"), GITHUB("GitHub", "GitHub"), VPN("VPN", "VPN"),
    THEME("Theme Studio", "Theme")   // v30: full page (Ctrl+8 / Ctrl+T), no modal
}

// ---------------------------------------------------------------------------------------------
// Windows desktop entry point (Compose for Desktop). Reuses every screen / repository / model of
// the Android app; only the shell (window, side rail, top bar, notification center) is desktop-specific.
// ---------------------------------------------------------------------------------------------

/** Global navigation state so keyboard shortcuts (Ctrl+1..8, Ctrl+T, Ctrl+N, Ctrl+B) can drive it. */
object DesktopNav {
    var page by mutableStateOf(Page.HOME)
    var showTheme by mutableStateOf(false)
    var showNotifications by mutableStateOf(false)
    var railCollapsed by mutableStateOf(false)
}

fun main() {
    System.setProperty("sun.java2d.uiScale.enabled", "true")
    runCatching { UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName()) }
    val app = ContentStudioApp()
    app.onCreate()
    val vm = MainViewModel(app)
    val ghVm = GitHubViewModel(app)
    DesktopNotifier.ensureTray()

    application {
        val windowState = rememberWindowState(placement = WindowPlacement.Floating, position = WindowPosition(Alignment.Center), size = DpSize(1480.dp, 940.dp))
        Window(
            onCloseRequest = ::exitApplication,
            title = "Meta Hawladar",
            state = windowState,
            icon = remember(ThemeState.palette) { BitmapPainter(AppIcon.themedBitmap(ThemeState.palette.primary.toArgb(), ThemeState.palette.text.toArgb(), ThemeState.palette.surface.toArgb())) },   // v30: live theme-tinted icon
            onPreviewKeyEvent = { e -> handleShortcut(e) },
        ) {
            LaunchedEffect(Unit) { window.minimumSize = Dimension(1080, 680) }
            val themeKey by vm.activeKey.collectAsStateWithLifecycle()
            val themes by vm.theme.collectAsStateWithLifecycle()
            val themePreview by vm.themePreview.collectAsStateWithLifecycle()
            ContentStudioTheme(themePreview ?: themes[themeKey]) { DesktopRoot(vm, ghVm) }
        }
    }
}

private fun handleShortcut(e: KeyEvent): Boolean {
    if (e.type != KeyEventType.KeyDown || !e.isCtrlPressed) return false
    val pages = Page.entries
    val idx = when (e.key) {
        Key.One -> 0; Key.Two -> 1; Key.Three -> 2; Key.Four -> 3; Key.Five -> 4; Key.Six -> 5; Key.Seven -> 6; Key.Eight -> 7; Key.Nine -> 8
        else -> -1
    }
    if (idx >= 0) { if (idx < pages.size) DesktopNav.page = pages[idx]; return true }
    return when (e.key) {
        Key.T -> { DesktopNav.page = Page.THEME; true }
        Key.N -> { DesktopNav.showNotifications = !DesktopNav.showNotifications; if (DesktopNav.showNotifications) NotificationCenter.markRead(); true }
        Key.B -> { DesktopNav.railCollapsed = !DesktopNav.railCollapsed; true }
        else -> false
    }
}

private fun pageIcon(p: Page): ImageVector = when (p) {
    Page.HOME -> Icons.Default.Dashboard
    Page.UPLOAD -> Icons.Default.CloudUpload
    Page.SCHEDULE -> Icons.Default.EditCalendar
    Page.PINS -> Icons.Default.PushPin
    Page.DISTRIBUTE -> Icons.Default.Hub
    Page.GITHUB -> Icons.Default.Code
    Page.VPN -> Icons.Default.VpnKey
    Page.THEME -> Icons.Default.Palette
}

@Composable
fun DesktopRoot(vm: MainViewModel, ghVm: GitHubViewModel) {
    val snack = remember { SnackbarHostState() }
    val activeKey by vm.activeKey.collectAsStateWithLifecycle()
    val connected by vm.connected.collectAsStateWithLifecycle()
    val dialog by vm.dialog.collectAsStateWithLifecycle()
    val importPreview by vm.importPreview.collectAsStateWithLifecycle()
    val ghDialog by ghVm.dialog.collectAsStateWithLifecycle()
    val progress by vm.progress.collectAsStateWithLifecycle()
    val selected by vm.selectedItem.collectAsStateWithLifecycle()
    val shared by vm.sharedUris.collectAsStateWithLifecycle()
    val page = DesktopNav.page

    LaunchedEffect(Unit) {
        vm.messages.collectLatest { m ->
            NotificationCenter.push(m.text, "", m.kind)
            snack.showSnackbar(m.text)
        }
    }
    LaunchedEffect(shared) { if (shared.isNotEmpty()) DesktopNav.page = Page.UPLOAD }

    AuroraBackground {
        Row(Modifier.fillMaxSize().fileDropTarget { files -> vm.sharedUris.value = files.map { Uri.fromFile(it) } }) {
            SideRail(page = page, activeKey = activeKey, connected = connected, onSelect = { DesktopNav.page = it }, onAccount = { vm.switchAccount(it) })
            Column(Modifier.weight(1f).fillMaxHeight()) {
                DesktopTopBar(page = page, activeKey = activeKey, connected = connected, onAccount = { vm.switchAccount(it) })
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    AnimatedContent(
                        targetState = page,
                        transitionSpec = {
                            val forward = targetState.ordinal >= initialState.ordinal
                            (slideInHorizontally(tween(260)) { if (forward) it / 8 else -it / 8 } + fadeIn(tween(260)) + scaleIn(tween(260), initialScale = 0.98f)) togetherWith
                                (slideOutHorizontally(tween(200)) { if (forward) -it / 8 else it / 8 } + fadeOut(tween(200)))
                        },
                        label = "page",
                    ) { p ->
                        Box(Modifier.fillMaxSize().padding(horizontal = 22.dp, vertical = 4.dp), contentAlignment = Alignment.TopCenter) {
                            Box(Modifier.fillMaxHeight().widthIn(max = 1240.dp)) {
                                when (p) {
                                    Page.HOME -> HomeScreen(vm, onOpenPage = { DesktopNav.page = it })
                                    Page.UPLOAD -> UploadScreen(vm)
                                    Page.SCHEDULE -> ScheduleScreen(vm)
                                    Page.PINS -> PinManagerScreen(vm)
                                    Page.DISTRIBUTE -> DistributeScreen(vm)
                                    Page.GITHUB -> GitHubScreen(ghVm)
                                    Page.VPN -> VpnScreen(ghVm, activeKey)
                                    Page.THEME -> ThemeStudioScreen(vm, activeKey) { DesktopNav.page = Page.HOME }
                                }
                            }
                        }
                    }
                    ProgressCard(progress, Modifier.align(Alignment.BottomEnd).padding(18.dp).widthIn(max = 460.dp))
                    SnackbarHost(snack, Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp).widthIn(max = 640.dp))
                    if (DesktopNav.showNotifications) {
                        NotificationPanel(Modifier.align(Alignment.TopEnd).padding(top = 6.dp, end = 18.dp)) { DesktopNav.showNotifications = false }
                    }
                }
            }
        }
    }

    RequestDialog(dialog)
    importPreview?.let { ImportPreviewSheet(it) }
    RequestDialog(ghDialog)
    selected?.let { item -> ItemDetailSheet(vm, item, onDismiss = { vm.selectedItem.value = null }) }
}

/** Collapsible glass side rail: brand, pages, accounts, theme / notifications / clock. */
@Composable
private fun SideRail(page: Page, activeKey: String, connected: Boolean, onSelect: (Page) -> Unit, onAccount: (String) -> Unit) {
    val collapsed = DesktopNav.railCollapsed
    val width by animateDpAsState(if (collapsed) 84.dp else 252.dp, tween(240), label = "rail")
    val unread by NotificationCenter.unread.collectAsStateWithLifecycle()
    val cs = MaterialTheme.colorScheme
    Column(
        Modifier.width(width).fillMaxHeight()
            .background(cs.surface.copy(alpha = 0.62f))
            .drawWithContent { drawContent(); drawRect(cs.outline.copy(alpha = 0.35f), topLeft = Offset(size.width - 1f, 0f), size = Size(1f, size.height)) }
            .padding(horizontal = 14.dp, vertical = 16.dp),
    ) {
        // Brand
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().height(44.dp)) {
            MhLogoMark(Modifier.size(40.dp), corner = 13.dp)   // v30: user logo, tinted by the live theme
            if (!collapsed) {
                Spacer(Modifier.width(12.dp))
                Column {
                    Text("Meta Hawladar", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("Windows · Glass · v30", style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant)
                }
            }
        }
        Spacer(Modifier.height(22.dp))
        if (!collapsed) Text("WORKSPACE", style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant, letterSpacing = 1.4.sp, modifier = Modifier.padding(start = 6.dp, bottom = 8.dp))
        Page.entries.forEachIndexed { i, p ->
            RailItem(icon = pageIcon(p), label = p.title, hint = "Ctrl+${i + 1}", selected = p == page, collapsed = collapsed) { onSelect(p) }
            Spacer(Modifier.height(4.dp))
        }
        Spacer(Modifier.height(18.dp))
        if (!collapsed) Text("ACCOUNTS", style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant, letterSpacing = 1.4.sp, modifier = Modifier.padding(start = 6.dp, bottom = 8.dp))
        Accounts.all.forEach { a ->
            val on = a.key == activeKey
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                    .background(if (on) cs.surfaceContainerHigh else Color.Transparent)
                    .clickable { onAccount(a.key) }
                    .padding(horizontal = 10.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(24.dp).clip(CircleShape).background(if (on) Brush.linearGradient(listOf(BrandNavActive, BrandNavActive.copy(alpha = 0.7f))) else SolidColor(cs.surfaceContainerHighest)), contentAlignment = Alignment.Center) {
                    Text(a.label.filter { it.isDigit() }.ifBlank { a.label.take(1) }, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = if (on) BrandOnNavActive else cs.onSurface)
                }
                if (!collapsed) {
                    Spacer(Modifier.width(10.dp))
                    Text(a.label, style = MaterialTheme.typography.labelLarge, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (on) Box(Modifier.size(8.dp).clip(CircleShape).background(if (connected) Ok else Warn))
                }
            }
            Spacer(Modifier.height(2.dp))
        }
        Spacer(Modifier.weight(1f))
        Spacer(Modifier.height(4.dp))
        RailItem(icon = Icons.Default.Notifications, label = "Notifications", hint = "Ctrl+N", selected = DesktopNav.showNotifications, collapsed = collapsed, badge = unread) {
            DesktopNav.showNotifications = !DesktopNav.showNotifications; if (DesktopNav.showNotifications) NotificationCenter.markRead()
        }
        Spacer(Modifier.height(10.dp))
        HorizontalDivider(color = cs.outline.copy(alpha = 0.3f))
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            if (!collapsed) {
                Column(Modifier.weight(1f)) {
                    DhakaClock(color = cs.onSurface, style = MaterialTheme.typography.titleMedium)
                    Text("Dhaka time", style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant)
                }
            }
            FilledTonalIconButton(onClick = { DesktopNav.railCollapsed = !collapsed }, modifier = Modifier.size(36.dp)) {
                Icon(if (collapsed) Icons.Default.ChevronRight else Icons.Default.ChevronLeft, contentDescription = "Toggle sidebar (Ctrl+B)")
            }
        }
    }
}

@Composable
private fun RailItem(icon: ImageVector, label: String, hint: String, selected: Boolean, collapsed: Boolean, badge: Int = 0, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val bg by animateColorAsState(if (selected) BrandNavActive else Color.Transparent, tween(200), label = "bg")
    val fg = if (selected) BrandOnNavActive else cs.onSurface
    Row(
        Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(13.dp)).background(bg).clickable(onClick = onClick).padding(horizontal = if (collapsed) 0.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (collapsed) Arrangement.Center else Arrangement.Start,
    ) {
        Box {
            Icon(icon, contentDescription = label, tint = fg, modifier = Modifier.size(22.dp))
            if (badge > 0) Box(Modifier.align(Alignment.TopEnd).offset(x = 6.dp, y = (-5).dp).size(16.dp).clip(CircleShape).background(Warn), contentAlignment = Alignment.Center) {
                Text(if (badge > 9) "9+" else badge.toString(), fontSize = 9.sp, lineHeight = 10.sp, fontWeight = FontWeight.Bold, color = Color.Black)
            }
        }
        if (!collapsed) {
            Spacer(Modifier.width(12.dp))
            Text(label, style = MaterialTheme.typography.labelLarge, fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium, color = fg, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(hint, style = MaterialTheme.typography.labelSmall, color = fg.copy(alpha = 0.55f))
        }
    }
}

/** Top bar: page title, live status, account switcher, theme + notification buttons. */
@Composable
private fun DesktopTopBar(page: Page, activeKey: String, connected: Boolean, onAccount: (String) -> Unit) {
    val cs = MaterialTheme.colorScheme
    val unread by NotificationCenter.unread.collectAsStateWithLifecycle()
    Row(Modifier.fillMaxWidth().height(68.dp).padding(horizontal = 22.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(page.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${Accounts.byKey(activeKey).label} · Meta Hawladar for Windows", style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant)
        }
        Surface(shape = CircleShape, color = (if (connected) Ok else Warn).copy(alpha = 0.14f)) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(if (connected) Ok else Warn))
                Spacer(Modifier.width(7.dp))
                Text(if (connected) "LIVE SYNC" else "OFFLINE", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, color = if (connected) Ok else Warn)
            }
        }
        Spacer(Modifier.width(10.dp))
        AccountSwitcher(activeKey, connected, onAccount)
        IconButton(onClick = { DesktopNav.page = Page.THEME }) { Icon(Icons.Default.Palette, contentDescription = "Theme Studio", tint = cs.onSurface) }
        Box {
            IconButton(onClick = { DesktopNav.showNotifications = !DesktopNav.showNotifications; if (DesktopNav.showNotifications) NotificationCenter.markRead() }) {
                Icon(Icons.Default.Notifications, contentDescription = "Notifications", tint = cs.onSurface)
            }
            if (unread > 0) Box(Modifier.align(Alignment.TopEnd).padding(top = 6.dp, end = 6.dp).size(16.dp).clip(CircleShape).background(Warn), contentAlignment = Alignment.Center) {
                Text(if (unread > 9) "9+" else unread.toString(), fontSize = 9.sp, lineHeight = 10.sp, fontWeight = FontWeight.Bold, color = Color.Black)
            }
        }
    }
}

/** Notification center popover (top-right). */
@Composable
private fun NotificationPanel(modifier: Modifier, onClose: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val items by NotificationCenter.items.collectAsStateWithLifecycle()
    val fmt = remember { DateTimeFormatter.ofPattern("dd MMM, hh:mm a") }
    Surface(modifier.width(400.dp).heightIn(max = 560.dp), shape = RoundedCornerShape(20.dp), color = cs.surface.copy(alpha = 0.96f), tonalElevation = 6.dp, shadowElevation = 18.dp, border = BorderStroke(1.dp, cs.outline.copy(alpha = 0.35f))) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Notifications, null, tint = cs.primary)
                Spacer(Modifier.width(8.dp))
                Text("Notifications", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                TextButton(onClick = { NotificationCenter.clear() }, enabled = items.isNotEmpty()) { Text("Clear all") }
                IconButton(onClick = onClose, modifier = Modifier.size(32.dp)) { Icon(Icons.Default.Close, null, Modifier.size(18.dp)) }
            }
            Spacer(Modifier.height(8.dp))
            if (items.isEmpty()) {
                Box(Modifier.fillMaxWidth().padding(vertical = 34.dp), contentAlignment = Alignment.Center) {
                    Text("You're all caught up", style = MaterialTheme.typography.bodyMedium, color = cs.onSurfaceVariant)
                }
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(items, key = { it.id }) { n ->
                        val accent = when (n.kind) { "ok" -> Ok; "warn" -> Warn; "err" -> cs.error; else -> cs.primary }
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(cs.surfaceContainerHigh).padding(12.dp)) {
                            Box(Modifier.width(4.dp).height(40.dp).clip(CircleShape).background(accent))
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(n.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 3, overflow = TextOverflow.Ellipsis)
                                if (n.body.isNotBlank()) Text(n.body, style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant, maxLines = 4, overflow = TextOverflow.Ellipsis)
                                Text(fmt.format(Instant.ofEpochMilli(n.at).atZone(ZoneId.systemDefault())), style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant)
                            }
                            IconButton(onClick = { NotificationCenter.remove(n.id) }, modifier = Modifier.size(28.dp)) { Icon(Icons.Default.Close, null, Modifier.size(14.dp), tint = cs.onSurfaceVariant) }
                        }
                    }
                }
            }
        }
    }
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

