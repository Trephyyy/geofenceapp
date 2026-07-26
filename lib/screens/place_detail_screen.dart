import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../models/place.dart';
import '../models/visit.dart';
import '../repositories/place_repository.dart';
import '../repositories/visit_repository.dart';

class PlaceDetailScreen extends StatefulWidget {
  final Place place;

  const PlaceDetailScreen({super.key, required this.place});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  final PlaceRepository _placeRepository = PlaceRepository();
  final VisitRepository _visitRepository = VisitRepository();

  late Place _currentPlace;
  late TextEditingController _labelController;
  late PlaceIcon _selectedIcon;
  late double _radius;
  late GeofenceTriggerType _triggerType;
  late LatLng _mapCenter;

  List<Visit> _visits = [];
  bool _isLoadingVisits = true;
  bool _isSaving = false;
  bool _isDragging = false;

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _currentPlace = widget.place;
    _labelController = TextEditingController(text: _currentPlace.label);
    _selectedIcon = _currentPlace.icon;
    _radius = _currentPlace.radiusM;
    _triggerType = _currentPlace.triggerType;
    _mapCenter = LatLng(_currentPlace.lat, _currentPlace.lng);
    _loadVisits();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadVisits() async {
    setState(() => _isLoadingVisits = true);
    try {
      final visits = await _visitRepository.getVisitsForPlace(_currentPlace.id);
      // Sort visits descending by enter time
      visits.sort((a, b) => b.enterTs.compareTo(a.enterTs));
      setState(() {
        _visits = visits;
      });
    } catch (e) {
      _showSnackBar('Error loading activity logs');
    } finally {
      setState(() => _isLoadingVisits = false);
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

  Future<void> _saveChanges() async {
    final newLabel = _labelController.text.trim();
    if (newLabel.isEmpty) {
      _showSnackBar('Label cannot be empty');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updated = _currentPlace.copyWith(
        label: newLabel,
        icon: _selectedIcon,
        lat: _mapCenter.latitude,
        lng: _mapCenter.longitude,
        radiusM: _radius,
        triggerType: _triggerType,
        updatedAt: DateTime.now(),
      );

      await _placeRepository.updatePlace(updated);
      setState(() {
        _currentPlace = updated;
      });
      _showSnackBar('Changes saved successfully');
    } catch (e) {
      _showSnackBar('Failed to save changes');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deletePlace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F35),
        title: const Text(
          'Delete Place',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "${_currentPlace.label}"? '
          'This will permanently delete the geofence and all associated visit logs.',
          style: const TextStyle(color: Colors.white70),
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

    if (confirmed == true) {
      setState(() => _isSaving = true);
      try {
        await _placeRepository.deletePlace(_currentPlace.id);
        _showSnackBar('Place deleted');
        if (mounted) {
          Navigator.of(context).pop(true); // Return true to indicate change
        }
      } catch (e) {
        _showSnackBar('Failed to delete place');
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _resetToLearning() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F35),
        title: const Text(
          'Reset to Learning',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Do you want to reset "${_currentPlace.label}" back to learning mode? '
          'This unregisters the active geofence and lets you re-train this location from stationary points.',
          style: const TextStyle(color: Colors.white70),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isSaving = true);
      try {
        await _placeRepository.reEnterLearningMode(_currentPlace);
        _showSnackBar('Place reset to learning mode');
        if (mounted) {
          Navigator.of(context).pop(true); // Return true to indicate change
        }
      } catch (e) {
        _showSnackBar('Failed to reset place');
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteVisit(Visit visit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F35),
        title: const Text('Delete Log', style: TextStyle(color: Colors.white)),
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

    if (confirmed == true) {
      try {
        await _visitRepository.deleteVisit(visit.id);
        setState(() {
          _visits.removeWhere((v) => v.id == visit.id);
        });
        _showSnackBar('Visit log deleted.');
      } catch (e) {
        _showSnackBar('Failed to delete visit log');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _getIconColor(_selectedIcon);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () =>
              Navigator.of(context).pop(true), // Return true to refresh parent
        ),
        title: Text(
          _currentPlace.label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Color(0xFF6C63FF),
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(
                Icons.check_rounded,
                color: Color(0xFF00F5D4),
                size: 28,
              ),
              tooltip: 'Save changes',
              onPressed: _saveChanges,
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Map View Header (Draggable - tap to reposition geofence)
            Container(
              height: 280,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF22223C), width: 1),
                ),
              ),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _mapCenter,
                      initialZoom: 15.5,
                      minZoom: 12,
                      maxZoom: 18,
                      onPositionChanged: (camera, hasGesture) {
                        if (hasGesture) {
                          setState(() {
                            _mapCenter = camera.center;
                            _isDragging = true;
                          });
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.geofenceapp',
                      ),
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _mapCenter,
                            color: iconColor.withValues(alpha:0.25),
                            borderStrokeWidth: 2,
                            borderColor: iconColor,
                            useRadiusInMeter: true,
                            radius: _radius,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _mapCenter,
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F0F1A),
                                shape: BoxShape.circle,
                                border: Border.all(color: iconColor, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: iconColor.withValues(alpha:0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _getIconData(_selectedIcon),
                                color: iconColor,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Dragging indicator
                  if (_isDragging)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_mapCenter.latitude.toStringAsFixed(4)}, ${_mapCenter.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(
                            color: Color(0xFF00F5D4),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 2. Editor Panel
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Edit Label
                  const Text(
                    'Geofence Name',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _labelController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      fillColor: const Color(0xFF16162A),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF22223C)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF22223C)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF6C63FF)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Edit Icon
                  const Text(
                    'Category Icon',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: PlaceIcon.values.map((icon) {
                      final isSelected = _selectedIcon == icon;
                      final col = _getIconColor(icon);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedIcon = icon;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? col.withValues(alpha:0.12)
                                : const Color(0xFF16162A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? col : const Color(0xFF22223C),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            _getIconData(icon),
                            color: isSelected ? col : Colors.white60,
                            size: 24,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Edit Radius
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Geofence Radius',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_radius.toInt()} meters',
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _radius,
                    min: 50.0,
                    max: 500.0,
                    divisions: 9,
                    activeColor: const Color(0xFF6C63FF),
                    inactiveColor: const Color(0xFF22223C),
                    onChanged: (val) {
                      setState(() {
                        _radius = val;
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // Trigger Type
                  const Text(
                    'Trigger Type',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF16162A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: GeofenceTriggerType.values.map((type) {
                        final isSelected = _triggerType == type;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _triggerType = type);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF6C63FF).withValues(alpha:0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF6C63FF)
                                      : const Color(0xFF22223C),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    type.displayName,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFFA0A0C0),
                                      fontSize: 11,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _triggerType.description,
                    style: const TextStyle(
                      color: Color(0xFF6C63FF),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Color(0xFF22223C), height: 1),

            // 3. Recent Activity Logs
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    color: Color(0xFF6C63FF),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Recent Activity',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (!_isLoadingVisits)
                    Text(
                      '${_visits.length} logs',
                      style: const TextStyle(
                        color: Color(0xFFA0A0C0),
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),

            _buildActivityLogsList(),

            const SizedBox(height: 20),
            const Divider(color: Color(0xFF22223C), height: 1),

            // 4. Action Buttons
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 30,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _resetToLearning,
                      icon: const Icon(
                        Icons.settings_backup_restore_outlined,
                        size: 18,
                      ),
                      label: const Text('Reset Learning'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFA0A0C0),
                        side: const BorderSide(color: Color(0xFF22223C)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _deletePlace,
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Delete Geofence',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade900,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
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

  Widget _buildActivityLogsList() {
    if (_isLoadingVisits) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
        ),
      );
    }

    if (_visits.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF16162A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF22223C), width: 1),
        ),
        child: const Center(
          child: Text(
            'No visit logs recorded for this place yet.',
            style: TextStyle(color: Color(0xFFA0A0C0), fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _visits.length,
      itemBuilder: (context, index) {
        final visit = _visits[index];
        final isOngoing = visit.exitTs == null;

        String timeText = '';
        String durationText = '';

        final formatter = DateFormat('jm'); // E.g. "5:30 PM"
        final dayFormatter = DateFormat('MMM d'); // E.g. "Jul 20"

        final enterTimeStr = formatter.format(visit.enterTs);
        final dayStr = dayFormatter.format(visit.enterTs);

        if (isOngoing) {
          timeText = 'Arrived at $enterTimeStr • $dayStr';
          final elapsedS = DateTime.now().difference(visit.enterTs).inSeconds;
          durationText = 'Ongoing (${_formatSeconds(elapsedS)})';
        } else {
          final exitTimeStr = formatter.format(visit.exitTs!);
          timeText = '$enterTimeStr - $exitTimeStr • $dayStr';
          durationText = _formatSeconds(visit.durationS ?? 0);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF16162A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF22223C), width: 1),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            title: Text(
              timeText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F1F3D),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      visit.source.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  durationText,
                  style: TextStyle(
                    color: isOngoing ? const Color(0xFF00F5D4) : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white30,
                    size: 20,
                  ),
                  onPressed: () => _deleteVisit(visit),
                ),
              ],
            ),
          ),
        );
      },
    );
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
