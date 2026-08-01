import 'dart:math';
import 'db_service.dart';
import 'native_geofence_service.dart';
import '../models/learning_point.dart';
import '../models/place.dart';

class StationarySession {
  final List<LearningPoint> points;
  late double lat;
  late double lng;

  StationarySession(this.points) {
    if (points.isEmpty) {
      lat = 0;
      lng = 0;
      return;
    }
    double sumLat = 0;
    double sumLng = 0;
    for (final p in points) {
      sumLat += p.lat;
      sumLng += p.lng;
    }
    lat = sumLat / points.length;
    lng = sumLng / points.length;
  }

  int get durationMs =>
      points.last.timestamp.difference(points.first.timestamp).inMilliseconds;
  DateTime get startTime => points.first.timestamp;
  DateTime get endTime => points.last.timestamp;
}

class SuggestedCluster {
  double lat;
  double lng;
  final List<StationarySession> sessions;

  SuggestedCluster({
    required this.lat,
    required this.lng,
    required this.sessions,
  });

  int get visitCount => sessions.length;

  double get averageDurationMinutes {
    if (sessions.isEmpty) return 0;
    final totalMs = sessions.fold<int>(0, (sum, s) => sum + s.durationMs);
    return (totalMs / sessions.length) / (60 * 1000);
  }
}

class ClusteringService {
  static final ClusteringService _instance = ClusteringService._internal();
  factory ClusteringService() => _instance;
  ClusteringService._internal();

  final DbService _dbService = DbService();
  final NativeGeofenceService _geofenceService = NativeGeofenceService();

  /// Calculate distance in meters using Haversine formula
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lng2 - lng1) * p)) / 2;
    return 12742000 * asin(sqrt(a)); // 2 * R; R = 6371000 m
  }

  /// Processes learning points and generates place suggestions.
  Future<List<SuggestedCluster>> getSuggestedPlaces({
    double mergeRadiusMeters = 150.0,
    int minDwellMinutes = 20,
    int minVisits = 3,
  }) async {
    final points = await _dbService.getAllLearningPoints();
    if (points.isEmpty) return [];

    // 1. Group points into temporal stationary sessions
    // Points are taken every 10-15 minutes. If gap > 20 minutes, it's a new session.
    final List<StationarySession> sessions = [];
    List<LearningPoint> currentSessionPoints = [];

    for (final p in points) {
      if (currentSessionPoints.isEmpty) {
        currentSessionPoints.add(p);
      } else {
        final lastPoint = currentSessionPoints.last;
        final gap = p.timestamp.difference(lastPoint.timestamp).inMinutes;

        if (gap <= 20) {
          currentSessionPoints.add(p);
        } else {
          // Close current session and start a new one
          sessions.add(StationarySession(currentSessionPoints));
          currentSessionPoints = [p];
        }
      }
    }
    if (currentSessionPoints.isNotEmpty) {
      sessions.add(StationarySession(currentSessionPoints));
    }

    // 2. Filter sessions by minimum dwell time
    final validSessions = sessions.where((s) {
      return s.durationMs >= (minDwellMinutes * 60 * 1000);
    }).toList();

    if (validSessions.isEmpty) return [];

    // 3. Cluster sessions spatially
    final List<SuggestedCluster> clusters = [];

    for (final session in validSessions) {
      SuggestedCluster? nearestCluster;
      double minDistance = mergeRadiusMeters;

      for (final cluster in clusters) {
        final distance = calculateDistance(
          session.lat,
          session.lng,
          cluster.lat,
          cluster.lng,
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearestCluster = cluster;
        }
      }

      if (nearestCluster != null) {
        nearestCluster.sessions.add(session);

        // Recalculate cluster centroid
        double sumLat = 0;
        double sumLng = 0;
        for (final s in nearestCluster.sessions) {
          sumLat += s.lat;
          sumLng += s.lng;
        }
        nearestCluster.lat = sumLat / nearestCluster.sessions.length;
        nearestCluster.lng = sumLng / nearestCluster.sessions.length;
      } else {
        clusters.add(
          SuggestedCluster(
            lat: session.lat,
            lng: session.lng,
            sessions: [session],
          ),
        );
      }
    }

    // 4. Fetch confirmed places to filter out clusters that overlap
    final places = await _dbService.getAllPlaces();
    final confirmedPlaces = places
        .where((p) => p.status == PlaceStatus.confirmed)
        .toList();

    // 5. Filter clusters by minimum visits and exclude already confirmed areas
    return clusters.where((cluster) {
      // Must meet minimum visit counts
      if (cluster.visitCount < minVisits) return false;

      // Must not overlap with an existing confirmed place (within radius + merge offset)
      for (final place in confirmedPlaces) {
        final distance = calculateDistance(
          cluster.lat,
          cluster.lng,
          place.lat,
          place.lng,
        );
        if (distance < (place.radiusM + mergeRadiusMeters)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Purge learning points within a radius using native (decrypts, checks, deletes).
  Future<void> purgeLearningPointsWithin(
    double lat,
    double lng,
    double radiusM,
  ) async {
    await _geofenceService.purgeLearningPointsWithinNative(lat, lng, radiusM);
  }
}
