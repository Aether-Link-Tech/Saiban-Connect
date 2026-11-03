// Renders the real app screens for each role against an in-memory Firestore.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saibaan_connect/app.dart';
import 'package:saibaan_connect/core/providers.dart';
import 'package:saibaan_connect/core/utils/formatters.dart';
import 'package:saibaan_connect/data/datasources/firebase/functions_api.dart';
import 'package:saibaan_connect/data/datasources/local/local_db.dart';
import 'package:saibaan_connect/shared/services/device_identity.dart';
import 'package:saibaan_connect/shared/services/push_service.dart';
import 'package:saibaan_connect/shared/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi implements FunctionsApi {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic>? data]) async {
    calls.add(name);
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietSync extends SyncService {
  _QuietSync(super.db, super.api);
  @override
  void start(String uid) {}
  @override
  Future<bool> flush() async => true;
}

class _NoPush extends PushService {
  _NoPush(FunctionsApi api) : super(api, GlobalKey<ScaffoldMessengerState>());
  @override
  Future<void> start() async {}
}

const device = DeviceIdentity('device-1', 'Test Phone');

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  final now = Timestamp.now();
  Map<String, dynamic> user(String name, String role, {String status = 'active', String? manager, String? supervisor}) => {
        'displayName': name,
        'role': role,
        'accountStatus': status,
        'activeDeviceId': status == 'active' ? device.id : null,
        'activeDeviceModel': 'Test Phone',
        'pendingDeviceModel': 'Test Phone',
        'phone': '923000000000',
        'managerUid': manager,
        'supervisorUid': supervisor,
        'assignedSiteIds': ['site-1'],
        'requestedAt': now,
      };
  await db.doc('users/admin').set(user('Ayesha Admin', 'admin'));
  await db.doc('users/hr').set(user('Hina HR', 'hr'));
  await db.doc('users/manager').set(user('Usman Manager', 'manager'));
  await db.doc('users/supervisor').set(user('Saad Supervisor', 'supervisor', manager: 'manager'));
  await db.doc('users/emp').set(user('Bilal Employee', 'employee', manager: 'manager', supervisor: 'supervisor'));
  await db.doc('users/pending').set(user('Zain New Joiner', 'employee', status: 'pending'));
  await db.doc('users/otherphone').set({...user('Other Phone', 'employee'), 'activeDeviceId': 'another-device'});
  await db.doc('sites/site-1').set({'name': 'Field Site — Kasur', 'latitude': 31.1, 'longitude': 74.4, 'radiusM': 300, 'isActive': true});
  await db.doc('departments/d1').set({'name': 'Field Operations', 'isActive': true});
  await db.doc('config/policy').set({'leave': {'requiredApprovals': 2}});
  final key = todayKey();
  await db.doc('attendanceDays/emp_$key').set({
    'uid': 'emp', 'employeeName': 'Bilal Employee', 'dateKey': key, 'status': 'checked_in',
    'checkInAt': now, 'siteName': 'Field Site — Kasur', 'flags': ['outside_geofence'],
    'viewerUids': ['manager', 'supervisor'],
  });
  await db.doc('liveLocations/emp').set({
    'uid': 'emp', 'employeeName': 'Bilal Employee', 'isTracking': true, 'latitude': 31.1, 'longitude': 74.4,
    'accuracyM': 8, 'capturedAt': now, 'siteName': 'Field Site — Kasur', 'insideGeofence': true,
    'viewerUids': ['manager', 'supervisor'],
  });
  await db.doc('leaveRequests/l1').set({
    'uid': 'emp', 'employeeName': 'Bilal Employee', 'leaveType': 'sick', 'startDate': '2026-12-01',
    'endDate': '2026-12-02', 'reason': 'Fever', 'status': 'pending', 'decisions': [], 'attachmentPaths': [],
    'managerUid': 'manager', 'viewerUids': ['manager'], 'createdAt': now,
  });
  await db.collection('notifications').add({
    'recipientUid': 'emp', 'title': 'Leave approved', 'body': 'Your leave was approved.',
    'type': 'leave_decision', 'read': false, 'createdAt': now,
  });
  return db;
}

Future<void> pumpApp(WidgetTester tester, {String? uid}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  firestoreOverride = await seed();
  SharedPreferences.setMockInitialValues({if (uid != null) 'location_consent_v1_$uid': true});
  final User? user = uid == null ? null : MockUser(uid: uid, email: '$uid@test.dev');
  final api = _FakeApi();
  final localDb = MemoryLocalDb();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith((ref) => Stream.value(user)),
      apiProvider.overrideWithValue(api),
      localDbProvider.overrideWithValue(localDb),
      syncServiceProvider.overrideWith((ref) => _QuietSync(localDb, api)),
      pushServiceProvider.overrideWithValue(_NoPush(api)),
      deviceIdentityProvider.overrideWith((ref) async => device),
    ],
    child: const SaibaanConnectApp(),
  ));
  await settle(tester);
}

/// Pumps frames until streams have delivered (pumpAndSettle can't be used with spinners).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Finder navItem(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(navItem(label));
  await settle(tester);
}

void main() {
  tearDown(() => firestoreOverride = null);

  testWidgets('signed out: login page', (tester) async {
    await pumpApp(tester);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('New employee? Register'), findsOneWidget);
    expect(find.text('Email or phone number'), findsOneWidget);
  });

  testWidgets('pending registration: waiting for approval', (tester) async {
    await pumpApp(tester, uid: 'pending');
    expect(find.text('Waiting for approval'), findsOneWidget);
  });

  testWidgets('unapproved phone: device change screen', (tester) async {
    await pumpApp(tester, uid: 'otherphone');
    expect(find.text('This phone is not registered for your account.'), findsOneWidget);
    expect(find.text('Request approval for this phone'), findsOneWidget);
  });

  testWidgets('employee: home, check-in card, leave, photos, alerts', (tester) async {
    await pumpApp(tester, uid: 'emp');
    expect(find.text("Today's attendance"), findsOneWidget);
    expect(find.text('Check out'), findsOneWidget, reason: 'employee is already checked in today');
    expect(find.text('Outside site'), findsOneWidget);
    for (final t in ['Home', 'Leave', 'Photos', 'Alerts']) {
      expect(navItem(t), findsOneWidget);
    }
    expect(navItem('Team'), findsNothing);
    expect(navItem('Admin'), findsNothing);

    await openTab(tester, 'Leave');
    expect(find.text('Sick leave'), findsOneWidget);

    await openTab(tester, 'Photos');
    expect(find.textContaining('No site photos yet'), findsOneWidget);

    await openTab(tester, 'Alerts');
    expect(find.text('Leave approved'), findsOneWidget);
  });

  testWidgets('manager: team roster, live location, leave review', (tester) async {
    await pumpApp(tester, uid: 'manager');
    expect(navItem('Team'), findsOneWidget);
    expect(navItem('Admin'), findsNothing);

    await openTab(tester, 'Team');
    expect(find.text('My team'), findsOneWidget);
    expect(find.text('Bilal Employee'), findsWidgets);
    expect(find.text('1 of 2 checked in'), findsOneWidget);

    await tester.tap(find.text('Live location'));
    await settle(tester);
    expect(find.text('live'), findsOneWidget);

    await openTab(tester, 'Leave');
    expect(find.text('To review'), findsOneWidget);
    expect(find.text('Bilal Employee · Sick'), findsOneWidget);
    await tester.tap(find.text('Bilal Employee · Sick'));
    await settle(tester);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('admin: administration menu and registrations', (tester) async {
    await pumpApp(tester, uid: 'admin');
    await openTab(tester, 'Admin');
    for (final t in ['Registrations', 'Device requests', 'Flagged attendance', 'Employees', 'Sites & geofences', 'Policy settings']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.scrollUntilVisible(find.text('Audit log'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Audit log'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 1000));
    await settle(tester);
    await tester.tap(find.text('Registrations'));
    await settle(tester);
    expect(find.text('Zain New Joiner'), findsOneWidget);
    await tester.tap(find.text('Zain New Joiner'));
    await settle(tester);
    expect(find.text('Review registration'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
  });

  testWidgets('HR: no admin-only items', (tester) async {
    await pumpApp(tester, uid: 'hr');
    await openTab(tester, 'Admin');
    expect(find.text('HR'), findsWidgets);
    expect(find.text('Registrations'), findsOneWidget);
    expect(find.text('Policy settings'), findsNothing);
    expect(find.text('Sites & geofences'), findsNothing);
  });

  testWidgets('supervisor: team view without leave review', (tester) async {
    await pumpApp(tester, uid: 'supervisor');
    await openTab(tester, 'Team');
    expect(find.text('Bilal Employee'), findsWidgets);
    await openTab(tester, 'Leave');
    expect(find.text('To review'), findsNothing);
  });
}
