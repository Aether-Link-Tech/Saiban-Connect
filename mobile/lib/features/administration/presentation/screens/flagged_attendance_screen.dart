import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';

/// Attendance events flagged by the server (outside geofence, late sync, etc.).
class FlaggedAttendanceScreen extends ConsumerWidget {
  const FlaggedAttendanceScreen({super.key});

  Future<void> _decide(BuildContext context, WidgetRef ref, AttendanceEvent e, String decision) async {
    final comment = await promptText(
      context,
      title: decision == 'approve' ? 'Accept record' : 'Reject record',
      hint: decision == 'approve' ? 'Comment (optional)' : 'Reason',
      required: decision == 'reject',
      confirmLabel: decision == 'approve' ? 'Accept' : 'Reject',
    );
    if (comment == null || !context.mounted) return;
    await runWithFeedback(
      context,
      () => ref.read(apiProvider).call('reviewAttendanceEvent', {
        'eventId': e.id,
        'decision': decision,
        'comment': comment.isEmpty ? null : comment,
      }),
      success: 'Review saved.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final stream = scopeForViewer(fs.collection('attendanceEvents'), me)
        .where('reviewStatus', isEqualTo: 'pending')
        .orderBy('serverReceivedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(AttendanceEvent.fromDoc).where((e) => e.uid != me.uid).toList());

    return Scaffold(
      appBar: AppBar(title: const Text('Flagged attendance')),
      body: QueryList<AttendanceEvent>(
        stream: stream,
        emptyMessage: 'Nothing to review.',
        itemBuilder: (context, e) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${e.employeeName} · ${e.typeLabel}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text([
                  'Device time: ${fmtDateTime(e.deviceTime)}',
                  'Received: ${fmtDateTime(e.serverReceivedAt)}',
                  if (e.siteName != null) 'Nearest site: ${e.siteName}${e.distanceM != null ? ' (${e.distanceM!.round()} m)' : ''}',
                  if (e.accuracyM != null) 'GPS accuracy: ±${e.accuracyM!.round()} m',
                ].join('\n')),
                const SizedBox(height: 8),
                FlagChips(e.flags),
                if (e.latitude != null && e.longitude != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => openMap(e.latitude!, e.longitude!),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('View on map'),
                    ),
                  ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => _decide(context, ref, e, 'reject'), child: const Text('Reject')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(onPressed: () => _decide(context, ref, e, 'approve'), child: const Text('Accept')),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
