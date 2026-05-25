package com.nexusdev.runner_imperio

import android.content.Intent
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "run_tracker/methods"
    private val EVENT_CHANNEL = "run_tracker/events"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startTracking" -> {
                        val userId = call.argument<String>("userId")
                        val weight = call.argument<Double>("weight") ?: 70.0
                        if (userId != null) {
                            startTrackingService(userId, weight)
                            result.success(null)
                        } else {
                            result.error("MISSING_ARG", "UserId is required", null)
                        }
                    }
                    "stopTracking" -> {
                        stopTrackingService()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    TrackingService.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    TrackingService.eventSink = null
                }
            })
    }

    private fun startTrackingService(userId: String, weight: Double) {
        val intent = Intent(this, TrackingService::class.java).apply {
            putExtra("userId", userId)
            putExtra("weight", weight)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopTrackingService() {
        val intent = Intent(this, TrackingService::class.java)
        stopService(intent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("tracking_channel", "Tracking Service", NotificationManager.IMPORTANCE_LOW)
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
