import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/providers.dart';
import '../../../../shared/widgets/common.dart';

/// Upload a site photograph (proposal §4.5). In-app camera by default; gallery only
/// if allowed by policy, and then marked as unverified.
class PhotoUploadScreen extends ConsumerStatefulWidget {
  const PhotoUploadScreen({super.key});
  @override
  ConsumerState<PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends ConsumerState<PhotoUploadScreen> {
  final _caption = TextEditingController();
  File? _file;
  String _source = 'camera';
  DateTime? _capturedAt;
  String? _siteId;
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, maxWidth: 1920, imageQuality: 80);
    if (x == null) return;
    final file = File(x.path);
    setState(() {
      _file = file;
      _source = source == ImageSource.camera ? 'camera' : 'gallery';
      _capturedAt = source == ImageSource.camera ? DateTime.now() : file.lastModifiedSync();
    });
  }

  Future<void> _upload() async {
    final file = _file;
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final uid = ref.read(currentUidProvider);
      if (uid == null) throw const AppException('Please sign in again.');
      final location = ref.read(locationServiceProvider);
      final pos = _source == 'camera' ? await location.currentPosition(timeout: const Duration(seconds: 10)) : null;

      final photoId = const Uuid().v4();
      final path = 'field-photos/$uid/$photoId.jpg';
      await FirebaseStorage.instance.ref(path).putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      await ref.read(apiProvider).call('registerFieldPhoto', {
        'photoId': photoId,
        'storagePath': path,
        'source': _source,
        'siteId': _siteId,
        'caption': _caption.text.trim().isEmpty ? null : _caption.text.trim(),
        'capturedAt': (_capturedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'latitude': pos?.latitude,
        'longitude': pos?.longitude,
        'accuracyM': pos?.accuracy,
      });
      if (mounted) {
        showSnack(context, 'Photo uploaded.');
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
    final policy = ref.watch(currentPolicyProvider);
    final sites = (ref.watch(sitesProvider).valueOrNull ?? const [])
        .where((s) => s.isActive && me.assignedSiteIds.contains(s.id))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Upload site photo')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _file == null
                  ? const Center(child: Icon(Icons.photo_camera_outlined, size: 64))
                  : Image.file(_file!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Take photo'),
              ),
            ),
            if (policy.allowGallery) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ]),
          if (_source == 'gallery' && _file != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Gallery photos are marked as unverified: their time and location cannot be confirmed.'),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: _siteId,
            decoration: const InputDecoration(labelText: 'Site'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Detect from my location')),
              for (final s in sites) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _siteId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _caption,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Caption (optional)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || _file == null ? null : _upload,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Upload'),
          ),
        ],
      ),
    );
  }
}
