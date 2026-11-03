import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../domain/entities/models.dart';
import '../../../administration/presentation/screens/admin_screen.dart';
import '../../../attendance/application/attendance_actions.dart';
import '../../../employees/presentation/screens/team_screen.dart';
import '../../../leave/presentation/screens/leave_screen.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../photos/presentation/screens/photos_screen.dart';
import 'home_tab.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final Widget Function() builder;
}

/// Main navigation. Tabs depend on role:
/// Employee: Home, Leave, Photos, Alerts
/// Supervisor/Manager: Home, Team, Leave, Photos, Alerts
/// HR/Admin: Home, Team, Leave, Admin, Alerts
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startServices());
  }

  Future<void> _startServices() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    ref.read(syncServiceProvider).start(uid);
    ref.read(pushServiceProvider).start();
    // Give the server day record a moment to load before deciding to resume tracking.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) await ref.read(attendanceActionsProvider).resumeTrackingIfNeeded();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncServiceProvider).flush();
      ref.invalidate(localTodayProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<_Tab> _tabsFor(UserRole role) => [
        _Tab('Home', Icons.home_outlined, () => const HomeTab()),
        if (role.isTeamLead) _Tab('Team', Icons.groups_outlined, () => const TeamScreen()),
        _Tab('Leave', Icons.event_note_outlined, () => const LeaveScreen()),
        if (!role.isHrOrAdmin) _Tab('Photos', Icons.photo_library_outlined, () => const MyPhotosScreen()),
        if (role.isHrOrAdmin) _Tab('Admin', Icons.admin_panel_settings_outlined, () => const AdminScreen()),
        _Tab('Alerts', Icons.notifications_outlined, () => const NotificationsScreen()),
      ];

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final tabs = _tabsFor(me.role);
    if (_index >= tabs.length) _index = 0;
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [for (final t in tabs) t.builder()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: t.label == 'Alerts' && unread > 0
                  ? Badge(label: Text('$unread'), child: Icon(t.icon))
                  : Icon(t.icon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
