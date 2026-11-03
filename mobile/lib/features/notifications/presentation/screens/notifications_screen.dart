import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markAllRead(String uid) async {
    final unread = await fs
        .collection('notifications')
        .where('recipientUid', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .get();
    final batch = fs.batch();
    for (final d in unread.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final stream = fs
        .collection('notifications')
        .where('recipientUid', isEqualTo: me.uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(AppNotification.fromDoc).toList());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => runWithFeedback(context, () => _markAllRead(me.uid)),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: QueryList<AppNotification>(
        stream: stream,
        emptyMessage: 'No notifications.',
        itemBuilder: (context, n) => Card(
          child: ListTile(
            leading: Icon(_iconFor(n.type), color: n.read ? null : Theme.of(context).colorScheme.primary),
            title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.normal : FontWeight.bold)),
            subtitle: Text('${n.body}\n${relativeAge(n.createdAt)}'),
            isThreeLine: true,
            onTap: n.read
                ? null
                : () => fs.doc('notifications/${n.id}').update({'read': true}).catchError((Object _) {}),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    if (type.startsWith('leave')) return Icons.event_note;
    if (type.startsWith('registration')) return Icons.person_add_alt;
    if (type.startsWith('device')) return Icons.phone_android;
    if (type.startsWith('attendance') || type == 'missing_checkout') return Icons.fingerprint;
    return Icons.notifications;
  }
}
