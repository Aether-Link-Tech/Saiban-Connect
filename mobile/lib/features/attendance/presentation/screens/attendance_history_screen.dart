import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';
import '../widgets/correction_dialog.dart';

/// Daily attendance records for one employee (own history, or a team member's).
class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({super.key, required this.employee});
  final UserProfile employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final policy = ref.watch(currentPolicyProvider);
    final canCorrect = policy.correctionRoles.contains(me.role.name) &&
        (employee.uid != me.uid || me.role == UserRole.admin);

    final query = scopeForViewer(
      fs.collection('attendanceDays').where('uid', isEqualTo: employee.uid),
      me,
      ownerUid: employee.uid,
    ).orderBy('dateKey', descending: true).limit(62);

    return Scaffold(
      appBar: AppBar(
        title: Text(employee.uid == me.uid ? 'My attendance' : employee.displayName),
        actions: [
          if (canCorrect)
            IconButton(
              tooltip: 'Add correction',
              icon: const Icon(Icons.edit_calendar_outlined),
              onPressed: () => showCorrectionDialog(context, ref, employee: employee),
            ),
        ],
      ),
      body: QueryList<AttendanceDay>(
        stream: query.snapshots().map((s) => s.docs.map(AttendanceDay.fromDoc).toList()),
        emptyMessage: 'No attendance records yet.',
        itemBuilder: (context, d) => Card(
          child: ListTile(
            title: Text(fmtDateKey(d.dateKey)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('In ${fmtTime(d.checkInAt)} · Out ${fmtTime(d.checkOutAt)} · ${fmtDuration(d.workedMinutes)}'
                    '${d.siteName != null ? '\n${d.siteName}' : ''}'),
                if (d.flags.isNotEmpty) ...[const SizedBox(height: 4), FlagChips(d.flags)],
                if (d.corrected && d.corrections.isNotEmpty)
                  Text('Corrected by ${d.corrections.last.byName}: ${d.corrections.last.reason}',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            trailing: StatusChip.status(d.status),
            isThreeLine: true,
            onTap: canCorrect ? () => showCorrectionDialog(context, ref, employee: employee, day: d) : null,
          ),
        ),
      ),
    );
  }
}
