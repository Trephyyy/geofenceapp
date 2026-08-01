import 'dart:async';

import 'package:flutter/services.dart';

class LocationData {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
  });
}

class GeofenceEvent {
  final String placeId;
  final String transition;
  final DateTime timestamp;

  const GeofenceEvent({
    required this.placeId,
    required this.transition,
    required this.timestamp,
  });
}

class DebugLogEntry {
  final int id;
  final int timestamp;
  final String level;
  final String category;
  final String message;
  final String placeId;
  final String extraJson;

  const DebugLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.placeId = '',
    this.extraJson = '',
  });

  factory DebugLogEntry.fromMap(Map<String, dynamic> map) {
    return DebugLogEntry(
      id: (map['id'] as num).toInt(),
      timestamp: (map['timestamp'] as num).toInt(),
      level: map['level'] as String,
      category: map['category'] as String,
      message: map['message'] as String,
      placeId: (map['placeId'] as String?) ?? '',
      extraJson: (map['extraJson'] as String?) ?? '',
    );
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  bool get hasExtra => extraJson.isNotEmpty && extraJson != '{}' && extraJson != 'null';
}

class DebugLogBridge {
  static const MethodChannel _channel = MethodChannel('com.example.geofenceapp/debug');

  Future<List<DebugLogEntry>> getLogs({int limit = 200}) async {
    final result = await _channel.invokeMethod<List<dynamic>>('getLogs', {'limit': limit});
    if (result == null) return [];
    return result.map((e) => DebugLogEntry.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> clearLogs() async {
    await _channel.invokeMethod('clearLogs');
  }

  Future<String> exportLogsToFile() async {
    final path = await _channel.invokeMethod<String>('exportLogsToFile');
    return path ?? '';
  }

  Future<void> setLoggingEnabled(bool enabled) async {
    await _channel.invokeMethod('setLoggingEnabled', {'enabled': enabled});
  }

  Future<bool> isLoggingEnabled() async {
    final result = await _channel.invokeMethod<bool>('isLoggingEnabled');
    return result ?? true;
  }

  Future<int> getLogCount() async {
    final result = await _channel.invokeMethod<int>('getLogCount');
    return result ?? 0;
  }
}

class LocationNativeBridge {
  static final LocationNativeBridge _instance = LocationNativeBridge._internal();
  factory LocationNativeBridge() => _instance;
  LocationNativeBridge._internal();

  static const MethodChannel _methodChannel = MethodChannel('com.example.geofenceapp/geofence');
  static const EventChannel _eventChannel = EventChannel('com.example.geofenceapp/geofence_events');

  final StreamController<GeofenceEvent> _eventController = StreamController<GeofenceEvent>.broadcast();
  StreamSubscription? _eventSub;
  Stream<GeofenceEvent> get geofenceEvents => _eventController.stream;

  void init() {
    _eventSub?.cancel();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        final map = event as Map<dynamic, dynamic>;
        _eventController.add(GeofenceEvent(
          placeId: map['placeId'] as String,
          transition: map['transition'] as String,
          timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        ));
      },
      onError: (Object e) {},
    );
  }

  Future<LocationData> getCurrentLocation() async {
    final result = await _methodChannel.invokeMapMethod<String, double>('getCurrentLocation');
    if (result == null || result['lat'] == null || result['lng'] == null) {
      throw Exception('Failed to get current location');
    }
    return LocationData(
      latitude: result['lat']!,
      longitude: result['lng']!,
      accuracy: result['accuracy'],
      altitude: result['altitude'],
      speed: result['speed'],
    );
  }

  Future<void> registerGeofence(String id, double lat, double lng, double radius) async {
    final success = await _methodChannel.invokeMethod<bool>('registerGeofence', {
      'id': id,
      'lat': lat,
      'lng': lng,
      'radius': radius,
    });
    if (success != true) throw Exception('Failed to register geofence');
  }

  Future<void> unregisterGeofence(String id) async {
    final success = await _methodChannel.invokeMethod<bool>('unregisterGeofence', {
      'id': id,
    });
    if (success != true) throw Exception('Failed to unregister geofence');
  }

  Future<void> configureWebhook(String endpoint, String? authHeader) async {
    final headersJson = authHeader != null
        ? '{"Authorization": "$authHeader"}'
        : '{}';
    const webhookChannel = MethodChannel('com.example.geofenceapp/webhook');
    final success = await webhookChannel.invokeMethod<bool>('configure', {
      'url': endpoint,
      'headersJson': headersJson,
    });
    if (success != true) throw Exception('Failed to configure webhook');
  }

  Future<void> requestPrivacyConsent() async {
    const privacyChannel = MethodChannel('com.example.geofenceapp/privacy');
    final granted = await privacyChannel.invokeMethod<bool>('grantConsent');
    if (granted != true) throw Exception('Failed to grant privacy consent');
  }

  Future<void> purgeAllHistory() async {
    const privacyChannel = MethodChannel('com.example.geofenceapp/privacy');
    final success = await privacyChannel.invokeMethod<bool>('purgeAllHistory');
    if (success != true) throw Exception('Failed to purge history');
  }

  void dispose() {
    _eventSub?.cancel();
    _eventController.close();
  }
}