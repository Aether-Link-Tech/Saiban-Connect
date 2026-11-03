import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';
import 'site_form_screen.dart';

/// Administrator: authorized work locations and geofences (proposal §4.3).
class SitesScreen extends ConsumerWidget {
  const SitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(sitesProvider);
    void open([Site? s]) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SiteFormScreen(site: s)));

    return Scaffold(
      appBar: AppBar(title: const Text('Sites & geofences')),
      body: sites.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (list) => list.isEmpty
            ? const EmptyView('No sites yet. Add the head office and field sites.')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final s = list[i];
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.place, color: s.isActive ? null : Colors.grey),
                      title: Text(s.name),
                      subtitle: Text([
                        if (s.address != null) s.address!,
                        '${s.latitude.toStringAsFixed(5)}, ${s.longitude.toStringAsFixed(5)} · radius ${s.radiusM.round()} m',
                      ].join('\n')),
                      isThreeLine: s.address != null,
                      trailing: s.isActive ? null : const StatusChip('inactive', color: Colors.grey),
                      onTap: () => open(s),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => open(),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Add site'),
      ),
    );
  }
}
