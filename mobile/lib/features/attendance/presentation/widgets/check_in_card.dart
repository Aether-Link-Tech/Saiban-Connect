import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/common.dart';
import '../../application/attendance_actions.dart';

class CheckInCard extends ConsumerStatefulWidget {
  const CheckInCard({super.key});
  @override
  ConsumerState<CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends ConsumerState<CheckInCard> {
  bool _busy = false;

  Future<void> _record(AttendanceType type) async {
    setState(() => _busy = true);
    try {
      final msg = await ref.read(attendanceActionsProvider).record(type);
      if (mounted) showSnack(context, msg);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(todayServerDayProvider).valueOrNull;
    final local = ref.watch(localTodayProvider).valueOrNull;
    final tracking = ref.watch(trackingServiceProvider);
    final inAt = server?.checkInAt ?? local?.checkInAt;
    final outAt = server?.checkOutAt ?? local?.checkOutAt;

    final (String status, Color color) = inAt == null
        ? ('Not checked in', AppColors.amber)
        : outAt == null
            ? ('Checked in', AppColors.green)
            : ('Day complete', AppColors.navy);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Today's attendance",
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(status, color: color),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _TimeBox(label: 'Check-in', time: fmtTime(inAt))),
                const SizedBox(width: 12),
                Expanded(child: _TimeBox(label: 'Check-out', time: fmtTime(outAt))),
              ],
            ),
            if (server?.siteName != null) ...[
              const SizedBox(height: 8),
              Text('Site: ${server!.siteName}'),
            ],
            if (server != null && server.flags.isNotEmpty) ...[
              const SizedBox(height: 8),
              FlagChips(server.flags),
            ],
            const SizedBox(height: 16),
            if (inAt == null)
              FilledButton.icon(
                onPressed: _busy ? null : () => _record(AttendanceType.checkIn),
                icon: const Icon(Icons.fingerprint),
                label: Text(_busy ? 'Recording…' : 'Check in'),
              )
            else if (outAt == null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                onPressed: _busy ? null : () => _record(AttendanceType.checkOut),
                icon: const Icon(Icons.fingerprint),
                label: Text(_busy ? 'Recording…' : 'Check out'),
              )
            else
              const FilledButton(onPressed: null, child: Text('Attendance recorded for today')),
            if (inAt != null && outAt == null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    tracking.isRunning ? Icons.my_location : Icons.location_disabled,
                    size: 16,
                    color: tracking.isRunning ? AppColors.green : AppColors.red,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tracking.lastError ??
                          (tracking.isRunning
                              ? 'Location is being shared until you check out.'
                              : 'Location sharing is off. Pull down to retry or check location permission.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.label, required this.time});
  final String label, time;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(time, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      );
}
