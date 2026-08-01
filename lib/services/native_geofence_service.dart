import 'dart:async';
import 'package:flutter/services.dart';

class NativeGeofenceService {
  static final NativeGeofenceService _instance =
      NativeGeofenceService._internal();
  factory NativeGeofenceService() => _instance;
  NativeGeofenceService._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
    _privacyChannel.setMethodCallHandler(_handlePrivacyMethodCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'com.example.geofenceapp/geofence',
  );

  static const MethodChannel _privacyChannel = MethodChannel(
    'com.example.geofenceapp/privacy',
  );

  static const MethodChannel _webhookChannel = MethodChannel(
    'com.example.geofenceapp/webhook',
  );

  final _transitionController =
      StreamController<Map<String, String>>.broadcast();
  final _learningPointsUpdatedController = StreamController<void>.broadcast();
  final _consentRevokedController = StreamController<void>.broadcast();

  Stream<Map<String, String>> get transitionStream =>
      _transitionController.stream;
  Stream<void> get learningPointsUpdatedStream =>
      _learningPointsUpdatedController.stream;
  Stream<void> get consentRevokedStream => _consentRevokedController.stream;

  // ========== Webhook Configuration ==========

  Future<bool> configureWebhook({
    required String url,
    String headersJson = '{}',
  }) async {
    try {
      final result = await _webhookChannel.invokeMethod<bool>('configure', {
        'url': url,
        'headersJson': headersJson,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> getWebhookConfig() async {
    try {
      final result = await _webhookChannel.invokeMapMethod<String, String>(
        'getConfig',
      );
      return {
        'url': result?['url'] ?? '',
        'headersJson': result?['headersJson'] ?? '{}',
      };
    } on PlatformException catch (_) {
      return {'url': '', 'headersJson': '{}'};
    }
  }

  Future<bool> clearWebhookConfig() async {
    try {
      final result = await _webhookChannel.invokeMethod<bool>('clearConfig');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  // ========== Privacy / Consent ==========

  Future<bool> hasConsent() async {
    try {
      final result = await _privacyChannel.invokeMethod<bool>('hasConsent');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> grantConsent() async {
    try {
      final result = await _privacyChannel.invokeMethod<bool>('grantConsent');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> revokeConsent() async {
    try {
      final result = await _privacyChannel.invokeMethod<bool>('revokeConsent');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> purgeAllHistory() async {
    try {
      final result = await _privacyChannel.invokeMethod<bool>(
        'purgeAllHistory',
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  // ========== Geofence Methods ==========

  Future<bool> startLearning() async {
    try {
      final result = await _channel.invokeMethod<bool>('startLearning');
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'CONSENT_DENIED') rethrow;
      return false;
    }
  }

  Future<bool> stopLearning() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopLearning');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> isLearningRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isLearningRunning');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> registerGeofence({
    required String id,
    required double lat,
    required double lng,
    required double radius,
    String triggerType = 'normal',
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('registerGeofence', {
        'id': id,
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'triggerType': triggerType,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> unregisterGeofence(String id) async {
    try {
      final result = await _channel.invokeMethod<bool>('unregisterGeofence', {
        'id': id,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> isIgnoreBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isIgnoreBatteryOptimizations',
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<Map<String, double>?> getCurrentLocation() async {
    try {
      final result = await _channel.invokeMapMethod<String, double>(
        'getCurrentLocation',
      );
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } on PlatformException catch (_) {}
  }

  // ========== Encrypted Native CRUD ==========

  /// Saves a place via native method channel (encrypted lat/lng).
  Future<bool> savePlace({
    required String id,
    required String label,
    required String icon,
    required double lat,
    required double lng,
    required double radius,
    required String status,
    required String triggerType,
    required String createdAt,
    required String updatedAt,
    int dirty = 0,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('savePlace', {
        'id': id,
        'label': label,
        'icon': icon,
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'status': status,
        'triggerType': triggerType,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'dirty': dirty,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'CONSENT_DENIED') rethrow;
      return false;
    }
  }

  /// Inserts a learning point via native (encrypted lat/lng).
  Future<bool> insertLearningPoint({
    required double lat,
    required double lng,
    required int timestamp,
    String source = 'FLUTTER',
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('insertLearningPoint', {
        'lat': lat,
        'lng': lng,
        'timestamp': timestamp,
        'source': source,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Returns storage stats: row counts per table and total DB size.
  Future<Map<String, int>?> getStorageStats() async {
    try {
      final result = await _channel.invokeMapMethod<String, int>(
        'getStorageStats',
      );
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Get all places (decrypted from native).
  Future<List<Map<String, dynamic>>?> getAllPlacesNative() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getAllPlaces');
      return result?.cast<Map<String, dynamic>>();
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Get a single place (decrypted from native).
  Future<Map<String, dynamic>?> getPlaceNative(String id) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getPlace',
        {'id': id},
      );
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Update a place via native (encrypted lat/lng).
  Future<bool> updatePlaceNative({
    required String id,
    String? label,
    String? icon,
    double? lat,
    double? lng,
    double? radius,
    String? status,
    String? triggerType,
    required String updatedAt,
    int dirty = 0,
  }) async {
    try {
      final args = <String, dynamic>{
        'id': id,
        'updatedAt': updatedAt,
        'dirty': dirty,
      };
      if (label != null) args['label'] = label;
      if (icon != null) args['icon'] = icon;
      if (lat != null) args['lat'] = lat;
      if (lng != null) args['lng'] = lng;
      if (radius != null) args['radius'] = radius;
      if (status != null) args['status'] = status;
      if (triggerType != null) args['triggerType'] = triggerType;
      final result = await _channel.invokeMethod<bool>('updatePlace', args);
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Delete a place via native.
  Future<bool> deletePlaceNative(String id) async {
    try {
      final result = await _channel.invokeMethod<bool>('deletePlace', {
        'id': id,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Get all learning points (decrypted from native).
  Future<List<Map<String, dynamic>>?> getAllLearningPointsNative() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getAllLearningPoints',
      );
      return result?.cast<Map<String, dynamic>>();
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// Clear all learning points via native.
  Future<bool> clearLearningPointsNative() async {
    try {
      final result = await _channel.invokeMethod<bool>('clearLearningPoints');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Delete learning points older than a timestamp.
  Future<bool> deleteLearningPointsOlderThanNative(int timestamp) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'deleteLearningPointsOlderThan',
        {'timestamp': timestamp},
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Purge learning points within a radius (decrypts, checks, deletes).
  Future<bool> purgeLearningPointsWithinNative(
    double lat,
    double lng,
    double radius,
  ) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'purgeLearningPointsWithin',
        {'lat': lat, 'lng': lng, 'radius': radius},
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'geofenceTransition':
        final arguments = call.arguments as Map;
        final placeId = arguments['placeId'] as String;
        final transition = arguments['transition'] as String;
        _transitionController.add({
          'placeId': placeId,
          'transition': transition,
        });
        break;
      case 'learningPointsUpdated':
        _learningPointsUpdatedController.add(null);
        break;
      default:
        break;
    }
  }

  Future<void> _handlePrivacyMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'consentRevoked':
        _consentRevokedController.add(null);
        break;
      default:
        break;
    }
  }

  void dispose() {
    _transitionController.close();
    _learningPointsUpdatedController.close();
    _consentRevokedController.close();
  }
}
