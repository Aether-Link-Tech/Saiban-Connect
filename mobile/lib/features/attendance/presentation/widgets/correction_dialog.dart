import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';

/// Converts a wall-clock time on a date (organization time) to epoch ms.
int _orgMillis(DateTime date, TimeOfDay t) =>
    DateTime.utc(date.year, date.month, date.day, t.hour, t.minute)
        .subtract(AppConstants.orgUtcOffset)
        .millisecondsSinceEpoch;

TimeOfDay? _orgTimeOf(DateTime? t) {
  if (t == null) return null;
  final o = t.toUtc().add(AppConstants.orgUtcOffset);
  return TimeOfDay(hour: o.hour, minute: o.minute);
}

/// HR/Admin correction of missed or wrong check-in/check-out (times in Pakistan time).
Future<void> showCorrectionDialog(
  BuildContext context,
  WidgetRef ref, {
  required UserProfile employee,
  AttendanceDay? day,
}) async {
  DateTime date = day != null ? DateTime.parse(day.dateKey) : DateTime.parse(todayKey());
  TimeOfDay? inTime = _orgTimeOf(day?.checkInAt);
  TimeOfDay? outTime = _orgTimeOf(day?.checkOutAt);
  final reason = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        String fmt(TimeOfDay? t) => t == null ? 'Not set' : t.format(ctx);
        return AlertDialog(
          title: Text('Correct attendance — ${employee.displayName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(fmtDateKey(dateKeyFromDate(date))),
                  enabled: day == null,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => date = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.login),
                  title: Text('Check-in: ${fmt(inTime)}'),
                  onTap: () async {
                    final t = await showTimePicker(context: ctx, initialTime: inTime ?? const TimeOfDay(hour: 9, minute: 0));
                    if (t != null) setState(() => inTime = t);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout),
                  title: Text('Check-out: ${fmt(outTime)}'),
                  onTap: () async {
                    final t = await showTimePicker(context: ctx, initialTime: outTime ?? const TimeOfDay(hour: 17, minute: 0));
                    if (t != null) setState(() => outTime = t);
                  },
                ),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Reason (required)'),
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: reason.text.trim().length < 3 || (inTime == null && outTime == null)
                  ? null
                  : () async {
                      final ok = await runWithFeedback(
                        ctx,
                        () => ref.read(apiProvider).call('correctAttendance', {
                          'uid': employee.uid,
                          'dateKey': dateKeyFromDate(date),
                          'checkInAt': inTime == null ? null : _orgMillis(date, inTime!),
                          'checkOutAt': outTime == null ? null : _orgMillis(date, outTime!),
                          'reason': reason.text.trim(),
                        }),
                        success: 'Attendance corrected.',
                      );
                      if (ok && ctx.mounted) Navigator.pop(ctx);
                    },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
