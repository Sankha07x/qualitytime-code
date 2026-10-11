package com.example.QualityTime

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class ScreenShareService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val builder: Notification.Builder
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    "qt_share", "Screen sharing",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
            builder = Notification.Builder(this, "qt_share")
        } else {
            @Suppress("DEPRECATION")
            builder = Notification.Builder(this)
        }
        val n = builder
            .setContentTitle("QualityTime")
            .setContentText("Sharing your screen")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                7351, n,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(7351, n)
        }
        return START_NOT_STICKY
    }
}