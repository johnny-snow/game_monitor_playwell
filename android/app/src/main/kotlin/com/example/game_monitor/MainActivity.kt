package com.example.game_monitor

import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.usage.UsageEvents

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.playwell/tracker"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    result.success(hasUsagePermission())
                }
                "requestPermission" -> {
                    try {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            data = android.net.Uri.parse("package:$packageName")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                    } catch (e: Exception) {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                    }
                    result.success(true)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = android.net.Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                    }
                    result.success(true)
                }
                "startForegroundService" -> {
                    val intent = Intent(this, TrackingService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopForegroundService" -> {
                    val intent = Intent(this, TrackingService::class.java)
                    stopService(intent)
                    result.success(true)
                }
                "getInstalledApps" -> {
                    result.success(getInstalledApps())
                }
                "getForegroundApp" -> {
                    result.success(getForegroundAppPackage())
                }
                "killToHome" -> {
    val pkgName = call.argument<String>("packageName")
    killGameToHome(pkgName)
    result.success(true)
}
                else -> result.notImplemented()
            }
        }
    }

    private fun hasUsagePermission(): Boolean {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val time = System.currentTimeMillis()
        val stats = usageStatsManager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 1000 * 10, time)
        return !stats.isNullOrEmpty()
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PackageManager.MATCH_ALL
        } else {
            0
        }
        
        val packages = pm.getInstalledApplications(flags)
        val appList = mutableListOf<Map<String, String>>()

        for (appInfo in packages) {
            // Check if application has an active launcher intent (appears in app drawer)
            val launchIntent = pm.getLaunchIntentForPackage(appInfo.packageName)
            if (launchIntent != null) {
                val appName = try {
                    pm.getApplicationLabel(appInfo).toString()
                } catch (e: Exception) {
                    appInfo.packageName
                }

                val isCategoryGame = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appInfo.category == ApplicationInfo.CATEGORY_GAME
                } else {
                    (appInfo.flags and ApplicationInfo.FLAG_IS_GAME) != 0
                }

                appList.add(mapOf(
                    "packageName" to appInfo.packageName,
                    "appName" to appName,
                    "isGameDefault" to isCategoryGame.toString()
                ))
            }
        }
        return appList.sortedBy { it["appName"]?.lowercase() ?: "" }
    }

    private fun getForegroundAppPackage(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val time = System.currentTimeMillis()
        
        // Query the last 24 hours to ensure we don't miss the resume event of long gaming sessions
        val usageEvents = usm.queryEvents(time - (1000 * 60 * 60 * 24), time)
        val event = UsageEvents.Event()
        var currentApp: String? = null

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            // Track when an app comes to the foreground
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                currentApp = event.packageName
            } 
            // Track if that same app goes to the background
            else if (event.eventType == UsageEvents.Event.ACTIVITY_PAUSED || event.eventType == UsageEvents.Event.ACTIVITY_STOPPED) {
                if (currentApp == event.packageName) {
                    currentApp = null
                }
            }
        }
        return currentApp
    }

    private fun killGameToHome(packageName: String?) {
    // 1. Send home command to minimize all foreground tasks
    val homeIntent = Intent(Intent.ACTION_MAIN).apply {
        addCategory(Intent.CATEGORY_HOME)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK
    }
    startActivity(homeIntent)

    // 2. Kill any background threads/processes allowed by Android OS
    if (!packageName.isNullOrEmpty()) {
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            am.killBackgroundProcesses(packageName)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // 3. Launch PlayWell on top after a micro-delay to prevent flag collisions
    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
        val appIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(appIntent)
    }, 300)
}
}