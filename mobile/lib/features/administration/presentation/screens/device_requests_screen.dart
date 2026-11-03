import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';

class DeviceRequestsScreen extends ConsumerWidget {
  const DeviceRequestsScreen({super.key});

  Future<void> _decide(BuildContext context, WidgetRef ref, DeviceRequest r, String decision) async {
    final comment = await promptText(
      context,
      title: decision == 'approve' ? 'Approve new phone' : 'Reject request',
      hint: 'Comment (optional)',
      confirmLabel: decision == 'approve' ? 'Approve' : 'Reject',
    );
    if (comment == null || !context.mounted) return;
    await runWithFeedback(
      context,
      () => ref.read(apiProvider).call('reviewDeviceChange', {
        'requestId': r.id,
        'decision': decision,
        'comment': comment.isEmpty ? null : comment,
      }),
      success: decision == 'approve' ? 'New phone approved.' : 'Request rejected.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = fs
        .collection('deviceRequests')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(DeviceRequest.fromDoc).toList());
    return Scaffold(
      appBar: AppBar(title: const Text('Device change requests')),
      body: QueryList<DeviceRequest>(
        stream: stream,
        emptyMessage: 'No pending device requests.',
        itemBuilder: (context, r) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(r.employeeName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('New phone: ${r.deviceModel}\nCurrent phone: ${r.previousDeviceModel ?? 'none'}'
                    '\nRequested ${fmtDateTime(r.createdAt)}${r.reason != null ? '\nReason: ${r.reason}' : ''}'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => _decide(context, ref, r, 'reject'), child: const Text('Reject')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(onPressed: () => _decide(context, ref, r, 'approve'), child: const Text('Approve')),
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
