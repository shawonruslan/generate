package com.zedge.contentstudio.core

import android.content.Context
import com.zedge.contentstudio.data.QueueItem
import com.zedge.contentstudio.desktop.DesktopNotifier
import com.zedge.contentstudio.desktop.NotificationCenter

/**
 * v23 metadata guard (desktop edition): watches the active account's queue and raises a Windows toast +
 * an in-app notification when NEW files without title/tags/category appear.
 */
object MetaNotifier {
    private const val PREFS = "meta_guard"

    fun ensureChannel(ctx: Context) { DesktopNotifier.ensureTray() }
    fun canPost(ctx: Context): Boolean = true

    /** @return the items that are newly missing metadata, empty when nothing new. */
    fun onQueue(ctx: Context, accountKey: String, queue: List<QueueItem>): List<QueueItem> {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val prefKey = "seen_$accountKey"
        val missing = queue.filter { it.isBlockedNoMeta }
        val ids = missing.map { it.id }.toSet()
        val seen = prefs.getStringSet(prefKey, null)
        prefs.edit().putStringSet(prefKey, ids).apply()
        if (seen == null) return emptyList()
        val fresh = missing.filter { it.id !in seen }
        if (fresh.isEmpty()) return emptyList()
        post(accountKey, fresh, missing.size)
        return fresh
    }

    private fun post(accountKey: String, fresh: List<QueueItem>, total: Int) {
        val label = Accounts.byKey(accountKey).label
        val names = fresh.map { it.title.ifBlank { it.name.ifBlank { it.id } } }
        val title = if (fresh.size == 1) "1 file without metadata - $label" else "${fresh.size} files without metadata - $label"
        val body = names.take(3).joinToString(", ") + (if (names.size > 3) " \u2026" else "") +
            "\nThe bot will skip these until title, tags and category are added ($total blocked in total)."
        NotificationCenter.push(title, body, "warn")
        DesktopNotifier.notify(title, body, warn = true)
    }
}
