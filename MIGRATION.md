# Data Migration: SQLCipher → Android KeyStore Field Encryption

## What changed

- **SQLCipher removed**: The `net.zetetic:sqlcipher-android` dependency has been removed. The database is now opened with standard Android SQLite via `android.database.sqlite.SQLiteOpenHelper`.

- **Application-level field encryption**: Instead of whole-database encryption via SQLCipher, sensitive fields are encrypted individually using AES-256-GCM through the hardware-backed Android KeyStore. The encryption key is stored exclusively in the Android KeyStore (alias: `GeofenceAppMasterKey`) and never leaves secure hardware.

- **New `CryptoManager` singleton**: Handles all encryption/decryption operations. Thread-safe — no shared `Cipher` instance. IVs are generated fresh via `SecureRandom` for every encryption call.

## Schema changes (database version 4 → 5)

| Table | Change |
|---|---|
| `location_logs` | `lat`/`lng` → `lat_encrypted`/`lng_encrypted` (Base64 AES-GCM), ID changed from TEXT (UUID) to INTEGER PRIMARY KEY AUTOINCREMENT |
| `geofence_transitions` | ID changed from TEXT (UUID) to INTEGER PRIMARY KEY AUTOINCREMENT. All columns remain plaintext. |
| `webhook_queue` | `payload_json`/`endpoint_url`/`headers_json` → `payload_encrypted`/`endpoint_url_encrypted`/`headers_encrypted` (Base64 AES-GCM), ID changed from TEXT (UUID) to INTEGER PRIMARY KEY AUTOINCREMENT |
| `places`, `visits`, `learning_points` | Unchanged |

## Automatic migration on first launch

On the first app launch after upgrading, `onUpgrade` runs:

1. Detects old plaintext schema via `PRAGMA table_info()`.
2. For each table, creates a `_new` table with the v5 schema.
3. Reads all rows from the old table, encrypts the designated fields using `CryptoManager`, and inserts into the new table.
4. Drops the old table and renames the new table in its place.
5. All operations run inside a single SQLite transaction — if anything fails, the entire migration rolls back.

This means **existing plaintext location data will be encrypted automatically** on the very first database open after the upgrade. No user action is required.

## Rollback safety

If the app is downgraded, the v5 database will not be readable by the old SQLCipher-based code. Before downgrading, export any needed data.
