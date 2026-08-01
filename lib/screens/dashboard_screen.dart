import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/place.dart';
import '../models/visit.dart';
import '../repositories/place_repository.dart';
import '../repositories/visit_repository.dart';
import '../services/native_geofence_service.dart';
import '../services/clustering_service.dart';
import '../services/event_logger_service.dart';
import '../widgets/app_shell.dart';
import 'suggested_places_screen.dart';
import 'place_detail_screen.dart';
import 'add_place_modal.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final PlaceRepository _placeRepository = PlaceRepository();
  final VisitRepository _visitRepository = VisitRepository();
  final NativeGeofenceService _geofenceService = NativeGeofenceService();
  final ClusteringService _clusteringService = ClusteringService();
  final EventLoggerService _logger = EventLoggerService();

  List<Place> _places = [];
  List<Visit> _visits = [];
  bool _isLearningActive = false;
  int _suggestionCount = 0;
  String _timeFilter = 'weekly';
  String _viewMode = 'overview';
  bool _isLoading = true;

  late AnimationController _pulseController;
  late StreamSubscription _transitionSub;
  late StreamSubscription _learningPointsSub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _loadData();
    _checkLearningStatus();

    _transitionSub = _geofenceService.transitionStream.listen((event) {
      _onGeofenceTransition(event);
      _loadData();
    });

    _learningPointsSub = _geofenceService.learningPointsUpdatedStream.listen((
      _,
    ) {
      _checkSuggestions();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _transitionSub.cancel();
    _learningPointsSub.cancel();
    super.dispose();
  }

  void _onGeofenceTransition(Map<String, String> event) {
    final placeId = event['placeId'];
    final transition = event['transition'];
    final place = _places.firstWhere(
      (p) => p.id == placeId,
      orElse: () => Place(
        id: placeId ?? '',
        label: 'Unknown',
        icon: PlaceIcon.custom,
        lat: 0,
        lng: 0,
        radiusM: 0,
        status: PlaceStatus.archived,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dirty: false,
      ),
    );

    switch (transition) {
      case 'ENTER':
        _logger.logEntered(place.label, placeId: place.id);
        break;
      case 'EXIT':
        _logger.logLeft(place.label, placeId: place.id);
        break;
      case 'DWELL':
        _logger.logSystem('Dwelling at ${place.label}');
        break;
      default:
        _logger.logSystem('Geofence transition: $transition at ${place.label}');
    }
  }

  Future<void> _checkLearningStatus() async {
    final active = await _geofenceService.isLearningRunning();
    setState(() {
      _isLearningActive = active;
    });
  }

  Future<void> _toggleLearningMode() async {
    if (_isLearningActive) {
      final stopped = await _geofenceService.stopLearning();
      if (stopped) {
        setState(() {
          _isLearningActive = false;
        });
        _logger.logLearningStopped();
        _showSnackBar('Passive location learning mode stopped.');
      }
    } else {
      final started = await _geofenceService.startLearning();
      if (started) {
        setState(() {
          _isLearningActive = true;
        });
        _logger.logLearningStarted();
        _showSnackBar('Passive location learning mode started.');
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final places = await _placeRepository.getAllPlaces();
      final visits = await _visitRepository.getAllVisits();
      setState(() {
        _places = places;
        _visits = visits;
      });
      await _checkSuggestions();
    } catch (e) {
      _showSnackBar('Error loading tracking data');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkSuggestions() async {
    final clusters = await _clusteringService.getSuggestedPlaces();
    if (mounted) {
      setState(() {
        _suggestionCount = clusters.length;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1F1F35),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Map<String, double> _calculatePlaceHours() {
    final Map<String, double> totals = {};
    final now = DateTime.now();
    DateTime cutoff;

    if (_timeFilter == 'daily') {
      cutoff = DateTime(now.year, now.month, now.day);
    } else if (_timeFilter == 'weekly') {
      cutoff = now.subtract(const Duration(days: 7));
    } else {
      cutoff = now.subtract(const Duration(days: 30));
    }

    for (final visit in _visits) {
      if (visit.enterTs.isBefore(cutoff)) continue;

      double durationHours = 0.0;
      if (visit.exitTs != null) {
        durationHours = (visit.durationS ?? 0) / 3600.0;
      } else {
        final elapsedS = now.difference(visit.enterTs).inSeconds;
        durationHours = elapsedS / 3600.0;
      }

      totals[visit.placeId] = (totals[visit.placeId] ?? 0.0) + durationHours;
    }
    return totals;
  }

  IconData _getIconData(PlaceIcon icon) {
    switch (icon) {
      case PlaceIcon.work:
        return Icons.work_outline;
      case PlaceIcon.gym:
        return Icons.fitness_center;
      case PlaceIcon.home:
        return Icons.home_outlined;
      case PlaceIcon.custom:
        return Icons.place_outlined;
    }
  }

  Color _getIconColor(PlaceIcon icon) {
    switch (icon) {
      case PlaceIcon.work:
        return const Color(0xFF00BBF9);
      case PlaceIcon.gym:
        return const Color(0xFFFF007F);
      case PlaceIcon.home:
        return const Color(0xFF00F5D4);
      case PlaceIcon.custom:
        return const Color(0xFF9B5DE5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmedPlaces = _places
        .where((p) => p.status == PlaceStatus.confirmed)
        .toList();
    final placeHours = _calculatePlaceHours();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFF6C63FF),
          backgroundColor: const Color(0xFF1F1F35),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),

              if (_suggestionCount > 0)
                SliverToBoxAdapter(child: _buildSuggestionBanner()),

              SliverToBoxAdapter(child: _buildWebhookStatusCard()),

              SliverToBoxAdapter(child: _buildViewModeToggle()),

              if (_viewMode == 'overview') ...[
                SliverToBoxAdapter(child: _buildTimeFilterToggle()),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Places',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            AppShell.of(context).switchToTab(2);
                          },
                          icon: const Icon(Icons.edit_road_outlined, size: 16),
                          label: const Text('Manage'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF6C63FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (confirmedPlaces.isEmpty)
                  SliverToBoxAdapter(child: _buildEmptyPlacesCard())
                else
                  SliverToBoxAdapter(
                    child: _buildPlacesHorizontalList(
                      confirmedPlaces,
                      placeHours,
                    ),
                  ),

                SliverToBoxAdapter(
                  child: const Padding(
                    padding: EdgeInsets.only(
                      left: 20.0,
                      right: 20.0,
                      top: 24.0,
                      bottom: 8.0,
                    ),
                    child: Text(
                      'Recent Logs',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                if (_visits.isEmpty)
                  SliverToBoxAdapter(child: _buildEmptyVisitsCard())
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final visit = _visits[index];
                      final place = _places.firstWhere(
                        (p) => p.id == visit.placeId,
                        orElse: () => Place(
                          id: '',
                          label: 'Deleted Place',
                          icon: PlaceIcon.custom,
                          lat: 0,
                          lng: 0,
                          radiusM: 0,
                          status: PlaceStatus.archived,
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                          dirty: false,
                        ),
                      );
                      return _buildVisitTile(visit, place);
                    }, childCount: _visits.length),
                  ),
              ] else
                SliverToBoxAdapter(child: _buildDayTimeline()),

              const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => AddPlaceModal(existingPlaces: _places),
          );
          if (added == true) {
            _loadData();
          }
        },
        backgroundColor: const Color(0xFF6C63FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'ClockIt',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      AppShell.of(context).switchToTab(4);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22223C),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF3F3F6B),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.developer_mode_rounded,
                        color: Color(0xFF6C63FF),
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Silent Background Tracker',
                style: TextStyle(color: Color(0xFFA0A0C0), fontSize: 13),
              ),
            ],
          ),
          GestureDetector(
            onTap: _toggleLearningMode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isLearningActive
                    ? const Color(0xFF1E3A2F)
                    : const Color(0xFF22223A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isLearningActive
                      ? const Color(0xFF2E6B4F)
                      : const Color(0xFF3F3F6B),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  if (_isLearningActive)
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF52B788,
                            ).withValues(alpha: _pulseController.value),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF52B788),
                                blurRadius: 4 * _pulseController.value,
                                spreadRadius: 1 * _pulseController.value,
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  else
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Text(
                    _isLearningActive ? 'Learning ON' : 'Learning OFF',
                    style: TextStyle(
                      color: _isLearningActive
                          ? const Color(0xFFD8F3DC)
                          : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8A2BE2), Color(0xFF6C63FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8A2BE2).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SuggestedPlacesScreen()),
            );
            _loadData();
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New Places Discovered!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'We detected $_suggestionCount regular stationary cluster${_suggestionCount > 1 ? 's' : ''}. Label them now to start geofence tracking.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebhookStatusCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22223C), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A44),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.webhook,
              color: Color(0xFF6C63FF),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Webhook Engine',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isLearningActive
                      ? 'Active — events queued on-device'
                      : 'Standby',
                  style: TextStyle(
                    color: _isLearningActive
                        ? const Color(0xFF52B788)
                        : const Color(0xFFA0A0C0),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _onTestWebhook(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A44),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Test',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _onPurgeHistory(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'Purge',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onTestWebhook() async {
    _logger.logWebhookDispatched();
    _showSnackBar('Test webhook dispatched (check server logs)');
  }

  Future<void> _onPurgeHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F35),
        title: const Text(
          'Purge All History?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will delete all location logs, visits, and geofence transitions. This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Purge'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _geofenceService.purgeAllHistory();
      _logger.logHistoryPurged();
      _loadData();
      _showSnackBar('All history purged');
    }
  }

  Widget _buildViewModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildFilterButton2('overview', 'Overview'),
            _buildFilterButton2('timeline', 'Timeline'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterButton2(String mode, String label) {
    final active = _viewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _viewMode = mode;
          });
        },
        child: Container(
          margin: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2E2E4A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFFA0A0C0),
              fontSize: 13,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayTimeline() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayVisits = _visits
        .where(
          (v) =>
              v.enterTs.isAfter(todayStart) ||
              v.enterTs.isAtSameMomentAs(todayStart),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today\'s Timeline',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (todayVisits.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF16162A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF22223C), width: 1),
              ),
              child: const Center(
                child: Text(
                  'No activity logged today yet',
                  style: TextStyle(color: Color(0xFFA0A0C0), fontSize: 13),
                ),
              ),
            )
          else
            Column(
              children: todayVisits.map((visit) {
                final place = _places.firstWhere(
                  (p) => p.id == visit.placeId,
                  orElse: () => Place(
                    id: '',
                    label: 'Unknown',
                    icon: PlaceIcon.custom,
                    lat: 0,
                    lng: 0,
                    radiusM: 0,
                    status: PlaceStatus.archived,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                    dirty: false,
                  ),
                );
                final formatter = DateFormat('h:mm a');
                final enterStr = formatter.format(visit.enterTs);
                final exitStr = visit.exitTs != null
                    ? formatter.format(visit.exitTs!)
                    : 'Now';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16162A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF22223C),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _getIconColor(place.icon),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              place.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$enterStr — $exitStr',
                              style: const TextStyle(
                                color: Color(0xFFA0A0C0),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeFilterToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildFilterButton('daily', 'Today'),
            _buildFilterButton('weekly', 'This Week'),
            _buildFilterButton('monthly', 'This Month'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterButton(String filter, String label) {
    final active = _timeFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _timeFilter = filter;
          });
        },
        child: Container(
          margin: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2E2E4A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFFA0A0C0),
              fontSize: 13,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPlacesCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22223C), width: 1),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.add_location_alt_outlined,
            size: 48,
            color: Color(0xFF6C63FF),
          ),
          const SizedBox(height: 16),
          const Text(
            'No confirmed places yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep Learning Mode enabled, or manually check for suggestions once you\'ve visited places.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFA0A0C0),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SuggestedPlacesScreen(),
                ),
              );
              _loadData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Check Suggestions',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlacesHorizontalList(
    List<Place> confirmedPlaces,
    Map<String, double> placeHours,
  ) {
    return SizedBox(
      height: 140,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: confirmedPlaces.length,
        itemBuilder: (context, index) {
          final place = confirmedPlaces[index];
          final hours = placeHours[place.id] ?? 0.0;
          final color = _getIconColor(place.icon);

          return GestureDetector(
            onTap: () async {
              final updated = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlaceDetailScreen(place: place),
                ),
              );
              if (updated == true) {
                _loadData();
              }
            },
            child: Container(
              width: 140,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF16162A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF22223C), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(_getIconData(place.icon), color: color, size: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatHours(hours),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyVisitsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22223C), width: 1),
      ),
      child: Center(
        child: Text(
          _isLoading ? 'Loading logs...' : 'No visit logs recorded yet',
          style: const TextStyle(color: Color(0xFFA0A0C0), fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildVisitTile(Visit visit, Place place) {
    final isOngoing = visit.exitTs == null;
    final color = _getIconColor(place.icon);

    String timeText = '';
    String durationText = '';

    final formatter = DateFormat('jm');
    final dayFormatter = DateFormat('MMM d');

    final enterTimeStr = formatter.format(visit.enterTs);
    final dayStr = dayFormatter.format(visit.enterTs);

    if (isOngoing) {
      timeText = 'Arrived at $enterTimeStr • $dayStr';
      final elapsedS = DateTime.now().difference(visit.enterTs).inSeconds;
      durationText = 'Still there (${_formatSeconds(elapsedS)})';
    } else {
      final exitTimeStr = formatter.format(visit.exitTs!);
      timeText = '$enterTimeStr - $exitTimeStr • $dayStr';
      durationText = _formatSeconds(visit.durationS ?? 0);
    }

    return Dismissible(
      key: Key(visit.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade900,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1F1F35),
            title: const Text(
              'Delete Log',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Are you sure you want to delete this visit log?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        await _visitRepository.deleteVisit(visit.id);
        setState(() {
          _visits.removeWhere((v) => v.id == visit.id);
        });
        _showSnackBar('Visit log deleted.');
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF16162A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF22223C), width: 1),
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(_getIconData(place.icon), color: color, size: 20),
          ),
          title: Text(
            place.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              timeText,
              style: const TextStyle(color: Color(0xFFA0A0C0), fontSize: 12),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                durationText,
                style: TextStyle(
                  color: isOngoing ? const Color(0xFF00F5D4) : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                visit.source.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatHours(double hours) {
    if (hours == 0.0) return '0h';
    final wholeHours = hours.toInt();
    final minutes = ((hours - wholeHours) * 60).round();
    if (wholeHours == 0) return '${minutes}m';
    if (minutes == 0) return '${wholeHours}h';
    return '${wholeHours}h ${minutes}m';
  }

  String _formatSeconds(int seconds) {
    final mins = seconds ~/ 60;
    if (mins < 1) return '< 1m';
    if (mins < 60) return '${mins}m';
    final hrs = mins ~/ 60;
    final remMins = mins % 60;
    if (remMins == 0) return '${hrs}h';
    return '${hrs}h ${remMins}m';
  }
}
