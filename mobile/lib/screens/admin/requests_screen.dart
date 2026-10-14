import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/backend.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Admin queue of pending booking requests, plus a view of all upcoming bookings.
class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Pending'), Tab(text: 'Approved'), Tab(text: 'In use')]),
        Expanded(
          child: TabBarView(children: [
            _AdminBookingList(status: 'pending'),
            _AdminBookingList(status: 'approved'),
            _AdminBookingList(status: 'checked_in'),
          ]),
        ),
      ]),
    );
  }
}

class _AdminBookingList extends StatelessWidget {
  const _AdminBookingList({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Booking>>(
      load: () => context.read<Backend>().allBookings(status: status),
      builder: (context, items, reload) {
        if (items.isEmpty) return const EmptyState(icon: Icons.inbox_outlined, message: 'Nothing here');
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, i) => _RequestCard(booking: items[i], onChanged: reload),
        );
      },
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.booking, required this.onChanged});

  final Booking booking;
  final Future<void> Function() onChanged;

  Future<void> _decide(BuildContext context, {required bool approve}) async {
    final remarks = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(approve ? 'Approve request' : 'Reject request'),
        content: TextField(
          controller: remarks,
          decoration: InputDecoration(labelText: approve ? 'Remarks (optional)' : 'Reason (shown to the user)'),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(approve ? 'Approve' : 'Reject')),
        ],
      ),
    );
    final text = remarks.text.trim();
    remarks.dispose();
    if (ok != true || !context.mounted) return;
    final backend = context.read<Backend>();
    try {
      final r = text.isEmpty ? null : text;
      approve ? await backend.approve(booking.id, remarks: r) : await backend.reject(booking.id, remarks: r);
      if (context.mounted) showMessage(context, approve ? 'Approved — the user was notified' : 'Rejected');
      await onChanged();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _cancel(BuildContext context) async {
    try {
      await context.read<Backend>().cancel(booking.id);
      if (context.mounted) showMessage(context, 'Booking cancelled — the user was notified');
      await onChanged();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(b.facilityName, style: Theme.of(context).textTheme.titleMedium)),
            StatusChip(b.status),
          ]),
          const SizedBox(height: 6),
          Text(formatRange(b.startsAt, b.endsAt)),
          const SizedBox(height: 4),
          Text('${b.userName} · ${b.userEmail}', style: const TextStyle(color: Colors.black54)),
          Text('${b.attendees} attendee(s) — ${b.purpose}'),
          if (b.status == BookingStatus.pending)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: () => _decide(context, approve: false), child: const Text('Reject')),
                FilledButton(onPressed: () => _decide(context, approve: true), child: const Text('Approve')),
              ]),
            ),
          if (b.status == BookingStatus.approved)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => _cancel(context), child: const Text('Cancel booking')),
            ),
        ]),
      ),
    );
  }
}
