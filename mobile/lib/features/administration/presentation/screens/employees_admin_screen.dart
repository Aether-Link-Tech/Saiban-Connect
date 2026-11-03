import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../shared/widgets/common.dart';
import '../../../employees/presentation/screens/employee_detail_screen.dart';

/// All accounts (active and disabled) for HR/Admin.
class EmployeesAdminScreen extends ConsumerStatefulWidget {
  const EmployeesAdminScreen({super.key});
  @override
  ConsumerState<EmployeesAdminScreen> createState() => _EmployeesAdminScreenState();
}

class _EmployeesAdminScreenState extends ConsumerState<EmployeesAdminScreen> {
  String _search = '';
  bool _showDisabled = false;

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(allUsersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Employees')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, code or phone'),
            onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
          ),
        ),
        SwitchListTile(
          title: const Text('Show disabled accounts'),
          value: _showDisabled,
          onChanged: (v) => setState(() => _showDisabled = v),
        ),
        Expanded(
          child: users.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(e),
            data: (all) {
              final list = all.where((u) {
                if (u.accountStatus != 'active' && !(_showDisabled && u.accountStatus == 'disabled')) return false;
                if (_search.isEmpty) return true;
                return u.displayName.toLowerCase().contains(_search) ||
                    (u.employeeCode ?? '').toLowerCase().contains(_search) ||
                    (u.phone ?? '').contains(_search);
              }).toList();
              if (list.isEmpty) return const EmptyView('No employees found.');
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final u = list[i];
                  return ListTile(
                    leading: Avatar(initials: u.initials, photoPath: u.photoPath),
                    title: Text(u.displayName),
                    subtitle: Text([u.role.label, if (u.employeeCode != null) u.employeeCode!].join(' · ')),
                    trailing: u.accountStatus == 'active' ? null : StatusChip.status(u.accountStatus),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EmployeeDetailScreen(employee: u)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
