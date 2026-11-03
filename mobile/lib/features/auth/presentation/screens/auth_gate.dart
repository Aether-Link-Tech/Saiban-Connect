import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/providers.dart';
import '../../../../shared/widgets/common.dart';
import '../../../dashboard/presentation/screens/home_shell.dart';
import '../../../onboarding/presentation/screens/consent_screen.dart';
import 'account_status_screen.dart';
import 'device_blocked_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Routes the user by session state:
/// signed out → login; no profile → finish registration; not active → status;
/// unapproved phone → device change; no consent → disclosure; otherwise home.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading && !auth.hasValue) return const SplashView();
    if (auth.valueOrNull == null) return const LoginScreen();

    final profileAsync = ref.watch(profileProvider);
    if (profileAsync.hasError) return _ErrorScaffold(error: profileAsync.error!);
    if (!profileAsync.hasValue) return const SplashView();
    final profile = profileAsync.value;
    if (profile == null) return const RegisterScreen(completingExistingAccount: true);
    if (!profile.isActive) return AccountStatusScreen(profile: profile);

    final claims = ref.watch(claimsSyncProvider);
    if (claims.isLoading && !claims.hasValue) return const SplashView();

    final device = ref.watch(deviceIdentityProvider);
    if (!device.hasValue) return const SplashView();
    if (profile.activeDeviceId != device.value!.id) {
      return DeviceBlockedScreen(profile: profile, device: device.value!);
    }

    final consent = ref.watch(consentProvider);
    if (!consent.hasValue) return const SplashView();
    if (consent.value != true) return const ConsentScreen();

    return HomeShell(key: ValueKey(profile.uid));
  }
}

class _ErrorScaffold extends ConsumerWidget {
  const _ErrorScaffold({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: MessageView(
          icon: Icons.cloud_off,
          message: 'Could not load your account.\n\n${friendlyError(error)}',
          action: OutlinedButton(onPressed: () => signOut(ref), child: const Text('Sign out')),
        ),
      );
}
