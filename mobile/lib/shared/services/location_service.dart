import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../core/errors/app_exception.dart';

class LocationService {
  /// Ensures GPS is on and the app has location permission (while in use).
  Future<void> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AppException('Turn on location (GPS) on your phone to continue.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AppException('Location permission is blocked. Allow it for SAIBAAN Connect in phone settings.');
    }
    if (permission == LocationPermission.denied) {
      throw const AppException('Location permission is required for attendance.');
    }
  }

  /// Best-effort current position; falls back to the last known fix. Returns null if none.
  Future<Position?> currentPosition({Duration timeout = const Duration(seconds: 20)}) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
      );
    } on TimeoutException {
      return Geolocator.getLastKnownPosition();
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }
}
