import 'package:flutter/material.dart';
import '../screens/dashboard_screen.dart';
import '../screens/storage_screen.dart';
import '../screens/place_management_screen.dart';
import '../screens/logs_screen.dart';
import '../screens/developer_panel_screen.dart';

class AppShell extends StatefulWidget {
  final int initialIndex;
  const AppShell({super.key, this.initialIndex = 0});

  static AppShellState of(BuildContext context) {
    final state = context.findAncestorStateOfType<AppShellState>();
    assert(state != null, 'AppShell not found in widget tree');
    return state!;
  }

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void switchToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const DashboardScreen(),
          const StorageScreen(),
          const PlaceManagementScreen(),
          const LogsScreen(),
          const DeveloperPanelScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    final navItems = [
      _NavItem(Icons.home_rounded, 'Home', 0),
      _NavItem(Icons.storage_rounded, 'Storage', 1),
      _NavItem(Icons.place_outlined, 'Places', 2),
      _NavItem(Icons.list_alt_rounded, 'Logs', 3),
      _NavItem(Icons.developer_mode_rounded, 'Dev', 4),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF16162A),
        border: Border(
          top: BorderSide(color: Color(0xFF22223C), width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
        top: 8,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: navItems.map((item) {
            final isActive = _currentIndex == item.index;
            return GestureDetector(
              onTap: () => switchToTab(item.index),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      color: isActive
                          ? const Color(0xFF6C63FF)
                          : const Color(0xFF5A5A7A),
                      size: 22,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: TextStyle(
                        color: isActive
                            ? const Color(0xFF6C63FF)
                            : const Color(0xFF5A5A7A),
                        fontSize: 10,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final int index;
  const _NavItem(this.icon, this.label, this.index);
}
