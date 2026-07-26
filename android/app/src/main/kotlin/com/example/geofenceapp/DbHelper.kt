package com.example.geofenceapp

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.io.File
import java.util.UUID

class DbHelper(private val context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val TAG = "DbHelper"
        private const val DATABASE_NAME = "geofence.db"
        private const val DATABASE_VERSION = 2

        // Tables
        const val TABLE_PLACES = "places"
        const val TABLE_VISITS = "visits"
        const val TABLE_LEARNING_POINTS = "learning_points"

        // Places columns
        const val COL_PLACE_TRIGGER_TYPE = "trigger_type"

        const val COL_PLACE_ID = "id"
        const val COL_PLACE_SERVER_ID = "server_id"
        const val COL_PLACE_LABEL = "label"
        const val COL_PLACE_ICON = "icon"
        const val COL_PLACE_LAT = "lat"
        const val COL_PLACE_LNG = "lng"
        const val COL_PLACE_RADIUS = "radius_m"
        const val COL_PLACE_STATUS = "status"
        const val COL_PLACE_CREATED = "created_at"
        const val COL_PLACE_UPDATED = "updated_at"
        const val COL_PLACE_DIRTY = "dirty"

        // Visits columns
        const val COL_VISIT_ID = "id"
        const val COL_VISIT_SERVER_ID = "server_id"
        const val COL_VISIT_PLACE_ID = "place_id"
        const val COL_VISIT_ENTER = "enter_ts"
        const val COL_VISIT_EXIT = "exit_ts"
        const val COL_VISIT_DURATION = "duration_s"
        const val COL_VISIT_SOURCE = "source"
        const val COL_VISIT_DIRTY = "dirty"

        // Learning points columns
        const val COL_LP_LAT = "lat"
        const val COL_LP_LNG = "lng"
        const val COL_LP_TIMESTAMP = "timestamp"
    }

    override fun onCreate(db: SQLiteDatabase) {
        Log.d(TAG, "Creating database tables")

        val createPlacesTable = """
            CREATE TABLE IF NOT EXISTS $TABLE_PLACES (
                $COL_PLACE_ID TEXT PRIMARY KEY,
                $COL_PLACE_SERVER_ID TEXT,
                $COL_PLACE_LABEL TEXT NOT NULL,
                $COL_PLACE_ICON TEXT NOT NULL,
                $COL_PLACE_LAT REAL NOT NULL,
                $COL_PLACE_LNG REAL NOT NULL,
                $COL_PLACE_RADIUS REAL NOT NULL,
                $COL_PLACE_STATUS TEXT NOT NULL,
                $COL_PLACE_TRIGGER_TYPE TEXT NOT NULL DEFAULT 'normal',
                $COL_PLACE_CREATED TEXT NOT NULL,
                $COL_PLACE_UPDATED TEXT NOT NULL,
                $COL_PLACE_DIRTY INTEGER NOT NULL DEFAULT 0
            )
        """.trimIndent()

        val createVisitsTable = """
            CREATE TABLE IF NOT EXISTS $TABLE_VISITS (
                $COL_VISIT_ID TEXT PRIMARY KEY,
                $COL_VISIT_SERVER_ID TEXT,
                $COL_VISIT_PLACE_ID TEXT NOT NULL,
                $COL_VISIT_ENTER INTEGER NOT NULL,
                $COL_VISIT_EXIT INTEGER,
                $COL_VISIT_DURATION INTEGER,
                $COL_VISIT_SOURCE TEXT NOT NULL,
                $COL_VISIT_DIRTY INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY($COL_VISIT_PLACE_ID) REFERENCES $TABLE_PLACES($COL_PLACE_ID) ON DELETE CASCADE
            )
        """.trimIndent()

        val createLearningPointsTable = """
            CREATE TABLE IF NOT EXISTS $TABLE_LEARNING_POINTS (
                $COL_LP_LAT REAL NOT NULL,
                $COL_LP_LNG REAL NOT NULL,
                $COL_LP_TIMESTAMP INTEGER NOT NULL
            )
        """.trimIndent()

        db.execSQL(createPlacesTable)
        db.execSQL(createVisitsTable)
        db.execSQL(createLearningPointsTable)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            try {
                db.execSQL("ALTER TABLE $TABLE_PLACES ADD COLUMN $COL_PLACE_TRIGGER_TYPE TEXT NOT NULL DEFAULT 'normal'")
            } catch (_: Exception) { }
        }
    }

    // Insert a learning point
    fun insertLearningPoint(lat: Double, lng: Double, timestamp: Long) {
        try {
            val db = writableDatabase
            val values = ContentValues().apply {
                put(COL_LP_LAT, lat)
                put(COL_LP_LNG, lng)
                put(COL_LP_TIMESTAMP, timestamp)
            }
            db.insert(TABLE_LEARNING_POINTS, null, values)
            Log.d(TAG, "Learning point inserted: ($lat, $lng) at $timestamp")
        } catch (e: Exception) {
            Log.e(TAG, "Error inserting learning point", e)
        }
    }

    // Get place label from ID
    fun getPlaceLabel(placeId: String): String? {
        try {
            val db = readableDatabase
            val cursor = db.query(
                TABLE_PLACES,
                arrayOf(COL_PLACE_LABEL),
                "$COL_PLACE_ID = ?",
                arrayOf(placeId),
                null, null, null
            )
            var label: String? = null
            if (cursor.moveToFirst()) {
                label = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LABEL))
            }
            cursor.close()
            return label
        } catch (e: Exception) {
            Log.e(TAG, "Error getting place label for $placeId", e)
            return null
        }
    }

    // Record ENTER transition -> starts a visit
    fun startVisit(placeId: String, enterTimestamp: Long): String? {
        try {
            val db = writableDatabase

            // Check if there's already an active (unclosed) visit for this place
            // to avoid duplicates due to OS geofence re-triggers
            val checkCursor = db.query(
                TABLE_VISITS,
                arrayOf(COL_VISIT_ID),
                "$COL_VISIT_PLACE_ID = ? AND $COL_VISIT_EXIT IS NULL",
                arrayOf(placeId),
                null, null, null
            )
            if (checkCursor.moveToFirst()) {
                val activeId = checkCursor.getString(checkCursor.getColumnIndexOrThrow(COL_VISIT_ID))
                checkCursor.close()
                Log.d(TAG, "Visit already active for place $placeId: $activeId")
                return activeId
            }
            checkCursor.close()

            val visitId = UUID.randomUUID().toString()
            val values = ContentValues().apply {
                put(COL_VISIT_ID, visitId)
                put(COL_VISIT_PLACE_ID, placeId)
                put(COL_VISIT_ENTER, enterTimestamp)
                put(COL_VISIT_SOURCE, "geofence")
                put(COL_VISIT_DIRTY, 1)
            }
            db.insert(TABLE_VISITS, null, values)
            Log.d(TAG, "Visit started: $visitId for place $placeId")
            return visitId
        } catch (e: Exception) {
            Log.e(TAG, "Error starting visit", e)
            return null
        }
    }

    // Record EXIT transition -> closes active visit
    fun endVisit(placeId: String, exitTimestamp: Long): Pair<String, Long>? {
        try {
            val db = writableDatabase

            // Find the latest active visit for this place
            val cursor = db.query(
                TABLE_VISITS,
                arrayOf(COL_VISIT_ID, COL_VISIT_ENTER),
                "$COL_VISIT_PLACE_ID = ? AND $COL_VISIT_EXIT IS NULL",
                arrayOf(placeId),
                null, null, "$COL_VISIT_ENTER DESC", "1"
            )

            var result: Pair<String, Long>? = null
            if (cursor.moveToFirst()) {
                val visitId = cursor.getString(cursor.getColumnIndexOrThrow(COL_VISIT_ID))
                val enterTs = cursor.getLong(cursor.getColumnIndexOrThrow(COL_VISIT_ENTER))
                val durationS = (exitTimestamp - enterTs) / 1000

                val values = ContentValues().apply {
                    put(COL_VISIT_EXIT, exitTimestamp)
                    put(COL_VISIT_DURATION, durationS)
                    put(COL_VISIT_DIRTY, 1)
                }
                db.update(TABLE_VISITS, values, "$COL_VISIT_ID = ?", arrayOf(visitId))
                Log.d(TAG, "Visit ended: $visitId, duration: ${durationS}s")
                result = Pair(visitId, durationS)
            } else {
                Log.d(TAG, "No active visit found to end for place $placeId, inserting manual exit entry")
                // If no active visit is found, we might have missed the entry event. Let's create a completed visit from 10 minutes ago
                val visitId = UUID.randomUUID().toString()
                val enterTs = exitTimestamp - (10 * 60 * 1000) // 10 minutes ago
                val durationS = 600L
                val values = ContentValues().apply {
                    put(COL_VISIT_ID, visitId)
                    put(COL_VISIT_PLACE_ID, placeId)
                    put(COL_VISIT_ENTER, enterTs)
                    put(COL_VISIT_EXIT, exitTimestamp)
                    put(COL_VISIT_DURATION, durationS)
                    put(COL_VISIT_SOURCE, "geofence")
                    put(COL_VISIT_DIRTY, 1)
                }
                db.insert(TABLE_VISITS, null, values)
                result = Pair(visitId, durationS)
            }
            cursor.close()
            return result
        } catch (e: Exception) {
            Log.e(TAG, "Error ending visit", e)
            return null
        }
    }

    // Get list of active/confirmed places to re-register geofences
    fun getPlaceTriggerType(placeId: String): String? {
        try {
            val db = readableDatabase
            val cursor = db.query(
                TABLE_PLACES,
                arrayOf(COL_PLACE_TRIGGER_TYPE),
                "$COL_PLACE_ID = ?",
                arrayOf(placeId),
                null, null, null
            )
            var triggerType: String? = null
            if (cursor.moveToFirst()) {
                triggerType = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_TRIGGER_TYPE))
            }
            cursor.close()
            return triggerType
        } catch (e: Exception) {
            Log.e(TAG, "Error getting place trigger type for $placeId", e)
            return null
        }
    }

    fun getConfirmedPlaces(): List<PlaceData> {
        val list = mutableListOf<PlaceData>()
        try {
            val db = readableDatabase
            val cursor = db.query(
                TABLE_PLACES,
                arrayOf(COL_PLACE_ID, COL_PLACE_LABEL, COL_PLACE_LAT, COL_PLACE_LNG, COL_PLACE_RADIUS, COL_PLACE_TRIGGER_TYPE),
                "$COL_PLACE_STATUS = ?",
                arrayOf("confirmed"),
                null, null, null
            )
            while (cursor.moveToNext()) {
                val id = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_ID))
                val label = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LABEL))
                val lat = cursor.getDouble(cursor.getColumnIndexOrThrow(COL_PLACE_LAT))
                val lng = cursor.getDouble(cursor.getColumnIndexOrThrow(COL_PLACE_LNG))
                val radius = cursor.getFloat(cursor.getColumnIndexOrThrow(COL_PLACE_RADIUS))
                val triggerType = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_TRIGGER_TYPE))
                list.add(PlaceData(id, label, lat, lng, radius, triggerType))
            }
            cursor.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error getting confirmed places", e)
        }
        return list
    }

    // Harbor mode: check if this place has a "harbor" visit that has entered but not yet been completed
    fun getHarborPendingVisit(placeId: String): Pair<String, Long>? {
        try {
            val db = readableDatabase
            // In harbor mode, we look for a visit that has been started (enter_ts set)
            // AND has an exit_ts (from the first exit) but no second enter
            // We use a special source marker to identify harbor visits
            val cursor = db.query(
                TABLE_VISITS,
                arrayOf(COL_VISIT_ID, COL_VISIT_ENTER),
                "$COL_VISIT_PLACE_ID = ? AND $COL_VISIT_SOURCE = 'harbor_pending'",
                arrayOf(placeId),
                null, null, "$COL_VISIT_ENTER DESC", "1"
            )
            var result: Pair<String, Long>? = null
            if (cursor.moveToFirst()) {
                val visitId = cursor.getString(cursor.getColumnIndexOrThrow(COL_VISIT_ID))
                val enterTs = cursor.getLong(cursor.getColumnIndexOrThrow(COL_VISIT_ENTER))
                result = Pair(visitId, enterTs)
            }
            cursor.close()
            return result
        } catch (e: Exception) {
            Log.e(TAG, "Error getting harbor pending visit", e)
            return null
        }
    }

    // Harbor mode: start a "pending" harbor visit (enter event but waiting for 5 min)
    fun startHarborPending(placeId: String, timestamp: Long): String? {
        try {
            val db = writableDatabase
            val visitId = UUID.randomUUID().toString()
            val values = ContentValues().apply {
                put(COL_VISIT_ID, visitId)
                put(COL_VISIT_PLACE_ID, placeId)
                put(COL_VISIT_ENTER, timestamp)
                put(COL_VISIT_SOURCE, "harbor_pending")
                put(COL_VISIT_DIRTY, 1)
            }
            db.insert(TABLE_VISITS, null, values)
            Log.d(TAG, "Harbor pending visit started: $visitId for place $placeId")
            return visitId
        } catch (e: Exception) {
            Log.e(TAG, "Error starting harbor pending visit", e)
            return null
        }
    }

    // Harbor mode: promote pending visit to real visit (after 5 min inside)
    fun confirmHarborVisit(visitId: String) {
        try {
            val db = writableDatabase
            val values = ContentValues().apply {
                put(COL_VISIT_SOURCE, "geofence")
            }
            db.update(TABLE_VISITS, values, "$COL_VISIT_ID = ?", arrayOf(visitId))
            Log.d(TAG, "Harbor visit confirmed: $visitId")
        } catch (e: Exception) {
            Log.e(TAG, "Error confirming harbor visit", e)
        }
    }

    // Harbor mode: remove pending visit (user left before 5 min)
    fun cancelHarborPending(visitId: String) {
        try {
            val db = writableDatabase
            db.delete(TABLE_VISITS, "$COL_VISIT_ID = ?", arrayOf(visitId))
            Log.d(TAG, "Harbor pending visit cancelled: $visitId")
        } catch (e: Exception) {
            Log.e(TAG, "Error cancelling harbor pending visit", e)
        }
    }

    // Harbor mode: close the visit when re-enter → exit cycle completes
    fun endHarborVisit(visitId: String, exitTimestamp: Long, enterTs: Long): Pair<String, Long>? {
        try {
            val db = writableDatabase
            val durationS = (exitTimestamp - enterTs) / 1000
            val values = ContentValues().apply {
                put(COL_VISIT_EXIT, exitTimestamp)
                put(COL_VISIT_DURATION, durationS)
                put(COL_VISIT_SOURCE, "geofence")
                put(COL_VISIT_DIRTY, 1)
            }
            db.update(TABLE_VISITS, values, "$COL_VISIT_ID = ?", arrayOf(visitId))
            Log.d(TAG, "Harbor visit ended: $visitId, duration: ${durationS}s")
            return Pair(visitId, durationS)
        } catch (e: Exception) {
            Log.e(TAG, "Error ending harbor visit", e)
            return null
        }
    }
}

data class PlaceData(
    val id: String,
    val label: String,
    val lat: Double,
    val lng: Double,
    val radius: Float,
    val triggerType: String = "normal"
)
