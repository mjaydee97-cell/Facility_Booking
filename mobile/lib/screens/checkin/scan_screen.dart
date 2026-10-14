import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../api/backend.dart';
import '../../config.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Check-in tab. The camera only starts when the user opens the scanner, so it
/// is not running while this tab sits in the background.
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  Future<void> _scan(BuildContext context) async {
    final payload = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _ScannerPage()));
    if (payload == null || !context.mounted) return;
    try {
      final Booking b = await context.read<Backend>().checkIn(payload);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Checked in'),
          content: Text('${b.facilityName}\n${formatRange(b.startsAt, b.endsAt)}\n\n'
              'Remember to check out from My Bookings when you leave.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.qr_code_2, size: 120, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Arrived at your facility?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Scan the QR code posted at the entrance to check in. '
            'Bookings not checked in within 15 minutes of the start time are released.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _scan(context),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
          ),
        ]),
      ),
    );
  }
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final v = code.rawValue;
      if (v != null && v.startsWith(qrPrefix)) {
        _done = true;
        Navigator.pop(context, v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan facility QR')),
      body: Stack(children: [
        MobileScanner(onDetect: _onDetect),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ]),
    );
  }
}
