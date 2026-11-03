import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../domain/entities/app_policy.dart';
import '../../../../shared/widgets/common.dart';

/// Administrator edits the operational policy (proposal §11). Values are validated
/// and clamped again by the backend.
class PolicyScreen extends ConsumerStatefulWidget {
  const PolicyScreen({super.key});
  @override
  ConsumerState<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends ConsumerState<PolicyScreen> {
  late AppPolicy _p = ref.read(currentPolicyProvider);
  late final Map<String, TextEditingController> _num = {
    'requiredApprovals': TextEditingController(text: '${_p.requiredApprovals}'),
    'maxAttachments': TextEditingController(text: '${_p.maxAttachments}'),
    'maxAccuracyM': TextEditingController(text: '${_p.maxAccuracyM}'),
    'lateSyncMinutes': TextEditingController(text: '${_p.lateSyncMinutes}'),
    'clockSkewToleranceMinutes': TextEditingController(text: '${_p.clockSkewToleranceMinutes}'),
    'trackingIntervalSeconds': TextEditingController(text: '${_p.trackingIntervalSeconds}'),
    'distanceFilterM': TextEditingController(text: '${_p.distanceFilterM}'),
    'locationRetentionDays': TextEditingController(text: '${_p.locationRetentionDays}'),
    'defaultRadiusM': TextEditingController(text: '${_p.defaultRadiusM}'),
  };
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _num.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _n(String key, int fallback) => int.tryParse(_num[key]!.text.trim()) ?? fallback;

  Future<void> _save() async {
    final next = AppPolicy(
      requiredApprovals: _n('requiredApprovals', _p.requiredApprovals),
      adminCanApproveAlone: _p.adminCanApproveAlone,
      rejectionBlocks: _p.rejectionBlocks,
      adminCanOverrideRejection: _p.adminCanOverrideRejection,
      maxAttachments: _n('maxAttachments', _p.maxAttachments),
      maxAccuracyM: _n('maxAccuracyM', _p.maxAccuracyM),
      lateSyncMinutes: _n('lateSyncMinutes', _p.lateSyncMinutes),
      clockSkewToleranceMinutes: _n('clockSkewToleranceMinutes', _p.clockSkewToleranceMinutes),
      allowWithoutBiometric: _p.allowWithoutBiometric,
      correctionRoles: _p.correctionRoles,
      trackingIntervalSeconds: _n('trackingIntervalSeconds', _p.trackingIntervalSeconds),
      distanceFilterM: _n('distanceFilterM', _p.distanceFilterM),
      locationRetentionDays: _n('locationRetentionDays', _p.locationRetentionDays),
      allowGallery: _p.allowGallery,
      defaultRadiusM: _n('defaultRadiusM', _p.defaultRadiusM),
    );
    setState(() => _busy = true);
    await runWithFeedback(
      context,
      () => ref.read(apiProvider).call('updatePolicy', {'policy': next.toMap()}),
      success: 'Policy saved. Out-of-range values were adjusted to the allowed limits.',
    );
    if (mounted) setState(() => _busy = false);
  }

  Widget _numberField(String key, String label, String help) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _num[key],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, helperText: help),
        ),
      );

  Widget _switch(String title, String subtitle, bool value, AppPolicy Function(bool) update) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: (v) => setState(() => _p = update(v)),
      );

  AppPolicy _copy({
    bool? adminCanApproveAlone,
    bool? rejectionBlocks,
    bool? adminCanOverrideRejection,
    bool? allowWithoutBiometric,
    bool? allowGallery,
    List<String>? correctionRoles,
  }) =>
      AppPolicy(
        requiredApprovals: _p.requiredApprovals,
        adminCanApproveAlone: adminCanApproveAlone ?? _p.adminCanApproveAlone,
        rejectionBlocks: rejectionBlocks ?? _p.rejectionBlocks,
        adminCanOverrideRejection: adminCanOverrideRejection ?? _p.adminCanOverrideRejection,
        maxAttachments: _p.maxAttachments,
        maxAccuracyM: _p.maxAccuracyM,
        lateSyncMinutes: _p.lateSyncMinutes,
        clockSkewToleranceMinutes: _p.clockSkewToleranceMinutes,
        allowWithoutBiometric: allowWithoutBiometric ?? _p.allowWithoutBiometric,
        correctionRoles: correctionRoles ?? _p.correctionRoles,
        trackingIntervalSeconds: _p.trackingIntervalSeconds,
        distanceFilterM: _p.distanceFilterM,
        locationRetentionDays: _p.locationRetentionDays,
        allowGallery: allowGallery ?? _p.allowGallery,
        defaultRadiusM: _p.defaultRadiusM,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Policy settings')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'These rules were listed in the project proposal as decisions to confirm with SAIBAAN. '
              'Changes apply immediately and are recorded in the audit log.',
            ),
            const SectionTitle('Leave approval'),
            _numberField('requiredApprovals', 'Approvals required', 'Out of Manager / HR / Administrator (1–3)'),
            _switch('Administrator can approve alone', 'Admin approval closes the request', _p.adminCanApproveAlone,
                (v) => _copy(adminCanApproveAlone: v)),
            _switch('One rejection rejects', 'A Manager or HR rejection ends the request', _p.rejectionBlocks,
                (v) => _copy(rejectionBlocks: v)),
            _switch('Administrator can override a rejection', 'Admin may approve a rejected request',
                _p.adminCanOverrideRejection, (v) => _copy(adminCanOverrideRejection: v)),
            _numberField('maxAttachments', 'Max attachments per request', '0–5'),
            const SectionTitle('Attendance'),
            _switch('Allow attendance without biometrics', 'For phones without fingerprint/face unlock (flagged)',
                _p.allowWithoutBiometric, (v) => _copy(allowWithoutBiometric: v)),
            _switch('HR can correct attendance', 'Administrators can always correct',
                _p.correctionRoles.contains('hr'),
                (v) => _copy(correctionRoles: v ? ['hr', 'admin'] : ['admin'])),
            _numberField('maxAccuracyM', 'Flag GPS accuracy worse than (m)', '10–5000'),
            _numberField('lateSyncMinutes', 'Flag records synced later than (min)', 'Offline records'),
            _numberField('clockSkewToleranceMinutes', 'Flag device clock ahead by (min)', '1–1440'),
            const SectionTitle('Location tracking'),
            _numberField('trackingIntervalSeconds', 'Update interval (seconds)', '30–3600. Shorter uses more battery.'),
            _numberField('distanceFilterM', 'Minimum movement (m)', '0 = send on every interval'),
            _numberField('locationRetentionDays', 'Keep location history (days)', '7–3650'),
            _numberField('defaultRadiusM', 'Default geofence radius (m)', '20–5000'),
            const SectionTitle('Site photos'),
            _switch('Allow photos from gallery', 'Otherwise only the in-app camera is allowed', _p.allowGallery,
                (v) => _copy(allowGallery: v)),
            const SizedBox(height: 24),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Save policy')),
          ],
        ),
      );
}
