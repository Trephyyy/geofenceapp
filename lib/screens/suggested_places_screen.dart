import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../models/place.dart';
import '../repositories/place_repository.dart';
import '../services/clustering_service.dart';
import '../services/db_service.dart';

class SuggestedPlacesScreen extends StatefulWidget {
  const SuggestedPlacesScreen({super.key});

  @override
  State<SuggestedPlacesScreen> createState() => _SuggestedPlacesScreenState();
}

class _SuggestedPlacesScreenState extends State<SuggestedPlacesScreen> {
  final ClusteringService _clusteringService = ClusteringService();
  final PlaceRepository _placeRepository = PlaceRepository();

  List<SuggestedCluster> _suggestions = [];
  bool _isLoading = true;

  // Form states per suggestion (indexed by suggestions list)
  final Map<int, TextEditingController> _labelControllers = {};
  final Map<int, PlaceIcon> _selectedIcons = {};
  final Map<int, double> _selectedRadii = {};

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    for (final controller in _labelControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoading = true);
    try {
      final clusters = await _clusteringService.getSuggestedPlaces();
      
      // Initialize form controllers for each cluster
      _labelControllers.clear();
      _selectedIcons.clear();
      _selectedRadii.clear();

      for (int i = 0; i < clusters.length; i++) {
        _labelControllers[i] = TextEditingController();
        _selectedIcons[i] = PlaceIcon.custom;
        _selectedRadii[i] = 150.0; // Default geofence radius is 150m
      }

      setState(() {
        _suggestions = clusters;
      });
    } catch (e) {
      _showSnackBar('Error loading place suggestions');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1F1F35),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _confirmPlace(int index, SuggestedCluster cluster) async {
    final label = _labelControllers[index]?.text.trim() ?? '';
    if (label.isEmpty) {
      _showSnackBar('Please enter a label for this place.');
      return;
    }

    final selectedIcon = _selectedIcons[index] ?? PlaceIcon.custom;
    final radius = _selectedRadii[index] ?? 150.0;

    final newPlace = Place(
      id: const Uuid().v4(),
      label: label,
      icon: selectedIcon,
      lat: cluster.lat,
      lng: cluster.lng,
      radiusM: radius,
      status: PlaceStatus.confirmed,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      dirty: true,
    );

    setState(() => _isLoading = true);

    try {
      // 1. Add place to DB & register geofence
      await _placeRepository.addPlace(newPlace);

      // 2. Purge corresponding learning points from DB so they exit the sampling pool
      await _clusteringService.purgeLearningPointsWithin(cluster.lat, cluster.lng, radius + 150.0);

      _showSnackBar('Place "$label" confirmed and geofence registered!');
      
      // Reload suggestions
      await _loadSuggestions();
    } catch (e) {
      _showSnackBar('Failed to save place: ${e.toString()}');
      setState(() => _isLoading = false);
    }
  }

  // --- Widgets ---

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
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Suggestions',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : _suggestions.isEmpty
              ? _buildEmptyState()
              : _buildSuggestionsList(),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: const [
            Icon(Icons.query_stats_outlined, size: 72, color: Color(0xFF3F3F6B)),
            SizedBox(height: 24),
            Text(
              'No new suggestions',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Our background clustering engine needs more stationary data. Suggestions will appear once we detect places you visit at least 3 times for over 20 minutes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFA0A0C0), fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return _buildSuggestionCard(index, suggestion);
      },
    );
  }

  Widget _buildSuggestionCard(int index, SuggestedCluster cluster) {
    final selectedIcon = _selectedIcons[index] ?? PlaceIcon.custom;
    final currentRadius = _selectedRadii[index] ?? 150.0;
    final mapCenter = LatLng(cluster.lat, cluster.lng);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22223C), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Map Preview
            SizedBox(
              height: 180,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: mapCenter,
                  initialZoom: 15.5,
                  minZoom: 12,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.geofenceapp',
                  ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: mapCenter,
                        color: _getIconColor(selectedIcon).withValues(alpha:0.25),
                        borderStrokeWidth: 2,
                        borderColor: _getIconColor(selectedIcon),
                        useRadiusInMeter: true,
                        radius: currentRadius,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Info Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Location Hotspot #${index + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F1F3D),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${cluster.visitCount} visits',
                          style: const TextStyle(color: Color(0xFF00BBF9), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Avg. Dwell time: ${cluster.averageDurationMinutes.toStringAsFixed(0)} mins',
                    style: const TextStyle(color: Color(0xFFA0A0C0), fontSize: 12),
                  ),
                  
                  const Divider(color: Color(0xFF22223C), height: 24),
                  
                  // Label field
                  const Text(
                    'Place Label',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _labelControllers[index],
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. Work, Gym, Home',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                      fillColor: const Color(0xFF0F0F1A),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF22223C)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF22223C)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF6C63FF)),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),

                  // Icon Row Selector
                  const Text(
                    'Select Category Icon',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: PlaceIcon.values.map((icon) {
                      final isSelected = selectedIcon == icon;
                      final iconColor = _getIconColor(icon);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedIcons[index] = icon;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? iconColor.withValues(alpha:0.12) : const Color(0xFF0F0F1A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? iconColor : const Color(0xFF22223C),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            _getIconData(icon),
                            color: isSelected ? iconColor : Colors.white60,
                            size: 24,
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // Radius Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Geofence Radius',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${currentRadius.toInt()}m',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: currentRadius,
                    min: 50.0,
                    max: 500.0,
                    divisions: 9,
                    activeColor: const Color(0xFF6C63FF),
                    inactiveColor: const Color(0xFF22223C),
                    onChanged: (val) {
                      setState(() {
                        _selectedRadii[index] = val;
                      });
                    },
                  ),
                  
                  const SizedBox(height: 8),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _confirmPlace(index, cluster),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Confirm Place & Start Geofencing',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
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
}

// Add the helper method to ClusteringService to purge points
extension PurgeLearningPoints on ClusteringService {
  Future<void> purgeLearningPointsWithin(double lat, double lng, double radiusM) async {
    final dbService = DbService();
    final points = await dbService.getAllLearningPoints();
    for (final p in points) {
      if (calculateDistance(lat, lng, p.lat, p.lng) <= radiusM) {
        final db = await dbService.database;
        await db.delete(
          'learning_points',
          where: 'timestamp = ? AND lat = ? AND lng = ?',
          whereArgs: [p.timestamp.millisecondsSinceEpoch, p.lat, p.lng],
        );
      }
    }
  }
}
