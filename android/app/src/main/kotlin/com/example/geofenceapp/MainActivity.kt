package com.example.geofenceapp

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.geofenceapp/geofence"
        private var methodChannel: MethodChannel? = null

        fun notifyGeofenceTransition(placeId: String, transitionType: String) {
            // Check if there is an active Flutter engine and channel
            methodChannel?.let { channel ->
                val data = mapOf("placeId" to placeId, "transition" to transitionType)
                // Need to ensure method is invoked on the main thread
                channel.invokeMethod("geofenceTransition", data)
                Log.d(TAG, "Notified Flutter of geofence transition: $data")
            }
        }

        fun notifyLearningPointsUpdated() {
            methodChannel?.let { channel ->
                // Notify Dart that there are new learning points to fetch/re-cluster
                channel.invokeMethod("learningPointsUpdated", null)
                Log.d(TAG, "Notified Flutter of new learning points")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startLearning" -> {
                    GeofenceManager.startActivityRecognition(this)
                    result.success(true)
                }
                "stopLearning" -> {
                    GeofenceManager.stopActivityRecognition(this)
                    result.success(true)
                }
                "isLearningRunning" -> {
                    val prefs = getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                    val isActive = prefs.getBoolean("learning_mode_active", false)
                    result.success(isActive)
                }
                "registerGeofence" -> {
                    val id = call.argument<String>("id")
                    val lat = call.argument<Double>("lat")
                    val lng = call.argument<Double>("lng")
                    val radius = call.argument<Double>("radius")

                    if (id != null && lat != null && lng != null && radius != null) {
                        GeofenceManager.registerGeofence(this, id, lat, lng, radius.toFloat())
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENTS", "id, lat, lng, or radius is missing", null)
                    }
                }
                "unregisterGeofence" -> {
                    val id = call.argument<String>("id")
                    if (id != null) {
                        GeofenceManager.unregisterGeofence(this, id)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENTS", "id is missing", null)
                    }
                }
                "getCurrentLocation" -> {
                    if (androidx.core.app.ActivityCompat.checkSelfPermission(
                            this,
                            android.Manifest.permission.ACCESS_FINE_LOCATION
                        ) == android.content.pm.PackageManager.PERMISSION_GRANTED ||
                        androidx.core.app.ActivityCompat.checkSelfPermission(
                            this,
                            android.Manifest.permission.ACCESS_COARSE_LOCATION
                        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    ) {
                        val locationClient = com.google.android.gms.location.LocationServices.getFusedLocationProviderClient(this)
                        locationClient.lastLocation.addOnSuccessListener { location ->
                            if (location != null) {
                                result.success(mapOf("lat" to location.latitude, "lng" to location.longitude))
                            } else {
                                result.success(null)
                            }
                        }.addOnFailureListener { e ->
                            result.error("LOCATION_ERROR", e.message, null)
                        }
                    } else {
                        result.success(null)
                    }
                }
                "isIgnoreBatteryOptimizations" -> {
                    val isIgnoring = isBatteryOptimizationExempt()
                    result.success(isIgnoring)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    triggerBatteryOptimizationExemption()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        methodChannel = null
        super.onDestroy()
    }

    private fun isBatteryOptimizationExempt(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun triggerBatteryOptimizationExemption() {
        if (!isBatteryOptimizationExempt()) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start battery optimization settings", e)
            }
        }
    }
}
