import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';

class LeaveDetailScreen extends ConsumerWidget {
  const LeaveDetailScreen({super.key, required this.requestId});
  final String requestId;

  /// Mirrors reviewer-slot logic in backend leave.ts / leaveWorkflow.ts (backend is authoritative).
  String? _reviewerRole(UserProfile me, LeaveRequest r) {
    if (r.uid == me.uid) return null;
    if (me.role == UserRole.admin) return 'admin';
    if (me.role == UserRole.hr) return 'hr';
    if (me.role == UserRole.manager && r.managerUid == me.uid) return 'manager';
    return null;
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, String decision) async {
    final comment = await promptText(
      context,
      title: decision == 'approve' ? 'Approve leave' : 'Reject leave',
      hint: decision == 'approve' ? 'Comment (optional)' : 'Reason for rejection',
      required: decision == 'reject',
      confirmLabel: decision == 'approve' ? 'Approve' : 'Reject',
    );
    if (comment == null || !context.mounted) return;
    await runWithFeedback(
      context,
      () => ref.read(apiProvider).call('reviewLeaveRequest', {
        'requestId': requestId,
        'decision': decision,
        'comment': comment.isEmpty ? null : comment,
      }),
      success: 'Decision recorded.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final policy = ref.watch(currentPolicyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Leave request')),
      body: StreamBuilder(
        stream: fs.doc('leaveRequests/$requestId').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(snap.error!);
          if (!snap.hasData) return const LoadingView();
          if (!snap.data!.exists) return const EmptyView('This request no longer exists.');
          final r = LeaveRequest.fromDoc(snap.data!);
          final slot = _reviewerRole(me, r);
          final alreadyDecided = r.decisions.any((d) => d.uid == me.uid && d.role == slot);
          final canReview = slot != null &&
              (r.status == 'pending' ||
                  (r.status == 'rejected' && slot == 'admin' && policy.adminCanOverrideRejection && policy.adminCanApproveAlone));

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(children: [
                Expanded(
                  child: Text('${r.typeLabel} leave', style: Theme.of(context).textTheme.titleLarge),
                ),
                StatusChip.status(r.status),
              ]),
              const SizedBox(height: 16),
              InfoRow('Employee', r.employeeName),
              InfoRow('Dates', r.dateRange),
              if (r.halfDayPeriod != null)
                InfoRow('Half', r.halfDayPeriod == 'first_half' ? 'First half' : 'Second half'),
              if (r.days != null) InfoRow('Days', r.days! % 1 == 0 ? r.days!.toInt().toString() : r.days.toString()),
              InfoRow('Applied', fmtDateTime(r.createdAt)),
              InfoRow('Reason', r.reason),
              if (r.attachmentPaths.isNotEmpty) ...[
                const SectionTitle('Attachments'),
                for (final (i, path) in r.attachmentPaths.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(path.endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image_outlined),
                    title: Text('Attachment ${i + 1}'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => runWithFeedback(context, () => openStorageFile(path)),
                  ),
              ],
              const SectionTitle('Review'),
              Text(
                'Approval: ${policy.requiredApprovals} of Manager / HR / Administrator'
                '${policy.adminCanApproveAlone ? ', or Administrator alone' : ''}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (r.decisions.isEmpty) const Text('No decisions yet.'),
              for (final d in r.decisions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    d.decision == 'approve' ? Icons.check_circle : Icons.cancel,
                    color: d.decision == 'approve' ? AppColors.green : AppColors.red,
                  ),
                  title: Text('${d.name} (${d.role.toUpperCase()}) ${d.decision == 'approve' ? 'approved' : 'rejected'}'),
                  subtitle: Text([fmtDateTime(d.at), if (d.comment != null) d.comment!].join('\n')),
                ),
              const SizedBox(height: 24),
              if (canReview) ...[
                if (alreadyDecided)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('You have already decided. A new decision replaces your earlier one.'),
                  ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _decide(context, ref, 'reject'),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _decide(context, ref, 'approve'),
                      child: const Text('Approve'),
                    ),
                  ),
                ]),
              ],
              if (r.uid == me.uid && r.status == 'pending')
                OutlinedButton(
                  onPressed: () async {
                    final ok = await confirm(context,
                        title: 'Cancel request?', message: 'This withdraws your leave request.', confirmLabel: 'Withdraw');
                    if (!ok || !context.mounted) return;
                    await runWithFeedback(
                      context,
                      () => ref.read(apiProvider).call('cancelLeaveRequest', {'requestId': requestId}),
                      success: 'Request withdrawn.',
                    );
                  },
                  child: const Text('Withdraw request'),
                ),
            ],
          );
        },
      ),
    );
  }
}
