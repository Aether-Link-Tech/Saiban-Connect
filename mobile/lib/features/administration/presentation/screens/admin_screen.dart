import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../domain/entities/models.dart';
import '../../../sites/presentation/screens/sites_screen.dart';
import 'audit_log_screen.dart';
import 'departments_screen.dart';
import 'device_requests_screen.dart';
import 'employees_admin_screen.dart';
import 'flagged_attendance_screen.dart';
import 'policy_screen.dart';
import 'registrations_screen.dart';

/// HR / Administrator menu (proposal §4.7).
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final isAdmin = me.role == UserRole.admin;
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    final pendingRegs = fs.collection('users').where('accountStatus', isEqualTo: 'pending').snapshots().map((s) => s.size);
    final pendingDevices = fs.collection('deviceRequests').where('status', isEqualTo: 'pending').snapshots().map((s) => s.size);
    final flagged = fs.collection('attendanceEvents').where('reviewStatus', isEqualTo: 'pending').snapshots().map((s) => s.size);

    Widget tile(IconData icon, String title, String subtitle, Widget page, {Stream<int>? badge}) => Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: badge == null
                ? const Icon(Icons.chevron_right)
                : StreamBuilder<int>(
                    stream: badge,
                    builder: (_, s) => (s.data ?? 0) > 0
                        ? Badge(label: Text('${s.data}'), child: const Icon(Icons.chevron_right))
                        : const Icon(Icons.chevron_right),
                  ),
            onTap: () => open(page),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(isAdmin ? 'Administration' : 'HR')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          tile(Icons.person_add_alt, 'Registrations', 'Approve new employee accounts', const RegistrationsScreen(),
              badge: pendingRegs),
          const SizedBox(height: 8),
          tile(Icons.phone_android, 'Device requests', 'Approve phone changes', const DeviceRequestsScreen(),
              badge: pendingDevices),
          const SizedBox(height: 8),
          tile(Icons.flag_outlined, 'Flagged attendance', 'Review unusual check-ins/outs', const FlaggedAttendanceScreen(),
              badge: flagged),
          const SizedBox(height: 8),
          tile(Icons.badge_outlined, 'Employees', 'Roles, departments, managers, sites', const EmployeesAdminScreen()),
          if (isAdmin) ...[
            const SizedBox(height: 8),
            tile(Icons.place_outlined, 'Sites & geofences', 'Head office and field locations', const SitesScreen()),
            const SizedBox(height: 8),
            tile(Icons.apartment, 'Departments', 'Organization structure', const DepartmentsScreen()),
            const SizedBox(height: 8),
            tile(Icons.tune, 'Policy settings', 'Leave approvals, GPS, photos, retention', const PolicyScreen()),
          ],
          const SizedBox(height: 8),
          tile(Icons.receipt_long_outlined, 'Audit log', 'Approvals and administrative actions', const AuditLogScreen()),
        ],
      ),
    );
  }
}
