import 'package:flutter/material.dart';
import '../models/place.dart';
import '../repositories/place_repository.dart';
import 'place_detail_screen.dart';

class PlaceManagementScreen extends StatefulWidget {
  const PlaceManagementScreen({super.key});

  @override
  State<PlaceManagementScreen> createState() => _PlaceManagementScreenState();
}

class _PlaceManagementScreenState extends State<PlaceManagementScreen> {
  final PlaceRepository _placeRepository = PlaceRepository();
  List<Place> _places = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaces();
  }

  Future<void> _loadPlaces() async {
    setState(() => _isLoading = true);
    try {
      final list = await _placeRepository.getAllPlaces();
      setState(() {
        _places = list.where((p) => p.status == PlaceStatus.confirmed).toList();
      });
    } catch (e) {
      _showSnackBar('Error loading places');
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

  Future<void> _deletePlace(Place place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F35),
        title: const Text('Delete Place', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${place.label}"? This will delete all its visit logs and remove the geofence.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _placeRepository.deletePlace(place.id);
        _showSnackBar('Place "${place.label}" deleted.');
        _loadPlaces();
      } catch (e) {
        _showSnackBar('Failed to delete place');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _reEnterLearning(Place place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F35),
        title: const Text('Reset to Learning', style: TextStyle(color: Colors.white)),
        content: Text('Do you want to reset "${place.label}" back to learning mode? This unregisters the geofence and lets you re-train this location from stationary samples.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _placeRepository.reEnterLearningMode(place);
        _showSnackBar('Place "${place.label}" reset to learning.');
        _loadPlaces();
      } catch (e) {
        _showSnackBar('Failed to reset place');
        setState(() => _isLoading = false);
      }
    }
  }



  // --- Helpers ---

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
        title: const Text('Manage Places', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : _places.isEmpty
              ? _buildEmptyState()
              : _buildPlacesList(),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 72, color: Color(0xFF3F3F6B)),
            SizedBox(height: 20),
            Text(
              'No registered places',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Confirmed places will appear here. Go back and check suggested places to register geofences.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFA0A0C0), fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlacesList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _places.length,
      itemBuilder: (context, index) {
        final place = _places[index];
        final color = _getIconColor(place.icon);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF16162A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF22223C), width: 1),
          ),
          child: ListTile(
            onTap: () async {
              final updated = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlaceDetailScreen(place: place),
                ),
              );
              if (updated == true) {
                _loadPlaces();
              }
            },
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(_getIconData(place.icon), color: color, size: 22),
            ),
            title: Text(
              place.label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Text(
              'Radius: ${place.radiusM.toInt()}m',
              style: const TextStyle(color: Color(0xFFA0A0C0), fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.settings_backup_restore_outlined, color: Colors.white70),
                  tooltip: 'Reset to Learning',
                  onPressed: () => _reEnterLearning(place),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white70),
                  tooltip: 'Edit details',
                  onPressed: () async {
                    final updated = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlaceDetailScreen(place: place),
                      ),
                    );
                    if (updated == true) {
                      _loadPlaces();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  tooltip: 'Delete place',
                  onPressed: () => _deletePlace(place),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
