import 'dart:developer';

class SyncQueue {
  static final SyncQueue _instance = SyncQueue._internal();
  factory SyncQueue() => _instance;
  SyncQueue._internal();

  /// Enqueues a sync task.
  ///
  /// This is a no-op stub for the MVP, acting as the architectural integration seam
  /// for v2 sync engines (e.g. Firebase, Supabase, or custom outbound webhooks).
  Future<void> enqueue({
    required String entityType, // 'place' | 'visit'
    required String entityId,
    required String operation, // 'create' | 'update' | 'delete'
  }) async {
    log('SyncQueue: Enqueued $operation for $entityType ($entityId). Ready for sync in v2.');
  }
}
