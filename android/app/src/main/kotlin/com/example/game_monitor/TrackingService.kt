package com.example.game_monitor

import android.app.*
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.util.*

class TrackingService : Service() {
    private var timer: Timer? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForegroundServiceNotification()
        startNativeTracking()
    }

    private fun startForegroundServiceNotification() {
        val channelId = "playwell_tracker_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "PlayWell Background Tracker",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("PlayWell Active")
            .setContentText("Monitoring game limits in real time...")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
            .build()

        startForeground(1001, notification)
    }

    private fun startNativeTracking() {
        timer = Timer()
        timer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                if (!hasUsagePermission()) return

                val currentPkg = getForegroundAppPackage() ?: return
                
                val intent = Intent("com.playwell.GAME_TICK")
                intent.putExtra("packageName", currentPkg)
                sendBroadcast(intent)
            }
        }, 0, 1000)
    }

    private fun hasUsagePermission(): Boolean {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val time = System.currentTimeMillis()
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 1000 * 10, time)
        return !stats.isNullOrEmpty()
    }

    private fun getForegroundAppPackage(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val time = System.currentTimeMillis()
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 1000 * 5, time)
        if (stats.isNullOrEmpty()) return null

        var recentPackage: String? = null
        var maxTime: Long = 0
        for (stat in stats) {
            if (stat.lastTimeUsed > maxTime) {
                maxTime = stat.lastTimeUsed
                recentPackage = stat.packageName
            }
        }
        return recentPackage
    }

    override fun onDestroy() {
        timer?.cancel()
        super.onDestroy()
    }
}