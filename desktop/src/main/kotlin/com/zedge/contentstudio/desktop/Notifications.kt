package com.zedge.contentstudio.desktop

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.awt.SystemTray
import java.awt.TrayIcon
import java.util.concurrent.atomic.AtomicLong

data class Notice(val id: Long, val title: String, val body: String, val kind: String, val at: Long)

/** In-app notification center (bell in the top bar) - every toast / metadata alert lands here with a timestamp. */
object NotificationCenter {
    private val ids = AtomicLong(1)
    private val _items = MutableStateFlow<List<Notice>>(emptyList())
    val items: StateFlow<List<Notice>> = _items
    private val _unread = MutableStateFlow(0)
    val unread: StateFlow<Int> = _unread

    fun push(title: String, body: String = "", kind: String = "info") {
        _items.value = (listOf(Notice(ids.getAndIncrement(), title, body, kind, System.currentTimeMillis())) + _items.value).take(200)
        _unread.value = _unread.value + 1
    }
    fun markRead() { _unread.value = 0 }
    fun clear() { _items.value = emptyList(); _unread.value = 0 }
    fun remove(id: Long) { _items.value = _items.value.filterNot { it.id == id } }
}

/** Windows toast notifications through the system tray icon. */
object DesktopNotifier {
    private var tray: TrayIcon? = null

    fun ensureTray() {
        if (tray != null || !SystemTray.isSupported()) return
        runCatching {
            val icon = TrayIcon(AppIcon.image.getScaledInstance(16, 16, java.awt.Image.SCALE_SMOOTH), "Meta Hawladar")
            icon.isImageAutoSize = true
            SystemTray.getSystemTray().add(icon)
            tray = icon
        }
    }

    fun notify(title: String, body: String, warn: Boolean = false) {
        ensureTray()
        runCatching { tray?.displayMessage(title, body, if (warn) TrayIcon.MessageType.WARNING else TrayIcon.MessageType.INFO) }
    }
}
