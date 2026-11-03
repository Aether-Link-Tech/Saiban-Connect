import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';

class DepartmentsScreen extends ConsumerWidget {
  const DepartmentsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Department? d]) async {
    final name = await promptText(
      context,
      title: d == null ? 'Add department' : 'Rename department',
      hint: d?.name ?? 'Department name',
      required: true,
      confirmLabel: 'Save',
    );
    if (name == null || !context.mounted) return;
    await runWithFeedback(
      context,
      () => ref.read(apiProvider).call('upsertDepartment', {
        if (d != null) 'departmentId': d.id,
        'name': name,
        'isActive': d?.isActive ?? true,
      }),
      success: 'Department saved.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deps = ref.watch(departmentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Departments')),
      body: deps.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (list) => list.isEmpty
            ? const EmptyView('No departments yet.')
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final d in list)
                    ListTile(
                      title: Text(d.name),
                      onTap: () => _edit(context, ref, d),
                      trailing: Switch(
                        value: d.isActive,
                        onChanged: (v) => runWithFeedback(
                          context,
                          () => ref.read(apiProvider).call('upsertDepartment', {
                            'departmentId': d.id,
                            'name': d.name,
                            'isActive': v,
                          }),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}
