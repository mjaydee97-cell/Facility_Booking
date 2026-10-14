import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/backend.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'facility_detail_screen.dart';

class FacilityListScreen extends StatefulWidget {
  const FacilityListScreen({super.key});

  @override
  State<FacilityListScreen> createState() => _FacilityListScreenState();
}

class _FacilityListScreenState extends State<FacilityListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Search facilities',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v.toLowerCase()),
        ),
      ),
      Expanded(
        child: AsyncView<List<Facility>>(
          load: () => context.read<Backend>().facilities(),
          builder: (context, all, reload) {
            final items = all
                .where((f) => '${f.name} ${f.location} ${f.description}'.toLowerCase().contains(_query))
                .toList();
            if (items.isEmpty) return const EmptyState(icon: Icons.search_off, message: 'No facilities found');
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) => _FacilityCard(facility: items[i]),
            );
          },
        ),
      ),
    ]);
  }
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard({required this.facility});

  final Facility facility;

  @override
  Widget build(BuildContext context) {
    final f = facility;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FacilityDetailScreen(facility: f))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(f.name, style: Theme.of(context).textTheme.titleMedium)),
              if (f.requiresApproval)
                const Tooltip(message: 'Requires admin approval', child: Icon(Icons.verified_user_outlined, size: 20)),
            ]),
            if (f.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(f.description, style: const TextStyle(color: Colors.black54)),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 4, children: [
              _info(Icons.place_outlined, f.location),
              _info(Icons.people_outline, 'Up to ${f.capacity}'),
              _info(Icons.schedule, '${f.openTime} – ${f.closeTime}'),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 13, color: Colors.black87)),
      ]);
}
