import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/location_native_bridge.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  final DebugLogBridge _bridge = DebugLogBridge();
  List<DebugLogEntry> _allLogs = [];
  List<DebugLogEntry> _filteredLogs = [];
  String _selectedCategory = 'ALL';
  bool _isLoading = true;
  bool _loggingEnabled = true;

  static const List<String> _categories = [
    'ALL', 'GEOFENCE', 'HARBOR', 'LOCATION', 'WEBHOOK', 'CRYPTO', 'CONSENT', 'SYSTEM'
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      _loggingEnabled = await _bridge.isLoggingEnabled();
      _allLogs = await _bridge.getLogs(limit: 200);
      _applyFilter();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFilter() {
    setState(() {
      if (_selectedCategory == 'ALL') {
        _filteredLogs = List.from(_allLogs);
      } else {
        _filteredLogs = _allLogs
            .where((l) => l.category == _selectedCategory)
            .toList();
      }
    });
  }

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logDate = DateTime(dt.year, dt.month, dt.day);
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    if (logDate == today) return time;
    return '${dt.month}/${dt.day} $time';
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F35),
        title: const Text('Clear All Debug Logs?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete all debug log entries.',
          style: TextStyle(color: Colors.white70),
        ),
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
      await _bridge.clearLogs();
      await _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debug logs cleared')),
        );
      }
    }
  }

  Future<void> _exportLogs() async {
    try {
      final path = await _bridge.exportLogsToFile();
      if (path.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export failed: empty path')),
          );
        }
        return;
      }
      await Clipboard.setData(ClipboardData(text: 'Logs exported to: $path'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logs exported to $path')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _toggleLogging() async {
    final newValue = !_loggingEnabled;
    await _bridge.setLoggingEnabled(newValue);
    setState(() => _loggingEnabled = newValue);
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
        title: const Text('Debug Logs', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(
              _loggingEnabled ? Icons.settings_rounded : Icons.toggle_off_outlined,
              color: _loggingEnabled ? Colors.white70 : Colors.white38,
            ),
            onPressed: _toggleLogging,
            tooltip: _loggingEnabled ? 'Logging enabled' : 'Logging disabled',
          ),
          IconButton(
            icon: const Icon(Icons.file_download_rounded, color: Colors.white70),
            onPressed: _exportLogs,
            tooltip: 'Export logs',
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.white54),
            onPressed: _clearLogs,
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildCategoryChips(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
                  : _filteredLogs.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          itemCount: _filteredLogs.length,
                          itemBuilder: (context, index) =>
                              _LogEntryTile(entry: _filteredLogs[index], formatTimestamp: _formatTimestamp),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _categories.map((cat) {
            final selected = _selectedCategory == cat;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(cat, style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                )),
                selected: selected,
                onSelected: (_) {
                  setState(() => _selectedCategory = cat);
                  _applyFilter();
                },
                selectedColor: const Color(0xFF6C63FF),
                checkmarkColor: Colors.white,
                backgroundColor: const Color(0xFF16162A),
                side: BorderSide(
                  color: selected ? const Color(0xFF6C63FF) : const Color(0xFF22223C),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.article_outlined, size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            _selectedCategory == 'ALL' ? 'No debug logs yet' : 'No $_selectedCategory logs',
            style: const TextStyle(color: Colors.white38, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Logs appear here as geofence and location events fire',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

const Map<String, Color> _levelColorMap = {
  'DEBUG': Color(0xFF808080),
  'INFO': Color(0xFF4FC3F7),
  'WARN': Color(0xFFFFB74D),
  'ERROR': Color(0xFFE57373),
};

class _LogEntryTile extends StatefulWidget {
  final DebugLogEntry entry;
  final String Function(int) formatTimestamp;

  const _LogEntryTile({required this.entry, required this.formatTimestamp});

  @override
  State<_LogEntryTile> createState() => _LogEntryTileState();
}

class _LogEntryTileState extends State<_LogEntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final levelColor = _levelColorMap[e.level] ?? Colors.white54;
    final ts = widget.formatTimestamp(e.timestamp);

    return GestureDetector(
      onTap: () {
        if (e.hasExtra) setState(() => _expanded = !_expanded);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF16162A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      ts,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: levelColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      e.level,
                      style: TextStyle(
                        color: levelColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      e.category,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.message,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (e.hasExtra)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white38,
                      size: 18,
                    ),
                ],
              ),
            ),
            if (_expanded && e.hasExtra)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F1A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _prettyPrintExtra(e.extraJson),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _prettyPrintExtra(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      return decoded.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');
    }
    return decoded.toString();
  } catch (_) {
    return json;
  }
}
