package com.example.geofenceapp

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

class ActivityTransitionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ActivityTransitionRec"

        fun setStillState(context: Context, isStill: Boolean) {
            val prefs = context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("is_still", isStill).apply()
            Log.d(TAG, "is_still set to $isStill")
        }

        fun isStillState(context: Context): Boolean {
            val prefs = context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
            return prefs.getBoolean("is_still", false)
        }

        fun getLocationPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, LocationUpdateReceiver::class.java)
            return PendingIntent.getBroadcast(
                context,
                2001,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
        }

        fun startLocationSampling(context: Context) {
            Log.d(TAG, "Starting location sampling...")
            val locationClient = LocationServices.getFusedLocationProviderClient(context)
            
            // Build balanced power accuracy request for 10 minutes interval
            val locationRequest = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 10 * 60 * 1000L)
                .setMinUpdateIntervalMillis(5 * 60 * 1000L)
                .setMaxUpdateDelayMillis(10 * 60 * 1000L)
                .build()

            try {
                locationClient.requestLocationUpdates(locationRequest, getLocationPendingIntent(context))
                Log.d(TAG, "Location updates requested successfully")
                
                // Immediately grab the current location to bootstrap this still session
                locationClient.lastLocation.addOnSuccessListener { location ->
                    if (location != null) {
                        saveLearningPoint(context, location.latitude, location.longitude)
                    } else {
                        // If last location is null, try to query current location
                        locationClient.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null)
                            .addOnSuccessListener { curLoc ->
                                if (curLoc != null) {
                                    saveLearningPoint(context, curLoc.latitude, curLoc.longitude)
                                }
                            }
                    }
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "Cannot start location updates due to missing permission", e)
            }
        }

        fun stopLocationSampling(context: Context) {
            Log.d(TAG, "Stopping location sampling...")
            val locationClient = LocationServices.getFusedLocationProviderClient(context)
            try {
                locationClient.removeLocationUpdates(getLocationPendingIntent(context))
                Log.d(TAG, "Location updates removed successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error removing location updates", e)
            }
        }

        private fun saveLearningPoint(context: Context, lat: Double, lng: Double) {
            val dbHelper = DbHelper(context)
            dbHelper.insertLearningPoint(lat, lng, System.currentTimeMillis())
            dbHelper.close()
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Received activity transition intent")
        if (ActivityTransitionResult.hasResult(intent)) {
            val result = ActivityTransitionResult.extractResult(intent) ?: return
            for (event in result.transitionEvents) {
                if (event.activityType == DetectedActivity.STILL) {
                    if (event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER) {
                        Log.d(TAG, "Activity Transition: ENTER STILL")
                        setStillState(context, true)
                        startLocationSampling(context)
                    } else if (event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_EXIT) {
                        Log.d(TAG, "Activity Transition: EXIT STILL")
                        setStillState(context, false)
                        stopLocationSampling(context)
                    }
                }
            }
        }
    }
}
