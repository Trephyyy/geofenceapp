import Flutter
import UIKit
import CoreLocation

public class GeofencePlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {
  private let locationManager = CLLocationManager()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.example.geofenceapp/geofence",
      binaryMessenger: registrar.messenger()
    )
    let instance = GeofencePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startLearning":
      locationManager.delegate = self
      locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
      locationManager.allowsBackgroundLocationUpdates = true
      locationManager.pausesLocationUpdatesAutomatically = true
      locationManager.startMonitoringSignificantLocationChanges()
      result(true)

    case "stopLearning":
      locationManager.stopMonitoringSignificantLocationChanges()
      locationManager.allowsBackgroundLocationUpdates = false
      result(true)

    case "isLearningRunning":
      result(false)

    case "registerGeofence":
      guard let args = call.arguments as? [String: Any],
            let id = args["id"] as? String,
            let lat = args["lat"] as? Double,
            let lng = args["lng"] as? Double,
            let radius = args["radius"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing geofence parameters", details: nil))
        return
      }
      let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
      let region = CLCircularRegion(center: center, radius: radius, identifier: id)
      region.notifyOnEntry = true
      region.notifyOnExit = true
      locationManager.startMonitoring(for: region)
      result(true)

    case "unregisterGeofence":
      guard let args = call.arguments as? [String: Any],
            let id = args["id"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing geofence id", details: nil))
        return
      }
      for region in locationManager.monitoredRegions {
        if region.identifier == id {
          locationManager.stopMonitoring(for: region)
        }
      }
      result(true)

    case "isIgnoreBatteryOptimizations":
      result(true)

    case "requestIgnoreBatteryOptimizations":
      result(nil)

    case "getCurrentLocation":
      if let loc = locationManager.location {
        result(["lat": loc.coordinate.latitude, "lng": loc.coordinate.longitude])
      } else {
        locationManager.requestLocation()
        result(nil)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // Learning points are handled on the Dart side via periodic polling
  }

  public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // Silent fail
  }

  public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    sendTransition(regionId: region.identifier, transition: "enter")
  }

  public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    sendTransition(regionId: region.identifier, transition: "exit")
  }

  private func sendTransition(regionId: String, transition: String) {
    guard let controller = UIApplication.shared.keyWindow?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(
      name: "com.example.geofenceapp/geofence",
      binaryMessenger: controller.binaryMessenger
    )
    channel.invokeMethod("geofenceTransition", arguments: [
      "placeId": regionId,
      "transition": transition
    ])
  }
}