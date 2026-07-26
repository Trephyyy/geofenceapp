package com.example.geofenceapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import java.util.concurrent.ConcurrentHashMap

class GeofenceBroadcastReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "GeofenceReceiver"
        private const val HARBOR_DEBOUNCE_MS = 5 * 60 * 1000L // 5 minutes
        // Track if we're inside the geofence for harbor mode (persisted via prefs)
        private val harborEnterTimestamps = ConcurrentHashMap<String, Long>()

        fun isHarborInside(placeId: String): Boolean {
            return harborEnterTimestamps.containsKey(placeId)
        }

        fun setHarborInside(placeId: String, timestamp: Long) {
            harborEnterTimestamps[placeId] = timestamp
        }

        fun clearHarborInside(placeId: String) {
            harborEnterTimestamps.remove(placeId)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    // Pending harbor confirmations keyed by placeId
    private val pendingHarborConfirmations = ConcurrentHashMap<String, Runnable>()

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Geofence transition received")
        val geofencingEvent = GeofencingEvent.fromIntent(intent) ?: return
        if (geofencingEvent.hasError()) {
            Log.e(TAG, "GeofencingEvent error code: ${geofencingEvent.errorCode}")
            return
        }

        val transitionType = geofencingEvent.geofenceTransition
        val triggeringGeofences = geofencingEvent.triggeringGeofences ?: return

        val dbHelper = DbHelper(context)
        val notificationHelper = NotificationHelper(context)
        val currentTime = System.currentTimeMillis()

        for (geofence in triggeringGeofences) {
            val placeId = geofence.requestId
            val label = dbHelper.getPlaceLabel(placeId) ?: "Unknown Place"
            val triggerType = dbHelper.getPlaceTriggerType(placeId) ?: "normal"

            if (triggerType == "harbor") {
                handleHarborTransition(context, dbHelper, notificationHelper, placeId, label, transitionType, currentTime)
            } else {
                handleNormalTransition(dbHelper, notificationHelper, placeId, label, transitionType, currentTime)
            }
        }
        dbHelper.close()
    }

    private fun handleNormalTransition(
        dbHelper: DbHelper,
        notificationHelper: NotificationHelper,
        placeId: String,
        label: String,
        transitionType: Int,
        currentTime: Long
    ) {
        if (transitionType == Geofence.GEOFENCE_TRANSITION_ENTER) {
            Log.d(TAG, "[Normal] ENTER: $placeId ($label)")
            dbHelper.startVisit(placeId, currentTime)
            notificationHelper.showTransitionNotification("Arrived", "You arrived at $label")
            MainActivity.notifyGeofenceTransition(placeId, "ENTER")
        } else if (transitionType == Geofence.GEOFENCE_TRANSITION_EXIT) {
            Log.d(TAG, "[Normal] EXIT: $placeId ($label)")
            val result = dbHelper.endVisit(placeId, currentTime)
            val durationText = if (result != null) formatDuration(result.second) else "some time"
            notificationHelper.showTransitionNotification("Departed", "You left $label \u2014 $durationText")
            MainActivity.notifyGeofenceTransition(placeId, "EXIT")
        }
    }

    private fun handleHarborTransition(
        context: Context,
        dbHelper: DbHelper,
        notificationHelper: NotificationHelper,
        placeId: String,
        label: String,
        transitionType: Int,
        currentTime: Long
    ) {
        if (transitionType == Geofence.GEOFENCE_TRANSITION_ENTER) {
            Log.d(TAG, "[Harbor] ENTER: $placeId ($label)")

            // Check if there's a pending harbor visit waiting for re-enter → exit
            val pendingVisit = dbHelper.getHarborPendingVisit(placeId)
            if (pendingVisit != null) {
                // This is the "re-enter" after leaving - now we need the user to leave again
                // to actually end the visit. Mark this as re-entered.
                Log.d(TAG, "[Harbor] Re-enter detected for place $placeId, waiting for final exit")
                harborEnterTimestamps[placeId] = currentTime
                notificationHelper.showTransitionNotification(
                    "Re-entered",
                    "You re-entered $label. Leave again to stop tracking."
                )
                MainActivity.notifyGeofenceTransition(placeId, "ENTER")
                return
            }

            // Check if we're currently inside (already have an active harbor visit)
            if (harborEnterTimestamps.containsKey(placeId)) {
                Log.d(TAG, "[Harbor] Already inside $placeId, ignoring duplicate enter")
                return
            }

            // First enter: start debounce timer for 5 minutes
            harborEnterTimestamps[placeId] = currentTime

            // Cancel any existing pending confirmation
            pendingHarborConfirmations[placeId]?.let { handler.removeCallbacks(it) }

            val confirmRunnable = Runnable {
                Log.d(TAG, "[Harbor] 5-min debounce passed for $placeId, starting visit")
                val db = DbHelper(context)
                try {
                    // Check if we're still inside (no exit happened during debounce)
                    if (harborEnterTimestamps.containsKey(placeId)) {
                        val existingVisit = db.getHarborPendingVisit(placeId)
                        if (existingVisit == null) {
                            // Start the actual visit after 5min of staying inside
                            db.startHarborPending(placeId, currentTime)
                        }
                        notificationHelper.showTransitionNotification(
                            "Docked at $label",
                            "You've been at $label for 5 minutes. Tracking started."
                        )
                        MainActivity.notifyGeofenceTransition(placeId, "HARBOR_CONFIRMED")
                    }
                } finally {
                    db.close()
                    pendingHarborConfirmations.remove(placeId)
                }
            }
            pendingHarborConfirmations[placeId] = confirmRunnable
            handler.postDelayed(confirmRunnable, HARBOR_DEBOUNCE_MS)

            notificationHelper.showTransitionNotification(
                "Entered $label",
                "Stay for 5 minutes to start tracking (Harbor mode)"
            )
            MainActivity.notifyGeofenceTransition(placeId, "HARBOR_PENDING")

        } else if (transitionType == Geofence.GEOFENCE_TRANSITION_EXIT) {
            Log.d(TAG, "[Harbor] EXIT: $placeId ($label)")

            // Cancel any pending 5-min confirmation
            pendingHarborConfirmations[placeId]?.let {
                handler.removeCallbacks(it)
                pendingHarborConfirmations.remove(placeId)
            }

            val pendingVisit = dbHelper.getHarborPendingVisit(placeId)

            // Check if we have a re-enter marker (this means the visit is active and we just re-entered)
            val wasInside = harborEnterTimestamps.containsKey(placeId)
            harborEnterTimestamps.remove(placeId)

            if (pendingVisit != null) {
                if (wasInside) {
                    // We re-entered and now we're leaving again - END the visit
                    Log.d(TAG, "[Harbor] Final exit detected for place $placeId, ending visit")
                    val result = dbHelper.endHarborVisit(pendingVisit.first, currentTime, pendingVisit.second)
                    val durationText = if (result != null) formatDuration(result.second) else "some time"
                    notificationHelper.showTransitionNotification(
                        "Departed $label",
                        "You left $label after $durationText (Harbor mode)"
                    )
                    MainActivity.notifyGeofenceTransition(placeId, "EXIT")
                } else {
                    // First exit after visit started - we're leaving the harbor on the ship
                    // Don't end the visit yet - wait for re-enter → exit
                    Log.d(TAG, "[Harbor] First exit for place $placeId, keeping visit alive")
                    notificationHelper.showTransitionNotification(
                        "Left harbor",
                        "Visit continues until you return and leave again."
                    )
                }
            } else {
                // No active harbor visit - if we left before 5 min debounce, nothing to do
                Log.d(TAG, "[Harbor] Exit without active visit for $placeId")
            }
        }
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
