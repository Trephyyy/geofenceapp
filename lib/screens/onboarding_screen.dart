import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/native_geofence_service.dart';
import 'dashboard_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final NativeGeofenceService _geofenceService = NativeGeofenceService();
  int _currentStep = 0;

  // Permission statuses
  bool _hasForegroundLocation = false;
  bool _hasBackgroundLocation = false;
  bool _hasActivityRecognition = false;
  bool _hasNotification = false;
  bool _isBatteryExempt = false;

  bool get _isAndroid => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _checkPermissionStatuses();
  }

  int get _totalSteps => _isAndroid ? 6 : 4;

  List<String> get _stepIds => _isAndroid
      ? ['welcome', 'foreground', 'background', 'activity', 'notification', 'battery']
      : ['welcome', 'foreground', 'background', 'notification'];

  Future<void> _checkPermissionStatuses() async {
    final foreground = await Permission.locationWhenInUse.isGranted;
    final background = await Permission.locationAlways.isGranted;
    final notification = await Permission.notification.isGranted;

    bool activity = false;
    bool battery = false;

    if (_isAndroid) {
      activity = await Permission.activityRecognition.isGranted;
      battery = await _geofenceService.isIgnoreBatteryOptimizations();
    }

    if (mounted) {
      setState(() {
        _hasForegroundLocation = foreground;
        _hasBackgroundLocation = background;
        _hasActivityRecognition = activity;
        _hasNotification = notification;
        _isBatteryExempt = battery;
      });
    }
  }

  void _nextPage() {
    final maxStep = _totalSteps - 1;
    if (_currentStep < maxStep) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _previousPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _finishOnboarding() async {
    // Start background learning mode
    await _geofenceService.startLearning();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A), // Sleek deep space dark background
      body: SafeArea(
        child: Column(
          children: [
            // Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_currentStep + 1) / _totalSteps,
                  backgroundColor: const Color(0xFF1F1F35),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8A2BE2)), // Vibrant violet
                  minHeight: 6,
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentStep = index;
                  });
                },
                children: _buildSteps(),
              ),
            ),
            // Footer Navigation
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentStep > 0)
                    TextButton(
                      onPressed: _previousPage,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      child: const Text('Back', style: TextStyle(fontSize: 16)),
                    )
                  else
                    const SizedBox.shrink(),
                  ElevatedButton(
                    onPressed: _isNextButtonEnabled() ? _nextPage : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF2E2E4A),
                      disabledForegroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
child: Text(
                        _currentStep == _totalSteps - 1 ? 'Get Started' : 'Continue',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSteps() {
    final steps = <Widget>[
      _buildWelcomeStep(),
      _buildForegroundLocationStep(),
      _buildBackgroundLocationStep(),
      _buildNotificationStep(),
    ];
    if (_isAndroid) {
      steps.insert(3, _buildActivityStep());
      steps.add(_buildBatteryStep());
    }
    return steps;
  }

  bool _isNextButtonEnabled() {
    final stepId = _stepIds[_currentStep];
    switch (stepId) {
      case 'welcome':
        return true;
      case 'foreground':
        return _hasForegroundLocation;
      case 'background':
        return _hasBackgroundLocation;
      case 'activity':
        return _hasActivityRecognition;
      case 'notification':
        return _hasNotification;
      case 'battery':
        return true;
      default:
        return false;
    }
  }

  // --- Step Builders ---

  Widget _buildStepContainer({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required List<Widget> actionContent,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          // Icon Container
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha:0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: iconColor.withValues(alpha:0.2),
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              size: 64,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFA0A0C0),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          ...actionContent,
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return _buildStepContainer(
      icon: Icons.timer_outlined,
      iconColor: const Color(0xFF6C63FF),
      title: 'Welcome to ClockIt',
      description: 'A silent time tracker. ClockIt auto-detects places you visit, clusters them on-device, and silently tracks your arrival and departure times using geofencing.',
      actionContent: [
        const Text(
          'Let\'s set up the required permissions to run quietly and efficiently in the background.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF8A8A9E),
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildForegroundLocationStep() {
    return _buildStepContainer(
      icon: Icons.location_on_outlined,
      iconColor: const Color(0xFF00F5D4),
      title: '1. Device Location',
      description: 'ClockIt needs foreground location access to discover places and map coordinates while you are using the app.',
      actionContent: [
        if (_hasForegroundLocation)
          _buildPermissionGrantedWidget()
        else
          ElevatedButton.icon(
            onPressed: () async {
              final status = await Permission.locationWhenInUse.request();
              setState(() {
                _hasForegroundLocation = status.isGranted;
              });
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Grant Location Access'),
            style: _permissionButtonStyle(),
          ),
      ],
    );
  }

  Widget _buildBackgroundLocationStep() {
    return _buildStepContainer(
      icon: Icons.my_location_rounded,
      iconColor: const Color(0xFF00BBF9),
      title: '2. Always-On Location',
      description: 'To automatically log your arrival and exit times without opening the app, ClockIt requires background location permission.\n\nIn the next dialog, please select "Allow all the time". We NEVER upload your location to any server.',
      actionContent: [
        if (_hasBackgroundLocation)
          _buildPermissionGrantedWidget()
        else
          ElevatedButton.icon(
            onPressed: () async {
              // Staged flow: foreground must be granted first.
              if (!_hasForegroundLocation) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please grant foreground location first.')),
                );
                return;
              }
              final status = await Permission.locationAlways.request();
              setState(() {
                _hasBackgroundLocation = status.isGranted;
              });
            },
            icon: const Icon(Icons.lock_open),
            label: const Text('Allow All The Time'),
            style: _permissionButtonStyle(),
          ),
      ],
    );
  }

  Widget _buildActivityStep() {
    return _buildStepContainer(
      icon: Icons.directions_run_outlined,
      iconColor: const Color(0xFFFF007F),
      title: '3. Physical Activity',
      description: 'We use the platform\'s activity detection API to recognize when you are STILL vs when you are moving. Location samples are only taken when you are stationary, saving up to 90% battery.',
      actionContent: [
        if (_hasActivityRecognition)
          _buildPermissionGrantedWidget()
        else
          ElevatedButton.icon(
            onPressed: () async {
              final status = await Permission.activityRecognition.request();
              setState(() {
                _hasActivityRecognition = status.isGranted;
              });
            },
            icon: const Icon(Icons.run_circle_outlined),
            label: const Text('Grant Activity Access'),
            style: _permissionButtonStyle(),
          ),
      ],
    );
  }

  Widget _buildNotificationStep() {
    return _buildStepContainer(
      icon: Icons.notifications_active_outlined,
      iconColor: const Color(0xFFFEE440),
      title: '4. Local Notifications',
      description: 'ClockIt will send local notifications when you arrive at or leave a place, keeping you updated in real-time (e.g. "You left Work — 8h 15m").',
      actionContent: [
        if (_hasNotification)
          _buildPermissionGrantedWidget()
        else
          ElevatedButton.icon(
            onPressed: () async {
              final status = await Permission.notification.request();
              setState(() {
                _hasNotification = status.isGranted;
              });
            },
            icon: const Icon(Icons.notifications_none_outlined),
            label: const Text('Allow Notifications'),
            style: _permissionButtonStyle(),
          ),
      ],
    );
  }

  Widget _buildBatteryStep() {
    return _buildStepContainer(
      icon: Icons.battery_charging_full_rounded,
      iconColor: const Color(0xFF9B5DE5),
      title: '5. Battery Optimization',
      description: 'Android\'s Doze mode can sleep our background tasks, delaying geofence triggers. Exclude ClockIt from battery optimization to guarantee timely logs. (iOS manages background tasks automatically.)',
      actionContent: [
        if (_isBatteryExempt)
          _buildPermissionGrantedWidget()
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () async {
                  await _geofenceService.requestIgnoreBatteryOptimizations();
                  // Check status again after a short delay
                  Future.delayed(const Duration(seconds: 2), () async {
                    final isExempt = await _geofenceService.isIgnoreBatteryOptimizations();
                    if (mounted) {
                      setState(() {
                        _isBatteryExempt = isExempt;
                      });
                    }
                  });
                },
                style: _permissionButtonStyle(),
                child: const Text('Request Exemption'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _nextPage,
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                child: const Text('Skip'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildPermissionGrantedWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A2F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E6B4F), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check, color: Color(0xFF52B788)),
          SizedBox(width: 8),
          Text(
            'Permission Granted',
            style: TextStyle(color: Color(0xFFD8F3DC), fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  ButtonStyle _permissionButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF2A2A44),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF3F3F6B), width: 1),
      ),
      elevation: 0,
    );
  }
}
