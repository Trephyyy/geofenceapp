package com.example.geofenceapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            DebugLogger.init(context)
            Log.d(TAG, "Device booted or app updated. Restoring geofences and learning tracking.")
            DebugLogger.i("SYSTEM", "Device boot detected. Re-registering geofences and rescheduling workers.")

            if (!PrivacyConsentManager.hasConsent(context)) {
                Log.d(TAG, "Privacy consent not granted, skipping re-registration on boot")
                return
            }

            // Re-register all geofences with updated parameters
            GeofenceManager.reRegisterAllGeofencesFromDb(context)

            // Clean up orphaned harbor state (e.g., after crash)
            val prefs = context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
            val activeHarborId = prefs.getString(
                GeofenceBroadcastReceiver.KEY_ACTIVE_HARBOR_PLACE_ID, null
            )
            if (activeHarborId != null) {
                val dbHelper = DbHelper(context)
                val activeVisit = dbHelper.getActiveVisitForPlace(activeHarborId)
                if (activeVisit == null) {
                    prefs.edit()
                        .remove(GeofenceBroadcastReceiver.KEY_ACTIVE_HARBOR_PLACE_ID)
                        .putLong(GeofenceBroadcastReceiver.KEY_LAST_HARBOR_EXIT, 0L)
                        .apply()
                    Log.w(TAG, "Cleared orphaned harbor state for $activeHarborId")
                    DebugLogger.w("HARBOR", "Cleared orphaned harbor state for $activeHarborId (no matching active visit)",
                        placeId = activeHarborId)
                }
                dbHelper.close()
            }

            // Check if learning mode was active and restart it
            val isLearningActive = prefs.getBoolean("learning_mode_active", false)
            if (isLearningActive) {
                Log.d(TAG, "Learning mode was active, restarting transition updates...")
                GeofenceManager.startActivityRecognition(context)
            }

            // Reschedule webhook dispatch worker
            WebhookWorker.rescheduleOnBoot(context)
        }
    }
}
