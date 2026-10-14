import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/backend.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Upcoming'), Tab(text: 'History')]),
        Expanded(child: TabBarView(children: [_BookingList(past: false), _BookingList(past: true)])),
      ]),
    );
  }
}

class _BookingList extends StatelessWidget {
  const _BookingList({required this.past});

  final bool past;

  @override
  Widget build(BuildContext context) {
    final backend = context.read<Backend>();
    return AsyncView<List<Booking>>(
      load: () => backend.myBookings(past: past),
      builder: (context, items, reload) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.event_busy,
            message: past ? 'No past bookings yet' : 'No upcoming bookings.\nPick a facility to reserve one.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, i) => BookingCard(booking: items[i], onChanged: reload),
        );
      },
    );
  }
}

class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, required this.onChanged});

  final Booking booking;
  final Future<void> Function() onChanged;

  Future<void> _run(BuildContext context, Future<Object?> Function() action, String done) async {
    try {
      await action();
      if (context.mounted) showMessage(context, done);
      await onChanged();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: Text('${booking.facilityName}\n${formatRange(booking.startsAt, booking.endsAt)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel booking')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, () => context.read<Backend>().cancel(booking.id), 'Booking cancelled');
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
          Text(b.purpose, style: const TextStyle(color: Colors.black54)),
          if (b.adminRemarks != null && b.adminRemarks!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Admin: ${b.adminRemarks}', style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
          if (b.status == BookingStatus.approved)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Scan the QR code at the entrance to check in (opens 15 min before start).',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          if (b.canCancel || b.status == BookingStatus.checkedIn)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 8, children: [
                if (b.canCancel)
                  TextButton(onPressed: () => _cancel(context), child: const Text('Cancel')),
                if (b.status == BookingStatus.checkedIn)
                  FilledButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Check out'),
                    onPressed: () =>
                        _run(context, () => context.read<Backend>().checkOut(b.id), 'Checked out. Thank you!'),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
