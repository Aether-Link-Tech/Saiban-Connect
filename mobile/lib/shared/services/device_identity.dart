import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/env.dart';

/// Stable per-installation identifier used for the one-device-per-employee rule.
/// Reinstalling the app or clearing its data creates a new ID, which then needs
/// HR/Admin approval as a device change.
class DeviceIdentity {
  const DeviceIdentity(this.id, this.model);
  final String id;
  final String model;

  static Future<DeviceIdentity>? _cached;
  static Future<DeviceIdentity> load() => _cached ??= _load();

  static Future<DeviceIdentity> _load() async {
    final model = await _model();
    if (Env.useEmulator) return DeviceIdentity(Env.demoDeviceId, '$model (local demo)');

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('device_id', id);
    }
    return DeviceIdentity(id, model);
  }

  static Future<String> _model() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await plugin.webBrowserInfo;
        return 'Web browser (${info.browserName.name})';
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await plugin.androidInfo;
          return '${info.manufacturer} ${info.model}';
        case TargetPlatform.iOS:
          final info = await plugin.iosInfo;
          return info.utsname.machine;
        default:
          return 'Unknown device';
      }
    } catch (_) {
      return 'Unknown device';
    }
  }
}
