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
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArrayList

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.geofenceapp/geofence"
        private const val PRIVACY_CHANNEL = "com.example.geofenceapp/privacy"
        private const val WEBHOOK_CHANNEL = "com.example.geofenceapp/webhook"
        private const val DEBUG_CHANNEL = "com.example.geofenceapp/debug"
        private const val EVENT_CHANNEL = "com.example.geofenceapp/geofence_events"
        private var methodChannel: MethodChannel? = null
        private var privacyChannel: MethodChannel? = null
        private var webhookChannel: MethodChannel? = null
        private var eventSink: EventChannel.EventSink? = null
        private val bufferedEvents = CopyOnWriteArrayList<Map<String, Any>>()

        fun notifyGeofenceTransition(placeId: String, transitionType: String) {
            val eventData = mapOf(
                "placeId" to placeId,
                "transition" to transitionType,
                "timestamp" to System.currentTimeMillis()
            )
            methodChannel?.let { channel ->
                val data = mapOf("placeId" to placeId, "transition" to transitionType)
                channel.invokeMethod("geofenceTransition", data)
                Log.d(TAG, "Notified Flutter of geofence transition: $data")
            }
            if (eventSink != null) {
                eventSink?.success(eventData)
            } else {
                bufferedEvents.add(eventData)
                Log.d(TAG, "Buffered event (no listener): $eventData")
            }
        }

        fun notifyLearningPointsUpdated() {
            methodChannel?.let { channel ->
                channel.invokeMethod("learningPointsUpdated", null)
                Log.d(TAG, "Notified Flutter of new learning points")
            }
        }

        fun notifyConsentRevoked() {
            privacyChannel?.let { channel ->
                channel.invokeMethod("consentRevoked", null)
                Log.d(TAG, "Notified Flutter of consent revocation")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        DebugLogger.init(this)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        val privacyChan = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIVACY_CHANNEL)
        privacyChannel = privacyChan

        val webhookChan = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WEBHOOK_CHANNEL)
        webhookChannel = webhookChan

        val eventChan = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        eventChan.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
                Log.d(TAG, "EventChannel listener attached, flushing ${bufferedEvents.size} buffered events")
                // Flush all buffered events on listen
                for (buffered in bufferedEvents) {
                    events.success(buffered)
                }
                bufferedEvents.clear()
            }

            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "EventChannel listener detached, buffering future events")
                eventSink = null
            }
        })

        if (PrivacyConsentManager.hasConsent(this)) {
            GeofenceManager.reRegisterAllGeofencesFromDb(this)
        }

        // Run auto-purge of expired location logs on startup
        try {
            val dbHelper = DbHelper(this)
            dbHelper.purgeExpiredLogs()
            dbHelper.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error during startup purge", e)
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startLearning" -> {
                    if (!PrivacyConsentManager.hasConsent(this)) {
                        result.error("CONSENT_DENIED", "Privacy consent not granted", null)
                        return@setMethodCallHandler
                    }
                    try {
                        GeofenceManager.startActivityRecognition(this)
                        result.success(true)
                    } catch (e: SecurityException) {
                        result.error("SECURITY_ERROR", "Activity recognition permission denied", null)
                    } catch (e: Exception) {
                        result.error("INTERNAL_ERROR", e.message ?: "Failed to start learning", null)
                    }
                }
                "stopLearning" -> {
                    try {
                        GeofenceManager.stopActivityRecognition(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "isLearningRunning" -> {
                    val prefs = getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                    val isActive = prefs.getBoolean("learning_mode_active", false)
                    result.success(isActive)
                }
                "registerGeofence" -> {
                    if (!PrivacyConsentManager.hasConsent(this)) {
                        result.error("CONSENT_DENIED", "Privacy consent not granted", null)
                        return@setMethodCallHandler
                    }
                    val id = call.argument<String>("id")
                    val lat = call.argument<Double>("lat")
                    val lng = call.argument<Double>("lng")
                    val radius = call.argument<Double>("radius")

                    if (id != null && lat != null && lng != null && radius != null) {
                        try {
                            GeofenceManager.registerGeofence(this, id, lat, lng, radius.toFloat())
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Location permission denied for geofence registration", null)
                        } catch (e: com.google.android.gms.common.api.ApiException) {
                            result.error("API_ERROR", "Google Play Services geofence error: ${e.statusCode}", null)
                        } catch (e: Exception) {
                            result.error("INTERNAL_ERROR", e.message ?: "Failed to register geofence", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "id, lat, lng, or radius is missing", null)
                    }
                }
                "unregisterGeofence" -> {
                    val id = call.argument<String>("id")
                    if (id != null) {
                        try {
                            GeofenceManager.unregisterGeofence(this, id)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INTERNAL_ERROR", e.message ?: "Failed to unregister geofence", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "id is missing", null)
                    }
                }
                "getCurrentLocation" -> {
                    try {
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
                            val cancellationTokenSource = com.google.android.gms.tasks.CancellationTokenSource()

                            val timeoutHandler = android.os.Handler(android.os.Looper.getMainLooper())
                            timeoutHandler.postDelayed({
                                cancellationTokenSource.cancel()
                                result.error("LOCATION_TIMEOUT", "Location request timed out after 10 seconds", null)
                            }, 10000)

                            locationClient.getCurrentLocation(
                                com.google.android.gms.location.Priority.PRIORITY_HIGH_ACCURACY,
                                cancellationTokenSource.token
                            ).addOnSuccessListener { location ->
                                timeoutHandler.removeCallbacksAndMessages(null)
                                if (location != null) {
                                    result.success(mapOf("lat" to location.latitude, "lng" to location.longitude))
                                } else {
                                    result.error("LOCATION_NULL", "Could not acquire a fresh location fix", null)
                                }
                            }.addOnFailureListener { e ->
                                timeoutHandler.removeCallbacksAndMessages(null)
                                val message = when (e) {
                                    is SecurityException -> "Location permission denied"
                                    is java.io.IOException -> "Location service unavailable"
                                    is com.google.android.gms.common.api.ApiException -> "Google Play Services error: ${e.statusCode}"
                                    else -> e.message ?: "Location request failed"
                                }
                                result.error("LOCATION_ERROR", message, null)
                            }
                        } else {
                            result.error("PERMISSION_DENIED", "Location permission not granted", null)
                        }
                    } catch (e: SecurityException) {
                        result.error("SECURITY_ERROR", "Location permission check failed", null)
                    } catch (e: Exception) {
                        result.error("INTERNAL_ERROR", e.message ?: "Failed to get current location", null)
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
                // Encrypted place save (Flutter routes through native)
                "savePlace" -> {
                    try {
                        val id = call.argument<String>("id")
                        val label = call.argument<String>("label")
                        val icon = call.argument<String>("icon")
                        val lat = call.argument<Double>("lat")
                        val lng = call.argument<Double>("lng")
                        val radius = call.argument<Double>("radius")
                        val status = call.argument<String>("status")
                        val triggerType = call.argument<String>("triggerType")
                        val createdAt = call.argument<String>("createdAt")
                        val updatedAt = call.argument<String>("updatedAt")
                        val dirty = call.argument<Int>("dirty") ?: 0

                        if (id != null && label != null && lat != null && lng != null) {
                            val dbHelper = DbHelper(this)
                            dbHelper.insertPlaceEncrypted(
                                id, label, icon ?: "custom",
                                lat, lng, radius ?: 150.0,
                                status ?: "learning", triggerType ?: "normal",
                                createdAt ?: getCurrentTimestamp(),
                                updatedAt ?: getCurrentTimestamp(),
                                dirty
                            )
                            dbHelper.close()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENTS", "Missing required place fields", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error saving encrypted place", e)
                        result.error("INTERNAL_ERROR", e.message ?: "Failed to save place", null)
                    }
                }
                // Insert learning point with encryption
                "insertLearningPoint" -> {
                    try {
                        val lat = call.argument<Double>("lat")
                        val lng = call.argument<Double>("lng")
                        val timestamp = call.argument<Long>("timestamp")
                        val source = call.argument<String>("source") ?: "FLUTTER"

                        if (lat != null && lng != null && timestamp != null) {
                            val dbHelper = DbHelper(this)
                            dbHelper.insertLearningPoint(lat, lng, timestamp, source)
                            dbHelper.close()
                            notifyLearningPointsUpdated()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENTS", "Missing lat, lng, or timestamp", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error inserting learning point", e)
                        result.error("INTERNAL_ERROR", e.message ?: "Failed to insert learning point", null)
                    }
                }
                // Storage and queue stats for the storage screen
                "getStorageStats" -> {
                    try {
                        val dbHelper = DbHelper(this)
                        val placesCount = dbHelper.getTableRowCount(DbHelper.TABLE_PLACES)
                        val visitsCount = dbHelper.getTableRowCount(DbHelper.TABLE_VISITS)
                        val learningPointsCount = dbHelper.getTableRowCount(DbHelper.TABLE_LEARNING_POINTS)
                        val locationLogsCount = dbHelper.getTableRowCount(DbHelper.TABLE_LOCATION_LOGS)
                        val webhookQueueCount = dbHelper.getTableRowCount(DbHelper.TABLE_WEBHOOK_QUEUE)
                        val geofenceTransitionsCount = dbHelper.getTableRowCount(DbHelper.TABLE_GEOFENCE_TRANSITIONS)
                        val pageCount = dbHelper.getDatabasePageCount()
                        val pageSize = dbHelper.getDatabasePageSize()
                        dbHelper.close()

                        result.success(mapOf(
                            "places" to placesCount,
                            "visits" to visitsCount,
                            "learningPoints" to learningPointsCount,
                            "locationLogs" to locationLogsCount,
                            "webhookQueue" to webhookQueueCount,
                            "geofenceTransitions" to geofenceTransitionsCount,
                            "dbSizeBytes" to (pageCount * pageSize)
                        ))
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting storage stats", e)
                        result.error("INTERNAL_ERROR", "Failed to get storage stats", null)
                    }
                }
                // Read all places (decrypted)
                "getAllPlaces" -> {
                    try {
                        val dbHelper = DbHelper(this)
                        val places = dbHelper.getAllPlacesDecrypted()
                        dbHelper.close()
                        result.success(places)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting all places", e)
                        result.error("INTERNAL_ERROR", "Failed to get places", null)
                    }
                }
                // Read single place (decrypted)
                "getPlace" -> {
                    try {
                        val id = call.argument<String>("id")
                        if (id != null) {
                            val dbHelper = DbHelper(this)
                            val place = dbHelper.getPlaceDecrypted(id)
                            dbHelper.close()
                            result.success(place)
                        } else {
                            result.error("INVALID_ARGUMENTS", "id is required", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting place", e)
                        result.error("INTERNAL_ERROR", "Failed to get place", null)
                    }
                }
                // Update encrypted place
                "updatePlace" -> {
                    try {
                        val id = call.argument<String>("id")
                        val label = call.argument<String>("label")
                        val icon = call.argument<String>("icon")
                        val lat = call.argument<Double>("lat")
                        val lng = call.argument<Double>("lng")
                        val radius = call.argument<Double>("radius")
                        val status = call.argument<String>("status")
                        val triggerType = call.argument<String>("triggerType")
                        val updatedAt = call.argument<String>("updatedAt")
                        val dirty = call.argument<Int>("dirty") ?: 0

                        if (id != null && updatedAt != null) {
                            val dbHelper = DbHelper(this)
                            dbHelper.updatePlaceEncrypted(
                                id, label, icon, lat, lng, radius, status, triggerType, updatedAt, dirty
                            )
                            dbHelper.close()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENTS", "id and updatedAt are required", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error updating place", e)
                        result.error("INTERNAL_ERROR", "Failed to update place", null)
                    }
                }
                // Delete encrypted place
                "deletePlace" -> {
                    try {
                        val id = call.argument<String>("id")
                        if (id != null) {
                            val dbHelper = DbHelper(this)
                            dbHelper.deletePlaceEncrypted(id)
                            dbHelper.close()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENTS", "id is required", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error deleting place", e)
                        result.error("INTERNAL_ERROR", "Failed to delete place", null)
                    }
                }
                // Read all learning points (decrypted)
                "getAllLearningPoints" -> {
                    try {
                        val dbHelper = DbHelper(this)
                        val points = dbHelper.getAllLearningPointsDecrypted()
                        dbHelper.close()
                        result.success(points)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting learning points", e)
                        result.error("INTERNAL_ERROR", "Failed to get learning points", null)
                    }
                }
                // Clear all learning points
                "clearLearningPoints" -> {
                    try {
                        val dbHelper = DbHelper(this)
                        dbHelper.clearLearningPointsEncrypted()
                        dbHelper.close()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error clearing learning points", e)
                        result.error("INTERNAL_ERROR", "Failed to clear learning points", null)
                    }
                }
                // Delete learning points older than timestamp
                "deleteLearningPointsOlderThan" -> {
                    try {
                        val timestamp = call.argument<Long>("timestamp")
                        if (timestamp != null) {
                            val dbHelper = DbHelper(this)
                            dbHelper.deleteLearningPointsOlderThanEncrypted(timestamp)
                            dbHelper.close()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENTS", "timestamp is required", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error deleting old learning points", e)
                        result.error("INTERNAL_ERROR", "Failed to delete old learning points", null)
                    }
                }
                // Purge learning points within radius (decrypts, checks, deletes)
                "purgeLearningPointsWithin" -> {
                    try {
                        val lat = call.argument<Double>("lat")
                        val lng = call.argument<Double>("lng")
                        val radius = call.argument<Double>("radius")
                        if (lat != null && lng != null && radius != null) {
                            val dbHelper = DbHelper(this)
                            dbHelper.deleteLearningPointsWithinEncrypted(lat, lng, radius)
                            dbHelper.close()
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENTS", "lat, lng, radius are required", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error purging learning points", e)
                        result.error("INTERNAL_ERROR", "Failed to purge learning points", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        webhookChan.setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    try {
                        val url = call.argument<String>("url")
                        val headersJson = call.argument<String>("headersJson")
                        if (url != null) {
                            PrivacyConsentManager.setWebhookEndpoint(this, url)
                            if (headersJson != null) {
                                PrivacyConsentManager.setWebhookHeaders(this, headersJson)
                            } else {
                                PrivacyConsentManager.setWebhookHeaders(this, "{}")
                            }
                            WebhookWorker.scheduleDispatch(this)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENTS", "url is required", null)
                        }
                    } catch (e: Exception) {
                        result.error("CONFIG_ERROR", e.message ?: "Failed to configure webhook", null)
                    }
                }
                "getConfig" -> {
                    try {
                        val url = PrivacyConsentManager.getWebhookEndpoint(this)
                        val headersJson = PrivacyConsentManager.getWebhookHeaders(this)
                        val safeUrl = if (url != null && url.length > 8) "${url.take(8)}..." else url
                        result.success(mapOf(
                            "url" to (safeUrl ?: ""),
                            "headersJson" to (headersJson?.let { "***" } ?: "{}")
                        ))
                    } catch (e: Exception) {
                        result.error("CONFIG_ERROR", "Failed to read webhook config", null)
                    }
                }
                "clearConfig" -> {
                    try {
                        PrivacyConsentManager.clearWebhookConfig(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CONFIG_ERROR", "Failed to clear webhook config", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        val debugChan = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEBUG_CHANNEL)
        debugChan.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLogs" -> {
                    val limit = call.argument<Int>("limit") ?: 200
                    val logs = DebugLogger.getRecentLogs(limit)
                    val jsonLogs = logs.map { entry ->
                        mapOf(
                            "id" to entry.id,
                            "timestamp" to entry.timestamp,
                            "level" to entry.level,
                            "category" to entry.category,
                            "message" to entry.message,
                            "placeId" to (entry.placeId ?: ""),
                            "extraJson" to (entry.extraJson ?: "")
                        )
                    }
                    result.success(jsonLogs)
                }
                "clearLogs" -> {
                    DebugLogger.clearLogs()
                    result.success(true)
                }
                "exportLogsToFile" -> {
                    try {
                        val text = DebugLogger.exportAsText()
                        val file = java.io.File(cacheDir, "debug_logs_export.txt")
                        file.writeText(text)
                        result.success(file.absolutePath)
                    } catch (e: Exception) {
                        result.error("EXPORT_FAILED", e.message, null)
                    }
                }
                "setLoggingEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    DebugLogger.setEnabled(enabled)
                    result.success(true)
                }
                "isLoggingEnabled" -> {
                    result.success(DebugLogger.isEnabled())
                }
                "getLogCount" -> {
                    result.success(DebugLogger.getLogCount())
                }
                else -> result.notImplemented()
            }
        }

        privacyChan.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasConsent" -> {
                    result.success(PrivacyConsentManager.hasConsent(this))
                }
                "grantConsent" -> {
                    try {
                        PrivacyConsentManager.grantConsent(this)
                        GeofenceManager.reRegisterAllGeofencesFromDb(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CONSENT_ERROR", "Failed to grant consent", null)
                    }
                }
                "revokeConsent" -> {
                    try {
                        PrivacyConsentManager.revokeConsent(this)
                        GeofenceManager.stopActivityRecognition(this)
                        val dbHelper = DbHelper(this)
                        dbHelper.purgeAllHistory()
                        dbHelper.close()
                        notifyConsentRevoked()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CONSENT_ERROR", "Failed to revoke consent", null)
                    }
                }
                "purgeAllHistory" -> {
                    try {
                        val dbHelper = DbHelper(this)
                        dbHelper.purgeAllHistory()
                        dbHelper.close()
                        if (!PrivacyConsentManager.hasConsent(this)) {
                            GeofenceManager.stopActivityRecognition(this)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PURGE_ERROR", "Failed to purge history", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        methodChannel = null
        privacyChannel = null
        webhookChannel = null
        eventSink = null
        bufferedEvents.clear()
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

    private fun getCurrentTimestamp(): String {
        val sdf = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US)
        return sdf.format(java.util.Date())
    }
}
