import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/services/device_identity.dart';
import '../../../../shared/widgets/common.dart';

/// Employee self-registration (proposal §4.1). The account stays pending until
/// HR/Admin approval; the phone used here becomes the employee's registered device.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.completingExistingAccount = false});

  /// True when a sign-in account already exists (e.g. resubmitting after rejection).
  final bool completingExistingAccount;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  Uint8List? _photo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider).valueOrNull;
    final authEmail = FirebaseAuth.instance.currentUser?.email;
    if (p != null) {
      _name.text = p.displayName;
      if (p.phone != null) _phone.text = '+${p.phone}';
      _email.text = p.email ?? '';
    } else if (authEmail != null && !isSyntheticEmail(authEmail)) {
      _email.text = authEmail;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker().pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 800,
      imageQuality: 80,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() => _photo = bytes);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_photo == null && !widget.completingExistingAccount) {
      showSnack(context, 'Please add a profile photograph.');
      return;
    }
    setState(() => _busy = true);
    try {
      final phone = normalizePhone(_phone.text)!;
      final email = _email.text.trim().toLowerCase();
      var user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final authEmail = email.isNotEmpty ? email : syntheticEmailFor(phone);
        final cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: authEmail, password: _password.text);
        user = cred.user;
        if (user == null) throw const AppException('Could not create the account.');
        await user.updateDisplayName(_name.text.trim());
      }

      String? photoPath;
      if (_photo != null) {
        photoPath = 'employee-photos/${user.uid}/profile.jpg';
        await FirebaseStorage.instance
            .ref(photoPath)
            .putData(_photo!, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        photoPath = ref.read(profileProvider).valueOrNull?.photoPath;
      }

      final device = await DeviceIdentity.load();
      await ref.read(apiProvider).call('submitRegistration', {
        'displayName': _name.text.trim(),
        'phone': phone,
        'email': email.isEmpty ? null : email,
        'photoPath': photoPath,
        'deviceId': device.id,
        'deviceModel': device.model,
      });
      if (mounted) {
        showSnack(context, 'Registration submitted. You will be notified when it is approved.');
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.completingExistingAccount;
    return Scaffold(
      appBar: AppBar(
        title: Text(existing ? 'Complete registration' : 'Register'),
        actions: [
          if (existing) TextButton(onPressed: () => signOut(ref), child: const Text('Sign out')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundImage: _photo == null ? null : MemoryImage(_photo!),
                    child: _photo == null ? const Icon(Icons.person, size: 48) : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: PopupMenuButton<ImageSource>(
                      icon: const CircleAvatar(radius: 16, child: Icon(Icons.camera_alt, size: 18)),
                      onSelected: _pickPhoto,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: ImageSource.camera, child: Text('Take photo')),
                        PopupMenuItem(value: ImageSource.gallery, child: Text('Choose from gallery')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Center(child: Text('Profile photograph')),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile number', hintText: '03XX XXXXXXX'),
              validator: (v) => normalizePhone(v ?? '') == null ? 'Enter a valid mobile number' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              enabled: !existing,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s) ? null : 'Enter a valid email';
              },
            ),
            if (!existing) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm password'),
                validator: (v) => v != _password.text ? 'Passwords do not match' : null,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Your department, role and work sites are assigned by HR during approval. '
              'This phone will be registered as your attendance device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit registration'),
            ),
          ],
        ),
      ),
    );
  }
}
