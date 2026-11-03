import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';

/// Shows queued offline records, sync errors and server review notices.
class SyncStatusCard extends ConsumerWidget {
  const SyncStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncServiceProvider);
    if (!sync.hasPending && sync.lastError == null && sync.notices.isEmpty) {
      return Text(
        sync.lastSyncAt == null ? '' : 'All records synced · ${relativeAge(sync.lastSyncAt)}',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Card(
      color: AppColors.amber.withAlpha(25),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sync.hasPending)
              Row(children: [
                const Icon(Icons.cloud_upload_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Waiting to sync: ${sync.pendingEvents} attendance record(s), '
                      '${sync.pendingPoints} location point(s).'),
                ),
                TextButton(onPressed: sync.flush, child: const Text('Sync now')),
              ]),
            if (sync.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(sync.lastError!, style: const TextStyle(color: AppColors.red)),
              ),
            for (final n in sync.notices)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $n'),
              ),
            if (sync.notices.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: sync.clearNotices, child: const Text('Dismiss')),
              ),
          ],
        ),
      ),
    );
  }
}
