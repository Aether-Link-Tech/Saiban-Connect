import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/providers.dart';
import '../../../../domain/entities/models.dart';
import '../../../../shared/widgets/common.dart';

class SiteFormScreen extends ConsumerStatefulWidget {
  const SiteFormScreen({super.key, this.site});
  final Site? site;
  @override
  ConsumerState<SiteFormScreen> createState() => _SiteFormScreenState();
}

class _SiteFormScreenState extends ConsumerState<SiteFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.site?.name);
  late final _address = TextEditingController(text: widget.site?.address);
  late final _lat = TextEditingController(text: widget.site?.latitude.toString());
  late final _lng = TextEditingController(text: widget.site?.longitude.toString());
  late final _radius = TextEditingController(
    text: (widget.site?.radiusM ?? ref.read(currentPolicyProvider).defaultRadiusM).round().toString(),
  );
  late bool _active = widget.site?.isActive ?? true;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _lat, _lng, _radius]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    await runWithFeedback(context, () async {
      final loc = ref.read(locationServiceProvider);
      await loc.ensureReady();
      final pos = await loc.currentPosition();
      if (pos == null) throw const AppException('Could not get a GPS fix. Try again outdoors.');
      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(6);
        _lng.text = pos.longitude.toStringAsFixed(6);
      });
    }, success: 'Location filled from this phone.');
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runWithFeedback(
      context,
      () => ref.read(apiProvider).call('upsertSite', {
        if (widget.site != null) 'siteId': widget.site!.id,
        'name': _name.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'latitude': double.parse(_lat.text.trim()),
        'longitude': double.parse(_lng.text.trim()),
        'radiusM': double.parse(_radius.text.trim()),
        'isActive': _active,
      }),
      success: 'Site saved.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }

  String? Function(String?) _number(double min, double max) => (v) {
        final n = double.tryParse(v?.trim() ?? '');
        if (n == null) return 'Enter a number';
        if (n < min || n > max) return 'Must be between $min and $max';
        return null;
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.site == null ? 'Add site' : 'Edit site')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Site name'),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address (optional)')),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    validator: _number(-90, 90),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    validator: _number(-180, 180),
                  ),
                ),
              ]),
              TextButton.icon(
                onPressed: _busy ? null : _useCurrentLocation,
                icon: const Icon(Icons.my_location),
                label: const Text('Use my current location'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _radius,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Geofence radius (metres)', helperText: '20 – 5000 m'),
                validator: _number(20, 5000),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (_lat.text.isNotEmpty && _lng.text.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    final lat = double.tryParse(_lat.text), lng = double.tryParse(_lng.text);
                    if (lat != null && lng != null) openMap(lat, lng);
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Check on map'),
                ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Save site')),
            ],
          ),
        ),
      );
}
