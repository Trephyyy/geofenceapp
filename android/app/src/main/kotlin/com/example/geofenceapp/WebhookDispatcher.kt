package com.example.geofenceapp

import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import org.json.JSONObject
import java.security.MessageDigest

object WebhookDispatcher {
    private const val TAG = "WebhookDispatcher"
    private const val SCHEMA_VERSION = "1.0"
    private val MAX_QUEUED_ROWS get() = DbHelper.MAX_QUEUED_ROWS

    fun dispatchGeofenceEvent(
        context: Context,
        eventType: String,
        placeId: String?,
        latitude: Double?,
        longitude: Double?,
        accuracy: Float?,
        altitude: Double?,
        speed: Float?,
        timestampHw: Long?,
        dwellDurationMs: Long?
    ) {
        DebugLogger.init(context)

        val endpoint = PrivacyConsentManager.getWebhookEndpoint(context)
        if (endpoint == null) {
            val dbHelper = DbHelper(context)
            try {
                val queueCount = dbHelper.getWebhookQueueCount()
                DebugLogger.i("WEBHOOK", "Event queued: $eventType for $placeId. Queue depth: $queueCount",
                    placeId = placeId, extra = mapOf("event_type" to eventType, "queue_depth" to queueCount))
            } finally {
                dbHelper.close()
            }
            enqueueWithoutNetwork(context, eventType, placeId, latitude, longitude, accuracy, altitude, speed, timestampHw, dwellDurationMs)
            return
        }

        val payload = buildPayload(context, eventType, placeId, latitude, longitude, accuracy, altitude, speed, timestampHw, dwellDurationMs)
        val headersJson = PrivacyConsentManager.getWebhookHeaders(context)
        val dbHelper = DbHelper(context)
        try {
            val queueCount = dbHelper.getWebhookQueueCount()

            if (queueCount >= MAX_QUEUED_ROWS) {
                Log.w(TAG, "Webhook queue at max capacity ($MAX_QUEUED_ROWS), dropping event: $eventType")
                DebugLogger.w("WEBHOOK", "Queue full ($MAX_QUEUED_ROWS). Dropped $eventType for $placeId",
                    placeId = placeId, extra = mapOf("event_type" to eventType, "queue_depth" to queueCount))
                return
            }

            DebugLogger.i("WEBHOOK", "Event queued: $eventType for $placeId. Queue depth: $queueCount",
                placeId = placeId, extra = mapOf("event_type" to eventType, "queue_depth" to queueCount))

            val now = System.currentTimeMillis()
            dbHelper.insertWebhookQueue(payload.toString(), endpoint, headersJson, 0, now, now)
            WebhookWorker.scheduleDispatch(context)
        } finally {
            dbHelper.close()
        }
    }

    fun dispatchStillSnapshot(
        context: Context,
        latitude: Double,
        longitude: Double,
        accuracy: Float?,
        timestampHw: Long?
    ) {
        dispatchGeofenceEvent(
            context = context,
            eventType = "STILL_SNAPSHOT",
            placeId = null,
            latitude = latitude,
            longitude = longitude,
            accuracy = accuracy,
            altitude = null,
            speed = null,
            timestampHw = timestampHw,
            dwellDurationMs = null
        )
    }

    private fun enqueueWithoutNetwork(
        context: Context,
        eventType: String,
        placeId: String?,
        latitude: Double?,
        longitude: Double?,
        accuracy: Float?,
        altitude: Double?,
        speed: Float?,
        timestampHw: Long?,
        dwellDurationMs: Long?
    ) {
        val payload = buildPayload(context, eventType, placeId, latitude, longitude, accuracy, altitude, speed, timestampHw, dwellDurationMs)
        val dbHelper = DbHelper(context)
        try {
            val queueCount = dbHelper.getWebhookQueueCount()

            if (queueCount >= MAX_QUEUED_ROWS) {
                Log.w(TAG, "Webhook queue at max capacity ($MAX_QUEUED_ROWS), dropping event: $eventType")
                return
            }

            val now = System.currentTimeMillis()
            dbHelper.insertWebhookQueue(payload.toString(), "", null, 0, now, now + 86400000L)
            Log.d(TAG, "Enqueued $eventType (no endpoint configured, delayed 24h)")
        } finally {
            dbHelper.close()
        }
    }

    private fun buildPayload(
        context: Context,
        eventType: String,
        placeId: String?,
        latitude: Double?,
        longitude: Double?,
        accuracy: Float?,
        altitude: Double?,
        speed: Float?,
        timestampHw: Long?,
        dwellDurationMs: Long?
    ): JSONObject {
        return JSONObject().apply {
            put("schema_version", SCHEMA_VERSION)
            put("event", eventType)
            if (placeId != null) put("place_id", placeId)
            put("timestamp", timestampHw ?: System.currentTimeMillis())

            val location = JSONObject()
            if (latitude != null) location.put("latitude", latitude)
            if (longitude != null) location.put("longitude", longitude)
            if (accuracy != null) location.put("accuracy_meters", accuracy)
            if (altitude != null) location.put("altitude", altitude)
            if (speed != null) location.put("speed_mps", speed)
            put("location", location)

            put("device", getDeviceInfo(context))

            put("session", getSessionInfo(context))
        }
    }

    private fun getDeviceInfo(context: Context): JSONObject {
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val batteryLevel = batteryManager?.let { bm ->
            val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (level in 0..100) level else 0
        } ?: 0

        val isCharging = batteryManager?.let { bm ->
            bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS) == BatteryManager.BATTERY_STATUS_CHARGING
        } ?: false

        return JSONObject().apply {
            put("battery_level", batteryLevel)
            put("is_charging", isCharging)
            put("os", "android")
            put("os_version", Build.VERSION.RELEASE ?: "unknown")
        }
    }

    private fun getSessionInfo(context: Context): JSONObject {
        val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        val hash = MessageDigest.getInstance("SHA-256").digest(androidId.toByteArray())
            .joinToString("") { "%02x".format(it) }

        return JSONObject().apply {
            put("device_id_hash", hash)
        }
    }
}