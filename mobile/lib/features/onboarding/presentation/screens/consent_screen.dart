import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';

/// Prominent disclosure for location tracking and biometrics (proposal §12; Google Play policy).
class ConsentScreen extends ConsumerWidget {
  const ConsentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    Widget point(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(body),
                  ],
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Before you start')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('How SAIBAAN Connect uses your data', style: textTheme.titleLarge),
            const SizedBox(height: 20),
            point(Icons.location_on_outlined, 'Location during working hours',
                'When you check in, the app records your location and keeps sharing it with your supervisor, '
                    'manager, HR and administrators until you check out — including while the app is in the background. '
                    'A notification is shown while this is active. Tracking stops when you check out.'),
            point(Icons.fingerprint, 'Fingerprint / face unlock',
                "Check-in and check-out use your phone's own biometric prompt. "
                    'The app never receives or stores your fingerprint or face data.'),
            point(Icons.cloud_off_outlined, 'Offline records',
                'If you have no internet, attendance and location are stored on this phone and uploaded later. '
                    'Unusual time or location records may be reviewed by management.'),
            point(Icons.photo_camera_outlined, 'Photos',
                'Site photos you upload are stored with their time and location and are visible to management.'),
            const SizedBox(height: 8),
            Text(
              'Location history is kept for a limited period set by your organization. '
              'Contact HR for questions about how your data is used.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => acceptConsent(ref), child: const Text('I understand and agree')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => signOut(ref), child: const Text('Sign out')),
          ],
        ),
      ),
    );
  }
}
