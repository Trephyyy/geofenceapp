package com.example.geofenceapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.LocationResult

class LocationUpdateReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "LocationUpdateRec"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Location update received")
        if (LocationResult.hasResult(intent)) {
            val result = LocationResult.extractResult(intent) ?: return
            
            // Check if STILL state is active
            if (ActivityTransitionReceiver.isStillState(context)) {
                val dbHelper = DbHelper(context)
                for (location in result.locations) {
                    dbHelper.insertLearningPoint(
                        location.latitude,
                        location.longitude,
                        System.currentTimeMillis()
                    )
                    Log.d(TAG, "Saved STILL learning point: ${location.latitude}, ${location.longitude}")
                }
                dbHelper.close()
                
                // Notify MainActivity that a new learning point is available
                MainActivity.notifyLearningPointsUpdated()
            } else {
                Log.d(TAG, "Location update received but state is not STILL. Removing updates.")
                ActivityTransitionReceiver.stopLocationSampling(context)
            }
        }
    }
}
