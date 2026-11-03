import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../data/datasources/local/local_db.dart';
import '../../domain/entities/app_policy.dart';
import 'sync_service.dart';

/// Records the employee's location between check-in and check-out (proposal §4.3).
/// On Android a foreground-service notification keeps tracking running while the
/// app is in the background. Tracking stops if the phone is off, permissions are
/// revoked or the OS kills the app; it resumes when the app is opened again.
class TrackingService extends ChangeNotifier {
  TrackingService(this._db, this._sync);

  final LocalDb _db;
  final SyncService _sync;

  StreamSubscription<Position>? _sub;
  String? _uid;
  DateTime? _lastSaved;
  int _intervalSeconds = 300;
  String? lastError;

  bool get isRunning => _sub != null;

  Future<void> start(String uid, AppPolicy policy) async {
    if (_sub != null && _uid == uid) return;
    await stop();
    _uid = uid;
    _intervalSeconds = policy.trackingIntervalSeconds;
    _lastSaved = null;

    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: policy.distanceFilterM,
            intervalDuration: Duration(seconds: policy.trackingIntervalSeconds),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'SAIBAAN Connect',
              notificationText: 'Your location is shared with your organization while you are checked in.',
              enableWakeLock: true,
            ),
          )
        : LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: policy.distanceFilterM);

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPosition,
      onError: (Object e) {
        lastError = 'Location tracking stopped: $e';
        notifyListeners();
      },
    );
    lastError = null;
    notifyListeners();
  }

  Future<void> _onPosition(Position p) async {
    final uid = _uid;
    if (uid == null) return;
    final now = DateTime.now();
    // Some devices deliver updates more often than requested; throttle to the policy interval.
    if (_lastSaved != null && now.difference(_lastSaved!).inSeconds < (_intervalSeconds * 0.8)) return;
    _lastSaved = now;
    await _db.enqueuePoint(
      uid,
      QueuedPoint(
        id: const Uuid().v4(),
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyM: p.accuracy,
        capturedAt: p.timestamp,
      ),
    );
    unawaited(_sync.flush());
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _uid = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
