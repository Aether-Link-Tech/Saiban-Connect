import 'package:cloud_firestore/cloud_firestore.dart';

typedef Json = Map<String, dynamic>;
typedef Doc = DocumentSnapshot<Map<String, dynamic>>;

DateTime? tsToDate(Object? v) => v is Timestamp ? v.toDate() : null;
List<String> strList(Object? v) => v is List ? v.whereType<String>().toList() : const [];
double? toDouble(Object? v) => v is num ? v.toDouble() : null;
String? str(Object? v) => v is String && v.isNotEmpty ? v : null;

enum UserRole {
  employee('Employee'),
  supervisor('Supervisor'),
  manager('Manager'),
  hr('HR'),
  admin('Administrator');

  const UserRole(this.label);
  final String label;

  static UserRole parse(Object? s) =>
      UserRole.values.firstWhere((r) => r.name == s, orElse: () => UserRole.employee);

  bool get isHrOrAdmin => this == hr || this == admin;
  bool get isTeamLead => this != employee;
  bool get canReviewLeave => this == manager || this == hr || this == admin;
}

class UserProfile {
  UserProfile({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.accountStatus,
    this.email,
    this.authEmail,
    this.phone,
    this.photoPath,
    this.employeeCode,
    this.designation,
    this.departmentId,
    this.managerUid,
    this.supervisorUid,
    this.activeDeviceId,
    this.activeDeviceModel,
    this.pendingDeviceModel,
    this.reviewComment,
    this.requestedAt,
    this.assignedSiteIds = const [],
  });

  factory UserProfile.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return UserProfile(
      uid: doc.id,
      displayName: str(d['displayName']) ?? 'Unnamed',
      role: UserRole.parse(d['role']),
      accountStatus: str(d['accountStatus']) ?? 'pending',
      email: str(d['email']),
      authEmail: str(d['authEmail']),
      phone: str(d['phone']),
      photoPath: str(d['photoPath']),
      employeeCode: str(d['employeeCode']),
      designation: str(d['designation']),
      departmentId: str(d['departmentId']),
      managerUid: str(d['managerUid']),
      supervisorUid: str(d['supervisorUid']),
      activeDeviceId: str(d['activeDeviceId']),
      activeDeviceModel: str(d['activeDeviceModel']),
      pendingDeviceModel: str(d['pendingDeviceModel']),
      reviewComment: str(d['reviewComment']),
      requestedAt: tsToDate(d['requestedAt']),
      assignedSiteIds: strList(d['assignedSiteIds']),
    );
  }

  final String uid;
  final String displayName;
  final UserRole role;
  final String accountStatus;
  final String? email, authEmail, phone, photoPath, employeeCode, designation, departmentId;
  final String? managerUid, supervisorUid, activeDeviceId, activeDeviceModel, pendingDeviceModel, reviewComment;
  final DateTime? requestedAt;
  final List<String> assignedSiteIds;

  bool get isActive => accountStatus == 'active';
  String get phoneDisplay => phone == null ? '—' : '+$phone';
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class Site {
  Site({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    required this.isActive,
    this.address,
  });

  factory Site.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return Site(
      id: doc.id,
      name: str(d['name']) ?? 'Site',
      address: str(d['address']),
      latitude: toDouble(d['latitude']) ?? 0,
      longitude: toDouble(d['longitude']) ?? 0,
      radiusM: toDouble(d['radiusM']) ?? 200,
      isActive: d['isActive'] != false,
    );
  }

  final String id, name;
  final String? address;
  final double latitude, longitude, radiusM;
  final bool isActive;
}

class Department {
  Department({required this.id, required this.name, required this.isActive});
  factory Department.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return Department(id: doc.id, name: str(d['name']) ?? 'Department', isActive: d['isActive'] != false);
  }
  final String id, name;
  final bool isActive;
}

class AttendanceCorrection {
  AttendanceCorrection({required this.byName, required this.reason, this.at});
  final String byName, reason;
  final DateTime? at;
}

class AttendanceDay {
  AttendanceDay({
    required this.id,
    required this.uid,
    required this.employeeName,
    required this.dateKey,
    required this.status,
    this.checkInAt,
    this.checkOutAt,
    this.siteName,
    this.workedMinutes,
    this.flags = const [],
    this.needsReview = false,
    this.corrected = false,
    this.corrections = const [],
  });

  factory AttendanceDay.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    final corrections = (d['corrections'] is List ? d['corrections'] as List : const [])
        .whereType<Map>()
        .map((c) => AttendanceCorrection(
              byName: str(c['byName']) ?? '',
              reason: str(c['reason']) ?? '',
              at: tsToDate(c['at']),
            ))
        .toList();
    return AttendanceDay(
      id: doc.id,
      uid: str(d['uid']) ?? '',
      employeeName: str(d['employeeName']) ?? '',
      dateKey: str(d['dateKey']) ?? '',
      status: str(d['status']) ?? 'incomplete',
      checkInAt: tsToDate(d['checkInAt']),
      checkOutAt: tsToDate(d['checkOutAt']),
      siteName: str(d['siteName']),
      workedMinutes: (d['workedMinutes'] as num?)?.toInt(),
      flags: strList(d['flags']),
      needsReview: d['needsReview'] == true,
      corrected: d['corrected'] == true,
      corrections: corrections,
    );
  }

  final String id, uid, employeeName, dateKey, status;
  final DateTime? checkInAt, checkOutAt;
  final String? siteName;
  final int? workedMinutes;
  final List<String> flags;
  final bool needsReview, corrected;
  final List<AttendanceCorrection> corrections;
}

class AttendanceEvent {
  AttendanceEvent({
    required this.id,
    required this.uid,
    required this.employeeName,
    required this.type,
    required this.dateKey,
    required this.flags,
    required this.reviewStatus,
    this.deviceTime,
    this.serverReceivedAt,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.siteName,
    this.distanceM,
  });

  factory AttendanceEvent.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return AttendanceEvent(
      id: doc.id,
      uid: str(d['uid']) ?? '',
      employeeName: str(d['employeeName']) ?? '',
      type: str(d['type']) ?? 'check_in',
      dateKey: str(d['dateKey']) ?? '',
      flags: strList(d['flags']),
      reviewStatus: str(d['reviewStatus']) ?? 'none',
      deviceTime: tsToDate(d['deviceTime']),
      serverReceivedAt: tsToDate(d['serverReceivedAt']),
      latitude: toDouble(d['latitude']),
      longitude: toDouble(d['longitude']),
      accuracyM: toDouble(d['accuracyM']),
      siteName: str(d['siteName']),
      distanceM: toDouble(d['distanceM']),
    );
  }

  final String id, uid, employeeName, type, dateKey, reviewStatus;
  final List<String> flags;
  final DateTime? deviceTime, serverReceivedAt;
  final double? latitude, longitude, accuracyM, distanceM;
  final String? siteName;

  String get typeLabel => type == 'check_in' ? 'Check-in' : 'Check-out';
}

class LiveLocation {
  LiveLocation({
    required this.uid,
    required this.employeeName,
    required this.isTracking,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.capturedAt,
    this.siteName,
    this.insideGeofence,
  });

  factory LiveLocation.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return LiveLocation(
      uid: doc.id,
      employeeName: str(d['employeeName']) ?? '',
      isTracking: d['isTracking'] == true,
      latitude: toDouble(d['latitude']),
      longitude: toDouble(d['longitude']),
      accuracyM: toDouble(d['accuracyM']),
      capturedAt: tsToDate(d['capturedAt']),
      siteName: str(d['siteName']),
      insideGeofence: d['insideGeofence'] as bool?,
    );
  }

  final String uid, employeeName;
  final bool isTracking;
  final double? latitude, longitude, accuracyM;
  final DateTime? capturedAt;
  final String? siteName;
  final bool? insideGeofence;
}

class FieldPhoto {
  FieldPhoto({
    required this.id,
    required this.uid,
    required this.employeeName,
    required this.storagePath,
    required this.source,
    this.siteName,
    this.caption,
    this.capturedAt,
    this.uploadedAt,
    this.latitude,
    this.longitude,
  });

  factory FieldPhoto.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return FieldPhoto(
      id: doc.id,
      uid: str(d['uid']) ?? '',
      employeeName: str(d['employeeName']) ?? '',
      storagePath: str(d['storagePath']) ?? '',
      source: str(d['source']) ?? 'camera',
      siteName: str(d['siteName']),
      caption: str(d['caption']),
      capturedAt: tsToDate(d['capturedAt']),
      uploadedAt: tsToDate(d['uploadedAt']),
      latitude: toDouble(d['latitude']),
      longitude: toDouble(d['longitude']),
    );
  }

  final String id, uid, employeeName, storagePath, source;
  final String? siteName, caption;
  final DateTime? capturedAt, uploadedAt;
  final double? latitude, longitude;
}

const leaveTypeLabels = {
  'sick': 'Sick',
  'emergency': 'Emergency',
  'half_day': 'Half-day',
  'other': 'Other',
};

class LeaveDecision {
  LeaveDecision({required this.role, required this.uid, required this.name, required this.decision, this.comment, this.at});
  final String role, uid, name, decision;
  final String? comment;
  final DateTime? at;
}

class LeaveRequest {
  LeaveRequest({
    required this.id,
    required this.uid,
    required this.employeeName,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
    required this.decisions,
    required this.attachmentPaths,
    this.days,
    this.halfDayPeriod,
    this.managerUid,
    this.createdAt,
  });

  factory LeaveRequest.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    final decisions = (d['decisions'] is List ? d['decisions'] as List : const [])
        .whereType<Map>()
        .map((x) => LeaveDecision(
              role: str(x['role']) ?? '',
              uid: str(x['uid']) ?? '',
              name: str(x['name']) ?? '',
              decision: str(x['decision']) ?? '',
              comment: str(x['comment']),
              at: tsToDate(x['at']),
            ))
        .toList();
    return LeaveRequest(
      id: doc.id,
      uid: str(d['uid']) ?? '',
      employeeName: str(d['employeeName']) ?? '',
      leaveType: str(d['leaveType']) ?? 'other',
      startDate: str(d['startDate']) ?? '',
      endDate: str(d['endDate']) ?? '',
      reason: str(d['reason']) ?? '',
      status: str(d['status']) ?? 'pending',
      decisions: decisions,
      attachmentPaths: strList(d['attachmentPaths']),
      days: (d['days'] as num?)?.toDouble(),
      halfDayPeriod: str(d['halfDayPeriod']),
      managerUid: str(d['managerUid']),
      createdAt: tsToDate(d['createdAt']),
    );
  }

  final String id, uid, employeeName, leaveType, startDate, endDate, reason, status;
  final List<LeaveDecision> decisions;
  final List<String> attachmentPaths;
  final double? days;
  final String? halfDayPeriod, managerUid;
  final DateTime? createdAt;

  String get typeLabel => leaveTypeLabels[leaveType] ?? leaveType;
  String get dateRange => startDate == endDate ? startDate : '$startDate → $endDate';
}

class AppNotification {
  AppNotification({required this.id, required this.title, required this.body, required this.type, required this.read, this.createdAt});
  factory AppNotification.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return AppNotification(
      id: doc.id,
      title: str(d['title']) ?? '',
      body: str(d['body']) ?? '',
      type: str(d['type']) ?? '',
      read: d['read'] == true,
      createdAt: tsToDate(d['createdAt']),
    );
  }
  final String id, title, body, type;
  final bool read;
  final DateTime? createdAt;
}

class DeviceRequest {
  DeviceRequest({
    required this.id,
    required this.uid,
    required this.employeeName,
    required this.deviceModel,
    required this.status,
    this.previousDeviceModel,
    this.reason,
    this.createdAt,
  });
  factory DeviceRequest.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return DeviceRequest(
      id: doc.id,
      uid: str(d['uid']) ?? '',
      employeeName: str(d['employeeName']) ?? '',
      deviceModel: str(d['deviceModel']) ?? 'Unknown device',
      status: str(d['status']) ?? 'pending',
      previousDeviceModel: str(d['previousDeviceModel']),
      reason: str(d['reason']),
      createdAt: tsToDate(d['createdAt']),
    );
  }
  final String id, uid, employeeName, deviceModel, status;
  final String? previousDeviceModel, reason;
  final DateTime? createdAt;
}

class AuditEntry {
  AuditEntry({required this.id, required this.action, required this.actorName, required this.targetType, required this.targetId, this.createdAt});
  factory AuditEntry.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return AuditEntry(
      id: doc.id,
      action: str(d['action']) ?? '',
      actorName: str(d['actorName']) ?? str(d['actorUid']) ?? '',
      targetType: str(d['targetType']) ?? '',
      targetId: str(d['targetId']) ?? '',
      createdAt: tsToDate(d['createdAt']),
    );
  }
  final String id, action, actorName, targetType, targetId;
  final DateTime? createdAt;
}
