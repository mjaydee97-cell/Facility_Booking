import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../models/models.dart';

final dateFmt = DateFormat('EEE, MMM d, y');
final timeFmt = DateFormat('h:mm a');

String formatRange(DateTime start, DateTime end) =>
    '${dateFmt.format(start)} · ${timeFmt.format(start)} – ${timeFmt.format(end)}';

String percent(double rate) => '${(rate * 100).toStringAsFixed(1)}%';

Color statusColor(BookingStatus s) => switch (s) {
      BookingStatus.pending => Colors.orange.shade700,
      BookingStatus.approved => Colors.blue.shade700,
      BookingStatus.checkedIn => Colors.green.shade700,
      BookingStatus.completed => Colors.grey.shade700,
      BookingStatus.rejected || BookingStatus.noShow => Colors.red.shade700,
      BookingStatus.cancelled => Colors.grey.shade500,
    };

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c),
      ),
      child: Text(status.label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

void showError(BuildContext context, Object error) {
  final msg = error is ApiException ? error.message : 'Something went wrong: $error';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700));
}

void showMessage(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Loads data with [load] and renders it with [builder], handling the loading,
/// error and pull-to-refresh states the same way on every screen.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder, this.empty});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final bool Function(T data)? empty;

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.load();

  Future<void> reload() async {
    final f = widget.load();
    setState(() => _future = f);
    await f.catchError((_) => null as T);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          final err = snap.error;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(err is ApiException ? err.message : '$err', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: reload, child: const Text('Retry')),
              ]),
            ),
          );
        }
        return RefreshIndicator(onRefresh: reload, child: widget.builder(context, snap.data as T, reload));
      },
    );
  }
}

/// A scrollable centered message, so pull-to-refresh still works on empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => ListView(children: [
        const SizedBox(height: 120),
        Icon(icon, size: 56, color: Colors.grey),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
      ]);
}
