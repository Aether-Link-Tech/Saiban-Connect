import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricOutcome { success, failed, unavailable }

class BiometricResult {
  const BiometricResult(this.outcome, [this.message]);
  final BiometricOutcome outcome;
  final String? message;
}

/// Uses the phone's own biometric prompt. No fingerprint or face data ever
/// reaches the app; the OS only reports whether an enrolled biometric matched.
class BiometricService {
  final _auth = LocalAuthentication();

  Future<BiometricResult> authenticate(String reason) async {
    if (kIsWeb) {
      return const BiometricResult(BiometricOutcome.unavailable, 'Biometrics are not available in a web browser.');
    }
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final enrolled = await _auth.getAvailableBiometrics();
      if (!supported || !canCheck || enrolled.isEmpty) {
        return const BiometricResult(
          BiometricOutcome.unavailable,
          'No fingerprint or face unlock is set up on this phone. Enrol one in the phone settings.',
        );
      }
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      return ok
          ? const BiometricResult(BiometricOutcome.success)
          : const BiometricResult(BiometricOutcome.failed, 'Biometric verification was cancelled.');
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'NotAvailable':
        case 'NotEnrolled':
        case 'PasscodeNotSet':
          return BiometricResult(BiometricOutcome.unavailable, e.message);
        case 'LockedOut':
        case 'PermanentlyLockedOut':
          return const BiometricResult(
              BiometricOutcome.failed, 'Biometrics are locked after too many attempts. Unlock your phone and try again.');
        default:
          return BiometricResult(BiometricOutcome.failed, e.message ?? 'Biometric verification failed.');
      }
    } on MissingPluginException {
      return const BiometricResult(BiometricOutcome.unavailable, 'Biometrics are not supported on this platform.');
    }
  }
}
