package com.example.suburban_life

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channels = listOf(
            NotificationChannel("reviews", "Request Reviews", NotificationManager.IMPORTANCE_HIGH),
            NotificationChannel("sanctions", "Sanctions", NotificationManager.IMPORTANCE_HIGH),
            NotificationChannel("qr_access", "QR Gate Access", NotificationManager.IMPORTANCE_HIGH),
            NotificationChannel("roommates", "Household & Roommates", NotificationManager.IMPORTANCE_DEFAULT),
            NotificationChannel("transparency", "Transparency Documents", NotificationManager.IMPORTANCE_DEFAULT),
            NotificationChannel("announcements", "Community Announcements", NotificationManager.IMPORTANCE_DEFAULT),
            NotificationChannel("admin_reviews", "Admin Pending Queue", NotificationManager.IMPORTANCE_HIGH),
        )
        manager.createNotificationChannels(channels)
    }
}
