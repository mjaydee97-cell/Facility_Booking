import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/backend.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Shows a facility's free/busy timeline for a chosen day and lets the user
/// book a range of 30-minute slots.
class FacilityDetailScreen extends StatefulWidget {
  const FacilityDetailScreen({super.key, required this.facility});

  final Facility facility;

  @override
  State<FacilityDetailScreen> createState() => _FacilityDetailScreenState();
}

class _FacilityDetailScreenState extends State<FacilityDetailScreen> {
  static const slotMinutes = 30;
  static const daysAhead = 30;

  final _purpose = TextEditingController();
  final _attendees = TextEditingController(text: '1');
  final _form = GlobalKey<FormState>();

  late DateTime _day = _today();
  List<BusySlot>? _busy;
  Object? _loadError;
  int? _startIdx;
  int? _endIdx; // inclusive
  bool _submitting = false;

  Facility get f => widget.facility;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime _at(String hhmm) {
    final p = hhmm.split(':').map(int.parse).toList();
    return DateTime(_day.year, _day.month, _day.day, p[0], p[1]);
  }

  List<DateTime> get _slots {
    final out = <DateTime>[];
    final close = _at(f.closeTime);
    for (var t = _at(f.openTime); !t.add(const Duration(minutes: slotMinutes)).isAfter(close);
        t = t.add(const Duration(minutes: slotMinutes))) {
      out.add(t);
    }
    return out;
  }

  /// null = free; otherwise the reason the slot cannot be chosen.
  String? _slotBlock(DateTime start) {
    final end = start.add(const Duration(minutes: slotMinutes));
    if (!start.isAfter(DateTime.now())) return 'past';
    for (final b in _busy ?? const <BusySlot>[]) {
      if (b.startsAt.isBefore(end) && b.endsAt.isAfter(start)) return b.isMine ? 'mine' : 'busy';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _purpose.dispose();
    _attendees.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = null;
      _loadError = null;
      _startIdx = _endIdx = null;
    });
    try {
      final busy = await context.read<Backend>().availability(f.id, _day);
      if (mounted) setState(() => _busy = busy);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _tapSlot(int i) {
    setState(() {
      if (_startIdx == null || _endIdx != _startIdx || i < _startIdx!) {
        _startIdx = _endIdx = i;
      } else if (i == _startIdx) {
        _startIdx = _endIdx = null;
      } else {
        final slots = _slots;
        final contiguousFree = [for (var k = _startIdx!; k <= i; k++) k].every((k) => _slotBlock(slots[k]) == null);
        if (contiguousFree) {
          _endIdx = i;
        } else {
          _startIdx = _endIdx = i;
        }
      }
    });
  }

  Future<void> _book() async {
    if (_startIdx == null || !_form.currentState!.validate()) return;
    final slots = _slots;
    final start = slots[_startIdx!];
    final end = slots[_endIdx!].add(const Duration(minutes: slotMinutes));
    setState(() => _submitting = true);
    try {
      final b = await context.read<Backend>().createBooking(
            facilityId: f.id,
            startsAt: start,
            endsAt: end,
            purpose: _purpose.text.trim(),
            attendees: int.parse(_attendees.text),
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: Icon(b.status == BookingStatus.pending ? Icons.hourglass_top : Icons.check_circle,
              color: statusColor(b.status), size: 40),
          title: Text(b.status == BookingStatus.pending ? 'Request submitted' : 'Booking confirmed'),
          content: Text('${b.facilityName}\n${formatRange(b.startsAt, b.endsAt)}'
              '${b.status == BookingStatus.pending ? '\n\nYou will be notified once an administrator reviews it.' : ''}'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showError(context, e);
      if (e.statusCode == 409) _load(); // Someone took the slot meanwhile; refresh the timeline.
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slots = _slots;
    final hasSelection = _startIdx != null;
    return Scaffold(
      appBar: AppBar(title: Text(f.name)),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('${f.location} · up to ${f.capacity} people · open ${f.openTime}–${f.closeTime}',
              style: const TextStyle(color: Colors.black54)),
          if (f.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(f.description)),
          if (f.requiresApproval)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(Icons.info_outline, size: 18, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                const Expanded(child: Text('Bookings here need administrator approval.')),
              ]),
            ),
          const SizedBox(height: 16),
          Text('Date', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: daysAhead,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final d = _today().add(Duration(days: i));
                final selected = d == _day;
                return ChoiceChip(
                  selected: selected,
                  label: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(DateFormat('EEE').format(d), style: const TextStyle(fontSize: 11)),
                    Text(DateFormat('MMM d').format(d), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  showCheckmark: false,
                  onSelected: (_) {
                    _day = d;
                    _load();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Text('Time', style: theme.textTheme.titleSmall),
            const Spacer(),
            _legend(Colors.white, 'Free'),
            _legend(theme.colorScheme.primary, 'Selected'),
            _legend(Colors.blue.shade100, 'Yours'),
            _legend(Colors.red.shade100, 'Taken'),
          ]),
          const SizedBox(height: 4),
          const Text('Tap a start slot, then tap an end slot.', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          if (_loadError != null)
            Center(child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text('$_loadError')))
          else if (_busy == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < slots.length; i++) _slotChip(i, slots[i], theme),
            ]),
          if (hasSelection) ...[
            const SizedBox(height: 20),
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  formatRange(slots[_startIdx!], slots[_endIdx!].add(const Duration(minutes: slotMinutes))),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _purpose,
              decoration: const InputDecoration(labelText: 'Purpose of use'),
              maxLines: 2,
              validator: (v) => (v == null || v.trim().length < 3) ? 'Describe what the facility is for' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _attendees,
              decoration: InputDecoration(labelText: 'Number of attendees (max ${f.capacity})'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1) return 'Enter a number';
                if (n > f.capacity) return 'This facility holds at most ${f.capacity}';
                return null;
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting ? null : _book,
              icon: const Icon(Icons.event_available),
              label: Text(_submitting ? 'Submitting…' : (f.requiresApproval ? 'Request booking' : 'Book now')),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _slotChip(int i, DateTime t, ThemeData theme) {
    final block = _slotBlock(t);
    final selected = _startIdx != null && i >= _startIdx! && i <= _endIdx!;
    final Color bg = selected
        ? theme.colorScheme.primary
        : switch (block) {
            'busy' => Colors.red.shade100,
            'mine' => Colors.blue.shade100,
            'past' => Colors.grey.shade200,
            _ => Colors.white,
          };
    return SizedBox(
      width: 84,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: selected ? Colors.white : Colors.black87,
          disabledForegroundColor: Colors.black38,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: block == null ? () => _tapSlot(i) : null,
        child: Text(DateFormat('h:mm a').format(t), style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _legend(Color c, String label) => Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, border: Border.all(color: Colors.black26))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ]),
      );
}
