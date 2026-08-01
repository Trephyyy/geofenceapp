import 'package:flutter/material.dart';
import '../services/native_geofence_service.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  final NativeGeofenceService _geofenceService = NativeGeofenceService();
  Map<String, int>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    final stats = await _geofenceService.getStorageStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Storage & Queue',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
            )
          : _stats == null
          ? const Center(
              child: Text(
                'Failed to load storage stats',
                style: TextStyle(color: Color(0xFFA0A0C0)),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadStats,
              color: const Color(0xFF6C63FF),
              backgroundColor: const Color(0xFF1F1F35),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildDatabaseSizeCard(),
                  const SizedBox(height: 16),
                  _buildTableStatsCard(),
                  const SizedBox(height: 16),
                  _buildQueueStatusCard(),
                  const SizedBox(height: 16),
                  _buildInfoCard(),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildDatabaseSizeCard() {
    final dbSize = _stats!['dbSizeBytes'] ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A2F), Color(0xFF16162A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E6B4F), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2E6B4F).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.storage_rounded,
              color: Color(0xFF52B788),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Database Size',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatBytes(dbSize),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableStatsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22223C), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.table_chart_outlined,
                color: Color(0xFF6C63FF),
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Table Row Counts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatRow(
            Icons.place_outlined,
            'Places',
            _stats!['places'] ?? 0,
            const Color(0xFF00BBF9),
          ),
          _buildStatRow(
            Icons.history_rounded,
            'Visits',
            _stats!['visits'] ?? 0,
            const Color(0xFF00F5D4),
          ),
          _buildStatRow(
            Icons.my_location_rounded,
            'Learning Points',
            _stats!['learningPoints'] ?? 0,
            const Color(0xFF9B5DE5),
          ),
          _buildStatRow(
            Icons.location_on_rounded,
            'Location Logs',
            _stats!['locationLogs'] ?? 0,
            const Color(0xFFFF007F),
          ),
          _buildStatRow(
            Icons.webhook_rounded,
            'Webhook Queue',
            _stats!['webhookQueue'] ?? 0,
            const Color(0xFFFFA500),
          ),
          _buildStatRow(
            Icons.swap_horiz_rounded,
            'Geofence Transitions',
            _stats!['geofenceTransitions'] ?? 0,
            const Color(0xFFFF6B6B),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Text(
            _formatCount(count),
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueStatusCard() {
    final queueCount = _stats!['webhookQueue'] ?? 0;
    final isNearCap = queueCount > 800;
    final isAtCap = queueCount >= 1000;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAtCap
              ? Colors.redAccent
              : isNearCap
              ? const Color(0xFFFFA500)
              : const Color(0xFF22223C),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.webhook_rounded,
                color: Color(0xFF6C63FF),
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Webhook Queue Health',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: queueCount / 1000.0,
              backgroundColor: const Color(0xFF22223C),
              valueColor: AlwaysStoppedAnimation<Color>(
                isAtCap
                    ? Colors.redAccent
                    : isNearCap
                    ? const Color(0xFFFFA500)
                    : const Color(0xFF52B788),
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$queueCount / 1000 events',
                style: TextStyle(
                  color: isAtCap ? Colors.redAccent : Colors.white70,
                  fontSize: 12,
                ),
              ),
              if (isAtCap)
                const Text(
                  'FIFO eviction active',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (isNearCap)
                const Text(
                  'Near capacity',
                  style: TextStyle(
                    color: Color(0xFFFFA500),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else
                const Text(
                  'Healthy',
                  style: TextStyle(
                    color: Color(0xFF52B788),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF6C63FF), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Location data is encrypted at rest using AES-256-GCM with keys stored in the Android KeyStore. '
              'The webhook queue uses FIFO eviction: when full (1000 events), the oldest event is dropped to make room for new ones.',
              style: const TextStyle(
                color: Color(0xFFA0A0C0),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}
