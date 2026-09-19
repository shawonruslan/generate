package com.zedge.contentstudio.core

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.zedge.contentstudio.MainActivity
import com.zedge.contentstudio.R
import com.zedge.contentstudio.data.QueueItem

/**
 * v23 - system notifications for the metadata guard.
 * Fires once per NEW file that has no title/tags/category (the bot skips those), per account.
 * Already-seen ids are remembered in SharedPreferences so re-opening the app does not re-notify.
 */
object MetaNotifier {
    const val CHANNEL_ID = "meta_alerts"
    private const val PREFS = "meta_notifier"

    fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Metadata alerts", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Files in the upload queue that have no title / tags / category - the bot skips them"
        })
    }

    fun canPost(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /**
     * Called whenever the active account's queue changes.
     * @return the items that are newly missing metadata (for an in-app toast), empty when nothing new.
     */
    fun onQueue(ctx: Context, accountKey: String, queue: List<QueueItem>): List<QueueItem> {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val prefKey = "seen_$accountKey"
        val missing = queue.filter { it.isBlockedNoMeta }
        val ids = missing.map { it.id }.toSet()
        val seen = prefs.getStringSet(prefKey, null)
        prefs.edit().putStringSet(prefKey, ids).apply()
        if (seen == null) return emptyList()            // first snapshot for this account -> just record
        val fresh = missing.filter { it.id !in seen }
        if (fresh.isEmpty()) return emptyList()
        post(ctx, accountKey, fresh, missing.size)
        return fresh
    }

    private fun post(ctx: Context, accountKey: String, fresh: List<QueueItem>, total: Int) {
        if (!canPost(ctx)) return
        ensureChannel(ctx)
        val label = Accounts.byKey(accountKey).label
        val names = fresh.map { it.title.ifBlank { it.name.ifBlank { it.id } } }
        val title = if (fresh.size == 1) "1 file without metadata - $label" else "${fresh.size} files without metadata - $label"
        val body = names.take(3).joinToString(", ") + (if (names.size > 3) " \u2026" else "") +
            "\nThe bot will skip these until title, tags and category are added ($total blocked in total)."
        val open = PendingIntent.getActivity(
            ctx, accountKey.hashCode(),
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("open_meta_alerts", accountKey),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(names.joinToString(", "))
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        try { NotificationManagerCompat.from(ctx).notify(2300 + Accounts.all.indexOfFirst { it.key == accountKey }.coerceAtLeast(0), n) } catch (_: SecurityException) {}
    }
}
