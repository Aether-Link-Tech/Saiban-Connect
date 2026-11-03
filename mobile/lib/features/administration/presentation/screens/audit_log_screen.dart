import 'package:flutter/material.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';

class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = fs
        .collection('auditLogs')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map(AuditEntry.fromDoc).toList());
    return Scaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: QueryList<AuditEntry>(
        stream: stream,
        emptyMessage: 'No audit entries yet.',
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemBuilder: (context, a) => ListTile(
          dense: true,
          leading: const Icon(Icons.history_edu),
          title: Text(a.action.replaceAll('.', ' › ').replaceAll('_', ' ')),
          subtitle: Text('${a.actorName} · ${a.targetType} ${a.targetId}\n${fmtDateTime(a.createdAt)}'),
          isThreeLine: true,
        ),
      ),
    );
  }
}
