import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';

/// Leave application (proposal §4.6): type, dates, reason, optional attachments.
class LeaveFormScreen extends ConsumerStatefulWidget {
  const LeaveFormScreen({super.key});
  @override
  ConsumerState<LeaveFormScreen> createState() => _LeaveFormScreenState();
}

class _LeaveFormScreenState extends ConsumerState<LeaveFormScreen> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  String _type = 'sick';
  String _halfDayPeriod = 'first_half';
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  final List<PlatformFile> _files = [];
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _isHalfDay => _type == 'half_day';

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked.isBefore(_start) ? _start : picked;
      }
    });
  }

  Future<void> _addAttachment() async {
    final max = ref.read(currentPolicyProvider).maxAttachments;
    if (_files.length >= max) {
      showSnack(context, 'You can attach at most $max files.');
      return;
    }
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    final file = res?.files.single;
    if (file == null || file.path == null) return;
    if (file.size > 10 * 1024 * 1024) {
      if (mounted) showSnack(context, 'Files must be smaller than 10 MB.');
      return;
    }
    setState(() => _files.add(file));
  }

  String _contentType(String ext) => switch (ext) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        _ => 'image/jpeg',
      };

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final uid = ref.read(currentUidProvider);
      if (uid == null) throw const AppException('Please sign in again.');
      final paths = <String>[];
      for (final f in _files) {
        final ext = p.extension(f.path!).replaceFirst('.', '').toLowerCase();
        final path = 'leave-attachments/$uid/${const Uuid().v4()}.$ext';
        await FirebaseStorage.instance
            .ref(path)
            .putFile(File(f.path!), SettableMetadata(contentType: _contentType(ext)));
        paths.add(path);
      }
      await ref.read(apiProvider).call('submitLeaveRequest', {
        'leaveType': _type,
        'startDate': dateKeyFromDate(_start),
        'endDate': dateKeyFromDate(_isHalfDay ? _start : _end),
        if (_isHalfDay) 'halfDayPeriod': _halfDayPeriod,
        'reason': _reason.text.trim(),
        'attachmentPaths': paths,
      });
      if (mounted) {
        showSnack(context, 'Leave request submitted.');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for leave')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Leave type'),
              items: leaveTypeLabels.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(_isHalfDay ? 'Date: ${fmtDate(_start)}' : 'From: ${fmtDate(_start)}'),
                  onPressed: () => _pickDate(true),
                ),
              ),
              if (!_isHalfDay) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text('To: ${fmtDate(_end)}'),
                    onPressed: () => _pickDate(false),
                  ),
                ),
              ],
            ]),
            if (_isHalfDay) ...[
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'first_half', label: Text('First half')),
                  ButtonSegment(value: 'second_half', label: Text('Second half')),
                ],
                selected: {_halfDayPeriod},
                onSelectionChanged: (s) => setState(() => _halfDayPeriod = s.first),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _reason,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Reason', alignLabelWithHint: true),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Please give a reason' : null,
            ),
            const SectionTitle('Supporting documents (optional)'),
            for (final f in _files)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(f.extension == 'pdf' ? Icons.picture_as_pdf : Icons.image_outlined),
                title: Text(f.name, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _files.remove(f)),
                ),
              ),
            TextButton.icon(
              onPressed: _busy ? null : _addAttachment,
              icon: const Icon(Icons.attach_file),
              label: const Text('Add attachment (photo or PDF)'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
  }
}
