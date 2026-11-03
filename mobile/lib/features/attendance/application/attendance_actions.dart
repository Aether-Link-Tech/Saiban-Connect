import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/datasources/local/local_db.dart';
import '../../../shared/services/biometric_service.dart';

enum AttendanceType { checkIn, checkOut }

final attendanceActionsProvider = Provider<AttendanceActions>((ref) => AttendanceActions(ref));

/// Check-in / check-out flow (proposal §4.2–4.4):
/// biometric prompt → GPS fix → saved to the local queue → tracking start/stop → sync.
class AttendanceActions {
  AttendanceActions(this._ref);
  final Ref _ref;

  Future<String> record(AttendanceType type) async {
    final uid = _ref.read(currentUidProvider);
    if (uid == null) throw const AppException('Please sign in again.');
    final policy = _ref.read(currentPolicyProvider);
    final db = _ref.read(localDbProvider);
    final now = DateTime.now();
    final key = orgDateKey(now);

    final local = await db.getLocalDay(uid, key);
    final server = _ref.read(todayServerDayProvider).valueOrNull;
    final checkedIn = local?.checkInAt != null || server?.checkInAt != null;
    final checkedOut = local?.checkOutAt != null || server?.checkOutAt != null;
    final isIn = type == AttendanceType.checkIn;
    if (isIn && checkedIn) throw const AppException('You have already checked in today.');
    if (!isIn && !checkedIn) throw const AppException('Check in before checking out.');
    if (!isIn && checkedOut) throw const AppException('You have already checked out today.');

    final location = _ref.read(locationServiceProvider);
    await location.ensureReady();

    final bio = await _ref.read(biometricProvider).authenticate(isIn ? 'Confirm your check-in' : 'Confirm your check-out');
    final bool biometricPassed;
    switch (bio.outcome) {
      case BiometricOutcome.success:
        biometricPassed = true;
      case BiometricOutcome.unavailable:
        if (!policy.allowWithoutBiometric) {
          throw AppException(bio.message ?? 'Biometric authentication is not available on this phone.');
        }
        biometricPassed = false;
      case BiometricOutcome.failed:
        throw AppException(bio.message ?? 'Biometric verification failed.');
    }

    final pos = await location.currentPosition();
    final eventTime = DateTime.now();
    await db.enqueueAttendance(QueuedAttendance(
      id: const Uuid().v4(),
      uid: uid,
      type: isIn ? 'check_in' : 'check_out',
      deviceTime: eventTime,
      biometricPassed: biometricPassed,
      latitude: pos?.latitude,
      longitude: pos?.longitude,
      accuracyM: pos?.accuracy,
      isMocked: pos?.isMocked ?? false,
    ));
    await db.recordLocalDay(uid, key,
        checkInAt: isIn ? eventTime : null, checkOutAt: isIn ? null : eventTime);

    final tracking = _ref.read(trackingServiceProvider);
    if (isIn) {
      await tracking.start(uid, policy);
    } else {
      await tracking.stop();
    }
    _ref.invalidate(localTodayProvider);

    final sync = _ref.read(syncServiceProvider);
    await sync.refreshCounts();
    final synced = await sync.flush().timeout(const Duration(seconds: 15), onTimeout: () => false);
    final label = isIn ? 'Checked in' : 'Checked out';
    final gpsNote = pos == null ? ' No GPS fix was available; the record will be reviewed.' : '';
    return synced
        ? '$label at ${fmtTime(eventTime)}.$gpsNote'
        : '$label at ${fmtTime(eventTime)}. Saved on this phone; it will sync when you are online.$gpsNote';
  }

  /// Restarts tracking after an app restart if the employee is still checked in today.
  Future<void> resumeTrackingIfNeeded() async {
    final uid = _ref.read(currentUidProvider);
    if (uid == null) return;
    final local = await _ref.read(localDbProvider).getLocalDay(uid, todayKey());
    final server = _ref.read(todayServerDayProvider).valueOrNull;
    final inAt = local?.checkInAt ?? server?.checkInAt;
    final outAt = local?.checkOutAt ?? server?.checkOutAt;
    if (inAt != null && outAt == null) {
      try {
        await _ref.read(locationServiceProvider).ensureReady();
        await _ref.read(trackingServiceProvider).start(uid, _ref.read(currentPolicyProvider));
      } catch (_) {
        // Shown on the home card via tracking state.
      }
    }
  }
}
