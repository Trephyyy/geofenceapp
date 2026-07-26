import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/place.dart';
import '../services/db_service.dart';
import '../services/native_geofence_service.dart';
import '../repositories/place_repository.dart';

class DeveloperPanelScreen extends StatefulWidget {
  const DeveloperPanelScreen({super.key});

  @override
  State<DeveloperPanelScreen> createState() => _DeveloperPanelScreenState();
}

class _DeveloperPanelScreenState extends State<DeveloperPanelScreen> with SingleTickerProviderStateMixin {
  final DbService _dbService = DbService();
  final PlaceRepository _placeRepository = PlaceRepository();
  final NativeGeofenceService _geofenceService = NativeGeofenceService();

  late TabController _tabController;
  final TextEditingController _importController = TextEditingController();
  
  String _exportedJson = '';
  bool _isLoading = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadExportData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _importController.dispose();
    super.dispose();
  }

  Future<void> _loadExportData() async {
    setState(() => _isLoading = true);
    try {
      final db = await _dbService.database;

      // 1. Query raw database maps to preserve original types directly
      final List<Map<String, dynamic>> placesRaw = await db.query('places');
      final List<Map<String, dynamic>> visitsRaw = await db.query('visits');
      final List<Map<String, dynamic>> learningPointsRaw = await db.query('learning_points');

      final exportData = {
        'places': placesRaw,
        'visits': visitsRaw,
        'learning_points': learningPointsRaw,
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(exportData);
      setState(() {
        _exportedJson = jsonStr;
      });
    } catch (e) {
      _showSnackBar('Failed to serialize database data');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade900 : const Color(0xFF1E3A2F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _copyToClipboard() async {
    if (_exportedJson.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _exportedJson));
    setState(() {
      _copied = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  Future<void> _importData() async {
    final text = _importController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('Please paste JSON data first', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final Map<String, dynamic> data = jsonDecode(text);

      // Simple structural validation
      if (!data.containsKey('places') || !data.containsKey('visits') || !data.containsKey('learning_points')) {
        throw const FormatException('Missing required database tables keys (places, visits, learning_points)');
      }

      final db = await _dbService.database;

      // Unregister all current geofences before wiping the database
      final currentPlaces = await _placeRepository.getAllPlaces();
      for (final place in currentPlaces) {
        await _geofenceService.unregisterGeofence(place.id);
      }

      // Execute transaction to insert new data
      await db.transaction((txn) async {
        // Clear tables
        await txn.delete('places');
        await txn.delete('visits');
        await txn.delete('learning_points');

        // Insert places
        final List<dynamic> places = data['places'];
        for (final p in places) {
          await txn.insert('places', Map<String, dynamic>.from(p));
        }

        // Insert visits
        final List<dynamic> visits = data['visits'];
        for (final v in visits) {
          await txn.insert('visits', Map<String, dynamic>.from(v));
        }

        // Insert learning points
        final List<dynamic> points = data['learning_points'];
        for (final lp in points) {
          await txn.insert('learning_points', Map<String, dynamic>.from(lp));
        }
      });

      // Register geofences for newly imported confirmed places
      final importedPlaces = await _placeRepository.getAllPlaces();
      int registeredCount = 0;
      for (final place in importedPlaces) {
        if (place.status == PlaceStatus.confirmed) {
          await _geofenceService.registerGeofence(
            id: place.id,
            lat: place.lat,
            lng: place.lng,
            radius: place.radiusM,
          );
          registeredCount++;
        }
      }

      _importController.clear();
      _showSnackBar(
        'Successfully imported ${importedPlaces.length} places ($registeredCount geofences registered) and ${data['visits']?.length} visit logs!',
      );
      
      // Switch to export tab to show updated data
      _tabController.animateTo(0);
      _loadExportData();
    } catch (e) {
      _showSnackBar('Import failed: ${e.toString()}', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _wipeDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F35),
        title: const Text('Wipe All Database Data?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete all confirmed geofences, registered places, visit logs, '
          'and location learning points. Geofences will be unregistered from the OS. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Wipe Everything'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        // 1. Unregister all geofences
        final places = await _placeRepository.getAllPlaces();
        for (final p in places) {
          await _geofenceService.unregisterGeofence(p.id);
        }

        // 2. Wipe DB
        final db = await _dbService.database;
        await db.transaction((txn) async {
          await txn.delete('places');
          await txn.delete('visits');
          await txn.delete('learning_points');
        });

        _showSnackBar('Database wiped successfully.');
        _loadExportData();
      } catch (e) {
        _showSnackBar('Failed to wipe database', isError: true);
      } finally {
        setState(() => _isLoading = false);
      }
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
        title: const Text('Developer Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6C63FF),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(icon: Icon(Icons.download_rounded), text: 'Export'),
            Tab(icon: Icon(Icons.upload_rounded), text: 'Import'),
            Tab(icon: Icon(Icons.delete_forever_rounded), text: 'Reset'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildExportTab(),
                _buildImportTab(),
                _buildResetTab(),
              ],
            ),
    );
  }

  Widget _buildExportTab() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Export Database (JSON)',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Copy the serialized database contents to backing file or transfer to another device.',
            style: TextStyle(color: Color(0xFFA0A0C0), fontSize: 12),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF16162A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF22223C)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _exportedJson.isEmpty ? '{}' : _exportedJson,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loadExportData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh Data'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF22223C)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, color: Colors.white),
                  label: Text(_copied ? 'Copied!' : 'Copy JSON', style: const TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _copied ? const Color(0xFF52B788) : const Color(0xFF6C63FF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImportTab() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Import Database Data',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paste database export JSON string below. This will overwrite all current database entries and re-initialize geofences.',
            style: TextStyle(color: Color(0xFFA0A0C0), fontSize: 12),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: _importController,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Paste export JSON here...',
                hintStyle: const TextStyle(color: Colors.white24),
                fillColor: const Color(0xFF16162A),
                filled: true,
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
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _importData,
            icon: const Icon(Icons.upload_rounded, color: Colors.white),
            label: const Text('Start Import', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 72,
            ),
            const SizedBox(height: 16),
            const Text(
              'Danger Zone',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Resetting database is an irreversible operation. It will unregister active geofences from the operating system and clear all tracked visits.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFA0A0C0), fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _wipeDatabase,
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
              label: const Text('Wipe All Database Tables', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
