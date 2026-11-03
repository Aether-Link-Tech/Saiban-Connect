import 'package:flutter/material.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';
import 'employee_editor_screen.dart';

class RegistrationsScreen extends StatelessWidget {
  const RegistrationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = fs
        .collection('users')
        .where('accountStatus', isEqualTo: 'pending')
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(UserProfile.fromDoc).toList());
    return Scaffold(
      appBar: AppBar(title: const Text('Pending registrations')),
      body: QueryList<UserProfile>(
        stream: stream,
        emptyMessage: 'No registrations awaiting approval.',
        itemBuilder: (context, u) => Card(
          child: ListTile(
            leading: Avatar(initials: u.initials, photoPath: u.photoPath),
            title: Text(u.displayName),
            subtitle: Text('${u.phoneDisplay}\nRequested ${fmtDateTime(u.requestedAt)} · ${u.pendingDeviceModel ?? ''}'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EmployeeEditorScreen(employee: u, registration: true)),
            ),
          ),
        ),
      ),
    );
  }
}
