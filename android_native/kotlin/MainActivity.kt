package com.aistudio.ai_image_studio

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Background generation (screen off / sleep): foreground service.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ais/keepawake")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            askNotifications()
                            GenerationService.update(
                                applicationContext,
                                call.argument<String>("title") ?: "AI Image Studio",
                                call.argument<String>("text") ?: "Working...",
                                call.argument<Int>("done") ?: 0,
                                call.argument<Int>("total") ?: 0
                            )
                            result.success(true)
                        }
                        "stop" -> {
                            GenerationService.stop(applicationContext)
                            result.success(true)
                        }
                        "batteryOk" -> {
                            val pm = getSystemService(PowerManager::class.java)
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        }
                        "askBattery" -> {
                            try {
                                @Suppress("BatteryLife")
                                val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName"))
                                startActivity(i)
                            } catch (_: Exception) {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            }
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    result.error("keepawake", e.toString(), null)
                }
            }

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ais/gecko")
        GeckoBridge.channel = ch
        ch.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "signIn" -> GeckoBridge.signIn(this, call.argument<String>("url"), result)
                        "refresh" -> GeckoBridge.refresh(this, result)
                        "cookies" -> GeckoBridge.readCookies(this) { result.success(it) }
                        "browserOpen" -> {
                            GeckoBridge.browserOpen(this, call.argument<String>("url"))
                            result.success(true)
                        }
                        "browserClose" -> {
                            GeckoBridge.browserClose()
                            result.success(true)
                        }
                        "browserBasket" -> {
                            GeckoBridge.browserBasket(call.arguments as String)
                            result.success(true)
                        }
                        "browserStatus" -> {
                            GeckoBridge.browserStatus(call.arguments as String)
                            result.success(true)
                        }
                        "browserToast" -> {
                            GeckoBridge.browserToast(call.arguments as String)
                            result.success(true)
                        }
                        "browserFetch" -> GeckoBridge.browserFetch(this, call.arguments as String) {
                            result.success(it)
                        }
                        "browserCapture" -> GeckoBridge.browserCapture(call.arguments as String) {
                            result.success(it)
                        }
                        "browserIsOpen" -> result.success(GeckoBridge.hasBrowserSession())
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    result.error("gecko", e.toString(), null)
                }
            }
    }

    private var askedNotifications = false

    /** Android 13+: the progress notification needs permission (the
     * service works without it, but then it is invisible). Asked once. */
    private fun askNotifications() {
        if (askedNotifications || Build.VERSION.SDK_INT < 33) return
        askedNotifications = true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 77)
        }
    }
}
