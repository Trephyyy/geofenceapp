package com.example.geofenceapp

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log

class DbHelper(context: Context) : SQLiteOpenHelper(
    context, DATABASE_NAME, null, DATABASE_VERSION
) {
    companion object {
        private const val TAG = "DbHelper"
        private const val DATABASE_NAME = "geofence.db"
        private const val DATABASE_VERSION = 8

        const val TABLE_PLACES = "places"
        const val TABLE_VISITS = "visits"
        const val TABLE_LEARNING_POINTS = "learning_points"
        const val TABLE_LOCATION_LOGS = "location_logs"
        const val TABLE_GEOFENCE_TRANSITIONS = "geofence_transitions"
        const val TABLE_WEBHOOK_QUEUE = "webhook_queue"
        const val MAX_QUEUED_ROWS = 1000
        const val TABLE_DEBUG_LOGS = "debug_logs"

        const val COL_PLACE_TRIGGER_TYPE = "trigger_type"
        const val COL_PLACE_ID = "id"
        const val COL_PLACE_SERVER_ID = "server_id"
        const val COL_PLACE_LABEL = "label"
        const val COL_PLACE_ICON = "icon"
        const val COL_PLACE_LAT = "lat"
        const val COL_PLACE_LNG = "lng"
        const val COL_PLACE_LAT_ENCRYPTED = "lat_encrypted"
        const val COL_PLACE_LNG_ENCRYPTED = "lng_encrypted"
        const val COL_PLACE_RADIUS = "radius_m"
        const val COL_PLACE_STATUS = "status"
        const val COL_PLACE_CREATED = "created_at"
        const val COL_PLACE_UPDATED = "updated_at"
        const val COL_PLACE_DIRTY = "dirty"

        const val COL_VISIT_ID = "id"
        const val COL_VISIT_SERVER_ID = "server_id"
        const val COL_VISIT_PLACE_ID = "place_id"
        const val COL_VISIT_ENTER = "enter_ts"
        const val COL_VISIT_EXIT = "exit_ts"
        const val COL_VISIT_DURATION = "duration_s"
        const val COL_VISIT_SOURCE = "source"
        const val COL_VISIT_DIRTY = "dirty"
        const val COL_VISIT_EVENT_TIMESTAMP = "event_timestamp"
        const val COL_VISIT_PROCESSED_AT = "processed_at"

        const val COL_LP_LAT = "lat"
        const val COL_LP_LNG = "lng"
        const val COL_LP_LAT_ENCRYPTED = "lat_encrypted"
        const val COL_LP_LNG_ENCRYPTED = "lng_encrypted"
        const val COL_LP_TIMESTAMP = "timestamp"
        const val COL_LP_SOURCE = "source"

        const val COL_LL_ID = "id"
        const val COL_LL_LAT_ENCRYPTED = "lat_encrypted"
        const val COL_LL_LNG_ENCRYPTED = "lng_encrypted"
        const val COL_LL_ACCURACY = "accuracy"
        const val COL_LL_ALTITUDE = "altitude"
        const val COL_LL_SPEED = "speed"
        const val COL_LL_TIMESTAMP_HW = "timestamp_hw"
        const val COL_LL_TIMESTAMP_SYSTEM = "timestamp_system"
        const val COL_LL_SOURCE = "source"

        const val COL_GT_ID = "id"
        const val COL_GT_PLACE_ID = "place_id"
        const val COL_GT_TRANSITION_TYPE = "transition_type"
        const val COL_GT_TIMESTAMP_HW = "timestamp_hw"
        const val COL_GT_TIMESTAMP_SYSTEM = "timestamp_system"
        const val COL_GT_ACCURACY = "accuracy"
        const val COL_GT_DWELL_DURATION_MS = "dwell_duration_ms"

        const val COL_WQ_ID = "id"
        const val COL_WQ_PAYLOAD_ENCRYPTED = "payload_encrypted"
        const val COL_WQ_ENDPOINT_URL_ENCRYPTED = "endpoint_url_encrypted"
        const val COL_WQ_HEADERS_ENCRYPTED = "headers_encrypted"
        const val COL_WQ_RETRY_COUNT = "retry_count"
        const val COL_WQ_CREATED_AT = "created_at"
        const val COL_WQ_SCHEDULED_AT = "scheduled_at"
    }

    private val cryptoManager = CryptoManager

    override fun onCreate(db: SQLiteDatabase) {
        Log.d(TAG, "Creating database tables")

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS $TABLE_PLACES (
                $COL_PLACE_ID TEXT PRIMARY KEY,
                $COL_PLACE_SERVER_ID TEXT,
                $COL_PLACE_LABEL TEXT NOT NULL,
                $COL_PLACE_ICON TEXT NOT NULL,
                $COL_PLACE_LAT_ENCRYPTED TEXT NOT NULL,
                $COL_PLACE_LNG_ENCRYPTED TEXT NOT NULL,
                $COL_PLACE_RADIUS REAL NOT NULL,
                $COL_PLACE_STATUS TEXT NOT NULL,
                $COL_PLACE_TRIGGER_TYPE TEXT NOT NULL DEFAULT 'normal',
                $COL_PLACE_CREATED TEXT NOT NULL,
                $COL_PLACE_UPDATED TEXT NOT NULL,
                $COL_PLACE_DIRTY INTEGER NOT NULL DEFAULT 0
            )
        """.trimIndent())

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS $TABLE_VISITS (
                $COL_VISIT_ID TEXT PRIMARY KEY,
                $COL_VISIT_SERVER_ID TEXT,
                $COL_VISIT_PLACE_ID TEXT NOT NULL,
                $COL_VISIT_ENTER INTEGER NOT NULL,
                $COL_VISIT_EXIT INTEGER,
                $COL_VISIT_DURATION INTEGER,
                $COL_VISIT_SOURCE TEXT NOT NULL,
                $COL_VISIT_DIRTY INTEGER NOT NULL DEFAULT 0,
                $COL_VISIT_EVENT_TIMESTAMP INTEGER,
                $COL_VISIT_PROCESSED_AT INTEGER,
                FOREIGN KEY($COL_VISIT_PLACE_ID) REFERENCES $TABLE_PLACES($COL_PLACE_ID) ON DELETE CASCADE
            )
        """.trimIndent())

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS $TABLE_LEARNING_POINTS (
                $COL_LP_LAT_ENCRYPTED TEXT NOT NULL,
                $COL_LP_LNG_ENCRYPTED TEXT NOT NULL,
                $COL_LP_TIMESTAMP INTEGER NOT NULL,
                $COL_LP_SOURCE TEXT NOT NULL DEFAULT 'LEARNING'
            )
        """.trimIndent())

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS $TABLE_LOCATION_LOGS (
                $COL_LL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_LL_LAT_ENCRYPTED TEXT NOT NULL,
                $COL_LL_LNG_ENCRYPTED TEXT NOT NULL,
                $COL_LL_ACCURACY REAL,
                $COL_LL_ALTITUDE REAL,
                $COL_LL_SPEED REAL,
                $COL_LL_TIMESTAMP_HW INTEGER NOT NULL,
                $COL_LL_TIMESTAMP_SYSTEM INTEGER NOT NULL,
                $COL_LL_SOURCE TEXT NOT NULL
            )
        """.trimIndent())

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS $TABLE_GEOFENCE_TRANSITIONS (
                $COL_GT_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_GT_PLACE_ID TEXT NOT NULL,
                $COL_GT_TRANSITION_TYPE TEXT NOT NULL,
                $COL_GT_TIMESTAMP_HW INTEGER NOT NULL,
                $COL_GT_TIMESTAMP_SYSTEM INTEGER NOT NULL,
                $COL_GT_ACCURACY REAL,
                $COL_GT_DWELL_DURATION_MS INTEGER
            )
        """.trimIndent())

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS $TABLE_WEBHOOK_QUEUE (
                $COL_WQ_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_WQ_PAYLOAD_ENCRYPTED TEXT NOT NULL,
                $COL_WQ_ENDPOINT_URL_ENCRYPTED TEXT NOT NULL,
                $COL_WQ_HEADERS_ENCRYPTED TEXT,
                $COL_WQ_RETRY_COUNT INTEGER NOT NULL DEFAULT 0,
                $COL_WQ_CREATED_AT INTEGER NOT NULL,
                $COL_WQ_SCHEDULED_AT INTEGER NOT NULL
            )
        """.trimIndent())

        db.execSQL("""
            CREATE TABLE IF NOT EXISTS $TABLE_DEBUG_LOGS (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                level TEXT NOT NULL,
                category TEXT NOT NULL,
                message TEXT NOT NULL,
                place_id TEXT,
                extra_json TEXT
            )
        """.trimIndent())
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            try {
                db.execSQL("ALTER TABLE $TABLE_PLACES ADD COLUMN $COL_PLACE_TRIGGER_TYPE TEXT NOT NULL DEFAULT 'normal'")
            } catch (_: Exception) { }
        }
        if (oldVersion < 3) {
            try {
                db.execSQL("ALTER TABLE $TABLE_LEARNING_POINTS ADD COLUMN $COL_LP_SOURCE TEXT NOT NULL DEFAULT 'LEARNING'")
            } catch (_: Exception) { }
            try {
                db.execSQL("ALTER TABLE $TABLE_VISITS ADD COLUMN $COL_VISIT_EVENT_TIMESTAMP INTEGER")
            } catch (_: Exception) { }
            try {
                db.execSQL("ALTER TABLE $TABLE_VISITS ADD COLUMN $COL_VISIT_PROCESSED_AT INTEGER")
            } catch (_: Exception) { }
        }
        if (oldVersion < 4) {
            try {
                db.execSQL("""
                    CREATE TABLE IF NOT EXISTS $TABLE_LOCATION_LOGS (
                        id TEXT PRIMARY KEY,
                        lat REAL NOT NULL,
                        lng REAL NOT NULL,
                        accuracy REAL,
                        altitude REAL,
                        speed REAL,
                        timestamp_hw INTEGER,
                        timestamp_system INTEGER NOT NULL,
                        source TEXT NOT NULL DEFAULT 'UNKNOWN',
                        encrypted_payload TEXT
                    )
                """.trimIndent())
            } catch (_: Exception) { }
            try {
                db.execSQL("""
                    CREATE TABLE IF NOT EXISTS $TABLE_GEOFENCE_TRANSITIONS (
                        id TEXT PRIMARY KEY,
                        place_id TEXT NOT NULL,
                        transition_type TEXT NOT NULL,
                        timestamp_hw INTEGER,
                        timestamp_system INTEGER NOT NULL,
                        accuracy REAL,
                        dwell_duration_ms INTEGER
                    )
                """.trimIndent())
            } catch (_: Exception) { }
            try {
                db.execSQL("""
                    CREATE TABLE IF NOT EXISTS $TABLE_WEBHOOK_QUEUE (
                        id TEXT PRIMARY KEY,
                        payload_json TEXT NOT NULL,
                        endpoint_url TEXT NOT NULL,
                        headers_json TEXT,
                        retry_count INTEGER NOT NULL DEFAULT 0,
                        created_at INTEGER NOT NULL,
                        scheduled_at INTEGER NOT NULL
                    )
                """.trimIndent())
            } catch (_: Exception) { }
        }
        if (oldVersion < 5) {
            migrateToV5(db)
        }
        if (oldVersion < 6) {
            migrateToV6(db)
        }
        if (oldVersion < 7) {
            migrateToV7(db)
        }
        if (oldVersion < 8) {
            migrateToV8(db)
        }
    }

    private fun migrateToV5(db: SQLiteDatabase) {
        val hasPlaintextLatLng = checkColumnExists(db, TABLE_LOCATION_LOGS, "lat")
        val hasPlaintextWebhook = checkColumnExists(db, TABLE_WEBHOOK_QUEUE, "payload_json")
        val hasPlaintextGt = hasPlaintextLatLng ||
                checkColumnExists(db, TABLE_GEOFENCE_TRANSITIONS, COL_GT_ID) &&
                !checkColumnExists(db, TABLE_GEOFENCE_TRANSITIONS, COL_GT_TIMESTAMP_SYSTEM)

        db.beginTransaction()
        try {
            if (hasPlaintextLatLng) {
                migrateLocationLogs(db)
            }
            if (hasPlaintextWebhook) {
                migrateWebhookQueue(db)
            }
            if (hasPlaintextGt) {
                migrateGeofenceTransitions(db)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun migrateToV6(db: SQLiteDatabase) {
        db.beginTransaction()
        try {
            // Migrate places: encrypt lat/lng
            if (checkColumnExists(db, TABLE_PLACES, COL_PLACE_LAT)) {
                migratePlacesToEncrypted(db)
            }
            // Migrate learning_points: encrypt lat/lng
            if (checkColumnExists(db, TABLE_LEARNING_POINTS, COL_LP_LAT)) {
                migrateLearningPointsToEncrypted(db)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun migratePlacesToEncrypted(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS ${TABLE_PLACES}_new (
                ${COL_PLACE_ID} TEXT PRIMARY KEY,
                ${COL_PLACE_SERVER_ID} TEXT,
                ${COL_PLACE_LABEL} TEXT NOT NULL,
                ${COL_PLACE_ICON} TEXT NOT NULL,
                ${COL_PLACE_LAT_ENCRYPTED} TEXT NOT NULL,
                ${COL_PLACE_LNG_ENCRYPTED} TEXT NOT NULL,
                ${COL_PLACE_RADIUS} REAL NOT NULL,
                ${COL_PLACE_STATUS} TEXT NOT NULL,
                ${COL_PLACE_TRIGGER_TYPE} TEXT NOT NULL DEFAULT 'normal',
                ${COL_PLACE_CREATED} TEXT NOT NULL,
                ${COL_PLACE_UPDATED} TEXT NOT NULL,
                ${COL_PLACE_DIRTY} INTEGER NOT NULL DEFAULT 0
            )
        """.trimIndent())

        var cursor: Cursor? = null
        try {
            cursor = db.rawQuery("SELECT * FROM $TABLE_PLACES", null)
            while (cursor.moveToNext()) {
                val id = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_ID))
                val serverIdIdx = cursor.getColumnIndexOrThrow(COL_PLACE_SERVER_ID)
                val serverId = if (cursor.isNull(serverIdIdx)) null else cursor.getString(serverIdIdx)
                val label = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LABEL))
                val icon = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_ICON))
                val lat = cursor.getDouble(cursor.getColumnIndexOrThrow(COL_PLACE_LAT))
                val lng = cursor.getDouble(cursor.getColumnIndexOrThrow(COL_PLACE_LNG))
                val radius = cursor.getDouble(cursor.getColumnIndexOrThrow(COL_PLACE_RADIUS))
                val status = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_STATUS))
                val triggerType = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_TRIGGER_TYPE))
                val createdAt = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_CREATED))
                val updatedAt = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_UPDATED))
                val dirty = cursor.getInt(cursor.getColumnIndexOrThrow(COL_PLACE_DIRTY))

                val latEncrypted = cryptoManager.encrypt(lat.toString())
                val lngEncrypted = cryptoManager.encrypt(lng.toString())

                val values = ContentValues().apply {
                    put(COL_PLACE_ID, id)
                    put(COL_PLACE_SERVER_ID, serverId)
                    put(COL_PLACE_LABEL, label)
                    put(COL_PLACE_ICON, icon)
                    put(COL_PLACE_LAT_ENCRYPTED, latEncrypted)
                    put(COL_PLACE_LNG_ENCRYPTED, lngEncrypted)
                    put(COL_PLACE_RADIUS, radius)
                    put(COL_PLACE_STATUS, status)
                    put(COL_PLACE_TRIGGER_TYPE, triggerType)
                    put(COL_PLACE_CREATED, createdAt)
                    put(COL_PLACE_UPDATED, updatedAt)
                    put(COL_PLACE_DIRTY, dirty)
                }
                db.insert("${TABLE_PLACES}_new", null, values)
            }
        } finally {
            cursor?.close()
        }

        db.execSQL("DROP TABLE IF EXISTS $TABLE_PLACES")
        db.execSQL("ALTER TABLE ${TABLE_PLACES}_new RENAME TO $TABLE_PLACES")
        Log.d(TAG, "Migrated places to encrypted lat/lng")
    }

    private fun migrateLearningPointsToEncrypted(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS ${TABLE_LEARNING_POINTS}_new (
                ${COL_LP_LAT_ENCRYPTED} TEXT NOT NULL,
                ${COL_LP_LNG_ENCRYPTED} TEXT NOT NULL,
                ${COL_LP_TIMESTAMP} INTEGER NOT NULL,
                ${COL_LP_SOURCE} TEXT NOT NULL DEFAULT 'LEARNING'
            )
        """.trimIndent())

        var cursor: Cursor? = null
        try {
            cursor = db.rawQuery("SELECT * FROM $TABLE_LEARNING_POINTS", null)
            while (cursor.moveToNext()) {
                val lat = cursor.getDouble(cursor.getColumnIndexOrThrow(COL_LP_LAT))
                val lng = cursor.getDouble(cursor.getColumnIndexOrThrow(COL_LP_LNG))
                val timestamp = cursor.getLong(cursor.getColumnIndexOrThrow(COL_LP_TIMESTAMP))
                val source = cursor.getString(cursor.getColumnIndexOrThrow(COL_LP_SOURCE)) ?: "LEARNING"

                val latEncrypted = cryptoManager.encrypt(lat.toString())
                val lngEncrypted = cryptoManager.encrypt(lng.toString())

                val values = ContentValues().apply {
                    put(COL_LP_LAT_ENCRYPTED, latEncrypted)
                    put(COL_LP_LNG_ENCRYPTED, lngEncrypted)
                    put(COL_LP_TIMESTAMP, timestamp)
                    put(COL_LP_SOURCE, source)
                }
                db.insert("${TABLE_LEARNING_POINTS}_new", null, values)
            }
        } finally {
            cursor?.close()
        }

        db.execSQL("DROP TABLE IF EXISTS $TABLE_LEARNING_POINTS")
        db.execSQL("ALTER TABLE ${TABLE_LEARNING_POINTS}_new RENAME TO $TABLE_LEARNING_POINTS")
        Log.d(TAG, "Migrated learning_points to encrypted lat/lng")
    }

    private fun migrateLocationLogs(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS ${TABLE_LOCATION_LOGS}_new (
                $COL_LL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_LL_LAT_ENCRYPTED TEXT NOT NULL,
                $COL_LL_LNG_ENCRYPTED TEXT NOT NULL,
                $COL_LL_ACCURACY REAL,
                $COL_LL_ALTITUDE REAL,
                $COL_LL_SPEED REAL,
                $COL_LL_TIMESTAMP_HW INTEGER NOT NULL,
                $COL_LL_TIMESTAMP_SYSTEM INTEGER NOT NULL,
                $COL_LL_SOURCE TEXT NOT NULL
            )
        """.trimIndent())

        var cursor: Cursor? = null
        try {
            cursor = db.rawQuery("SELECT * FROM $TABLE_LOCATION_LOGS", null)
            while (cursor.moveToNext()) {
                val lat = cursor.getDouble(cursor.getColumnIndexOrThrow("lat"))
                val lng = cursor.getDouble(cursor.getColumnIndexOrThrow("lng"))
                val accIdx = cursor.getColumnIndexOrThrow(COL_LL_ACCURACY)
                val accuracy = if (cursor.isNull(accIdx)) null else cursor.getDouble(accIdx)
                val altIdx = cursor.getColumnIndexOrThrow(COL_LL_ALTITUDE)
                val altitude = if (cursor.isNull(altIdx)) null else cursor.getDouble(altIdx)
                val spdIdx = cursor.getColumnIndexOrThrow(COL_LL_SPEED)
                val speed = if (cursor.isNull(spdIdx)) null else cursor.getDouble(spdIdx)
                val tsHwIdx = cursor.getColumnIndexOrThrow(COL_LL_TIMESTAMP_HW)
                val timestampHw = if (cursor.isNull(tsHwIdx)) 0L else cursor.getLong(tsHwIdx)
                val timestampSystem = cursor.getLong(cursor.getColumnIndexOrThrow(COL_LL_TIMESTAMP_SYSTEM))
                val source = cursor.getString(cursor.getColumnIndexOrThrow(COL_LL_SOURCE)) ?: "UNKNOWN"

                val latEncrypted = cryptoManager.encrypt(lat.toString())
                val lngEncrypted = cryptoManager.encrypt(lng.toString())

                val values = ContentValues().apply {
                    put(COL_LL_LAT_ENCRYPTED, latEncrypted)
                    put(COL_LL_LNG_ENCRYPTED, lngEncrypted)
                    put(COL_LL_ACCURACY, accuracy?.toFloat())
                    put(COL_LL_ALTITUDE, altitude)
                    put(COL_LL_SPEED, speed?.toFloat())
                    put(COL_LL_TIMESTAMP_HW, timestampHw)
                    put(COL_LL_TIMESTAMP_SYSTEM, timestampSystem)
                    put(COL_LL_SOURCE, source)
                }
                db.insert("${TABLE_LOCATION_LOGS}_new", null, values)
            }
        } finally {
            cursor?.close()
        }

        db.execSQL("DROP TABLE IF EXISTS $TABLE_LOCATION_LOGS")
        db.execSQL("ALTER TABLE ${TABLE_LOCATION_LOGS}_new RENAME TO $TABLE_LOCATION_LOGS")
        Log.d(TAG, "Migrated location_logs to encrypted schema")
    }

    private fun migrateWebhookQueue(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS ${TABLE_WEBHOOK_QUEUE}_new (
                $COL_WQ_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_WQ_PAYLOAD_ENCRYPTED TEXT NOT NULL,
                $COL_WQ_ENDPOINT_URL_ENCRYPTED TEXT NOT NULL,
                $COL_WQ_HEADERS_ENCRYPTED TEXT,
                $COL_WQ_RETRY_COUNT INTEGER NOT NULL DEFAULT 0,
                $COL_WQ_CREATED_AT INTEGER NOT NULL,
                $COL_WQ_SCHEDULED_AT INTEGER NOT NULL
            )
        """.trimIndent())

        var cursor: Cursor? = null
        try {
            cursor = db.rawQuery("SELECT * FROM $TABLE_WEBHOOK_QUEUE", null)
            while (cursor.moveToNext()) {
                val payloadJson = cursor.getString(cursor.getColumnIndexOrThrow("payload_json"))
                val endpointUrl = cursor.getString(cursor.getColumnIndexOrThrow("endpoint_url"))
                val hdrIdx = cursor.getColumnIndexOrThrow("headers_json")
                val headersJson = if (cursor.isNull(hdrIdx)) null else cursor.getString(hdrIdx)
                val retryCount = cursor.getInt(cursor.getColumnIndexOrThrow(COL_WQ_RETRY_COUNT))
                val createdAt = cursor.getLong(cursor.getColumnIndexOrThrow(COL_WQ_CREATED_AT))
                val scheduledAt = cursor.getLong(cursor.getColumnIndexOrThrow(COL_WQ_SCHEDULED_AT))

                val payloadEncrypted = cryptoManager.encrypt(payloadJson)
                val endpointEncrypted = cryptoManager.encrypt(endpointUrl)
                val headersEncrypted = if (headersJson != null) cryptoManager.encrypt(headersJson) else null

                val values = ContentValues().apply {
                    put(COL_WQ_PAYLOAD_ENCRYPTED, payloadEncrypted)
                    put(COL_WQ_ENDPOINT_URL_ENCRYPTED, endpointEncrypted)
                    put(COL_WQ_HEADERS_ENCRYPTED, headersEncrypted)
                    put(COL_WQ_RETRY_COUNT, retryCount)
                    put(COL_WQ_CREATED_AT, createdAt)
                    put(COL_WQ_SCHEDULED_AT, scheduledAt)
                }
                db.insert("${TABLE_WEBHOOK_QUEUE}_new", null, values)
            }
        } finally {
            cursor?.close()
        }

        db.execSQL("DROP TABLE IF EXISTS $TABLE_WEBHOOK_QUEUE")
        db.execSQL("ALTER TABLE ${TABLE_WEBHOOK_QUEUE}_new RENAME TO $TABLE_WEBHOOK_QUEUE")
        Log.d(TAG, "Migrated webhook_queue to encrypted schema")
    }

    private fun migrateGeofenceTransitions(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS ${TABLE_GEOFENCE_TRANSITIONS}_new (
                $COL_GT_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_GT_PLACE_ID TEXT NOT NULL,
                $COL_GT_TRANSITION_TYPE TEXT NOT NULL,
                $COL_GT_TIMESTAMP_HW INTEGER NOT NULL,
                $COL_GT_TIMESTAMP_SYSTEM INTEGER NOT NULL,
                $COL_GT_ACCURACY REAL,
                $COL_GT_DWELL_DURATION_MS INTEGER
            )
        """.trimIndent())

        var cursor: Cursor? = null
        try {
            cursor = db.rawQuery("SELECT * FROM $TABLE_GEOFENCE_TRANSITIONS", null)
            while (cursor.moveToNext()) {
                val placeId = cursor.getString(cursor.getColumnIndexOrThrow(COL_GT_PLACE_ID))
                val transitionType = cursor.getString(cursor.getColumnIndexOrThrow(COL_GT_TRANSITION_TYPE))
                val tsHwIdx = cursor.getColumnIndexOrThrow(COL_GT_TIMESTAMP_HW)
                val timestampHw = if (cursor.isNull(tsHwIdx)) 0L else cursor.getLong(tsHwIdx)
                val tsSysIdx = cursor.getColumnIndexOrThrow(COL_GT_TIMESTAMP_SYSTEM)
                val timestampSystem = if (cursor.isNull(tsSysIdx)) 0L else cursor.getLong(tsSysIdx)
                val accIdx = cursor.getColumnIndexOrThrow(COL_GT_ACCURACY)
                val accuracy = if (cursor.isNull(accIdx)) null else cursor.getDouble(accIdx)
                val dwellIdx = cursor.getColumnIndexOrThrow(COL_GT_DWELL_DURATION_MS)
                val dwellDurationMs = if (cursor.isNull(dwellIdx)) null else cursor.getLong(dwellIdx)

                val values = ContentValues().apply {
                    put(COL_GT_PLACE_ID, placeId)
                    put(COL_GT_TRANSITION_TYPE, transitionType)
                    put(COL_GT_TIMESTAMP_HW, timestampHw)
                    put(COL_GT_TIMESTAMP_SYSTEM, timestampSystem)
                    put(COL_GT_ACCURACY, accuracy?.toFloat())
                    put(COL_GT_DWELL_DURATION_MS, dwellDurationMs)
                }
                db.insert("${TABLE_GEOFENCE_TRANSITIONS}_new", null, values)
            }
        } finally {
            cursor?.close()
        }

        db.execSQL("DROP TABLE IF EXISTS $TABLE_GEOFENCE_TRANSITIONS")
        db.execSQL("ALTER TABLE ${TABLE_GEOFENCE_TRANSITIONS}_new RENAME TO $TABLE_GEOFENCE_TRANSITIONS")
        Log.d(TAG, "Migrated geofence_transitions to v5 schema")
    }

    private fun migrateToV8(db: SQLiteDatabase) {
        db.beginTransaction()
        try {
            db.execSQL("""
                CREATE TABLE IF NOT EXISTS $TABLE_DEBUG_LOGS (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp INTEGER NOT NULL,
                    level TEXT NOT NULL,
                    category TEXT NOT NULL,
                    message TEXT NOT NULL,
                    place_id TEXT,
                    extra_json TEXT
                )
            """.trimIndent())
            Log.d(TAG, "Created debug_logs table (migration v8)")
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun migrateToV7(db: SQLiteDatabase) {
        db.beginTransaction()
        try {
            // Remove old harbor_pending visits (replaced by new state machine)
            val deleted = db.delete(
                TABLE_VISITS,
                "$COL_VISIT_SOURCE = 'harbor_pending'",
                null
            )
            if (deleted > 0) {
                Log.d(TAG, "Cleaned up $deleted old harbor_pending visits (migration v7)")
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun checkColumnExists(db: SQLiteDatabase, tableName: String, columnName: String): Boolean {
        var cursor: Cursor? = null
        try {
            cursor = db.rawQuery("PRAGMA table_info($tableName)", null)
            while (cursor.moveToNext()) {
                if (cursor.getString(cursor.getColumnIndexOrThrow("name")) == columnName) {
                    return true
                }
            }
        } finally {
            cursor?.close()
        }
        return false
    }

    fun openWritableDatabase(): SQLiteDatabase {
        return writableDatabase
    }

    fun openReadableDatabase(): SQLiteDatabase {
        return readableDatabase
    }

    fun purgeExpiredLogs() {
        val cutoff = System.currentTimeMillis() - (30L * 24 * 60 * 60 * 1000)
        try {
            val deleted = writableDatabase.delete(
                TABLE_LOCATION_LOGS,
                "$COL_LL_TIMESTAMP_SYSTEM < ?",
                arrayOf(cutoff.toString())
            )
            if (deleted > 0) Log.d(TAG, "Purged $deleted expired location logs older than 30 days")
        } catch (e: Exception) {
            Log.e(TAG, "Error purging expired logs", e)
        }
    }

    fun purgeAllHistory() {
        try {
            val db = writableDatabase
            db.delete(TABLE_LOCATION_LOGS, null, null)
            db.delete(TABLE_GEOFENCE_TRANSITIONS, null, null)
            db.delete(TABLE_WEBHOOK_QUEUE, null, null)
            db.delete(TABLE_LEARNING_POINTS, null, null)
            db.delete(TABLE_VISITS, null, null)
            Log.d(TAG, "All history purged")
        } catch (e: Exception) {
            Log.e(TAG, "Error purging all history", e)
        }
    }

    fun insertLocationLog(
        lat: Double, lng: Double, accuracy: Float?, altitude: Double?, speed: Float?,
        timestampHw: Long, timestampSystem: Long, source: String
    ): Long {
        val latEncrypted = cryptoManager.encrypt(lat.toString())
        val lngEncrypted = cryptoManager.encrypt(lng.toString())
        val values = ContentValues().apply {
            put(COL_LL_LAT_ENCRYPTED, latEncrypted)
            put(COL_LL_LNG_ENCRYPTED, lngEncrypted)
            if (accuracy != null) put(COL_LL_ACCURACY, accuracy)
            if (altitude != null) put(COL_LL_ALTITUDE, altitude)
            if (speed != null) put(COL_LL_SPEED, speed)
            put(COL_LL_TIMESTAMP_HW, timestampHw)
            put(COL_LL_TIMESTAMP_SYSTEM, timestampSystem)
            put(COL_LL_SOURCE, source)
        }
        return writableDatabase.insert(TABLE_LOCATION_LOGS, null, values)
    }

    fun getLocationLogsSince(timestamp: Long): List<LocationLog> {
        val list = mutableListOf<LocationLog>()
        var cursor: Cursor? = null
        try {
            cursor = readableDatabase.query(
                TABLE_LOCATION_LOGS,
                null,
                "$COL_LL_TIMESTAMP_HW >= ?",
                arrayOf(timestamp.toString()),
                null, null, "$COL_LL_TIMESTAMP_HW ASC"
            )
            while (cursor.moveToNext()) {
                try {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(COL_LL_ID))
                    val latEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_LL_LAT_ENCRYPTED))
                    val lngEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_LL_LNG_ENCRYPTED))
                    val lat = cryptoManager.decrypt(latEncrypted).toDouble()
                    val lng = cryptoManager.decrypt(lngEncrypted).toDouble()
                    val accIdx = cursor.getColumnIndexOrThrow(COL_LL_ACCURACY)
                    val accuracy = if (cursor.isNull(accIdx)) null else cursor.getFloat(accIdx)
                    val altIdx = cursor.getColumnIndexOrThrow(COL_LL_ALTITUDE)
                    val altitude = if (cursor.isNull(altIdx)) null else cursor.getDouble(altIdx)
                    val spdIdx = cursor.getColumnIndexOrThrow(COL_LL_SPEED)
                    val speed = if (cursor.isNull(spdIdx)) null else cursor.getFloat(spdIdx)
                    val timestampHw = cursor.getLong(cursor.getColumnIndexOrThrow(COL_LL_TIMESTAMP_HW))
                    val timestampSystem = cursor.getLong(cursor.getColumnIndexOrThrow(COL_LL_TIMESTAMP_SYSTEM))
                    val source = cursor.getString(cursor.getColumnIndexOrThrow(COL_LL_SOURCE)) ?: ""
                    list.add(LocationLog(id, lat, lng, accuracy, altitude, speed, timestampHw, timestampSystem, source))
                } catch (e: Exception) {
                    Log.e(TAG, "Error decrypting location log row, skipping", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying location logs", e)
        } finally {
            cursor?.close()
        }
        return list
    }

    fun insertGeofenceTransition(
        placeId: String, transitionType: String, timestampHw: Long,
        timestampSystem: Long, accuracy: Float?, dwellDurationMs: Long?
    ): Long {
        val values = ContentValues().apply {
            put(COL_GT_PLACE_ID, placeId)
            put(COL_GT_TRANSITION_TYPE, transitionType)
            put(COL_GT_TIMESTAMP_HW, timestampHw)
            put(COL_GT_TIMESTAMP_SYSTEM, timestampSystem)
            if (accuracy != null) put(COL_GT_ACCURACY, accuracy)
            if (dwellDurationMs != null) put(COL_GT_DWELL_DURATION_MS, dwellDurationMs)
        }
        return writableDatabase.insert(TABLE_GEOFENCE_TRANSITIONS, null, values)
    }

    fun getGeofenceTransitionsForPlace(placeId: String): List<GeofenceTransition> {
        val list = mutableListOf<GeofenceTransition>()
        var cursor: Cursor? = null
        try {
            cursor = readableDatabase.query(
                TABLE_GEOFENCE_TRANSITIONS,
                null,
                "$COL_GT_PLACE_ID = ?",
                arrayOf(placeId),
                null, null, "$COL_GT_TIMESTAMP_HW ASC"
            )
            while (cursor.moveToNext()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(COL_GT_ID))
                val transitionType = cursor.getString(cursor.getColumnIndexOrThrow(COL_GT_TRANSITION_TYPE))
                val timestampHw = cursor.getLong(cursor.getColumnIndexOrThrow(COL_GT_TIMESTAMP_HW))
                val timestampSystem = cursor.getLong(cursor.getColumnIndexOrThrow(COL_GT_TIMESTAMP_SYSTEM))
                val accIdx = cursor.getColumnIndexOrThrow(COL_GT_ACCURACY)
                val accuracy = if (cursor.isNull(accIdx)) null else cursor.getFloat(accIdx)
                val dwellIdx = cursor.getColumnIndexOrThrow(COL_GT_DWELL_DURATION_MS)
                val dwellDurationMs = if (cursor.isNull(dwellIdx)) null else cursor.getLong(dwellIdx)
                list.add(GeofenceTransition(id, placeId, transitionType, timestampHw, timestampSystem, accuracy, dwellDurationMs))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying geofence transitions", e)
        } finally {
            cursor?.close()
        }
        return list
    }

    fun insertWebhookQueue(
        payloadJson: String, endpointUrl: String, headersJson: String?,
        retryCount: Int, createdAt: Long, scheduledAt: Long
    ): Long {
        // FIFO eviction: if at capacity, drop the oldest item first
        val count = getWebhookQueueCount()
        if (count >= MAX_QUEUED_ROWS) {
            val oldestId = getOldestWebhookQueueId()
            if (oldestId != null) {
                deleteWebhook(oldestId)
                Log.w(TAG, "Queue full ($MAX_QUEUED_ROWS). Dropped oldest item ($oldestId) to make room.")
            }
        }

        val payloadEncrypted = cryptoManager.encrypt(payloadJson)
        val endpointEncrypted = cryptoManager.encrypt(endpointUrl)
        val headersEncrypted = if (headersJson != null) cryptoManager.encrypt(headersJson) else null
        val values = ContentValues().apply {
            put(COL_WQ_PAYLOAD_ENCRYPTED, payloadEncrypted)
            put(COL_WQ_ENDPOINT_URL_ENCRYPTED, endpointEncrypted)
            put(COL_WQ_HEADERS_ENCRYPTED, headersEncrypted)
            put(COL_WQ_RETRY_COUNT, retryCount)
            put(COL_WQ_CREATED_AT, createdAt)
            put(COL_WQ_SCHEDULED_AT, scheduledAt)
        }
        return writableDatabase.insert(TABLE_WEBHOOK_QUEUE, null, values)
    }

    fun getOldestWebhookQueueId(): Long? {
        var cursor: Cursor? = null
        try {
            cursor = readableDatabase.rawQuery(
                "SELECT $COL_WQ_ID FROM $TABLE_WEBHOOK_QUEUE ORDER BY $COL_WQ_CREATED_AT ASC LIMIT 1",
                null
            )
            if (cursor.moveToFirst()) {
                return cursor.getLong(0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error finding oldest webhook", e)
        } finally {
            cursor?.close()
        }
        return null
    }

    fun getPendingWebhookItems(limit: Int): List<WebhookQueueItem> {
        val list = mutableListOf<WebhookQueueItem>()
        var cursor: Cursor? = null
        try {
            cursor = readableDatabase.query(
                TABLE_WEBHOOK_QUEUE,
                null,
                "$COL_WQ_SCHEDULED_AT <= ?",
                arrayOf(System.currentTimeMillis().toString()),
                null, null, "$COL_WQ_CREATED_AT ASC"
            )
            var count = 0
            while (cursor.moveToNext() && count < limit) {
                try {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(COL_WQ_ID))
                    val payloadEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_WQ_PAYLOAD_ENCRYPTED))
                    val endpointEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_WQ_ENDPOINT_URL_ENCRYPTED))
                    val hdrIdx = cursor.getColumnIndexOrThrow(COL_WQ_HEADERS_ENCRYPTED)
                    val headersEncrypted = if (cursor.isNull(hdrIdx)) null else cursor.getString(hdrIdx)
                    val retryCount = cursor.getInt(cursor.getColumnIndexOrThrow(COL_WQ_RETRY_COUNT))
                    val createdAt = cursor.getLong(cursor.getColumnIndexOrThrow(COL_WQ_CREATED_AT))
                    val scheduledAt = cursor.getLong(cursor.getColumnIndexOrThrow(COL_WQ_SCHEDULED_AT))

                    val payloadJson = cryptoManager.decrypt(payloadEncrypted)
                    val endpointUrl = cryptoManager.decrypt(endpointEncrypted)
                    val headersJson = if (headersEncrypted != null) cryptoManager.decrypt(headersEncrypted) else null

                    list.add(WebhookQueueItem(id, payloadJson, endpointUrl, headersJson, retryCount, createdAt, scheduledAt))
                    count++
                } catch (e: Exception) {
                    Log.e(TAG, "Error decrypting webhook queue row, skipping", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying pending webhooks", e)
        } finally {
            cursor?.close()
        }
        return list
    }

    fun getWebhookQueueCount(): Int {
        var cursor: Cursor? = null
        try {
            cursor = readableDatabase.rawQuery("SELECT COUNT(*) FROM $TABLE_WEBHOOK_QUEUE", null)
            if (cursor.moveToFirst()) {
                return cursor.getInt(0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error counting webhook queue", e)
        } finally {
            cursor?.close()
        }
        return 0
    }

    fun incrementWebhookRetry(webhookId: Long) {
        try {
            var cursor: Cursor? = null
            try {
                cursor = readableDatabase.query(
                    TABLE_WEBHOOK_QUEUE,
                    arrayOf(COL_WQ_RETRY_COUNT),
                    "$COL_WQ_ID = ?",
                    arrayOf(webhookId.toString()),
                    null, null, null
                )
                if (cursor.moveToFirst()) {
                    val retryCount = cursor.getInt(cursor.getColumnIndexOrThrow(COL_WQ_RETRY_COUNT))
                    val values = ContentValues().apply { put(COL_WQ_RETRY_COUNT, retryCount + 1) }
                    writableDatabase.update(
                        TABLE_WEBHOOK_QUEUE,
                        values,
                        "$COL_WQ_ID = ?",
                        arrayOf(webhookId.toString())
                    )
                }
            } finally {
                cursor?.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error incrementing webhook retry", e)
        }
    }

    fun updateWebhookRetry(webhookId: Long, retryCount: Int, scheduledAt: Long) {
        try {
            val values = ContentValues().apply {
                put(COL_WQ_RETRY_COUNT, retryCount)
                put(COL_WQ_SCHEDULED_AT, scheduledAt)
            }
            writableDatabase.update(
                TABLE_WEBHOOK_QUEUE,
                values,
                "$COL_WQ_ID = ?",
                arrayOf(webhookId.toString())
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error updating webhook retry", e)
        }
    }

    fun deleteWebhook(webhookId: Long) {
        try {
            writableDatabase.delete(
                TABLE_WEBHOOK_QUEUE,
                "$COL_WQ_ID = ?",
                arrayOf(webhookId.toString())
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting webhook", e)
        }
    }

    fun insertLearningPoint(lat: Double, lng: Double, timestamp: Long, source: String = "LEARNING") {
        try {
            val latEncrypted = cryptoManager.encrypt(lat.toString())
            val lngEncrypted = cryptoManager.encrypt(lng.toString())
            val values = ContentValues().apply {
                put(COL_LP_LAT_ENCRYPTED, latEncrypted)
                put(COL_LP_LNG_ENCRYPTED, lngEncrypted)
                put(COL_LP_TIMESTAMP, timestamp)
                put(COL_LP_SOURCE, source)
            }
            writableDatabase.insert(TABLE_LEARNING_POINTS, null, values)
            insertLocationLog(lat, lng, null, null, null, timestamp, System.currentTimeMillis(), source)
        } catch (e: Exception) {
            Log.e(TAG, "Error inserting learning point", e)
        }
    }

    fun getPlaceLabel(placeId: String): String? {
        try {
            var cursor: Cursor? = null
            try {
                cursor = readableDatabase.query(
                    TABLE_PLACES,
                    arrayOf(COL_PLACE_LABEL),
                    "$COL_PLACE_ID = ?",
                    arrayOf(placeId),
                    null, null, null
                )
                if (cursor.moveToFirst()) {
                    return cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LABEL))
                }
            } finally {
                cursor?.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting place label for $placeId", e)
        }
        return null
    }

    fun startVisit(placeId: String, enterTimestamp: Long, eventTimestamp: Long? = null, processedAt: Long? = null): String? {
        try {
            var checkCursor: Cursor? = null
            try {
                checkCursor = readableDatabase.query(
                    TABLE_VISITS,
                    arrayOf(COL_VISIT_ID),
                    "$COL_VISIT_PLACE_ID = ? AND $COL_VISIT_EXIT IS NULL",
                    arrayOf(placeId),
                    null, null, null
                )
                if (checkCursor.moveToFirst()) {
                    val activeId = checkCursor.getString(checkCursor.getColumnIndexOrThrow(COL_VISIT_ID))
                    Log.d(TAG, "Visit already active for place $placeId: $activeId")
                    return activeId
                }
            } finally {
                checkCursor?.close()
            }

            val visitId = java.util.UUID.randomUUID().toString()
            val values = ContentValues().apply {
                put(COL_VISIT_ID, visitId)
                put(COL_VISIT_PLACE_ID, placeId)
                put(COL_VISIT_ENTER, enterTimestamp)
                put(COL_VISIT_SOURCE, "geofence")
                put(COL_VISIT_DIRTY, 1)
                if (eventTimestamp != null) put(COL_VISIT_EVENT_TIMESTAMP, eventTimestamp)
                if (processedAt != null) put(COL_VISIT_PROCESSED_AT, processedAt)
            }
            writableDatabase.insert(TABLE_VISITS, null, values)
            Log.d(TAG, "Visit started: $visitId for place $placeId")
            insertGeofenceTransition(placeId, "DWELL", eventTimestamp ?: System.currentTimeMillis(), System.currentTimeMillis(), null, 120000L)
            return visitId
        } catch (e: Exception) {
            Log.e(TAG, "Error starting visit", e)
            return null
        }
    }

    fun endVisit(placeId: String, exitTimestamp: Long, eventTimestamp: Long? = null, processedAt: Long? = null): Pair<String, Long>? {
        try {
            var cursor: Cursor? = null
            try {
                cursor = readableDatabase.query(
                    TABLE_VISITS,
                    arrayOf(COL_VISIT_ID, COL_VISIT_ENTER),
                    "$COL_VISIT_PLACE_ID = ? AND $COL_VISIT_EXIT IS NULL",
                    arrayOf(placeId),
                    null, null, "$COL_VISIT_ENTER DESC", "1"
                )
                if (cursor.moveToFirst()) {
                    val visitId = cursor.getString(cursor.getColumnIndexOrThrow(COL_VISIT_ID))
                    val enterTs = cursor.getLong(cursor.getColumnIndexOrThrow(COL_VISIT_ENTER))
                    val durationS = (exitTimestamp - enterTs) / 1000
                    val values = ContentValues().apply {
                        put(COL_VISIT_EXIT, exitTimestamp)
                        put(COL_VISIT_DURATION, durationS)
                        put(COL_VISIT_DIRTY, 1)
                        if (eventTimestamp != null) put(COL_VISIT_EVENT_TIMESTAMP, eventTimestamp)
                        if (processedAt != null) put(COL_VISIT_PROCESSED_AT, processedAt)
                    }
                    writableDatabase.update(TABLE_VISITS, values, "$COL_VISIT_ID = ?", arrayOf(visitId))
                    Log.d(TAG, "Visit ended: $visitId, duration: ${durationS}s")
                    insertGeofenceTransition(placeId, "EXIT", eventTimestamp ?: System.currentTimeMillis(), System.currentTimeMillis(), null, null)
                    return Pair(visitId, durationS)
                }
            } finally {
                cursor?.close()
            }

            Log.d(TAG, "No active visit found to end for place $placeId, inserting manual exit entry")
            val visitId = java.util.UUID.randomUUID().toString()
            val enterTs = exitTimestamp - (10 * 60 * 1000)
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
            writableDatabase.insert(TABLE_VISITS, null, values)
            insertGeofenceTransition(placeId, "EXIT", eventTimestamp ?: System.currentTimeMillis(), System.currentTimeMillis(), null, null)
            return Pair(visitId, durationS)
        } catch (e: Exception) {
            Log.e(TAG, "Error ending visit", e)
            return null
        }
    }

    fun getPlaceTriggerType(placeId: String): String? {
        try {
            var cursor: Cursor? = null
            try {
                cursor = readableDatabase.query(
                    TABLE_PLACES,
                    arrayOf(COL_PLACE_TRIGGER_TYPE),
                    "$COL_PLACE_ID = ?",
                    arrayOf(placeId),
                    null, null, null
                )
                if (cursor.moveToFirst()) {
                    return cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_TRIGGER_TYPE))
                }
            } finally {
                cursor?.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting place trigger type for $placeId", e)
        }
        return null
    }

    fun insertPlaceEncrypted(
        id: String, label: String, icon: String, lat: Double, lng: Double,
        radius: Double, status: String, triggerType: String,
        createdAt: String, updatedAt: String, dirty: Int
    ) {
        try {
            val latEncrypted = cryptoManager.encrypt(lat.toString())
            val lngEncrypted = cryptoManager.encrypt(lng.toString())
            val values = ContentValues().apply {
                put(COL_PLACE_ID, id)
                put(COL_PLACE_LABEL, label)
                put(COL_PLACE_ICON, icon)
                put(COL_PLACE_LAT_ENCRYPTED, latEncrypted)
                put(COL_PLACE_LNG_ENCRYPTED, lngEncrypted)
                put(COL_PLACE_RADIUS, radius)
                put(COL_PLACE_STATUS, status)
                put(COL_PLACE_TRIGGER_TYPE, triggerType)
                put(COL_PLACE_CREATED, createdAt)
                put(COL_PLACE_UPDATED, updatedAt)
                put(COL_PLACE_DIRTY, dirty)
            }
            writableDatabase.insertWithOnConflict(TABLE_PLACES, null, values, SQLiteDatabase.CONFLICT_REPLACE)
        } catch (e: Exception) {
            Log.e(TAG, "Error inserting encrypted place", e)
        }
    }

    fun getAllPlacesDecrypted(): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        try {
            var cursor: Cursor? = null
            try {
                cursor = readableDatabase.query(TABLE_PLACES, null, null, null, null, null, null)
                while (cursor.moveToNext()) {
                    val latEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LAT_ENCRYPTED))
                    val lngEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LNG_ENCRYPTED))
                    val lat = cryptoManager.decrypt(latEncrypted).toDouble()
                    val lng = cryptoManager.decrypt(lngEncrypted).toDouble()
                    list.add(placeRowToMap(cursor, lat, lng))
                }
            } finally {
                cursor?.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting all decrypted places", e)
        }
        return list
    }

    fun getPlaceDecrypted(id: String): Map<String, Any?>? {
        try {
            var cursor: Cursor? = null
            try {
                cursor = readableDatabase.query(
                    TABLE_PLACES, null,
                    "$COL_PLACE_ID = ?", arrayOf(id),
                    null, null, null
                )
                if (cursor.moveToFirst()) {
                    val latEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LAT_ENCRYPTED))
                    val lngEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LNG_ENCRYPTED))
                    val lat = cryptoManager.decrypt(latEncrypted).toDouble()
                    val lng = cryptoManager.decrypt(lngEncrypted).toDouble()
                    return placeRowToMap(cursor, lat, lng)
                }
            } finally {
                cursor?.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting decrypted place $id", e)
        }
        return null
    }

    private fun placeRowToMap(cursor: Cursor, lat: Double, lng: Double): Map<String, Any?> {
        return mapOf(
            COL_PLACE_ID to cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_ID)),
            COL_PLACE_SERVER_ID to (cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_SERVER_ID)) ?: ""),
            COL_PLACE_LABEL to cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LABEL)),
            COL_PLACE_ICON to cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_ICON)),
            COL_PLACE_LAT to lat,
            COL_PLACE_LNG to lng,
            COL_PLACE_RADIUS to cursor.getDouble(cursor.getColumnIndexOrThrow(COL_PLACE_RADIUS)),
            COL_PLACE_STATUS to cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_STATUS)),
            COL_PLACE_TRIGGER_TYPE to cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_TRIGGER_TYPE)),
            COL_PLACE_CREATED to cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_CREATED)),
            COL_PLACE_UPDATED to cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_UPDATED)),
            COL_PLACE_DIRTY to cursor.getInt(cursor.getColumnIndexOrThrow(COL_PLACE_DIRTY)),
        )
    }

    fun getAllLearningPointsDecrypted(): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        try {
            var cursor: Cursor? = null
            try {
                cursor = readableDatabase.query(
                    TABLE_LEARNING_POINTS, null, null, null, null, null, "$COL_LP_TIMESTAMP ASC"
                )
                while (cursor.moveToNext()) {
                    val latEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_LP_LAT_ENCRYPTED))
                    val lngEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_LP_LNG_ENCRYPTED))
                    val lat = cryptoManager.decrypt(latEncrypted).toDouble()
                    val lng = cryptoManager.decrypt(lngEncrypted).toDouble()
                    list.add(mapOf(
                        COL_LP_LAT to lat,
                        COL_LP_LNG to lng,
                        COL_LP_TIMESTAMP to cursor.getLong(cursor.getColumnIndexOrThrow(COL_LP_TIMESTAMP)),
                        COL_LP_SOURCE to (cursor.getString(cursor.getColumnIndexOrThrow(COL_LP_SOURCE)) ?: "LEARNING")
                    ))
                }
            } finally {
                cursor?.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting learning points", e)
        }
        return list
    }

    fun deletePlaceEncrypted(id: String) {
        try {
            writableDatabase.delete(TABLE_PLACES, "$COL_PLACE_ID = ?", arrayOf(id))
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting place $id", e)
        }
    }

    fun updatePlaceEncrypted(
        id: String, label: String?, icon: String?, lat: Double?, lng: Double?,
        radius: Double?, status: String?, triggerType: String?,
        updatedAt: String, dirty: Int
    ) {
        try {
            val values = ContentValues().apply {
                if (label != null) put(COL_PLACE_LABEL, label)
                if (icon != null) put(COL_PLACE_ICON, icon)
                if (lat != null) put(COL_PLACE_LAT_ENCRYPTED, cryptoManager.encrypt(lat.toString()))
                if (lng != null) put(COL_PLACE_LNG_ENCRYPTED, cryptoManager.encrypt(lng.toString()))
                if (radius != null) put(COL_PLACE_RADIUS, radius)
                if (status != null) put(COL_PLACE_STATUS, status)
                if (triggerType != null) put(COL_PLACE_TRIGGER_TYPE, triggerType)
                put(COL_PLACE_UPDATED, updatedAt)
                put(COL_PLACE_DIRTY, dirty)
            }
            writableDatabase.update(TABLE_PLACES, values, "$COL_PLACE_ID = ?", arrayOf(id))
        } catch (e: Exception) {
            Log.e(TAG, "Error updating encrypted place $id", e)
        }
    }

    fun clearLearningPointsEncrypted() {
        try {
            writableDatabase.delete(TABLE_LEARNING_POINTS, null, null)
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing learning points", e)
        }
    }

    fun deleteLearningPointsOlderThanEncrypted(cutoff: Long) {
        try {
            writableDatabase.delete(
                TABLE_LEARNING_POINTS,
                "$COL_LP_TIMESTAMP < ?",
                arrayOf(cutoff.toString())
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting old learning points", e)
        }
    }

    fun deleteLearningPointsWithinEncrypted(lat: Double, lng: Double, radiusM: Double) {
        try {
            val allPoints = getAllLearningPointsDecrypted()
            for (point in allPoints) {
                val pLat = (point[COL_LP_LAT] as Double)
                val pLng = (point[COL_LP_LNG] as Double)
                val distance = haversine(lat, lng, pLat, pLng)
                if (distance <= radiusM) {
                    val timestamp = point[COL_LP_TIMESTAMP] as Long
                    Log.d(TAG, "Purging learning point at ($pLat, $pLng) within ${radiusM}m")
                    writableDatabase.delete(
                        TABLE_LEARNING_POINTS,
                        "$COL_LP_TIMESTAMP = ?",
                        arrayOf(timestamp.toString())
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error purging learning points within radius", e)
        }
    }

    private fun haversine(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val p = Math.PI / 180.0
        val a = 0.5 - kotlin.math.cos((lat2 - lat1) * p) / 2 +
                kotlin.math.cos(lat1 * p) * kotlin.math.cos(lat2 * p) *
                (1 - kotlin.math.cos((lng2 - lng1) * p)) / 2
        return 12742000.0 * kotlin.math.asin(kotlin.math.sqrt(a))
    }

    // Return row counts for storage stats
    fun getTableRowCount(tableName: String): Long {
        var cursor: Cursor? = null
        try {
            cursor = readableDatabase.rawQuery("SELECT COUNT(*) FROM $tableName", null)
            if (cursor.moveToFirst()) {
                return cursor.getLong(0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error counting $tableName", e)
        } finally {
            cursor?.close()
        }
        return 0
    }

    fun getDatabasePageCount(): Long {
        var cursor: Cursor? = null
        try {
            cursor = readableDatabase.rawQuery("PRAGMA page_count", null)
            if (cursor.moveToFirst()) {
                return cursor.getLong(0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting page count", e)
        } finally {
            cursor?.close()
        }
        return 0
    }

    fun getDatabasePageSize(): Long {
        var cursor: Cursor? = null
        try {
            cursor = readableDatabase.rawQuery("PRAGMA page_size", null)
            if (cursor.moveToFirst()) {
                return cursor.getLong(0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting page size", e)
        } finally {
            cursor?.close()
        }
        return 4096L
    }

    fun getConfirmedPlaces(): List<PlaceData> {
        val list = mutableListOf<PlaceData>()
        try {
            var cursor: Cursor? = null
            try {
                cursor = readableDatabase.query(
                    TABLE_PLACES,
                    arrayOf(COL_PLACE_ID, COL_PLACE_LABEL, COL_PLACE_LAT_ENCRYPTED, COL_PLACE_LNG_ENCRYPTED, COL_PLACE_RADIUS, COL_PLACE_TRIGGER_TYPE),
                    "$COL_PLACE_STATUS = ?",
                    arrayOf("confirmed"),
                    null, null, null
                )
                while (cursor.moveToNext()) {
                    val id = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_ID))
                    val label = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LABEL))
                    val latEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LAT_ENCRYPTED))
                    val lngEncrypted = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_LNG_ENCRYPTED))
                    val lat = cryptoManager.decrypt(latEncrypted).toDouble()
                    val lng = cryptoManager.decrypt(lngEncrypted).toDouble()
                    val radius = cursor.getFloat(cursor.getColumnIndexOrThrow(COL_PLACE_RADIUS))
                    val triggerType = cursor.getString(cursor.getColumnIndexOrThrow(COL_PLACE_TRIGGER_TYPE))
                    list.add(PlaceData(id, label, lat, lng, radius, triggerType))
                }
            } finally {
                cursor?.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting confirmed places", e)
        }
        return list
    }

    fun getActiveVisitForPlace(placeId: String): Pair<String, Long>? {
        try {
            var cursor: Cursor? = null
            try {
                cursor = readableDatabase.query(
                    TABLE_VISITS,
                    arrayOf(COL_VISIT_ID, COL_VISIT_ENTER),
                    "$COL_VISIT_PLACE_ID = ? AND $COL_VISIT_EXIT IS NULL",
                    arrayOf(placeId),
                    null, null, "$COL_VISIT_ENTER DESC", "1"
                )
                if (cursor.moveToFirst()) {
                    val visitId = cursor.getString(cursor.getColumnIndexOrThrow(COL_VISIT_ID))
                    val enterTs = cursor.getLong(cursor.getColumnIndexOrThrow(COL_VISIT_ENTER))
                    return Pair(visitId, enterTs)
                }
            } finally {
                cursor?.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting active visit for place $placeId", e)
        }
        return null
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

data class LocationLog(
    val id: Long,
    val lat: Double,
    val lng: Double,
    val accuracy: Float?,
    val altitude: Double?,
    val speed: Float?,
    val timestampHw: Long,
    val timestampSystem: Long,
    val source: String
)

data class WebhookQueueItem(
    val id: Long,
    val payloadJson: String,
    val endpointUrl: String,
    val headersJson: String?,
    val retryCount: Int,
    val createdAt: Long,
    val scheduledAt: Long
)

data class GeofenceTransition(
    val id: Long,
    val placeId: String,
    val transitionType: String,
    val timestampHw: Long,
    val timestampSystem: Long,
    val accuracy: Float?,
    val dwellDurationMs: Long?
)
