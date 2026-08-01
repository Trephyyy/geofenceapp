import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/place.dart';
import '../models/visit.dart';
import '../models/learning_point.dart';

class DbService {
  static final DbService _instance = DbService._internal();
  factory DbService() => _instance;
  DbService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  Future<Database> initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'geofence.db');

    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS places (
            id TEXT PRIMARY KEY,
            server_id TEXT,
            label TEXT NOT NULL,
            icon TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            radius_m REAL NOT NULL,
            status TEXT NOT NULL,
            trigger_type TEXT NOT NULL DEFAULT 'normal',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            dirty INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS visits (
            id TEXT PRIMARY KEY,
            server_id TEXT,
            place_id TEXT NOT NULL,
            enter_ts INTEGER NOT NULL,
            exit_ts INTEGER,
            duration_s INTEGER,
            source TEXT NOT NULL,
            dirty INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(place_id) REFERENCES places(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS learning_points (
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            timestamp INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS event_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            type TEXT NOT NULL,
            place_id TEXT,
            place_label TEXT,
            message TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute("ALTER TABLE places ADD COLUMN trigger_type TEXT NOT NULL DEFAULT 'normal'");
          } catch (_) {}
        }
        if (oldVersion < 3) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS event_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                type TEXT NOT NULL,
                place_id TEXT,
                place_label TEXT,
                message TEXT NOT NULL
              )
            ''');
          } catch (_) {}
        }
      },
    );
    return _db!;
  }

  // --- Places CRUD ---

  Future<void> insertPlace(Place place) async {
    final db = await database;
    await db.insert(
      'places',
      place.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updatePlace(Place place) async {
    final db = await database;
    await db.update(
      'places',
      place.toMap(),
      where: 'id = ?',
      whereArgs: [place.id],
    );
  }

  Future<void> deletePlace(String id) async {
    final db = await database;
    await db.delete(
      'places',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Place?> getPlace(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'places',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Place.fromMap(maps.first);
  }

  Future<List<Place>> getAllPlaces() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('places');
    return maps.map((map) => Place.fromMap(map)).toList();
  }

  // --- Visits CRUD ---

  Future<void> insertVisit(Visit visit) async {
    final db = await database;
    await db.insert(
      'visits',
      visit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateVisit(Visit visit) async {
    final db = await database;
    await db.update(
      'visits',
      visit.toMap(),
      where: 'id = ?',
      whereArgs: [visit.id],
    );
  }

  Future<void> deleteVisit(String id) async {
    final db = await database;
    await db.delete(
      'visits',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Visit>> getAllVisits() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'visits',
      orderBy: 'enter_ts DESC',
    );
    return maps.map((map) => Visit.fromMap(map)).toList();
  }

  Future<List<Visit>> getVisitsForPlace(String placeId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'visits',
      where: 'place_id = ?',
      whereArgs: [placeId],
      orderBy: 'enter_ts DESC',
    );
    return maps.map((map) => Visit.fromMap(map)).toList();
  }

  // --- Learning Points CRUD ---

  Future<void> insertLearningPoint(LearningPoint point) async {
    final db = await database;
    await db.insert(
      'learning_points',
      point.toMap(),
    );
  }

  Future<List<LearningPoint>> getAllLearningPoints() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'learning_points',
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => LearningPoint.fromMap(map)).toList();
  }

  Future<void> clearLearningPoints() async {
    final db = await database;
    await db.delete('learning_points');
  }

  Future<void> deleteLearningPointsOlderThan(DateTime time) async {
    final db = await database;
    await db.delete(
      'learning_points',
      where: 'timestamp < ?',
      whereArgs: [time.millisecondsSinceEpoch],
    );
  }

  // --- Event Logs CRUD ---

  Future<void> insertEventLog(Map<String, dynamic> log) async {
    final db = await database;
    await db.insert('event_logs', log);
  }

  Future<List<Map<String, dynamic>>> getEventLogs({int limit = 200}) async {
    final db = await database;
    final result = await db.query(
      'event_logs',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return result;
  }

  Future<void> clearEventLogs() async {
    final db = await database;
    await db.delete('event_logs');
  }

  Future<int> getEventLogCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM event_logs');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
