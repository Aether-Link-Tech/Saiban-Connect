import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';
import '../../../photos/presentation/screens/photos_screen.dart';
import 'employee_detail_screen.dart';

/// Team oversight for Supervisor / Manager / HR / Admin (proposal §3, §4.3, §4.7).
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(me.role.isHrOrAdmin ? 'Organization' : 'My team'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [Tab(text: 'Attendance'), Tab(text: 'Live location'), Tab(text: 'Photos'), Tab(text: 'Members')],
          ),
        ),
        body: TabBarView(children: [
          const _RosterTab(),
          const _LiveTab(),
          PhotoGrid(
            query: scopeForViewer(fs.collection('fieldPhotos'), me).orderBy('uploadedAt', descending: true).limit(60),
            showName: true,
            emptyMessage: 'No site photos from your team yet.',
          ),
          const _MembersTab(),
        ]),
      ),
    );
  }
}

void _openEmployee(BuildContext context, UserProfile u) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EmployeeDetailScreen(employee: u)));

class _RosterTab extends ConsumerStatefulWidget {
  const _RosterTab();
  @override
  ConsumerState<_RosterTab> createState() => _RosterTabState();
}

class _RosterTabState extends ConsumerState<_RosterTab> {
  String _dateKey = todayKey();

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final members = ref.watch(teamMembersProvider);
    final dayStream = scopeForViewer(fs.collection('attendanceDays'), me)
        .where('dateKey', isEqualTo: _dateKey)
        .snapshots()
        .map((s) => {for (final d in s.docs.map(AttendanceDay.fromDoc)) d.uid: d});

    return Column(children: [
      ListTile(
        leading: const Icon(Icons.calendar_today),
        title: Text(fmtDateKey(_dateKey)),
        trailing: const Icon(Icons.edit_calendar),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.parse(_dateKey),
            firstDate: DateTime(2024),
            lastDate: DateTime.now(),
          );
          if (picked != null) setState(() => _dateKey = dateKeyFromDate(picked));
        },
      ),
      const Divider(height: 1),
      Expanded(
        child: members.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(e),
          data: (list) => StreamBuilder<Map<String, AttendanceDay>>(
            stream: dayStream,
            builder: (context, snap) {
              if (snap.hasError) return ErrorView(snap.error!);
              if (!snap.hasData) return const LoadingView();
              final days = snap.data!;
              if (list.isEmpty) return const EmptyView('No employees are assigned to you yet.');
              final present = list.where((u) => days[u.uid]?.checkInAt != null).length;
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text('$present of ${list.length} checked in', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final u in list) _rosterTile(context, u, days[u.uid]),
                ],
              );
            },
          ),
        ),
      ),
    ]);
  }

  Widget _rosterTile(BuildContext context, UserProfile u, AttendanceDay? d) => Card(
        child: ListTile(
          leading: Avatar(initials: u.initials, photoPath: u.photoPath),
          title: Text(u.displayName),
          subtitle: d == null
              ? const Text('No check-in')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('In ${fmtTime(d.checkInAt)} · Out ${fmtTime(d.checkOutAt)}'
                        '${d.siteName != null ? ' · ${d.siteName}' : ''}'),
                    if (d.flags.isNotEmpty) ...[const SizedBox(height: 4), FlagChips(d.flags)],
                  ],
                ),
          trailing: d == null ? const StatusChip('absent', color: Colors.blueGrey) : StatusChip.status(d.status),
          onTap: () => _openEmployee(context, u),
        ),
      );
}

class _LiveTab extends ConsumerWidget {
  const _LiveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final policy = ref.watch(currentPolicyProvider);
    final staleAfter = Duration(seconds: policy.trackingIntervalSeconds * 3);
    final stream = scopeForViewer(fs.collection('liveLocations'), me)
        .snapshots()
        .map((s) => s.docs.map(LiveLocation.fromDoc).where((l) => l.uid != me.uid).toList()
          ..sort((a, b) {
            if (a.isTracking != b.isTracking) return a.isTracking ? -1 : 1;
            return a.employeeName.compareTo(b.employeeName);
          }));

    return QueryList<LiveLocation>(
      stream: stream,
      emptyMessage: 'No location data yet. Locations appear after employees check in.',
      itemBuilder: (context, l) {
        final stale = l.capturedAt == null || DateTime.now().difference(l.capturedAt!) > staleAfter;
        final status = !l.isTracking
            ? const StatusChip('checked out', color: Colors.blueGrey)
            : stale
                ? const StatusChip('no recent update', color: AppColors.amber)
                : const StatusChip('live', color: AppColors.green);
        return Card(
          child: ListTile(
            leading: Icon(
              l.insideGeofence == false ? Icons.wrong_location_outlined : Icons.location_on_outlined,
              color: l.insideGeofence == false ? AppColors.red : null,
            ),
            title: Text(l.employeeName),
            subtitle: Text([
              'Last update ${relativeAge(l.capturedAt)} (${fmtTime(l.capturedAt)})',
              if (l.siteName != null) '${l.insideGeofence == true ? 'At' : 'Nearest'}: ${l.siteName}',
              if (l.accuracyM != null) '±${l.accuracyM!.round()} m',
            ].join('\n')),
            isThreeLine: true,
            trailing: status,
            onTap: l.latitude == null ? null : () => openMap(l.latitude!, l.longitude!),
          ),
        );
      },
    );
  }
}

class _MembersTab extends ConsumerStatefulWidget {
  const _MembersTab();
  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(teamMembersProvider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name'),
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        ),
      ),
      Expanded(
        child: members.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(e),
          data: (list) {
            final filtered = list.where((u) => u.displayName.toLowerCase().contains(_search)).toList();
            if (filtered.isEmpty) return const EmptyView('No employees found.');
            return ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final u = filtered[i];
                return ListTile(
                  leading: Avatar(initials: u.initials, photoPath: u.photoPath),
                  title: Text(u.displayName),
                  subtitle: Text([u.role.label, if (u.designation != null) u.designation!].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openEmployee(context, u),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
