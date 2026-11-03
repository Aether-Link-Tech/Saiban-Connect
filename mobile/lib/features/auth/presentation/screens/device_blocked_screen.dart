import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/services/device_identity.dart';
import '../../../../shared/widgets/common.dart';

/// One registered device per employee: a different phone needs HR/Admin approval.
class DeviceBlockedScreen extends ConsumerWidget {
  const DeviceBlockedScreen({super.key, required this.profile, required this.device});
  final UserProfile profile;
  final DeviceIdentity device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = fs
        .collection('deviceRequests')
        .where('uid', isEqualTo: profile.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.map(DeviceRequest.fromDoc).toList());

    return Scaffold(
      appBar: AppBar(title: const Text('New phone detected')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.phonelink_lock, size: 72),
          const SizedBox(height: 16),
          Text(
            'This phone is not registered for your account.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Registered phone: ${profile.activeDeviceModel ?? 'none'}\nThis phone: ${device.model}\n\n'
            'Attendance can only be marked from your registered phone. '
            'Request approval to move your account to this phone.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          StreamBuilder<List<DeviceRequest>>(
            stream: pending,
            builder: (context, snap) {
              final req = snap.data?.where((r) => r.deviceModel == device.model).firstOrNull ??
                  snap.data?.firstOrNull;
              if (req != null) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.hourglass_top),
                    title: const Text('Request pending'),
                    subtitle: Text('Requested ${fmtDateTime(req.createdAt)} for ${req.deviceModel}.'),
                  ),
                );
              }
              return FilledButton(
                onPressed: () async {
                  final reason = await promptText(
                    context,
                    title: 'Request device change',
                    hint: 'Reason (e.g. new phone, old phone lost)',
                    confirmLabel: 'Send request',
                  );
                  if (reason == null || !context.mounted) return;
                  await runWithFeedback(
                    context,
                    () => ref.read(apiProvider).call('requestDeviceChange', {
                      'deviceId': device.id,
                      'deviceModel': device.model,
                      'reason': reason.isEmpty ? null : reason,
                    }),
                    success: 'Request sent to HR.',
                  );
                },
                child: const Text('Request approval for this phone'),
              );
            },
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: () => signOut(ref), child: const Text('Sign out')),
        ],
      ),
    );
  }
}
