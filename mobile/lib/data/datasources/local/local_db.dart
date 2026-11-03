import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// An attendance event waiting to be sent to the server.
class QueuedAttendance {
  QueuedAttendance({
    required this.id,
    required this.uid,
    required this.type,
    required this.deviceTime,
    required this.biometricPassed,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.isMocked = false,
    this.attempts = 0,
    this.lastError,
  });

  factory QueuedAttendance.fromRow(Map<String, Object?> r) => QueuedAttendance(
        id: r['id'] as String,
        uid: r['uid'] as String,
        type: r['type'] as String,
        deviceTime: DateTime.fromMillisecondsSinceEpoch(r['device_time'] as int),
        biometricPassed: (r['biometric'] as int) == 1,
        latitude: r['lat'] as double?,
        longitude: r['lng'] as double?,
        accuracyM: r['accuracy'] as double?,
        isMocked: (r['mocked'] as int? ?? 0) == 1,
        attempts: r['attempts'] as int? ?? 0,
        lastError: r['last_error'] as String?,
      );

  final String id, uid, type;
  final DateTime deviceTime;
  final bool biometricPassed, isMocked;
  final double? latitude, longitude, accuracyM;
  final int attempts;
  final String? lastError;

  Map<String, Object?> toRow() => {
        'id': id,
        'uid': uid,
        'type': type,
        'device_time': deviceTime.millisecondsSinceEpoch,
        'biometric': biometricPassed ? 1 : 0,
        'lat': latitude,
        'lng': longitude,
        'accuracy': accuracyM,
        'mocked': isMocked ? 1 : 0,
        'attempts': attempts,
        'last_error': lastError,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };

  Map<String, dynamic> toPayload() => {
        'eventId': id,
        'type': type,
        'deviceTime': deviceTime.millisecondsSinceEpoch,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyM': accuracyM,
        'biometricPassed': biometricPassed,
        'isMocked': isMocked,
      };
}

class QueuedPoint {
  QueuedPoint({required this.id, required this.latitude, required this.longitude, required this.capturedAt, this.accuracyM});
  final String id;
  final double latitude, longitude;
  final double? accuracyM;
  final DateTime capturedAt;

  Map<String, dynamic> toPayload() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyM': accuracyM,
        'capturedAt': capturedAt.millisecondsSinceEpoch,
      };
}

/// Check-in/out times recorded on this phone, so the UI is correct while offline.
class LocalDay {
  LocalDay({this.checkInAt, this.checkOutAt});
  final DateTime? checkInAt, checkOutAt;
}

/// Offline storage for the attendance queue and location samples (proposal §4.4).
/// SQLite on phones; in-memory in the browser (web is used for local demos only).
abstract class LocalDb {
  static final LocalDb instance = kIsWeb ? MemoryLocalDb() : SqliteLocalDb();

  Future<void> enqueueAttendance(QueuedAttendance e);
  Future<List<QueuedAttendance>> pendingAttendance(String uid, {int limit = 50});
  Future<void> deleteAttendance(List<String> ids);
  Future<void> markAttendanceAttempt(List<String> ids, String error);
  Future<void> enqueuePoint(String uid, QueuedPoint pt);
  Future<List<QueuedPoint>> pendingPoints(String uid, {int limit = 200});
  Future<void> deletePoints(List<String> ids);
  Future<({int events, int points})> pendingCounts(String uid);
  Future<LocalDay?> getLocalDay(String uid, String dateKey);
  Future<void> recordLocalDay(String uid, String dateKey, {DateTime? checkInAt, DateTime? checkOutAt});
}

/// In-memory implementation for the browser. Data is lost on page reload.
class MemoryLocalDb implements LocalDb {
  final _events = <String, QueuedAttendance>{};
  final _points = <String, ({String uid, QueuedPoint point})>{};
  final _days = <String, LocalDay>{};

  @override
  Future<void> enqueueAttendance(QueuedAttendance e) async => _events.putIfAbsent(e.id, () => e);

  @override
  Future<List<QueuedAttendance>> pendingAttendance(String uid, {int limit = 50}) async =>
      (_events.values.where((e) => e.uid == uid).toList()..sort((a, b) => a.deviceTime.compareTo(b.deviceTime)))
          .take(limit)
          .toList();

  @override
  Future<void> deleteAttendance(List<String> ids) async => ids.forEach(_events.remove);

  @override
  Future<void> markAttendanceAttempt(List<String> ids, String error) async {}

  @override
  Future<void> enqueuePoint(String uid, QueuedPoint pt) async => _points.putIfAbsent(pt.id, () => (uid: uid, point: pt));

  @override
  Future<List<QueuedPoint>> pendingPoints(String uid, {int limit = 200}) async =>
      (_points.values.where((p) => p.uid == uid).map((p) => p.point).toList()
            ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt)))
          .take(limit)
          .toList();

  @override
  Future<void> deletePoints(List<String> ids) async => ids.forEach(_points.remove);

  @override
  Future<({int events, int points})> pendingCounts(String uid) async => (
        events: _events.values.where((e) => e.uid == uid).length,
        points: _points.values.where((p) => p.uid == uid).length,
      );

  @override
  Future<LocalDay?> getLocalDay(String uid, String dateKey) async => _days['$uid|$dateKey'];

  @override
  Future<void> recordLocalDay(String uid, String dateKey, {DateTime? checkInAt, DateTime? checkOutAt}) async {
    final existing = _days['$uid|$dateKey'];
    _days['$uid|$dateKey'] = LocalDay(
      checkInAt: checkInAt ?? existing?.checkInAt,
      checkOutAt: checkOutAt ?? existing?.checkOutAt,
    );
  }
}

/// SQLite implementation used on Android/iOS.
class SqliteLocalDb implements LocalDb {
  SqliteLocalDb();

  Future<Database>? _opening;
  Future<Database> get _db => _opening ??= _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'saibaan_connect.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE attendance_queue (
            id TEXT PRIMARY KEY, uid TEXT NOT NULL, type TEXT NOT NULL,
            device_time INTEGER NOT NULL, biometric INTEGER NOT NULL,
            lat REAL, lng REAL, accuracy REAL, mocked INTEGER DEFAULT 0,
            attempts INTEGER DEFAULT 0, last_error TEXT, created_at INTEGER NOT NULL)
        ''');
        await db.execute('''
          CREATE TABLE location_queue (
            id TEXT PRIMARY KEY, uid TEXT NOT NULL, lat REAL NOT NULL, lng REAL NOT NULL,
            accuracy REAL, captured_at INTEGER NOT NULL)
        ''');
        await db.execute('''
          CREATE TABLE local_days (
            uid TEXT NOT NULL, date_key TEXT NOT NULL,
            check_in_at INTEGER, check_out_at INTEGER,
            PRIMARY KEY (uid, date_key))
        ''');
      },
    );
  }

  // ---- Attendance queue ----

  @override
  Future<void> enqueueAttendance(QueuedAttendance e) async {
    final db = await _db;
    await db.insert('attendance_queue', e.toRow(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<List<QueuedAttendance>> pendingAttendance(String uid, {int limit = 50}) async {
    final db = await _db;
    final rows = await db.query('attendance_queue',
        where: 'uid = ?', whereArgs: [uid], orderBy: 'device_time ASC', limit: limit);
    return rows.map(QueuedAttendance.fromRow).toList();
  }

  @override
  Future<void> deleteAttendance(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _db;
    await db.delete('attendance_queue',
        where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  @override
  Future<void> markAttendanceAttempt(List<String> ids, String error) async {
    if (ids.isEmpty) return;
    final db = await _db;
    await db.rawUpdate(
      'UPDATE attendance_queue SET attempts = attempts + 1, last_error = ? '
      'WHERE id IN (${List.filled(ids.length, '?').join(',')})',
      [error, ...ids],
    );
  }

  // ---- Location queue ----

  @override
  Future<void> enqueuePoint(String uid, QueuedPoint pt) async {
    final db = await _db;
    await db.insert(
      'location_queue',
      {
        'id': pt.id,
        'uid': uid,
        'lat': pt.latitude,
        'lng': pt.longitude,
        'accuracy': pt.accuracyM,
        'captured_at': pt.capturedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<List<QueuedPoint>> pendingPoints(String uid, {int limit = 200}) async {
    final db = await _db;
    final rows = await db.query('location_queue',
        where: 'uid = ?', whereArgs: [uid], orderBy: 'captured_at ASC', limit: limit);
    return rows
        .map((r) => QueuedPoint(
              id: r['id'] as String,
              latitude: r['lat'] as double,
              longitude: r['lng'] as double,
              accuracyM: r['accuracy'] as double?,
              capturedAt: DateTime.fromMillisecondsSinceEpoch(r['captured_at'] as int),
            ))
        .toList();
  }

  @override
  Future<void> deletePoints(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _db;
    await db.delete('location_queue',
        where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  @override
  Future<({int events, int points})> pendingCounts(String uid) async {
    final db = await _db;
    final e = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM attendance_queue WHERE uid = ?', [uid])) ??
        0;
    final pts = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM location_queue WHERE uid = ?', [uid])) ??
        0;
    return (events: e, points: pts);
  }

  // ---- Local day state ----

  @override
  Future<LocalDay?> getLocalDay(String uid, String dateKey) async {
    final db = await _db;
    final rows = await db.query('local_days', where: 'uid = ? AND date_key = ?', whereArgs: [uid, dateKey]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    DateTime? t(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return LocalDay(checkInAt: t(r['check_in_at']), checkOutAt: t(r['check_out_at']));
  }

  @override
  Future<void> recordLocalDay(String uid, String dateKey, {DateTime? checkInAt, DateTime? checkOutAt}) async {
    final db = await _db;
    final existing = await getLocalDay(uid, dateKey);
    await db.insert(
      'local_days',
      {
        'uid': uid,
        'date_key': dateKey,
        'check_in_at': (checkInAt ?? existing?.checkInAt)?.millisecondsSinceEpoch,
        'check_out_at': (checkOutAt ?? existing?.checkOutAt)?.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Keep the table small.
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final cutoffKey = '${cutoff.year.toString().padLeft(4, '0')}-'
        '${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';
    await db.delete('local_days', where: 'date_key < ?', whereArgs: [cutoffKey]);
  }
}
