/// Client view of config/policy. Defaults mirror DEFAULT_POLICY in
/// backend/functions/src/logic/policyModel.ts; the backend remains authoritative.
class AppPolicy {
  const AppPolicy({
    this.requiredApprovals = 2,
    this.adminCanApproveAlone = true,
    this.rejectionBlocks = true,
    this.adminCanOverrideRejection = true,
    this.maxAttachments = 3,
    this.maxAccuracyM = 100,
    this.lateSyncMinutes = 15,
    this.clockSkewToleranceMinutes = 5,
    this.allowWithoutBiometric = false,
    this.correctionRoles = const ['hr', 'admin'],
    this.trackingIntervalSeconds = 300,
    this.distanceFilterM = 0,
    this.locationRetentionDays = 90,
    this.allowGallery = false,
    this.defaultRadiusM = 200,
  });

  factory AppPolicy.fromMap(Map<String, dynamic>? m) {
    const d = AppPolicy();
    if (m == null) return d;
    Map<String, dynamic> sec(String k) => m[k] is Map ? Map<String, dynamic>.from(m[k] as Map) : const {};
    int i(Map<String, dynamic> s, String k, int def) => s[k] is num ? (s[k] as num).toInt() : def;
    bool b(Map<String, dynamic> s, String k, bool def) => s[k] is bool ? s[k] as bool : def;
    final leave = sec('leave'), att = sec('attendance'), trk = sec('tracking'), ph = sec('photos'), st = sec('sites');
    return AppPolicy(
      requiredApprovals: i(leave, 'requiredApprovals', d.requiredApprovals),
      adminCanApproveAlone: b(leave, 'adminCanApproveAlone', d.adminCanApproveAlone),
      rejectionBlocks: b(leave, 'rejectionBlocks', d.rejectionBlocks),
      adminCanOverrideRejection: b(leave, 'adminCanOverrideRejection', d.adminCanOverrideRejection),
      maxAttachments: i(leave, 'maxAttachments', d.maxAttachments),
      maxAccuracyM: i(att, 'maxAccuracyM', d.maxAccuracyM),
      lateSyncMinutes: i(att, 'lateSyncMinutes', d.lateSyncMinutes),
      clockSkewToleranceMinutes: i(att, 'clockSkewToleranceMinutes', d.clockSkewToleranceMinutes),
      allowWithoutBiometric: b(att, 'allowWithoutBiometric', d.allowWithoutBiometric),
      correctionRoles: att['correctionRoles'] is List
          ? (att['correctionRoles'] as List).whereType<String>().toList()
          : d.correctionRoles,
      trackingIntervalSeconds: i(trk, 'intervalSeconds', d.trackingIntervalSeconds),
      distanceFilterM: i(trk, 'distanceFilterM', d.distanceFilterM),
      locationRetentionDays: i(trk, 'locationRetentionDays', d.locationRetentionDays),
      allowGallery: b(ph, 'allowGallery', d.allowGallery),
      defaultRadiusM: i(st, 'defaultRadiusM', d.defaultRadiusM),
    );
  }

  final int requiredApprovals, maxAttachments, maxAccuracyM, lateSyncMinutes, clockSkewToleranceMinutes;
  final bool adminCanApproveAlone, rejectionBlocks, adminCanOverrideRejection, allowWithoutBiometric, allowGallery;
  final List<String> correctionRoles;
  final int trackingIntervalSeconds, distanceFilterM, locationRetentionDays, defaultRadiusM;

  Map<String, dynamic> toMap() => {
        'leave': {
          'requiredApprovals': requiredApprovals,
          'adminCanApproveAlone': adminCanApproveAlone,
          'rejectionBlocks': rejectionBlocks,
          'adminCanOverrideRejection': adminCanOverrideRejection,
          'maxAttachments': maxAttachments,
        },
        'attendance': {
          'maxAccuracyM': maxAccuracyM,
          'lateSyncMinutes': lateSyncMinutes,
          'clockSkewToleranceMinutes': clockSkewToleranceMinutes,
          'allowWithoutBiometric': allowWithoutBiometric,
          'correctionRoles': correctionRoles,
        },
        'tracking': {
          'intervalSeconds': trackingIntervalSeconds,
          'distanceFilterM': distanceFilterM,
          'locationRetentionDays': locationRetentionDays,
        },
        'photos': {'allowGallery': allowGallery},
        'sites': {'defaultRadiusM': defaultRadiusM},
      };
}
