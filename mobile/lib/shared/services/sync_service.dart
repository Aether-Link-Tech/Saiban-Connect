import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/formatters.dart';
import '../../data/datasources/firebase/functions_api.dart';
import '../../data/datasources/local/local_db.dart';
import 'device_identity.dart';

/// Uploads queued attendance events and location samples whenever the phone is
/// online: on start, on connectivity change, periodically and after new records.
class SyncService extends ChangeNotifier {
  SyncService(this._db, this._api);

  final LocalDb _db;
  final FunctionsApi _api;

  String? _uid;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Future<bool>? _inFlight;

  int pendingEvents = 0;
  int pendingPoints = 0;
  DateTime? lastSyncAt;
  String? lastError;

  /// Messages about events the server flagged or rejected, newest first.
  final List<String> notices = [];

  bool get hasPending => pendingEvents > 0 || pendingPoints > 0;

  void start(String uid) {
    if (_uid == uid) return;
    stop();
    _uid = uid;
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) flush();
    });
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => flush());
    refreshCounts();
    flush();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _connSub?.cancel();
    _connSub = null;
    _uid = null;
    notices.clear();
  }

  Future<void> refreshCounts() async {
    final uid = _uid;
    if (uid == null) return;
    final c = await _db.pendingCounts(uid);
    pendingEvents = c.events;
    pendingPoints = c.points;
    notifyListeners();
  }

  /// Returns true when everything queued was delivered.
  Future<bool> flush() {
    final uid = _uid;
    if (uid == null) return Future.value(false);
    return _inFlight ??= _flush(uid).whenComplete(() => _inFlight = null);
  }

  Future<bool> _flush(String uid) async {
    final device = await DeviceIdentity.load();
    try {
      // Attendance first, oldest first, in batches of 50.
      while (true) {
        final events = await _db.pendingAttendance(uid);
        if (events.isEmpty) break;
        final res = await _api.call('syncAttendanceEvents', {
          'deviceId': device.id,
          'events': events.map((e) => e.toPayload()).toList(),
        });
        final results = (res['results'] as List? ?? const []).whereType<Map>().toList();
        final done = <String>[];
        for (final r in results) {
          final id = r['eventId'] as String?;
          final status = r['status'] as String?;
          if (id == null || status == null) continue;
          done.add(id);
          final ev = events.where((e) => e.id == id).firstOrNull;
          final what = ev == null ? 'Attendance' : (ev.type == 'check_in' ? 'Check-in' : 'Check-out');
          final when = ev == null ? '' : ' (${fmtDateTime(ev.deviceTime)})';
          if (status == 'flagged') {
            final flags = (r['flags'] as List? ?? const []).whereType<String>().map(flagLabel).join(', ');
            _notice('$what$when recorded but flagged for review: $flags');
          } else if (status == 'rejected') {
            _notice('$what$when was not accepted: ${r['reason'] ?? 'rejected by server'}');
          }
        }
        await _db.deleteAttendance(done);
        if (done.isEmpty) break; // Avoid looping if the server returned nothing usable.
      }

      while (true) {
        final points = await _db.pendingPoints(uid, limit: 200);
        if (points.isEmpty) break;
        await _api.call('uploadLocationPoints', {
          'deviceId': device.id,
          'points': points.map((p) => p.toPayload()).toList(),
        });
        await _db.deletePoints(points.map((p) => p.id).toList());
        if (points.length < 200) break;
      }

      lastSyncAt = DateTime.now();
      lastError = null;
      return true;
    } on FirebaseFunctionsException catch (e) {
      lastError = friendlyError(e);
      final pending = await _db.pendingAttendance(uid);
      await _db.markAttendanceAttempt(pending.map((e) => e.id).toList(), lastError!);
      return false;
    } catch (e) {
      lastError = 'Offline. Records are saved on this phone and will sync automatically.';
      return false;
    } finally {
      await refreshCounts();
    }
  }

  void _notice(String message) {
    notices.insert(0, message);
    if (notices.length > 10) notices.removeLast();
  }

  void clearNotices() {
    notices.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
