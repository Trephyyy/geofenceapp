import 'dart:async';
import 'db_service.dart';

enum EventType {
  entered,
  left,
  startedTracking,
  stoppedTracking,
  polledLocation,
  geofenceRegistered,
  geofenceUnregistered,
  learningStarted,
  learningStopped,
  placeConfirmed,
  placeDeleted,
  webhookDispatched,
  historyPurged,
  system,
}

class EventLog {
  final int? id;
  final DateTime timestamp;
  final EventType type;
  final String? placeId;
  final String? placeLabel;
  final String message;

  EventLog({
    this.id,
    required this.timestamp,
    required this.type,
    this.placeId,
    this.placeLabel,
    required this.message,
  });

  factory EventLog.fromMap(Map<String, dynamic> map) {
    return EventLog(
      id: map['id'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      type: EventType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => EventType.system,
      ),
      placeId: map['place_id'] as String?,
      placeLabel: map['place_label'] as String?,
      message: map['message'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'type': type.name,
      'place_id': placeId,
      'place_label': placeLabel,
      'message': message,
    };
  }
}

class EventLoggerService {
  static final EventLoggerService _instance = EventLoggerService._internal();
  factory EventLoggerService() => _instance;
  EventLoggerService._internal();

  final DbService _dbService = DbService();
  final List<EventLog> _recentLogs = [];
  final StreamController<EventLog> _logController = StreamController<EventLog>.broadcast();
  Stream<EventLog> get onNewLog => _logController.stream;

  static const int _maxMemoryLogs = 500;

  Future<void> log(EventLog entry) async {
    _recentLogs.insert(0, entry);
    if (_recentLogs.length > _maxMemoryLogs) {
      _recentLogs.removeLast();
    }
    _logController.add(entry);
    try {
      await _dbService.insertEventLog(entry.toMap());
    } catch (_) {}
  }

  Future<void> logEntered(String placeLabel, {String? placeId}) async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.entered,
      placeId: placeId,
      placeLabel: placeLabel,
      message: 'Entered $placeLabel',
    ));
  }

  Future<void> logLeft(String placeLabel, {String? placeId, String? duration}) async {
    final suffix = duration != null ? ' ($duration)' : '';
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.left,
      placeId: placeId,
      placeLabel: placeLabel,
      message: 'Left $placeLabel$suffix',
    ));
  }

  Future<void> logStartedTracking() async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.startedTracking,
      message: 'Started tracking',
    ));
  }

  Future<void> logStoppedTracking() async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.stoppedTracking,
      message: 'Stopped tracking',
    ));
  }

  Future<void> logPolledLocation() async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.polledLocation,
      message: 'Polled location',
    ));
  }

  Future<void> logLearningStarted() async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.learningStarted,
      message: 'Passive learning mode started',
    ));
  }

  Future<void> logLearningStopped() async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.learningStopped,
      message: 'Passive learning mode stopped',
    ));
  }

  Future<void> logGeofenceRegistered(String label) async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.geofenceRegistered,
      placeLabel: label,
      message: 'Geofence registered for $label',
    ));
  }

  Future<void> logGeofenceUnregistered(String label) async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.geofenceUnregistered,
      placeLabel: label,
      message: 'Geofence unregistered for $label',
    ));
  }

  Future<void> logPlaceConfirmed(String label) async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.placeConfirmed,
      placeLabel: label,
      message: 'Place confirmed: $label',
    ));
  }

  Future<void> logPlaceDeleted(String label) async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.placeDeleted,
      placeLabel: label,
      message: 'Place deleted: $label',
    ));
  }

  Future<void> logWebhookDispatched() async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.webhookDispatched,
      message: 'Webhook event dispatched',
    ));
  }

  Future<void> logHistoryPurged() async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.historyPurged,
      message: 'All history purged',
    ));
  }

  Future<void> logSystem(String message) async {
    await log(EventLog(
      timestamp: DateTime.now(),
      type: EventType.system,
      message: message,
    ));
  }

  Future<List<EventLog>> getRecentLogs({int limit = 200}) async {
    if (_recentLogs.length >= limit) {
      return _recentLogs.take(limit).toList();
    }
    try {
      final dbLogs = await _dbService.getEventLogs(limit: limit);
      final result = dbLogs.map((m) => EventLog.fromMap(m)).toList();
      return result;
    } catch (_) {
      return List.from(_recentLogs);
    }
  }

  Future<void> clearAll() async {
    _recentLogs.clear();
    try {
      await _dbService.clearEventLogs();
    } catch (_) {}
  }

  void dispose() {
    _logController.close();
  }
}
