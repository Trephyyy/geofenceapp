import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/db_service.dart';
import 'services/native_geofence_service.dart';
import 'services/location_native_bridge.dart';
import 'services/event_logger_service.dart';
import 'screens/onboarding_screen.dart';
import 'widgets/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbService = DbService();
  await dbService.initDb();

  final bridge = LocationNativeBridge();
  bridge.init();

  final nativeService = NativeGeofenceService();

  final consentGranted = await nativeService.hasConsent();

  final hasForeground = await Permission.locationWhenInUse.isGranted;
  final hasBackground = await Permission.locationAlways.isGranted;

  bool onboardingCompleted = hasForeground && hasBackground;

  if (Platform.isAndroid) {
    final hasActivity = await Permission.activityRecognition.isGranted;
    onboardingCompleted = onboardingCompleted && hasActivity;
  }

  if (onboardingCompleted && consentGranted) {
    EventLoggerService().logSystem('App started');
  }

  runApp(MyApp(onboardingCompleted: onboardingCompleted && consentGranted));
}

class MyApp extends StatelessWidget {
  final bool onboardingCompleted;
  const MyApp({super.key, required this.onboardingCompleted});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClockIt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        primaryColor: const Color(0xFF6C63FF),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF00F5D4),
          surface: Color(0xFF16162A),
          onSurface: Colors.white,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(),
        ),
      ),
      home: onboardingCompleted
          ? const AppShell()
          : const OnboardingScreen(),
    );
  }
}
