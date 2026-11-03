import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Runs an action with a snackbar for success/failure. Returns true on success.
Future<bool> runWithFeedback(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) showSnack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e));
    return false;
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class SplashView extends StatelessWidget {
  const SplashView({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: LoadingView());
}

class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => MessageView(icon: Icons.inbox_outlined, message: message);
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.error, {super.key});
  final Object error;
  @override
  Widget build(BuildContext context) => MessageView(icon: Icons.error_outline, message: friendlyError(error));
}

/// Standard rendering for a Firestore query stream.
class QueryList<T> extends StatelessWidget {
  const QueryList({
    super.key,
    required this.stream,
    required this.itemBuilder,
    required this.emptyMessage,
    this.padding = const EdgeInsets.all(12),
  });
  final Stream<List<T>> stream;
  final Widget Function(BuildContext, T) itemBuilder;
  final String emptyMessage;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<T>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(snap.error!);
          if (!snap.hasData) return const LoadingView();
          final items = snap.data!;
          if (items.isEmpty) return EmptyView(emptyMessage);
          return ListView.separated(
            padding: padding,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (c, i) => itemBuilder(c, items[i]),
          );
        },
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  static Color colorFor(String status) {
    switch (status) {
      case 'approved':
      case 'completed':
      case 'accepted':
      case 'active':
        return AppColors.green;
      case 'rejected':
      case 'missing_checkout':
      case 'disabled':
        return AppColors.red;
      case 'pending':
      case 'checked_in':
      case 'incomplete':
        return AppColors.amber;
      default:
        return Colors.blueGrey;
    }
  }

  factory StatusChip.status(String status) =>
      StatusChip(status.replaceAll('_', ' '), color: colorFor(status));

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withAlpha(31), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class FlagChips extends StatelessWidget {
  const FlagChips(this.flags, {super.key});
  final List<String> flags;
  @override
  Widget build(BuildContext context) => flags.isEmpty
      ? const SizedBox.shrink()
      : Wrap(
          spacing: 6,
          runSpacing: 4,
          children: flags.map((f) => StatusChip(flagLabel(f), color: AppColors.amber)).toList(),
        );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

final Map<String, Future<String>> _urlCache = {};
Future<String> storageUrl(String path) => _urlCache[path] ??= FirebaseStorage.instance.ref(path).getDownloadURL();

/// Displays an image from Cloud Storage (access checked by storage rules).
class StorageImage extends StatelessWidget {
  const StorageImage(this.path, {super.key, this.fit = BoxFit.cover});
  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: storageUrl(path),
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Icon(Icons.broken_image_outlined));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          return Image.network(
            snap.data!,
            fit: fit,
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
          );
        },
      );
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initials, this.photoPath, this.radius = 22});
  final String initials;
  final String? photoPath;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        child: photoPath == null
            ? Text(initials)
            : ClipOval(child: SizedBox.expand(child: StorageImage(photoPath!))),
      );
}

Future<void> openMap(double lat, double lng) async {
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> openStorageFile(String path) async {
  final url = await storageUrl(path);
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? hint,
  bool required = false,
  String confirmLabel = 'OK',
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: required && controller.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String confirmLabel = 'Confirm'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return ok ?? false;
}
