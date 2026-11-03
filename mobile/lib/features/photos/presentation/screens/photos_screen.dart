import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';
import 'photo_upload_screen.dart';

/// The current user's own site photos.
class MyPhotosScreen extends ConsumerWidget {
  const MyPhotosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Site photos')),
      body: PhotoGrid(
        query: fs
            .collection('fieldPhotos')
            .where('uid', isEqualTo: me.uid)
            .orderBy('uploadedAt', descending: true)
            .limit(60),
        showName: false,
        emptyMessage: 'No site photos yet. Tap Upload to add one.',
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PhotoUploadScreen())),
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Upload'),
      ),
    );
  }
}

class PhotoGrid extends StatelessWidget {
  const PhotoGrid({super.key, required this.query, required this.showName, required this.emptyMessage});
  final Query<Map<String, dynamic>> query;
  final bool showName;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(snap.error!);
          if (!snap.hasData) return const LoadingView();
          final photos = snap.data!.docs.map(FieldPhoto.fromDoc).toList();
          if (photos.isEmpty) return EmptyView(emptyMessage);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: photos.length,
            itemBuilder: (context, i) {
              final ph = photos[i];
              return InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PhotoViewerScreen(photo: ph)),
                ),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: StorageImage(ph.storagePath)),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          [
                            if (showName) ph.employeeName,
                            ph.siteName ?? 'No site',
                            fmtDateTime(ph.capturedAt),
                          ].join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
}

class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.photo});
  final FieldPhoto photo;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(photo.siteName ?? 'Site photo')),
        body: ListView(
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: InteractiveViewer(child: StorageImage(photo.storagePath, fit: BoxFit.contain)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoRow('Employee', photo.employeeName),
                  InfoRow('Site', photo.siteName ?? '—'),
                  InfoRow('Caption', photo.caption ?? '—'),
                  InfoRow('Captured', fmtDateTime(photo.capturedAt)),
                  InfoRow('Uploaded', fmtDateTime(photo.uploadedAt)),
                  InfoRow('Source', photo.source == 'camera' ? 'In-app camera' : 'Gallery (time/location unverified)'),
                  if (photo.latitude != null && photo.longitude != null)
                    TextButton.icon(
                      onPressed: () => openMap(photo.latitude!, photo.longitude!),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Show location on map'),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}
