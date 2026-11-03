import 'package:flutter/foundation.dart';

/// Build-time configuration, set with --dart-define.
///
///   flutter run -d chrome --dart-define=USE_EMULATOR=true
///
/// USE_EMULATOR connects to the local Firebase Emulator Suite (project demo-saibaan)
/// instead of the cloud project. Never ship a release build with it enabled.
class Env {
  Env._();

  static const useEmulator = bool.fromEnvironment('USE_EMULATOR');
  static const _emulatorHostOverride = String.fromEnvironment('EMULATOR_HOST');

  /// Must match the --project used by `firebase emulators:start` and the seed script.
  static const demoProjectId = 'demo-saibaan';

  /// In emulator mode every account's approved device is this ID (set by the seed
  /// script), so the one-device rule doesn't block browser testing.
  static const demoDeviceId = 'demo-device-0001';

  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Android emulators reach the host machine at 10.0.2.2.
  static String get emulatorHost {
    if (_emulatorHostOverride.isNotEmpty) return _emulatorHostOverride;
    return isAndroid ? '10.0.2.2' : 'localhost';
  }
}
