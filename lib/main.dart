import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/db_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqlite database schema on launch
  final dbService = DbService();
  await dbService.initDb();

  // Check if permissions are already set up to bypass onboarding
  final hasForeground = await Permission.locationWhenInUse.isGranted;
  final hasBackground = await Permission.locationAlways.isGranted;

  bool onboardingCompleted = hasForeground && hasBackground;

  // Activity recognition is Android-only
  if (Platform.isAndroid) {
    final hasActivity = await Permission.activityRecognition.isGranted;
    onboardingCompleted = onboardingCompleted && hasActivity;
  }

  runApp(MyApp(onboardingCompleted: onboardingCompleted));
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
          titleLarge: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(fontFamily: 'Inter'),
        ),
      ),
      home: onboardingCompleted ? const DashboardScreen() : const OnboardingScreen(),
    );
  }
}
