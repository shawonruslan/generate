package com.aistudio.ai_image_studio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps generation running while the phone sleeps: a foreground service
 * (ongoing notification with progress) that holds a partial wake lock and
 * a Wi-Fi lock. Android does not freeze or cut the network of an app that
 * runs a foreground service, so queued images / sets keep going with the
 * screen off. Started by the app when a run begins, stopped when it ends.
 */
class GenerationService : Service() {
    companion object {
        private const val CHANNEL = "ais_generation"
        private const val ID = 4711
        private const val ACTION_STOP = "ais.stop"

        @Volatile var running = false
        private var title = "AI Image Studio"
        private var text = "Working..."
        private var done = 0
        private var total = 0

        private fun channel(ctx: Context) {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL) == null) {
                val c = NotificationChannel(CHANNEL, "Generation in progress",
                    NotificationManager.IMPORTANCE_LOW)
                c.description = "Shown while images, sets or prompts are being generated"
                c.setShowBadge(false)
                nm.createNotificationChannel(c)
            }
        }

        private fun build(ctx: Context): Notification {
            channel(ctx)
            val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
                ?: Intent(ctx, MainActivity::class.java)
            open.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            val pi = PendingIntent.getActivity(ctx, 0, open,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val b = Notification.Builder(ctx, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(pi)
                .setCategory(Notification.CATEGORY_PROGRESS)
            if (total > 0) b.setProgress(total, done.coerceIn(0, total), false)
            else b.setProgress(0, 0, true)
            return b.build()
        }

        /** Starts the service (or just updates its notification). */
        fun update(ctx: Context, t: String, msg: String, d: Int, n: Int) {
            title = t
            text = msg
            done = d
            total = n
            if (running) {
                // Already in the foreground: only refresh the notification
                // (starting a service from the background is not allowed).
                try {
                    ctx.getSystemService(NotificationManager::class.java).notify(ID, build(ctx))
                } catch (_: Exception) {
                }
                return
            }
            try {
                ctx.startForegroundService(Intent(ctx, GenerationService::class.java))
            } catch (_: Exception) {
            }
        }

        fun stop(ctx: Context) {
            if (!running) return
            try {
                ctx.startService(Intent(ctx, GenerationService::class.java).setAction(ACTION_STOP))
            } catch (_: Exception) {
                try {
                    ctx.stopService(Intent(ctx, GenerationService::class.java))
                } catch (_: Exception) {
                }
            }
        }
    }

    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            finish()
            return START_NOT_STICKY
        }
        val n = build(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, n)
        }
        running = true
        lock()
        return START_NOT_STICKY
    }

    private fun lock() {
        if (wake == null) {
            val pm = getSystemService(PowerManager::class.java)
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ais:generation").apply {
                setReferenceCounted(false)
            }
        }
        // Safety timeout; renewed on every start.
        wake?.acquire(6 * 60 * 60 * 1000L)
        if (wifi == null) {
            try {
                val wm = applicationContext.getSystemService(WifiManager::class.java)
                @Suppress("DEPRECATION")
                wifi = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "ais:generation").apply {
                    setReferenceCounted(false)
                }
            } catch (_: Exception) {
            }
        }
        try {
            wifi?.acquire()
        } catch (_: Exception) {
        }
    }

    private fun finish() {
        running = false
        try {
            if (wake?.isHeld == true) wake?.release()
        } catch (_: Exception) {
        }
        try {
            if (wifi?.isHeld == true) wifi?.release()
        } catch (_: Exception) {
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    // Android 15: dataSync services get a daily time budget; stop cleanly.
    override fun onTimeout(startId: Int) {
        finish()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        finish()
    }

    override fun onDestroy() {
        running = false
        try {
            if (wake?.isHeld == true) wake?.release()
        } catch (_: Exception) {
        }
        try {
            if (wifi?.isHeld == true) wifi?.release()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
