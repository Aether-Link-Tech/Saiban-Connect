import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/datasources/firebase/functions_api.dart';
import '../data/datasources/local/local_db.dart';
import '../domain/entities/app_policy.dart';
import '../domain/entities/models.dart';
import '../shared/services/biometric_service.dart';
import '../shared/services/device_identity.dart';
import '../shared/services/location_service.dart';
import '../shared/services/push_service.dart';
import '../shared/services/sync_service.dart';
import '../shared/services/tracking_service.dart';
import 'constants/app_constants.dart';
import 'utils/formatters.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

FirebaseFirestore get fs => FirebaseFirestore.instance;

// ---------- Services ----------

final apiProvider = Provider<FunctionsApi>(
  (ref) => FunctionsApi(FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion)),
);
final localDbProvider = Provider<LocalDb>((ref) => LocalDb.instance);
final biometricProvider = Provider<BiometricService>((ref) => BiometricService());
final locationServiceProvider = Provider<LocationService>((ref) => LocationService());
final syncServiceProvider = ChangeNotifierProvider<SyncService>(
  (ref) => SyncService(ref.read(localDbProvider), ref.read(apiProvider)),
);
final trackingServiceProvider = ChangeNotifierProvider<TrackingService>(
  (ref) => TrackingService(ref.read(localDbProvider), ref.read(syncServiceProvider)),
);
final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(ref.read(apiProvider), scaffoldMessengerKey),
);
final deviceIdentityProvider = FutureProvider<DeviceIdentity>((ref) => DeviceIdentity.load());

// ---------- Session ----------

final authStateProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

final currentUidProvider = Provider<String?>((ref) => ref.watch(authStateProvider).valueOrNull?.uid);

final profileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return fs.doc('users/$uid').snapshots().map((s) => s.exists ? UserProfile.fromDoc(s) : null);
});

UserProfile? _lastProfile;

/// The signed-in, active user's profile. Only use below the AuthGate. Keeps the
/// last value during sign-out so screens being torn down don't fail.
final meProvider = Provider<UserProfile>((ref) {
  final p = ref.watch(profileProvider).valueOrNull;
  if (p != null) _lastProfile = p;
  final result = p ?? _lastProfile;
  if (result == null) throw StateError('meProvider used without an active profile');
  return result;
});

/// "status|role" of the current profile; changes only when access changes.
final _accessKeyProvider = Provider<String?>((ref) {
  final p = ref.watch(profileProvider).valueOrNull;
  return p == null ? null : '${p.accountStatus}|${p.role.name}';
});

/// Refreshes the ID token when the profile's role/status differs from the token
/// claims, so security rules see the current role.
final claimsSyncProvider = FutureProvider<void>((ref) async {
  final key = ref.watch(_accessKeyProvider);
  final user = FirebaseAuth.instance.currentUser;
  if (key == null || user == null) return;
  final parts = key.split('|');
  final claims = (await user.getIdTokenResult()).claims ?? const {};
  final stale = claims['status'] != parts[0] || (parts[0] == 'active' && claims['role'] != parts[1]);
  if (stale) await user.getIdTokenResult(true);
});

final consentProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return false;
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('location_consent_v1_$uid') ?? false;
});

Future<void> acceptConsent(WidgetRef ref) async {
  final uid = ref.read(currentUidProvider);
  if (uid == null) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('location_consent_v1_$uid', true);
  ref.invalidate(consentProvider);
}

Future<void> signOut(WidgetRef ref) async {
  await ref.read(trackingServiceProvider).stop();
  ref.read(syncServiceProvider).stop();
  await ref.read(pushServiceProvider).stop();
  await FirebaseAuth.instance.signOut();
}

// ---------- Reference data ----------

final _activeKeyProvider = Provider<bool>((ref) => ref.watch(_accessKeyProvider)?.startsWith('active') ?? false);

final policyProvider = StreamProvider<AppPolicy>((ref) {
  if (!ref.watch(_activeKeyProvider)) return Stream.value(const AppPolicy());
  return fs.doc('config/policy').snapshots().map((s) => AppPolicy.fromMap(s.data()));
});

/// Current policy, falling back to defaults when unavailable.
final currentPolicyProvider = Provider<AppPolicy>((ref) => ref.watch(policyProvider).valueOrNull ?? const AppPolicy());

final sitesProvider = StreamProvider<List<Site>>((ref) {
  if (!ref.watch(_activeKeyProvider)) return Stream.value(const []);
  return fs.collection('sites').orderBy('name').snapshots().map((s) => s.docs.map(Site.fromDoc).toList());
});

final departmentsProvider = StreamProvider<List<Department>>((ref) {
  if (!ref.watch(_activeKeyProvider)) return Stream.value(const []);
  return fs.collection('departments').orderBy('name').snapshots().map((s) => s.docs.map(Department.fromDoc).toList());
});

/// All users (HR/Admin only — rules deny others).
final allUsersProvider = StreamProvider<List<UserProfile>>((ref) {
  if (!ref.watch(_activeKeyProvider)) return Stream.value(const []);
  return fs.collection('users').orderBy('displayName').snapshots().map((s) => s.docs.map(UserProfile.fromDoc).toList());
});

final _teamByManagerProvider = StreamProvider<List<UserProfile>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || !ref.watch(_activeKeyProvider)) return Stream.value(const []);
  return fs.collection('users').where('managerUid', isEqualTo: uid).snapshots().map((s) => s.docs.map(UserProfile.fromDoc).toList());
});

final _teamBySupervisorProvider = StreamProvider<List<UserProfile>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || !ref.watch(_activeKeyProvider)) return Stream.value(const []);
  return fs.collection('users').where('supervisorUid', isEqualTo: uid).snapshots().map((s) => s.docs.map(UserProfile.fromDoc).toList());
});

/// Employees the current user can oversee: everyone active for HR/Admin, otherwise
/// people who have this user as manager or supervisor.
final teamMembersProvider = Provider<AsyncValue<List<UserProfile>>>((ref) {
  final me = ref.watch(meProvider);
  if (me.role.isHrOrAdmin) {
    return ref.watch(allUsersProvider).whenData(
          (all) => all.where((u) => u.isActive && u.uid != me.uid).toList(),
        );
  }
  final a = ref.watch(_teamByManagerProvider);
  final b = ref.watch(_teamBySupervisorProvider);
  if (a.hasError) return AsyncValue.error(a.error!, a.stackTrace ?? StackTrace.current);
  if (b.hasError) return AsyncValue.error(b.error!, b.stackTrace ?? StackTrace.current);
  if (!a.hasValue || !b.hasValue) return const AsyncValue.loading();
  final byId = <String, UserProfile>{for (final u in [...a.value!, ...b.value!]) u.uid: u};
  final list = byId.values.where((u) => u.isActive).toList()
    ..sort((x, y) => x.displayName.compareTo(y.displayName));
  return AsyncValue.data(list);
});

/// Applies the viewerUids filter required by security rules for non-HR/Admin viewers
/// of other employees' records.
Query<Map<String, dynamic>> scopeForViewer(Query<Map<String, dynamic>> q, UserProfile me, {String? ownerUid}) {
  if (me.role.isHrOrAdmin || ownerUid == me.uid) return q;
  return q.where('viewerUids', arrayContains: me.uid);
}

// ---------- Attendance state ----------

final todayServerDayProvider = StreamProvider.autoDispose<AttendanceDay?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return fs
      .doc('attendanceDays/${uid}_${todayKey()}')
      .snapshots()
      .map((s) => s.exists ? AttendanceDay.fromDoc(s) : null);
});

final localTodayProvider = FutureProvider.autoDispose<LocalDay?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return ref.read(localDbProvider).getLocalDay(uid, todayKey());
});

final unreadCountProvider = StreamProvider<int>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(0);
  return fs
      .collection('notifications')
      .where('recipientUid', isEqualTo: uid)
      .where('read', isEqualTo: false)
      .snapshots()
      .map((s) => s.size);
});
