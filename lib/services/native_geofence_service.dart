import 'dart:async';
import 'package:flutter/services.dart';

class NativeGeofenceService {
  static final NativeGeofenceService _instance =
      NativeGeofenceService._internal();
  factory NativeGeofenceService() => _instance;
  NativeGeofenceService._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'com.example.geofenceapp/geofence',
  );

  // Broadcast controllers so the UI can listen to background changes in real-time
  final _transitionController =
      StreamController<Map<String, String>>.broadcast();
  final _learningPointsUpdatedController = StreamController<void>.broadcast();

  Stream<Map<String, String>> get transitionStream =>
      _transitionController.stream;
  Stream<void> get learningPointsUpdatedStream =>
      _learningPointsUpdatedController.stream;

  Future<bool> startLearning() async {
    try {
      final result = await _channel.invokeMethod<bool>('startLearning');
      return result ?? false;
    } on PlatformException catch (_) {
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
    } on PlatformException catch (_) {
      // Ignore exception if launch fails
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
}
