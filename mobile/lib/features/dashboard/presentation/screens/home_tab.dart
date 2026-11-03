import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/common.dart';
import '../../../attendance/presentation/screens/attendance_history_screen.dart';
import '../../../attendance/presentation/widgets/check_in_card.dart';
import '../../../attendance/presentation/widgets/sync_status_card.dart';
import '../../../leave/presentation/screens/leave_form_screen.dart';
import '../../../photos/presentation/screens/photo_upload_screen.dart';
import 'profile_screen.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(
        title: const Text('SAIBAAN Connect'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: Avatar(initials: me.initials, photoPath: me.photoPath, radius: 16),
            onPressed: () => open(const ProfileScreen()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(localTodayProvider);
          await ref.read(syncServiceProvider).flush();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Assalam-o-Alaikum, ${me.displayName.split(' ').first}',
                style: Theme.of(context).textTheme.titleLarge),
            Text('${me.role.label} · ${fmtDateKey(todayKey())}'),
            const SizedBox(height: 16),
            const CheckInCard(),
            const SizedBox(height: 12),
            const SyncStatusCard(),
            const SectionTitle('Quick actions'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('My attendance history'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(AttendanceHistoryScreen(employee: me)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.add_a_photo_outlined),
                    title: const Text('Upload site photo'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(const PhotoUploadScreen()),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: const Text('Apply for leave'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(const LeaveFormScreen()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
