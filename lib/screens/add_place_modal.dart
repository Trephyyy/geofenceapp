import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../models/place.dart';
import '../repositories/place_repository.dart';
import '../services/native_geofence_service.dart';
import '../services/event_logger_service.dart';
import '../widgets/radius_picker_widget.dart';

class AddPlaceModal extends StatefulWidget {
  final List<Place> existingPlaces;

  const AddPlaceModal({super.key, required this.existingPlaces});

  @override
  State<AddPlaceModal> createState() => _AddPlaceModalState();
}

class _AddPlaceModalState extends State<AddPlaceModal> {
  final PlaceRepository _placeRepository = PlaceRepository();
  final NativeGeofenceService _geofenceService = NativeGeofenceService();
  final EventLoggerService _logger = EventLoggerService();
  final MapController _mapController = MapController();

  final TextEditingController _labelController = TextEditingController();
  PlaceIcon _selectedIcon = PlaceIcon.custom;
  double _radius = 150.0;
  GeofenceTriggerType _triggerType = GeofenceTriggerType.normal;

  LatLng _mapCenter = const LatLng(37.4279613, -122.0857496);
  bool _isLoadingLocation = true;
  bool _isSaving = false;
  bool _editMode = false;
  LatLng _draftCenter = const LatLng(37.4279613, -122.0857496);
  bool _hasDraftChanges = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    if (widget.existingPlaces.isNotEmpty) {
      setState(() {
        _mapCenter = LatLng(widget.existingPlaces.first.lat, widget.existingPlaces.first.lng);
        _draftCenter = _mapCenter;
        _isLoadingLocation = false;
      });
    }

    try {
      final loc = await _geofenceService.getCurrentLocation();
      if (loc != null && mounted) {
        final userLatLng = LatLng(loc['lat']!, loc['lng']!);
        setState(() {
          _mapCenter = userLatLng;
          _draftCenter = userLatLng;
          _isLoadingLocation = false;
        });
        _mapController.move(userLatLng, 15.5);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _toggleEditMode() {
    setState(() {
      _editMode = !_editMode;
      if (!_editMode && _hasDraftChanges) {
        _hasDraftChanges = false;
      }
    });
  }

  void _onMapMoved(LatLng center, bool hasGesture) {
    if (!_editMode || !hasGesture) return;
    setState(() {
      _draftCenter = center;
      _hasDraftChanges = true;
    });
  }

  void _saveDraftCenter() {
    setState(() {
      _mapCenter = _draftCenter;
      _editMode = false;
      _hasDraftChanges = false;
    });
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
      await _geofenceService.registerGeofence(id: id, lat: newPlace.lat, lng: newPlace.lng, radius: newPlace.radiusM);
      _logger.logPlaceConfirmed(label);
      _logger.logGeofenceRegistered(label);
      _showSnackBar('Geofence "$label" added successfully!');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _showSnackBar('Failed to add geofence');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _getIconColor(_selectedIcon);
    final displayCenter = _editMode ? _draftCenter : _mapCenter;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Add New Geofence', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              Container(
                height: 220,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _editMode ? iconColor : const Color(0xFF22223C), width: 1.5),
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
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.pinchMove,
                          ),
                          onPositionChanged: (camera, hasGesture) => _onMapMoved(camera.center, hasGesture),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.geofenceapp',
                          ),
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: displayCenter,
                                color: _editMode
                                    ? iconColor.withValues(alpha: 0.12)
                                    : iconColor.withValues(alpha: 0.18),
                                borderStrokeWidth: _editMode ? 2.0 : 1.5,
                                borderColor: _editMode ? iconColor.withValues(alpha: 0.5) : iconColor,
                                useRadiusInMeter: true,
                                radius: _radius,
                              ),
                            ],
                          ),
                        ],
                      ),
                      Center(
                        child: IgnorePointer(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_pin, color: iconColor, size: 38),
                              const SizedBox(height: 38),
                            ],
                          ),
                        ),
                      ),
                      Center(
                        child: IgnorePointer(
                          child: Container(
                            width: 6, height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 2, spreadRadius: 1)],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _toggleEditMode,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _editMode ? const Color(0xFFFFA726) : const Color(0xFF2A2A44),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _editMode ? Icons.lock_open : Icons.lock_outline,
                                  color: _editMode ? Colors.black : Colors.white70,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _editMode ? 'Editing' : 'Edit Location',
                                  style: TextStyle(
                                    color: _editMode ? Colors.black : Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_editMode && _hasDraftChanges)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _saveDraftCenter,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: iconColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Save', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_isLoadingLocation)
                        Container(
                          color: const Color(0xFF0F0F1A).withValues(alpha: 0.6),
                          child: const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
                        ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Geofence Name', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _labelController,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'e.g. Office, Gym, Home',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                        fillColor: const Color(0xFF0F0F1A),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF22223C))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF22223C))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6C63FF))),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text('Category Icon', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: PlaceIcon.values.map((icon) {
                        final isSelected = _selectedIcon == icon;
                        final col = _getIconColor(icon);
                        return GestureDetector(
                          onTap: () => setState(() => _selectedIcon = icon),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? col.withValues(alpha: 0.12) : const Color(0xFF0F0F1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isSelected ? col : const Color(0xFF22223C), width: 1.5),
                            ),
                            child: Icon(_getIconData(icon), color: isSelected ? col : Colors.white60, size: 24),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    RadiusPickerWidget(
                      initialRadius: _radius,
                      activeColor: iconColor,
                      onChanged: (val) => setState(() => _radius = val),
                    ),

                    const SizedBox(height: 20),
                    const Text('Trigger Type', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFF0F0F1A), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: GeofenceTriggerType.values.map((type) {
                          final isSelected = _triggerType == type;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _triggerType = type),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                margin: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF6C63FF).withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isSelected ? const Color(0xFF6C63FF) : const Color(0xFF22223C), width: 1.5),
                                ),
                                child: Text(
                                  type.displayName,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : const Color(0xFFA0A0C0),
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_triggerType.description, style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 11, height: 1.3)),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _savePlace,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF2E2E4A),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Create Geofence', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
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