import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';
import 'register_screen.dart';

/// Shown while the account is pending, rejected or disabled.
class AccountStatusScreen extends ConsumerWidget {
  const AccountStatusScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, title, message) = switch (profile.accountStatus) {
      'rejected' => (
          Icons.cancel_outlined,
          'Registration not approved',
          profile.reviewComment ?? 'Your registration was not approved. You can correct your details and resubmit.',
        ),
      'disabled' => (Icons.block, 'Account disabled', 'Your account has been disabled. Please contact HR.'),
      _ => (
          Icons.hourglass_top,
          'Waiting for approval',
          'Thanks, ${profile.displayName}. HR or an administrator will review your registration. '
              'You will receive a notification when your account is approved.',
        ),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Account status')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          if (profile.accountStatus == 'rejected') ...[
            FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const RegisterScreen(completingExistingAccount: true),
              )),
              child: const Text('Update details and resubmit'),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton(
            onPressed: () => runWithFeedback(
              context,
              () async => FirebaseAuth.instance.currentUser?.getIdToken(true),
              success: 'Status refreshed.',
            ),
            child: const Text('Refresh'),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: () => signOut(ref), child: const Text('Sign out')),
        ],
      ),
    );
  }
}
