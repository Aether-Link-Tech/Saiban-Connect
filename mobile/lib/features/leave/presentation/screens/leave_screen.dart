import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';
import 'leave_detail_screen.dart';
import 'leave_form_screen.dart';

class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final mine = _LeaveList(
      stream: fs
          .collection('leaveRequests')
          .where('uid', isEqualTo: me.uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((s) => s.docs.map(LeaveRequest.fromDoc).toList()),
      emptyMessage: 'You have not applied for leave yet.',
      showName: false,
    );
    final fab = FloatingActionButton.extended(
      heroTag: null,
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaveFormScreen())),
      icon: const Icon(Icons.add),
      label: const Text('Apply'),
    );

    if (!me.role.canReviewLeave) {
      return Scaffold(appBar: AppBar(title: const Text('Leave')), body: mine, floatingActionButton: fab);
    }

    final reviewQuery =
        scopeForViewer(fs.collection('leaveRequests'), me).orderBy('createdAt', descending: true).limit(100);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leave'),
          bottom: const TabBar(tabs: [Tab(text: 'To review'), Tab(text: 'My requests')]),
        ),
        body: TabBarView(children: [
          _ReviewTab(
              stream: reviewQuery.snapshots().map(
                    (s) => s.docs.map(LeaveRequest.fromDoc).where((r) => r.uid != me.uid).toList(),
                  )),
          mine,
        ]),
        floatingActionButton: fab,
      ),
    );
  }
}

class _ReviewTab extends StatefulWidget {
  const _ReviewTab({required this.stream});
  final Stream<List<LeaveRequest>> stream;
  @override
  State<_ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<_ReviewTab> {
  bool _pendingOnly = true;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              FilterChip(
                label: const Text('Pending only'),
                selected: _pendingOnly,
                onSelected: (v) => setState(() => _pendingOnly = v),
              ),
            ]),
          ),
          Expanded(
            child: _LeaveList(
              stream: widget.stream.map((l) => _pendingOnly ? l.where((r) => r.status == 'pending').toList() : l),
              emptyMessage: _pendingOnly ? 'No leave requests awaiting review.' : 'No leave requests.',
              showName: true,
            ),
          ),
        ],
      );
}

class _LeaveList extends StatelessWidget {
  const _LeaveList({required this.stream, required this.emptyMessage, required this.showName});
  final Stream<List<LeaveRequest>> stream;
  final String emptyMessage;
  final bool showName;

  @override
  Widget build(BuildContext context) => QueryList<LeaveRequest>(
        stream: stream,
        emptyMessage: emptyMessage,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        itemBuilder: (context, r) => Card(
          child: ListTile(
            title: Text(showName ? '${r.employeeName} · ${r.typeLabel}' : '${r.typeLabel} leave'),
            subtitle: Text('${r.dateRange}\nApplied ${fmtDate(r.createdAt)}'),
            isThreeLine: true,
            trailing: StatusChip.status(r.status),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LeaveDetailScreen(requestId: r.id)),
            ),
          ),
        ),
      );
}
