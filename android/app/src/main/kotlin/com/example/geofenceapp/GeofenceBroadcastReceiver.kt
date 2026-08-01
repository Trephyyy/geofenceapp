package com.example.geofenceapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

/**
 * GeofenceBroadcastReceiver handles geofence transitions (DWELL, EXIT).
 *
 * ── Harbor State Machine ──
 *
 * A Harbor session represents "maritime duty." Unlike normal places where
 * DWELL starts a visit and EXIT ends it, harbor mode uses a persistent
 * session that survives multiple exits and re-entries:
 *
 *   DWELL (harbor)   → Start a new harbor visit if none is active.
 *                        If a session already exists (returning from sea),
 *                        keep the existing session alive.
 *
 *   EXIT (harbor)    → Record the hardware timestamp in SharedPreferences
 *                        as last_harbor_exit_time. Do NOT end the visit.
 *                        The session stays alive for multi-voyage days.
 *
 *   DWELL (any other) → If an active harbor session exists, close it using
 *                         the stored last_harbor_exit_time as the end time.
 *                         Then start a normal visit for the new place.
 *
 * SharedPreferences keys (geofence_prefs):
 *   active_harbor_place_id — place ID with an active harbor session, or null
 *   last_harbor_exit_time  — most recent harbor EXIT hardware timestamp (0 if none)
 *
 * This replaces the old "exit counter" approach which broke multi-voyage
 * workdays by either ending the session prematurely or never closing it.
 */
class GeofenceBroadcastReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "GeofenceReceiver"
        private const val PREFS_NAME = "geofence_prefs"
        const val KEY_ACTIVE_HARBOR_PLACE_ID = "active_harbor_place_id"
        const val KEY_LAST_HARBOR_EXIT = "last_harbor_exit_time"
        private const val LOITERING_DELAY_MS = 120000L
    }

    override fun onReceive(context: Context, intent: Intent) {
        DebugLogger.init(context)
        Log.d(TAG, "Geofence transition received")
        val geofencingEvent = GeofencingEvent.fromIntent(intent) ?: return
        if (geofencingEvent.hasError()) {
            Log.e(TAG, "GeofencingEvent error code: ${geofencingEvent.errorCode}")
            DebugLogger.e("GEOFENCE", "GeofencingEvent error: ${geofencingEvent.errorCode}")
            return
        }

        val transitionType = geofencingEvent.geofenceTransition
        val triggeringGeofences = geofencingEvent.triggeringGeofences ?: return

        val hardwareTimestamp = geofencingEvent.triggeringLocation?.time
            ?: System.currentTimeMillis()
        val processedAt = System.currentTimeMillis()

        val dbHelper = DbHelper(context)
        val notificationHelper = NotificationHelper(context)

        val transitionName = when (transitionType) {
            Geofence.GEOFENCE_TRANSITION_DWELL -> "DWELL"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "EXIT"
            else -> "UNKNOWN($transitionType)"
        }

        for (geofence in triggeringGeofences) {
            val placeId = geofence.requestId
            val label = dbHelper.getPlaceLabel(placeId) ?: "Unknown Place"
            val triggerType = dbHelper.getPlaceTriggerType(placeId) ?: "normal"

            DebugLogger.i("GEOFENCE", "Transition received: $transitionName at $placeId ($label)", placeId = placeId)

            when (transitionType) {
                Geofence.GEOFENCE_TRANSITION_DWELL -> {
                    if (triggerType == "harbor") {
                        handleHarborDwell(
                            context, dbHelper, notificationHelper,
                            placeId, label, hardwareTimestamp, processedAt
                        )
                    } else {
                        handleNormalPlaceDwell(
                            context, dbHelper, notificationHelper,
                            placeId, label, hardwareTimestamp, processedAt
                        )
                    }
                }
                Geofence.GEOFENCE_TRANSITION_EXIT -> {
                    if (triggerType == "harbor") {
                        handleHarborExit(context, placeId, label, hardwareTimestamp)
                    } else {
                        handleNormalPlaceExit(
                            context, dbHelper, notificationHelper,
                            placeId, label, hardwareTimestamp, processedAt
                        )
                    }
                }
            }
        }
        dbHelper.close()
    }

    private fun handleHarborDwell(
        context: Context,
        dbHelper: DbHelper,
        notificationHelper: NotificationHelper,
        placeId: String,
        label: String,
        hardwareTimestamp: Long,
        processedAt: Long
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val activeHarborId = prefs.getString(KEY_ACTIVE_HARBOR_PLACE_ID, null)

        if (activeHarborId != null && activeHarborId != placeId) {
            Log.w(TAG, "DWELL at harbor $placeId but session active for $activeHarborId. Ignoring.")
            DebugLogger.w("HARBOR", "DWELL at harbor $placeId but session active for $activeHarborId. Ignoring.", placeId = placeId)
            return
        }

        val arrivalTimestamp = hardwareTimestamp - LOITERING_DELAY_MS
        val lastHarborExit = prefs.getLong(KEY_LAST_HARBOR_EXIT, 0L)

        if (activeHarborId == null) {
            dbHelper.startVisit(placeId, arrivalTimestamp, hardwareTimestamp, processedAt)
            prefs.edit()
                .putString(KEY_ACTIVE_HARBOR_PLACE_ID, placeId)
                .putLong(KEY_LAST_HARBOR_EXIT, 0L)
                .apply()
            Log.d(TAG, "Harbor session STARTED: $placeId ($label) at $arrivalTimestamp")
            DebugLogger.i("HARBOR", "Session STARTED for $placeId at $arrivalTimestamp. Last exit was $lastHarborExit", placeId = placeId)
            notificationHelper.showTransitionNotification(
                "Docked at $label",
                "Harbor tracking started."
            )
            MainActivity.notifyGeofenceTransition(placeId, "HARBOR_CONFIRMED")
        } else {
            prefs.edit().putLong(KEY_LAST_HARBOR_EXIT, 0L).apply()
            Log.d(TAG, "Returned to harbor $placeId. Session still active.")
            DebugLogger.d("HARBOR", "Returned to $placeId. Active session $activeHarborId unchanged.", placeId = placeId)
            notificationHelper.showTransitionNotification(
                "Returned to $label",
                "Harbor tracking continues."
            )
            MainActivity.notifyGeofenceTransition(placeId, "HARBOR_RETURN")
        }
    }

    private fun handleHarborExit(
        context: Context,
        placeId: String,
        label: String,
        hardwareTimestamp: Long
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val activeHarborId = prefs.getString(KEY_ACTIVE_HARBOR_PLACE_ID, null)

        if (activeHarborId == placeId) {
            prefs.edit().putLong(KEY_LAST_HARBOR_EXIT, hardwareTimestamp).apply()
            Log.d(TAG, "Harbor EXIT recorded: $placeId at $hardwareTimestamp. Session stays alive.")
            DebugLogger.d("HARBOR", "EXIT recorded for $placeId at $hardwareTimestamp. Session stays alive.", placeId = placeId)
        } else {
            Log.d(TAG, "Harbor EXIT ignored \u2014 no active session for $placeId")
            DebugLogger.d("HARBOR", "EXIT ignored for $placeId \u2014 no active session.", placeId = placeId)
        }
    }

    private fun handleNormalPlaceDwell(
        context: Context,
        dbHelper: DbHelper,
        notificationHelper: NotificationHelper,
        placeId: String,
        label: String,
        hardwareTimestamp: Long,
        processedAt: Long
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val activeHarborId = prefs.getString(KEY_ACTIVE_HARBOR_PLACE_ID, null)
        val lastHarborExit = prefs.getLong(KEY_LAST_HARBOR_EXIT, 0L)

        if (activeHarborId != null) {
            val endTime = if (lastHarborExit > 0) lastHarborExit else hardwareTimestamp
            val result = dbHelper.endVisit(activeHarborId, endTime)
            val durationText =
                if (result != null) formatDuration(result.second) else "some time"
            Log.d(
                TAG,
                "Harbor session ENDED by $placeId ($label). Last harbor exit: $endTime, duration: $durationText"
            )
            val durationMs = if (result != null) result.second * 1000 else 0L
            DebugLogger.i("HARBOR", "Session ENDED by $placeId. Used exit time: $endTime. Duration: ${durationMs}ms",
                placeId = activeHarborId, extra = mapOf("terminating_place" to placeId))

            val harborLabel = dbHelper.getPlaceLabel(activeHarborId) ?: "Harbor"
            notificationHelper.showTransitionNotification(
                "Departed $harborLabel",
                "Harbor tracking ended. Duration: $durationText"
            )
            MainActivity.notifyGeofenceTransition(activeHarborId, "HARBOR_END")

            prefs.edit()
                .remove(KEY_ACTIVE_HARBOR_PLACE_ID)
                .putLong(KEY_LAST_HARBOR_EXIT, 0L)
                .apply()
        } else {
            DebugLogger.d("GEOFENCE", "Normal DWELL at $placeId. No active harbor session.", placeId = placeId)
        }

        val arrivalTimestamp = hardwareTimestamp - LOITERING_DELAY_MS
        Log.d(TAG, "[Normal] DWELL: $placeId ($label) arrival=$arrivalTimestamp hw=$hardwareTimestamp")
        dbHelper.startVisit(placeId, arrivalTimestamp, hardwareTimestamp, processedAt)
        notificationHelper.showTransitionNotification("Arrived", "You arrived at $label")
        MainActivity.notifyGeofenceTransition(placeId, "ENTER")
        WebhookDispatcher.dispatchGeofenceEvent(
            context, "DWELL", placeId,
            null, null, null, null, null,
            hardwareTimestamp, LOITERING_DELAY_MS
        )
    }

    private fun handleNormalPlaceExit(
        context: Context,
        dbHelper: DbHelper,
        notificationHelper: NotificationHelper,
        placeId: String,
        label: String,
        hardwareTimestamp: Long,
        processedAt: Long
    ) {
        Log.d(TAG, "[Normal] EXIT: $placeId ($label) hw=$hardwareTimestamp")
        val result = dbHelper.endVisit(
            placeId, hardwareTimestamp, hardwareTimestamp, processedAt
        )
        val durationText =
            if (result != null) formatDuration(result.second) else "some time"
        notificationHelper.showTransitionNotification(
            "Departed",
            "You left $label \u2014 $durationText"
        )
        MainActivity.notifyGeofenceTransition(placeId, "EXIT")
        WebhookDispatcher.dispatchGeofenceEvent(
            context, "EXIT", placeId,
            null, null, null, null, null,
            hardwareTimestamp, null
        )
    }

    private fun formatDuration(durationS: Long): String {
        val mins = durationS / 60
        if (mins <= 0) return "less than a minute"
        if (mins < 60) return "${mins}m"
        val hrs = mins / 60
        val remMins = mins % 60
        return if (remMins > 0) "${hrs}h ${remMins}m" else "${hrs}h"
    }
}
