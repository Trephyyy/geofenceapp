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
            Log.d(TAG, "Device booted or app updated. Restoring geofences and learning tracking.")
            
            // Re-register all geofences
            val dbHelper = DbHelper(context)
            val confirmedPlaces = dbHelper.getConfirmedPlaces()
            dbHelper.close()

            if (confirmedPlaces.isNotEmpty()) {
                Log.d(TAG, "Re-registering ${confirmedPlaces.size} geofences...")
                GeofenceManager.registerAllGeofences(context, confirmedPlaces)
            }

            // Check if learning mode was active and restart it
            val prefs = context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
            val isLearningActive = prefs.getBoolean("learning_mode_active", false)
            if (isLearningActive) {
                Log.d(TAG, "Learning mode was active, restarting transition updates...")
                GeofenceManager.startActivityRecognition(context)
            }
        }
    }
}
