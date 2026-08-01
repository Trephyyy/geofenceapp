package com.example.geofenceapp

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * DebugLogger: persistent, ring-buffered debug log for maritime audit trail.
 *
 * Ring buffer: keeps newest 500 entries; older entries auto-purged on insert.
 * Privacy: extra_json NEVER contains lat/lng — those keys are redacted to "<redacted>".
 * Thread-safe via synchronized. Zero crash risk — all exceptions swallowed.
 */
object DebugLogger {
    private const val TAG = "DebugLogger"
    private const val TABLE = "debug_logs"
    private const val MAX_ENTRIES = 500
    private const val RATE_LIMIT_WINDOW_MS = 60_000L
    private const val MAX_RAPID_FIRE = 50

    private val REDACTED_KEYS = setOf("lat", "lng", "latitude", "longitude")

    @Volatile
    private var enabled = true

    private var db: SQLiteDatabase? = null
    private val rateLimitTimestamps = mutableListOf<Long>()
    private val rateLimitLock = Any()
    @Volatile
    private var lastRateLimitWarning = 0L
    @Volatile
    private var initAttempted = false

    fun init(context: Context) {
        if (initAttempted) return
        initAttempted = true
        try {
            context.applicationContext.let { ctx ->
                db = DbHelper(ctx).openWritableDatabase()
                enabled = ctx.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                    .getBoolean("debug_logging_enabled", true)
            }
            purgeOldLogs()
        } catch (e: Exception) {
            Log.e(TAG, "DebugLogger init failed", e)
        }
    }

    fun setEnabled(e: Boolean) {
        enabled = e
        try {
            val ctx = contextRef() ?: return
            ctx.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                .edit().putBoolean("debug_logging_enabled", e).apply()
        } catch (_: Exception) { }
    }

    fun isEnabled(): Boolean = enabled

    fun d(category: String, message: String, placeId: String? = null, extra: Map<String, Any>? = null) {
        log("DEBUG", category, message, placeId, extra)
    }

    fun i(category: String, message: String, placeId: String? = null, extra: Map<String, Any>? = null) {
        log("INFO", category, message, placeId, extra)
    }

    fun w(category: String, message: String, placeId: String? = null, extra: Map<String, Any>? = null) {
        log("WARN", category, message, placeId, extra)
    }

    fun e(category: String, message: String, throwable: Throwable? = null, placeId: String? = null, extra: Map<String, Any>? = null) {
        val extraWithError = if (throwable != null) {
            val map = extra?.toMutableMap() ?: mutableMapOf()
            map["error"] = throwable.javaClass.simpleName + ": " + (throwable.message ?: "")
            map
        } else extra
        log("ERROR", category, message, placeId, extraWithError)
    }

    private fun log(level: String, category: String, message: String, placeId: String?, extra: Map<String, Any>?) {
        if (!enabled) return
        if (isRateLimited()) return
        writeLogInternal(level, category, message, placeId, extra)
    }

    private fun isRateLimited(): Boolean {
        val now = System.currentTimeMillis()
        synchronized(rateLimitLock) {
            rateLimitTimestamps.removeAll { it < now - RATE_LIMIT_WINDOW_MS }
            rateLimitTimestamps.add(now)
            if (rateLimitTimestamps.size > MAX_RAPID_FIRE) {
                if (lastRateLimitWarning < now - RATE_LIMIT_WINDOW_MS) {
                    lastRateLimitWarning = now
                    val suppressed = rateLimitTimestamps.size - MAX_RAPID_FIRE
                    writeLogInternal("WARN", "SYSTEM", "Log throttling active. Suppressed $suppressed rapid-fire entries.", null, null)
                }
                return true
            }
            return false
        }
    }

    private fun writeLogInternal(level: String, category: String, message: String, placeId: String?, extra: Map<String, Any>?) {
        synchronized(this) {
            try {
                val database = db ?: return
                val now = System.currentTimeMillis()
                val extraJson = extra?.let { sanitizeAndEncode(it) }

                val values = ContentValues().apply {
                    put("timestamp", now)
                    put("level", level)
                    put("category", category)
                    put("message", message)
                    if (placeId != null) put("place_id", placeId)
                    if (extraJson != null) put("extra_json", extraJson)
                }
                database.insert(TABLE, null, values)
                ringBufferTrim()
            } catch (_: Exception) { }
        }
    }

    private fun sanitizeAndEncode(extra: Map<String, Any>): String {
        val safe = JSONObject()
        for ((key, value) in extra) {
            safe.put(key, if (key in REDACTED_KEYS) "<redacted>" else value)
        }
        return safe.toString()
    }

    private fun ringBufferTrim() {
        try {
            val database = db ?: return
            database.execSQL("""
                DELETE FROM $TABLE WHERE id NOT IN (
                    SELECT id FROM $TABLE ORDER BY timestamp DESC LIMIT $MAX_ENTRIES
                )
            """.trimIndent())
        } catch (_: Exception) { }
    }

    fun purgeOldLogs() {
        try {
            val database = db ?: return
            val cutoff = System.currentTimeMillis() - (7L * 24 * 60 * 60 * 1000)
            val deleted = database.delete(TABLE, "timestamp < ?", arrayOf(cutoff.toString()))
            if (deleted > 0) {
                Log.d(TAG, "Purged $deleted debug log entries older than 7 days")
            }
        } catch (_: Exception) { }
    }

    fun getRecentLogs(limit: Int = 100): List<DebugLogEntry> {
        val entries = mutableListOf<DebugLogEntry>()
        try {
            val database = db ?: return entries
            var cursor: Cursor? = null
            try {
                cursor = database.query(TABLE, null, null, null, null, null, "timestamp DESC", limit.toString())
                while (cursor.moveToNext()) {
                    entries.add(parseEntry(cursor))
                }
            } finally {
                cursor?.close()
            }
        } catch (_: Exception) { }
        return entries
    }

    fun clearLogs() {
        try {
            val database = db ?: return
            database.delete(TABLE, null, null)
        } catch (_: Exception) { }
    }

    fun getLogCount(): Int {
        try {
            val database = db ?: return 0
            var cursor: Cursor? = null
            try {
                cursor = database.rawQuery("SELECT COUNT(*) FROM $TABLE", null)
                if (cursor.moveToFirst()) return cursor.getInt(0)
            } finally {
                cursor?.close()
            }
        } catch (_: Exception) { }
        return 0
    }

    fun exportAsText(): String {
        val entries = getRecentLogs(MAX_ENTRIES)
        val sb = StringBuilder()
        val df = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        for (entry in entries.reversed()) {
            sb.append("[${df.format(Date(entry.timestamp))}]")
            sb.append(" [${entry.level}]")
            sb.append(" [${entry.category}]")
            sb.append(" ${entry.message}")
            if (!entry.placeId.isNullOrBlank()) {
                sb.append(" (place: ${entry.placeId})")
            }
            if (!entry.extraJson.isNullOrBlank()) {
                sb.append(" | ${entry.extraJson}")
            }
            sb.append("\n")
        }
        return sb.toString()
    }

    private fun parseEntry(cursor: Cursor): DebugLogEntry {
        return DebugLogEntry(
            id = cursor.getLong(cursor.getColumnIndexOrThrow("id")),
            timestamp = cursor.getLong(cursor.getColumnIndexOrThrow("timestamp")),
            level = cursor.getString(cursor.getColumnIndexOrThrow("level")),
            category = cursor.getString(cursor.getColumnIndexOrThrow("category")),
            message = cursor.getString(cursor.getColumnIndexOrThrow("message")),
            placeId = cursor.getString(cursor.getColumnIndexOrThrow("place_id")),
            extraJson = cursor.getString(cursor.getColumnIndexOrThrow("extra_json"))
        )
    }

    private fun contextRef(): Context? {
        return try {
            val app = android.app.Application::class.java
            val activityThread = Class.forName("android.app.ActivityThread")
            val method = activityThread.getMethod("currentApplication")
            method.invoke(null) as? Context
        } catch (_: Exception) { null }
    }
}

data class DebugLogEntry(
    val id: Long,
    val timestamp: Long,
    val level: String,
    val category: String,
    val message: String,
    val placeId: String?,
    val extraJson: String?
)
