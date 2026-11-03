import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/providers.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';

/// Approve a registration or edit an employee's role and assignments.
class EmployeeEditorScreen extends ConsumerStatefulWidget {
  const EmployeeEditorScreen({super.key, required this.employee, this.registration = false});
  final UserProfile employee;
  final bool registration;

  @override
  ConsumerState<EmployeeEditorScreen> createState() => _EmployeeEditorScreenState();
}

class _EmployeeEditorScreenState extends ConsumerState<EmployeeEditorScreen> {
  late final _code = TextEditingController(text: widget.employee.employeeCode);
  late final _designation = TextEditingController(text: widget.employee.designation);
  late UserRole _role = widget.employee.role;
  late String _status = widget.employee.accountStatus;
  late String? _departmentId = widget.employee.departmentId;
  late String? _managerUid = widget.employee.managerUid;
  late String? _supervisorUid = widget.employee.supervisorUid;
  late final Set<String> _siteIds = {...widget.employee.assignedSiteIds};
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _designation.dispose();
    super.dispose();
  }

  Map<String, dynamic> _assignment(bool isAdmin) => {
        'uid': widget.employee.uid,
        if (isAdmin || widget.registration) 'role': _role.name,
        'employeeCode': _code.text.trim().isEmpty ? null : _code.text.trim(),
        'designation': _designation.text.trim().isEmpty ? null : _designation.text.trim(),
        'departmentId': _departmentId,
        'managerUid': _managerUid,
        'supervisorUid': _supervisorUid,
        'assignedSiteIds': _siteIds.toList(),
      };

  Future<void> _save({String? decision}) async {
    final isAdmin = ref.read(meProvider).role == UserRole.admin;
    String? comment;
    if (decision == 'reject') {
      comment = await promptText(context, title: 'Reject registration', hint: 'Reason', required: true, confirmLabel: 'Reject');
      if (comment == null) return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      if (widget.registration) {
        await api.call('reviewRegistration', {
          ..._assignment(isAdmin),
          'decision': decision,
          'comment': comment,
        });
      } else {
        await api.call('updateEmployee', {
          ..._assignment(isAdmin),
          if (isAdmin && _status != widget.employee.accountStatus) 'accountStatus': _status,
        });
      }
      if (mounted) {
        showSnack(context, decision == 'reject' ? 'Registration rejected.' : 'Saved.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final isAdmin = me.role == UserRole.admin;
    final e = widget.employee;
    final users = ref.watch(allUsersProvider).valueOrNull ?? const [];
    final sites = (ref.watch(sitesProvider).valueOrNull ?? const []).where((s) => s.isActive || _siteIds.contains(s.id)).toList();
    final departments = ref.watch(departmentsProvider).valueOrNull ?? const [];
    final managers = users.where((u) => u.isActive && u.uid != e.uid &&
        (u.role == UserRole.manager || u.role.isHrOrAdmin)).toList();
    final supervisors = users.where((u) => u.isActive && u.uid != e.uid &&
        (u.role == UserRole.supervisor || u.role == UserRole.manager)).toList();
    final assignableRoles = isAdmin
        ? UserRole.values
        : const [UserRole.employee, UserRole.supervisor, UserRole.manager];

    // Keep dropdown values valid even if the referenced user/department no longer qualifies.
    String? valid(String? id, Iterable<String> ids) => id != null && ids.contains(id) ? id : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.registration ? 'Review registration' : 'Edit employee')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            Avatar(initials: e.initials, photoPath: e.photoPath, radius: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.displayName, style: Theme.of(context).textTheme.titleMedium),
                  Text(e.phoneDisplay),
                  if (e.email != null) Text(e.email!),
                  if (widget.registration) Text('Phone model: ${e.pendingDeviceModel ?? 'unknown'}'),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),
          DropdownButtonFormField<UserRole>(
            value: assignableRoles.contains(_role) ? _role : null,
            decoration: const InputDecoration(labelText: 'Role'),
            items: assignableRoles.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
            onChanged: (isAdmin || widget.registration) ? (v) => setState(() => _role = v ?? _role) : null,
          ),
          const SizedBox(height: 16),
          TextField(controller: _code, decoration: const InputDecoration(labelText: 'Employee code')),
          const SizedBox(height: 16),
          TextField(controller: _designation, decoration: const InputDecoration(labelText: 'Designation')),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: valid(_departmentId, departments.map((d) => d.id)),
            decoration: const InputDecoration(labelText: 'Department'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              for (final d in departments.where((d) => d.isActive || d.id == _departmentId))
                DropdownMenuItem<String?>(value: d.id, child: Text(d.name)),
            ],
            onChanged: (v) => setState(() => _departmentId = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: valid(_managerUid, managers.map((u) => u.uid)),
            decoration: const InputDecoration(labelText: 'Manager (approves leave)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              for (final u in managers)
                DropdownMenuItem<String?>(value: u.uid, child: Text('${u.displayName} (${u.role.label})')),
            ],
            onChanged: (v) => setState(() => _managerUid = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: valid(_supervisorUid, supervisors.map((u) => u.uid)),
            decoration: const InputDecoration(labelText: 'Supervisor (field oversight)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              for (final u in supervisors)
                DropdownMenuItem<String?>(value: u.uid, child: Text('${u.displayName} (${u.role.label})')),
            ],
            onChanged: (v) => setState(() => _supervisorUid = v),
          ),
          const SectionTitle('Assigned sites'),
          if (sites.isEmpty) const Text('No sites yet. An administrator can add them under Sites & geofences.'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in sites)
                FilterChip(
                  label: Text(s.name),
                  selected: _siteIds.contains(s.id),
                  onSelected: (v) => setState(() => v ? _siteIds.add(s.id) : _siteIds.remove(s.id)),
                ),
            ],
          ),
          if (isAdmin && !widget.registration) ...[
            const SectionTitle('Account'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Account active'),
              subtitle: const Text('Disabled accounts cannot sign in.'),
              value: _status == 'active',
              onChanged: e.uid == me.uid ? null : (v) => setState(() => _status = v ? 'active' : 'disabled'),
            ),
          ],
          const SizedBox(height: 24),
          if (widget.registration)
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _save(decision: 'reject'),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _save(decision: 'approve'),
                  child: const Text('Approve'),
                ),
              ),
            ])
          else
            FilledButton(onPressed: _busy ? null : () => _save(), child: const Text('Save changes')),
        ],
      ),
    );
  }
}
