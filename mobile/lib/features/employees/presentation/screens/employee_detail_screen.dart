import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';
import '../../../administration/presentation/screens/employee_editor_screen.dart';
import '../../../attendance/presentation/screens/attendance_history_screen.dart';
import '../../../photos/presentation/screens/photos_screen.dart';

class EmployeeDetailScreen extends ConsumerWidget {
  const EmployeeDetailScreen({super.key, required this.employee});
  final UserProfile employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final sites = ref.watch(sitesProvider).valueOrNull ?? const [];
    final departments = ref.watch(departmentsProvider).valueOrNull ?? const [];
    final e = employee;
    final siteNames = sites.where((s) => e.assignedSiteIds.contains(s.id)).map((s) => s.name).join(', ');
    final dept = departments.where((d) => d.id == e.departmentId).map((d) => d.name).firstOrNull;
    final canEdit = me.role.isHrOrAdmin && (me.role == UserRole.admin || !e.role.isHrOrAdmin);
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(title: Text(e.displayName)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: Avatar(initials: e.initials, photoPath: e.photoPath, radius: 40)),
          const SizedBox(height: 8),
          Center(child: StatusChip.status(e.accountStatus)),
          const SizedBox(height: 16),
          InfoRow('Role', e.role.label),
          InfoRow('Employee code', e.employeeCode ?? '—'),
          InfoRow('Designation', e.designation ?? '—'),
          InfoRow('Department', dept ?? '—'),
          InfoRow('Phone', e.phoneDisplay),
          InfoRow('Email', e.email ?? '—'),
          InfoRow('Sites', siteNames.isEmpty ? '—' : siteNames),
          InfoRow('Registered phone', e.activeDeviceModel ?? '—'),
          const SizedBox(height: 16),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Attendance history'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(AttendanceHistoryScreen(employee: e)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Site photos'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(Scaffold(
                  appBar: AppBar(title: Text('Photos — ${e.displayName}')),
                  body: PhotoGrid(
                    query: scopeForViewer(fs.collection('fieldPhotos').where('uid', isEqualTo: e.uid), me, ownerUid: e.uid)
                        .orderBy('uploadedAt', descending: true)
                        .limit(60),
                    showName: false,
                    emptyMessage: 'No photos.',
                  ),
                )),
              ),
              if (canEdit) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Edit employee'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(EmployeeEditorScreen(employee: e)),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}
