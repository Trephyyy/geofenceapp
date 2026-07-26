package com.example.geofenceapp

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

object GeofenceManager {
    private const val TAG = "GeofenceManager"

    fun registerGeofence(context: Context, id: String, lat: Double, lng: Double, radius: Float) {
        Log.d(TAG, "Registering geofence: $id at ($lat, $lng) with radius ${radius}m")
        val geofencingClient = LocationServices.getGeofencingClient(context)
        
        val geofence = Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(lat, lng, radius)
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .build()

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        try {
            geofencingClient.addGeofences(request, pendingIntent)
                .addOnSuccessListener {
                    Log.d(TAG, "Geofence added successfully: $id")
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Failed to add geofence: $id", e)
                }
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException adding geofence: $id", e)
        }
    }

    fun unregisterGeofence(context: Context, id: String) {
        Log.d(TAG, "Unregistering geofence: $id")
        val geofencingClient = LocationServices.getGeofencingClient(context)
        
        // Remove by request ID
        geofencingClient.removeGeofences(listOf(id))
            .addOnSuccessListener {
                Log.d(TAG, "Geofence removed by ID successfully: $id")
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Failed to remove geofence by ID: $id", e)
            }
    }

    fun registerAllGeofences(context: Context, places: List<PlaceData>) {
        Log.d(TAG, "Registering ${places.size} geofences...")
        for (place in places) {
            registerGeofence(context, place.id, place.lat, place.lng, place.radius)
        }
    }

    fun startActivityRecognition(context: Context) {
        Log.d(TAG, "Registering Activity Recognition Transitions")
        val activityRecognitionClient = ActivityRecognition.getClient(context)
        
        val transitions = mutableListOf<ActivityTransition>()
        transitions.add(
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.STILL)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build()
        )
        transitions.add(
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.STILL)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_EXIT)
                .build()
        )

        val request = ActivityTransitionRequest(transitions)
        val intent = Intent(context, ActivityTransitionReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            1002,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        try {
            activityRecognitionClient.requestActivityTransitionUpdates(request, pendingIntent)
                .addOnSuccessListener {
                    Log.d(TAG, "Activity transitions requested successfully")
                    val prefs = context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("learning_mode_active", true).apply()
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Failed to request activity transitions", e)
                }
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException requesting activity transitions", e)
        }
    }

    fun stopActivityRecognition(context: Context) {
        Log.d(TAG, "Unregistering Activity Recognition Transitions")
        val activityRecognitionClient = ActivityRecognition.getClient(context)
        val intent = Intent(context, ActivityTransitionReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            1002,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        try {
            activityRecognitionClient.removeActivityTransitionUpdates(pendingIntent)
                .addOnSuccessListener {
                    Log.d(TAG, "Activity transitions removed successfully")
                    val prefs = context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("learning_mode_active", false).apply()
                    
                    // Stop ongoing location sampling
                    ActivityTransitionReceiver.setStillState(context, false)
                    ActivityTransitionReceiver.stopLocationSampling(context)
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Failed to remove activity transitions", e)
                }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing activity transitions", e)
        }
    }
}
