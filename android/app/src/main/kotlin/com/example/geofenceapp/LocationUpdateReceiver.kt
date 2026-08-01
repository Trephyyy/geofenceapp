package com.example.geofenceapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource

class LocationUpdateReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "LocationUpdateRec"
        private const val MAX_RETRIES = 3
        private const val ACCURACY_THRESHOLD_M = 20f
        private const val PREFS_KEY_RETRY = "still_snapshot_retry_count"

        fun requestSingleStillFix(context: Context) {
            DebugLogger.init(context)

            val retryCount = context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                .getInt(PREFS_KEY_RETRY, 0)

            DebugLogger.i("LOCATION", "STILL snapshot requested. Retry attempt: $retryCount", extra = mapOf("retry" to retryCount))

            if (retryCount >= MAX_RETRIES) {
                Log.w(TAG, "Max retries ($MAX_RETRIES) reached for STILL snapshot, giving up")
                DebugLogger.e("LOCATION", "STILL fix failed after $MAX_RETRIES attempts. Giving up.")
                context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                    .edit().putInt(PREFS_KEY_RETRY, 0).apply()
                ActivityTransitionReceiver.stopLocationSampling(context)
                return
            }

            if (!ActivityTransitionReceiver.isStillState(context)) {
                Log.d(TAG, "STILL state no longer active, skipping snapshot")
                context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                    .edit().putInt(PREFS_KEY_RETRY, 0).apply()
                return
            }

            Log.d(TAG, "Requesting single high-accuracy STILL snapshot (attempt ${retryCount + 1}/$MAX_RETRIES)")
            val locationClient = LocationServices.getFusedLocationProviderClient(context)
            val cancellationTokenSource = CancellationTokenSource()
            val handler = Handler(Looper.getMainLooper())

            handler.postDelayed({
                cancellationTokenSource.cancel()
            }, 10000)

            locationClient.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cancellationTokenSource.token)
                .addOnSuccessListener { location ->
                    handler.removeCallbacksAndMessages(null)
                    if (location == null) {
                        scheduleRetry(context, retryCount + 1)
                        return@addOnSuccessListener
                    }

                    val accuracy = location.accuracy
                    DebugLogger.i("LOCATION", "STILL fix acquired. Accuracy: ${accuracy}m, source: ${location.provider}",
                        extra = mapOf("accuracy" to (accuracy ?: -1f), "provider" to (location.provider ?: "unknown")))

                    if (accuracy <= ACCURACY_THRESHOLD_M) {
                        val dbHelper = DbHelper(context)
                        dbHelper.insertLearningPoint(
                            location.latitude,
                            location.longitude,
                            System.currentTimeMillis(),
                            "STILL_SNAPSHOT"
                        )
                        dbHelper.close()
                        Log.d(TAG, "STILL_SNAPSHOT saved with accuracy ${accuracy}m")

                        WebhookDispatcher.dispatchStillSnapshot(
                            context,
                            location.latitude,
                            location.longitude,
                            location.accuracy,
                            location.time
                        )

                        context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                            .edit().putInt(PREFS_KEY_RETRY, 0).apply()

                        ActivityTransitionReceiver.stopLocationSampling(context)
                        MainActivity.notifyLearningPointsUpdated()
                    } else {
                        Log.d(TAG, "Accuracy ${accuracy}m exceeds threshold ${ACCURACY_THRESHOLD_M}m, retrying")
                        DebugLogger.w("LOCATION", "STILL fix rejected. Accuracy: ${accuracy}m > ${ACCURACY_THRESHOLD_M}m threshold. Scheduling retry.",
                            extra = mapOf("accuracy" to (accuracy ?: -1f), "threshold" to ACCURACY_THRESHOLD_M))
                        scheduleRetry(context, retryCount + 1)
                    }
                }
                .addOnFailureListener { e ->
                    handler.removeCallbacksAndMessages(null)
                    Log.e(TAG, "STILL snapshot failed", e)
                    DebugLogger.e("LOCATION", "STILL snapshot failed: ${e.message}", throwable = e)
                    scheduleRetry(context, retryCount + 1)
                }
        }

        private fun scheduleRetry(context: Context, retryCount: Int) {
            if (retryCount >= MAX_RETRIES) {
                Log.w(TAG, "Max retries reached, stopping STILL sampling")
                DebugLogger.e("LOCATION", "STILL fix failed after $MAX_RETRIES attempts. Giving up.")
                context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                    .edit().putInt(PREFS_KEY_RETRY, 0).apply()
                ActivityTransitionReceiver.stopLocationSampling(context)
                return
            }

            context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                .edit().putInt(PREFS_KEY_RETRY, retryCount).apply()

            val delayMs = when (retryCount) {
                1 -> 1000L
                2 -> 2000L
                else -> 4000L
            }
            Log.d(TAG, "Scheduling retry $retryCount in ${delayMs}ms")

            val handler = Handler(Looper.getMainLooper())
            handler.postDelayed({
                requestSingleStillFix(context)
            }, delayMs)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (ActivityTransitionReceiver.isStillState(context)) {
            requestSingleStillFix(context)
        }
    }
}