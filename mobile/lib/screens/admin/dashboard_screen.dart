import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/backend.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Utilization monitoring dashboard for administrators.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _days = 30;
  final _view = GlobalKey<AsyncViewState<AnalyticsSummary>>();

  Future<AnalyticsSummary> _load() {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    return context.read<Backend>().analytics(from: to.subtract(Duration(days: _days - 1)), to: to);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<AnalyticsSummary>(
      key: _view,
      load: _load,
      builder: (context, s, reload) => ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 days')),
              ButtonSegment(value: 30, label: Text('30 days')),
              ButtonSegment(value: 90, label: Text('90 days')),
            ],
            selected: {_days},
            onSelectionChanged: (v) {
              setState(() => _days = v.first);
              _view.currentState?.reload();
            },
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '${DateFormat.yMMMd().format(DateTime.parse(s.from))} – ${DateFormat.yMMMd().format(DateTime.parse(s.to))}',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        _kpis(s),
        const SizedBox(height: 24),
        _section('Utilization by facility', 'Used hours vs. booked hours, as a share of opening hours'),
        for (final f in s.facilities) _FacilityBar(f),
        const SizedBox(height: 24),
        _section('Daily usage', 'Hours booked vs. hours actually used'),
        SizedBox(height: 200, child: _DailyChart(s.daily)),
        const SizedBox(height: 8),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Legend(color: Color(0xFF9FB3D9), label: 'Booked'),
          SizedBox(width: 16),
          _Legend(color: Color(0xFF13235B), label: 'Used'),
        ]),
        const SizedBox(height: 24),
        _section('Peak hours', 'Number of bookings occupying each hour'),
        SizedBox(height: 200, child: _PeakHoursChart(s.peakHours)),
        const SizedBox(height: 24),
        _section('Bookings by status', null),
        _statusTable(s.byStatus),
      ]),
    );
  }

  Widget _kpis(AnalyticsSummary s) {
    final tiles = [
      ('Utilization rate', percent(s.utilizationRate), '${s.usedHours.toStringAsFixed(1)} h used of ${s.availableHours.toStringAsFixed(0)} h'),
      ('Booking rate', percent(s.bookingRate), '${s.bookedHours.toStringAsFixed(1)} h reserved'),
      ('No-show rate', percent(s.noShowRate), '${s.byStatus['no_show'] ?? 0} no-shows'),
      ('Total bookings', '${s.totalBookings}', '${s.byStatus['cancelled'] ?? 0} cancelled'),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 600 ? 4 : 2;
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final t in tiles)
          SizedBox(
            width: w,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.$1, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text(t.$2, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  Text(t.$3, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ]),
              ),
            ),
          ),
      ]);
    });
  }

  Widget _section(String title, String? subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );

  Widget _statusTable(Map<String, int> byStatus) {
    const labels = {
      'pending': 'Pending',
      'approved': 'Approved (upcoming)',
      'checked_in': 'In use',
      'completed': 'Completed',
      'no_show': 'No-show',
      'cancelled': 'Cancelled',
      'rejected': 'Rejected',
    };
    return Card(
      child: Column(children: [
        for (final e in labels.entries)
          ListTile(dense: true, title: Text(e.value), trailing: Text('${byStatus[e.key] ?? 0}')),
      ]),
    );
  }
}

/// A "nice" axis step (1, 2, 5, 10, 20, 50, …) giving about four gridlines.
double _niceStep(double max) {
  final raw = math.max(max, 1) / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final step = [1, 2, 5, 10].map((m) => m * mag).firstWhere((s) => s >= raw);
  return step;
}

class _FacilityBar extends StatelessWidget {
  const _FacilityBar(this.f);

  final FacilityUtilization f;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${percent(f.utilizationRate)} used · ${percent(f.bookingRate)} booked',
              style: const TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 14,
            child: Stack(children: [
              Container(color: Colors.grey.shade200),
              FractionallySizedBox(widthFactor: f.bookingRate.clamp(0, 1), child: Container(color: const Color(0xFF9FB3D9))),
              FractionallySizedBox(widthFactor: f.utilizationRate.clamp(0, 1), child: Container(color: primary)),
            ]),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${f.totalBookings} bookings · ${f.usedHours.toStringAsFixed(1)} h used · '
          '${f.noShow} no-show (${percent(f.noShowRate)})',
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ]),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart(this.daily);

  final List<({DateTime date, double booked, double used})> daily;

  @override
  Widget build(BuildContext context) {
    final maxV = daily.fold<double>(1, (m, d) => math.max(m, d.booked));
    final yStep = _niceStep(maxV);
    final step = math.max(1, (daily.length / 6).ceil());
    LineChartBarData line(List<double> ys, Color c, {bool fill = false}) => LineChartBarData(
          spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
          color: c,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: fill, color: c.withValues(alpha: 0.15)),
        );
    return LineChart(LineChartData(
      minY: 0,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                '${s.barIndex == 0 ? 'Booked' : 'Used'}: ${s.y.toStringAsFixed(1)} h',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
          ],
        ),
      ),
      maxY: (maxV / yStep).ceil() * yStep,
      gridData: FlGridData(drawVerticalLine: false, horizontalInterval: yStep),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: yStep)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: step.toDouble(),
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= daily.length || v != i.toDouble()) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(DateFormat('M/d').format(daily[i].date), style: const TextStyle(fontSize: 10)),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        line([for (final d in daily) d.booked], const Color(0xFF9FB3D9), fill: true),
        line([for (final d in daily) d.used], const Color(0xFF13235B)),
      ],
    ));
  }
}

class _PeakHoursChart extends StatelessWidget {
  const _PeakHoursChart(this.hours);

  final List<int> hours;

  @override
  Widget build(BuildContext context) {
    // Only show the span of hours that has any activity (plus a margin), min 07:00–20:00.
    var first = hours.indexWhere((h) => h > 0);
    var last = hours.lastIndexWhere((h) => h > 0);
    first = first < 0 ? 7 : math.min(first, 7);
    last = last < 0 ? 20 : math.max(last, 20);
    final maxV = hours.fold<int>(1, math.max);
    final yStep = _niceStep(maxV.toDouble());
    return BarChart(BarChartData(
      maxY: (maxV / yStep).ceil() * yStep,
      gridData: FlGridData(drawVerticalLine: false, horizontalInterval: yStep),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: yStep)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, meta) => v.toInt() % 2 == 0
                ? Text('${v.toInt()}', style: const TextStyle(fontSize: 10))
                : const SizedBox.shrink(),
          ),
        ),
      ),
      barGroups: [
        for (var h = first; h <= last; h++)
          BarChartGroupData(x: h, barRods: [
            BarChartRodData(
              toY: hours[h].toDouble(),
              width: 10,
              color: hours[h] == maxV && maxV > 0 ? const Color(0xFFC00000) : const Color(0xFF13235B),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ]),
      ],
    ));
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 4, color: color),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}
