package com.nexusdev.runner_imperio

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import io.flutter.plugin.common.EventChannel
import java.util.*

class TrackingService : Service() {

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback

    private var userId: String? = null
    private var userWeight: Double = 70.0
    private val db = FirebaseFirestore.getInstance()

    private var lastLocation: Location? = null
    private var totalDistance = 0.0
    private var lastAnnouncedKm = 0
    private var startTime: Long = 0
    private var lastFirestoreUpdate: Long = 0
    private val mainHandler = Handler(Looper.getMainLooper())

    data class NativeTerritory(val id: String, val points: List<Location>, val ownerId: String)
    private val territories = mutableListOf<NativeTerritory>()
    private val visitedPointsIndices = mutableMapOf<String, MutableSet<Int>>()

    companion object {
        var eventSink: EventChannel.EventSink? = null
        const val NOTIFICATION_ID = 1
        const val CHANNEL_ID = "tracking_channel"
    }

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        startTime = System.currentTimeMillis()
        loadTerritoriesFromFirestore()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        userId = intent?.getStringExtra("userId")
        userWeight = intent?.getDoubleExtra("weight", 70.0) ?: 70.0

        startForegroundService()
        startLocationUpdates()

        return START_STICKY
    }

    private fun startForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Tracking Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Runner: Rastreamento Ativo")
            .setContentText("Calculando métricas reais...")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun startLocationUpdates() {
        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            3000
        ).setMinUpdateIntervalMillis(2000).build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                for (location in result.locations) {
                    processNewLocation(location)
                }
            }
        }

        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            fusedLocationClient.lastLocation.addOnSuccessListener {
                if (it != null) processNewLocation(it)
            }

            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                Looper.getMainLooper()
            )
        }
    }

    private fun processNewLocation(location: Location) {
        if (lastLocation != null) {
            val distance = lastLocation!!.distanceTo(location)
            if (distance in 2.0..50.0) {
                totalDistance += distance
            }
        }

        lastLocation = location

        val now = System.currentTimeMillis()
        val elapsedMs = now - startTime
        val elapsedMinutes = elapsedMs / 60000.0
        val km = totalDistance / 1000.0

        val currentKm = km.toInt()
        val pace = if (km > 0) elapsedMinutes / km else 0.0
        val calories = km * userWeight * 1.036

        // 📢 DETECTA NOVO KM E PREPARA O ANÚNCIO
        var shouldAnnounce = false
        if (currentKm > lastAnnouncedKm) {
            lastAnnouncedKm = currentKm
            shouldAnnounce = true
        }

        val currentProgressMap = mutableMapOf<String, Double>()

        for (territory in territories) {
            val visited = visitedPointsIndices[territory.id] ?: mutableSetOf()

            if (visited.size == territory.points.size) {
                currentProgressMap[territory.id] = 1.0
            } else {
                currentProgressMap[territory.id] =
                    if (territory.points.isNotEmpty())
                        visited.size.toDouble() / territory.points.size
                    else 0.0
            }
        }

        val data = mutableMapOf<String, Any>(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "altitude" to location.altitude,
            "accuracy" to location.accuracy,
            "distance_m" to totalDistance,
            "kcal" to calories,
            "pace_min_km" to pace,
            "speed" to location.speed,
            "territory_progress" to currentProgressMap
        )

        // Se completou 1km, adiciona a marcação para o Flutter falar
        if (shouldAnnounce) {
            data["type"] = "km_reached"
            data["km_count"] = currentKm
        }

        mainHandler.post { eventSink?.success(data) }

        if (now - lastFirestoreUpdate > 10000 && userId != null) {
            lastFirestoreUpdate = now
            updateFirestore(data)
        }
    }

    private fun loadTerritoriesFromFirestore() {
        db.collection("territorios").get().addOnSuccessListener { result ->
            territories.clear()

            for (doc in result) {
                val pointsRaw = doc.get("points") as? List<Map<String, Any>> ?: continue

                val locList = pointsRaw.map {
                    Location("").apply {
                        latitude = (it["lat"] as? Number)?.toDouble() ?: 0.0
                        longitude = (it["lng"] as? Number)?.toDouble() ?: 0.0
                    }
                }

                territories.add(
                    NativeTerritory(
                        doc.id,
                        locList,
                        doc.getString("userId") ?: ""
                    )
                )

                visitedPointsIndices[doc.id] = mutableSetOf()
            }
        }
    }

    private fun updateFirestore(data: Map<String, Any>) {
        userId?.let { uid ->
            val update = hashMapOf<String, Any>(
                "updatedAt" to FieldValue.serverTimestamp(),
                "lat" to (data["latitude"] ?: 0.0),
                "lng" to (data["longitude"] ?: 0.0),
                "distance_m" to (data["distance_m"] ?: 0.0),
                "kcal" to (data["kcal"] ?: 0.0),
                "pace_min_km" to (data["pace_min_km"] ?: 0.0)
            )

            db.collection("users").document(uid).update(update)
        }
    }

    override fun onDestroy() {
        fusedLocationClient.removeLocationUpdates(locationCallback)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
