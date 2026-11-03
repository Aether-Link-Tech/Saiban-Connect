import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('device_id', id);
    }
    var model = 'Unknown device';
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        model = '${info.manufacturer} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        model = info.utsname.machine;
      }
    } catch (_) {}
    return DeviceIdentity(id, model);
  }
}
