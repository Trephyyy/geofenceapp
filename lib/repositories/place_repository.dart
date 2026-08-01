import '../models/place.dart';
import '../services/db_service.dart';
import '../services/sync_queue.dart';
import '../services/native_geofence_service.dart';

class PlaceRepository {
  final DbService _dbService = DbService();
  final SyncQueue _syncQueue = SyncQueue();
  final NativeGeofenceService _geofenceService = NativeGeofenceService();

  Future<List<Place>> getAllPlaces() => _dbService.getAllPlaces();

  Future<Place?> getPlace(String id) => _dbService.getPlace(id);

  Future<void> addPlace(Place place) async {
    // Route through native for encrypted lat/lng storage
    final saved = await _geofenceService.savePlace(
      id: place.id,
      label: place.label,
      icon: place.icon.name,
      lat: place.lat,
      lng: place.lng,
      radius: place.radiusM,
      status: place.status.name,
      triggerType: place.triggerType.name,
      createdAt: place.createdAt.toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
      dirty: 1,
    );
    if (!saved) {
      // Fallback to direct DB write
      final updatedPlace = place.copyWith(
        dirty: true,
        updatedAt: DateTime.now(),
      );
      await _dbService.insertPlace(updatedPlace);
    }
    await _syncQueue.enqueue(
      entityType: 'place',
      entityId: place.id,
      operation: 'create',
    );

    // If the place is created directly in the confirmed state, register the geofence
    if (place.status == PlaceStatus.confirmed) {
      await _geofenceService.registerGeofence(
        id: place.id,
        lat: place.lat,
        lng: place.lng,
        radius: place.radiusM,
        triggerType: place.triggerType.name,
      );
    }
  }

  Future<void> updatePlace(Place place) async {
    // Route through native for encrypted lat/lng storage
    final saved = await _geofenceService.updatePlaceNative(
      id: place.id,
      label: place.label,
      icon: place.icon.name,
      lat: place.lat,
      lng: place.lng,
      radius: place.radiusM,
      status: place.status.name,
      triggerType: place.triggerType.name,
      updatedAt: DateTime.now().toIso8601String(),
      dirty: 1,
    );
    if (!saved) {
      // Fallback to direct DB write
      final updatedPlace = place.copyWith(
        dirty: true,
        updatedAt: DateTime.now(),
      );
      await _dbService.updatePlace(updatedPlace);
    }
    await _syncQueue.enqueue(
      entityType: 'place',
      entityId: place.id,
      operation: 'update',
    );

    // If place is confirmed, register/update its geofence.
    // If it is changed back to learning or archived, unregister the geofence.
    if (place.status == PlaceStatus.confirmed) {
      await _geofenceService.registerGeofence(
        id: place.id,
        lat: place.lat,
        lng: place.lng,
        radius: place.radiusM,
        triggerType: place.triggerType.name,
      );
    } else {
      await _geofenceService.unregisterGeofence(place.id);
    }
  }

  Future<void> deletePlace(String id) async {
    // Unregister geofence first
    await _geofenceService.unregisterGeofence(id);
    // Route through native for encrypted storage
    await _geofenceService.deletePlaceNative(id);
    await _dbService.deletePlace(id);
    await _syncQueue.enqueue(
      entityType: 'place',
      entityId: id,
      operation: 'delete',
    );
  }

  Future<void> reEnterLearningMode(Place place) async {
    // Unregister geofence
    await _geofenceService.unregisterGeofence(place.id);

    // Update status to learning via native
    await _geofenceService.updatePlaceNative(
      id: place.id,
      status: PlaceStatus.learning.name,
      updatedAt: DateTime.now().toIso8601String(),
      dirty: 1,
    );
    await _syncQueue.enqueue(
      entityType: 'place',
      entityId: place.id,
      operation: 'update',
    );
  }
}
