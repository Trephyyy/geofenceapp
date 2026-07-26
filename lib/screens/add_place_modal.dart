import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../models/place.dart';
import '../repositories/place_repository.dart';
import '../services/native_geofence_service.dart';

class AddPlaceModal extends StatefulWidget {
  final List<Place> existingPlaces;

  const AddPlaceModal({super.key, required this.existingPlaces});

  @override
  State<AddPlaceModal> createState() => _AddPlaceModalState();
}

class _AddPlaceModalState extends State<AddPlaceModal> {
  final PlaceRepository _placeRepository = PlaceRepository();
  final NativeGeofenceService _geofenceService = NativeGeofenceService();
  final MapController _mapController = MapController();

  final TextEditingController _labelController = TextEditingController();
  PlaceIcon _selectedIcon = PlaceIcon.custom;
  double _radius = 150.0;
  GeofenceTriggerType _triggerType = GeofenceTriggerType.normal;

  LatLng _mapCenter = const LatLng(
    37.4279613,
    -122.0857496,
  ); // Fallback: Googleplex
  bool _isLoadingLocation = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    // 1. First, try to center on the most recent existing place as a better fallback
    if (widget.existingPlaces.isNotEmpty) {
      setState(() {
        _mapCenter = LatLng(
          widget.existingPlaces.first.lat,
          widget.existingPlaces.first.lng,
        );
        _isLoadingLocation = false;
      });
    }

    // 2. Query Fused Location natively
    try {
      final loc = await _geofenceService.getCurrentLocation();
      if (loc != null && mounted) {
        final userLatLng = LatLng(loc['lat']!, loc['lng']!);
        setState(() {
          _mapCenter = userLatLng;
          _isLoadingLocation = false;
        });
        _mapController.move(userLatLng, 15.5);
      }
    } catch (e) {
      // Keep fallback
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
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

  Future<void> _savePlace() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      _showSnackBar('Please enter a name for the place');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final id = const Uuid().v4();
      final newPlace = Place(
        id: id,
        label: label,
        icon: _selectedIcon,
        lat: _mapCenter.latitude,
        lng: _mapCenter.longitude,
        radiusM: _radius,
        status: PlaceStatus.confirmed,
        triggerType: _triggerType,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dirty: true,
      );

      await _placeRepository.addPlace(newPlace);
      _showSnackBar('Geofence "$label" added successfully!');
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showSnackBar('Failed to add geofence');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _getIconColor(_selectedIcon);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF16162A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Add New Geofence',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Dragging Map Container
              Container(
                height: 220,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF22223C),
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
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
                                color: iconColor.withValues(alpha:0.18),
                                borderStrokeWidth: 1.5,
                                borderColor: iconColor,
                                useRadiusInMeter: true,
                                radius: _radius,
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Fixed Center Pin Overlay
                      Center(
                        child: IgnorePointer(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_pin,
                                color: iconColor,
                                size: 38,
                              ),
                              const SizedBox(
                                height: 38,
                              ), // Offset the pin tip to sit on center
                            ],
                          ),
                        ),
                      ),

                      // Center point indicator
                      Center(
                        child: IgnorePointer(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 2,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Loading indicator overlay
                      if (_isLoadingLocation)
                        Container(
                          color: const Color(0xFF0F0F1A).withValues(alpha:0.6),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF6C63FF),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Form fields
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Label
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
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'e.g. Office, Gym, Home',
                        hintStyle: const TextStyle(
                          color: Colors.white30,
                          fontSize: 14,
                        ),
                        fillColor: const Color(0xFF0F0F1A),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF22223C),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF22223C),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF6C63FF),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Icon/Category Selection
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
                                  : const Color(0xFF0F0F1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? col
                                    : const Color(0xFF22223C),
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

                    // Radius Selector
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
                    // Trigger Type
                    const SizedBox(height: 20),
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
                        color: const Color(0xFF0F0F1A),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                margin: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(
                                          0xFF6C63FF,
                                        ).withValues(alpha:0.15)
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
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _savePlace,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Create Geofence',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
