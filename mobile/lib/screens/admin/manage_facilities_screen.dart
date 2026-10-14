import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/backend.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class ManageFacilitiesScreen extends StatefulWidget {
  const ManageFacilitiesScreen({super.key});

  @override
  State<ManageFacilitiesScreen> createState() => _ManageFacilitiesScreenState();
}

class _ManageFacilitiesScreenState extends State<ManageFacilitiesScreen> {
  final _list = GlobalKey<AsyncViewState<List<Facility>>>();

  Future<void> _edit([Facility? f]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => FacilityFormScreen(facility: f)));
    if (saved == true) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add facility'),
      ),
      body: AsyncView<List<Facility>>(
        key: _list,
        load: () => context.read<Backend>().facilities(includeInactive: true),
        builder: (context, items, reload) => ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            for (final f in items)
              ListTile(
                title: Text(f.name, style: TextStyle(color: f.isActive ? null : Colors.grey)),
                subtitle: Text('${f.location} · ${f.capacity} pax · ${f.openTime}–${f.closeTime}'
                    '${f.requiresApproval ? ' · approval' : ''}${f.isActive ? '' : ' · INACTIVE'}'),
                onTap: () => _edit(f),
                trailing: IconButton(
                  tooltip: 'Check-in QR code',
                  icon: const Icon(Icons.qr_code),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => FacilityQrScreen(facility: f))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows the QR code to print and post at the facility entrance.
class FacilityQrScreen extends StatefulWidget {
  const FacilityQrScreen({super.key, required this.facility});

  final Facility facility;

  @override
  State<FacilityQrScreen> createState() => _FacilityQrScreenState();
}

class _FacilityQrScreenState extends State<FacilityQrScreen> {
  late Future<String> _payload = context.read<Backend>().facilityQr(widget.facility.id);

  Future<void> _rotate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Generate a new code?'),
        content: const Text('The currently posted QR code will stop working. Use this if the code was copied or leaked.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Generate')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _payload = context.read<Backend>().facilityQr(widget.facility.id, rotate: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check-in QR code'), actions: [
        IconButton(tooltip: 'Generate new code', onPressed: _rotate, icon: const Icon(Icons.autorenew)),
      ]),
      body: FutureBuilder<String>(
        future: _payload,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.facility.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              QrImageView(data: snap.data!, size: 280, backgroundColor: Colors.white),
              const SizedBox(height: 16),
              const Text('Print this and post it at the entrance.\nUsers scan it to check in.',
                  textAlign: TextAlign.center),
            ]),
          );
        },
      ),
    );
  }
}

class FacilityFormScreen extends StatefulWidget {
  const FacilityFormScreen({super.key, this.facility});

  final Facility? facility;

  @override
  State<FacilityFormScreen> createState() => _FacilityFormScreenState();
}

class _FacilityFormScreenState extends State<FacilityFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.facility?.name);
  late final _description = TextEditingController(text: widget.facility?.description);
  late final _location = TextEditingController(text: widget.facility?.location);
  late final _capacity = TextEditingController(text: widget.facility?.capacity.toString());
  late String _open = widget.facility?.openTime ?? '07:00';
  late String _close = widget.facility?.closeTime ?? '21:00';
  late bool _approval = widget.facility?.requiresApproval ?? false;
  late bool _active = widget.facility?.isActive ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _location, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(bool open) async {
    final cur = (open ? _open : _close).split(':').map(int.parse).toList();
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur[0], minute: cur[1]));
    if (t == null) return;
    final s = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => open ? _open = s : _close = s);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_close.compareTo(_open) <= 0) {
      showMessage(context, 'Closing time must be after opening time');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<Backend>().saveFacility(
            Facility(
              id: widget.facility?.id ?? 0,
              name: _name.text.trim(),
              description: _description.text.trim(),
              location: _location.text.trim(),
              capacity: int.parse(_capacity.text),
              openTime: _open,
              closeTime: _close,
              requiresApproval: _approval,
              isActive: _active,
            ),
            id: widget.facility?.id,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.facility == null ? 'New facility' : 'Edit facility')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) => (v == null || v.trim().length < 2) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Location')),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description / equipment'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _capacity,
            decoration: const InputDecoration(labelText: 'Capacity (people)'),
            keyboardType: TextInputType.number,
            validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Enter a positive number' : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickTime(true),
                icon: const Icon(Icons.wb_sunny_outlined),
                label: Text('Opens $_open'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickTime(false),
                icon: const Icon(Icons.nightlight_outlined),
                label: Text('Closes $_close'),
              ),
            ),
          ]),
          SwitchListTile(
            title: const Text('Requires admin approval'),
            value: _approval,
            onChanged: (v) => setState(() => _approval = v),
          ),
          SwitchListTile(
            title: const Text('Available for booking'),
            subtitle: const Text('Turn off to hide it; history is kept for reports.'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ]),
      ),
    );
  }
}
