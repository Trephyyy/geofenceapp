import 'dart:async';
import 'package:flutter/material.dart';
import '../services/event_logger_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final EventLoggerService _logger = EventLoggerService();
  List<EventLog> _logs = [];
  bool _isLoading = true;
  StreamSubscription? _logSub;

  static const Map<EventType, IconData> _typeIcons = {
    EventType.entered: Icons.login_rounded,
    EventType.left: Icons.logout_rounded,
    EventType.startedTracking: Icons.play_arrow_rounded,
    EventType.stoppedTracking: Icons.stop_rounded,
    EventType.polledLocation: Icons.my_location_rounded,
    EventType.geofenceRegistered: Icons.add_location_alt_rounded,
    EventType.geofenceUnregistered: Icons.location_off_rounded,
    EventType.learningStarted: Icons.tips_and_updates_rounded,
    EventType.learningStopped: Icons.tips_and_updates_rounded,
    EventType.placeConfirmed: Icons.check_circle_rounded,
    EventType.placeDeleted: Icons.delete_rounded,
    EventType.webhookDispatched: Icons.webhook_rounded,
    EventType.historyPurged: Icons.cleaning_services_rounded,
    EventType.system: Icons.info_outline_rounded,
  };

  static const Map<EventType, Color> _typeColors = {
    EventType.entered: Color(0xFF52B788),
    EventType.left: Color(0xFFE57373),
    EventType.startedTracking: Color(0xFF4FC3F7),
    EventType.stoppedTracking: Color(0xFFFFB74D),
    EventType.polledLocation: Color(0xFF9B5DE5),
    EventType.geofenceRegistered: Color(0xFF6C63FF),
    EventType.geofenceUnregistered: Color(0xFFA0A0C0),
    EventType.learningStarted: Color(0xFF52B788),
    EventType.learningStopped: Color(0xFFFFB74D),
    EventType.placeConfirmed: Color(0xFF52B788),
    EventType.placeDeleted: Color(0xFFE57373),
    EventType.webhookDispatched: Color(0xFF6C63FF),
    EventType.historyPurged: Color(0xFFE57373),
    EventType.system: Color(0xFFA0A0C0),
  };

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _logSub = _logger.onNewLog.listen((_) {
      _loadLogs();
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final logs = await _logger.getRecentLogs();
    if (mounted) {
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F35),
        title: const Text('Clear Event Logs?', style: TextStyle(color: Colors.white)),
        content: const Text('This will permanently delete all event log entries.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _logger.clearAll();
      await _loadLogs();
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logDate = DateTime(dt.year, dt.month, dt.day);
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    if (logDate == today) return time;
    return '${dt.month}/${dt.day} $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
                  : _logs.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadLogs,
                          color: const Color(0xFF6C63FF),
                          backgroundColor: const Color(0xFF1F1F35),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            itemCount: _logs.length,
                            itemBuilder: (context, index) => _buildLogTile(_logs[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.list_alt_rounded, color: Color(0xFF6C63FF), size: 22),
          const SizedBox(width: 10),
          const Text(
            'Event Logs',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (_logs.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A2F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E6B4F), width: 1),
              ),
              child: Text(
                '${_logs.length}',
                style: const TextStyle(
                  color: Color(0xFF52B788),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
            onPressed: _logs.isEmpty ? null : _clearLogs,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          const Text(
            'No events yet',
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Geofence transitions, location polls,\nand app events will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildLogTile(EventLog log) {
    final icon = _typeIcons[log.type] ?? Icons.info_outline;
    final color = _typeColors[log.type] ?? Colors.white54;
    final timeStr = _formatTime(log.timestamp);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF22223C), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (log.placeLabel != null && log.type != EventType.system)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        log.placeLabel!,
                        style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              timeStr,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
