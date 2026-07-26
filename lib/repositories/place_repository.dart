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
    final updatedPlace = place.copyWith(dirty: true, updatedAt: DateTime.now());
    await _dbService.insertPlace(updatedPlace);
    await _syncQueue.enqueue(
      entityType: 'place',
      entityId: place.id,
      operation: 'create',
    );

    // If the place is created directly in the confirmed state, register the geofence
    if (updatedPlace.status == PlaceStatus.confirmed) {
      await _geofenceService.registerGeofence(
        id: updatedPlace.id,
        lat: updatedPlace.lat,
        lng: updatedPlace.lng,
        radius: updatedPlace.radiusM,
        triggerType: updatedPlace.triggerType.name,
      );
    }
  }

  Future<void> updatePlace(Place place) async {
    final updatedPlace = place.copyWith(dirty: true, updatedAt: DateTime.now());
    await _dbService.updatePlace(updatedPlace);
    await _syncQueue.enqueue(
      entityType: 'place',
      entityId: place.id,
      operation: 'update',
    );

    // If place is confirmed, register/update its geofence.
    // If it is changed back to learning or archived, unregister the geofence.
    if (updatedPlace.status == PlaceStatus.confirmed) {
      await _geofenceService.registerGeofence(
        id: updatedPlace.id,
        lat: updatedPlace.lat,
        lng: updatedPlace.lng,
        radius: updatedPlace.radiusM,
        triggerType: updatedPlace.triggerType.name,
      );
    } else {
      await _geofenceService.unregisterGeofence(updatedPlace.id);
    }
  }

  Future<void> deletePlace(String id) async {
    // Unregister geofence first
    await _geofenceService.unregisterGeofence(id);
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

    // Update status to learning
    final updatedPlace = place.copyWith(
      status: PlaceStatus.learning,
      dirty: true,
      updatedAt: DateTime.now(),
    );
    await _dbService.updatePlace(updatedPlace);
    await _syncQueue.enqueue(
      entityType: 'place',
      entityId: place.id,
      operation: 'update',
    );
  }
}
