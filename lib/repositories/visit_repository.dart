import '../models/visit.dart';
import '../services/db_service.dart';
import '../services/sync_queue.dart';

class VisitRepository {
  final DbService _dbService = DbService();
  final SyncQueue _syncQueue = SyncQueue();

  Future<List<Visit>> getAllVisits() => _dbService.getAllVisits();

  Future<List<Visit>> getVisitsForPlace(String placeId) =>
      _dbService.getVisitsForPlace(placeId);

  Future<void> addVisit(Visit visit) async {
    final updated = visit.copyWith(dirty: true);
    await _dbService.insertVisit(updated);
    await _syncQueue.enqueue(
      entityType: 'visit',
      entityId: visit.id,
      operation: 'create',
    );
  }

  Future<void> updateVisit(Visit visit) async {
    final updated = visit.copyWith(dirty: true);
    await _dbService.updateVisit(updated);
    await _syncQueue.enqueue(
      entityType: 'visit',
      entityId: visit.id,
      operation: 'update',
    );
  }

  Future<void> deleteVisit(String id) async {
    await _dbService.deleteVisit(id);
    await _syncQueue.enqueue(
      entityType: 'visit',
      entityId: id,
      operation: 'delete',
    );
  }
}
