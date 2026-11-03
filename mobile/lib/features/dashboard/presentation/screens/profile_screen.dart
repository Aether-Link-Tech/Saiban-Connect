import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../shared/widgets/common.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final sites = ref.watch(sitesProvider).valueOrNull ?? const [];
    final departments = ref.watch(departmentsProvider).valueOrNull ?? const [];
    final siteNames = sites.where((s) => me.assignedSiteIds.contains(s.id)).map((s) => s.name).join(', ');
    final dept = departments.where((d) => d.id == me.departmentId).map((d) => d.name).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: Avatar(initials: me.initials, photoPath: me.photoPath, radius: 44)),
          const SizedBox(height: 12),
          Center(child: Text(me.displayName, style: Theme.of(context).textTheme.titleLarge)),
          Center(child: Text(me.role.label)),
          const SizedBox(height: 24),
          InfoRow('Employee code', me.employeeCode ?? '—'),
          InfoRow('Designation', me.designation ?? '—'),
          InfoRow('Department', dept ?? '—'),
          InfoRow('Phone', me.phoneDisplay),
          InfoRow('Email', me.email ?? '—'),
          InfoRow('Assigned sites', siteNames.isEmpty ? '—' : siteNames),
          InfoRow('Registered phone', me.activeDeviceModel ?? '—'),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Sign out?',
                message: 'Location tracking stops when you sign out. Records not yet synced stay on this phone.',
                confirmLabel: 'Sign out',
              );
              if (!ok || !context.mounted) return;
              Navigator.of(context).popUntil((r) => r.isFirst);
              await signOut(ref);
            },
          ),
        ],
      ),
    );
  }
}
