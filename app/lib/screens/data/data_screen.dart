import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/tremor_reading.dart';
import '../../repositories/tremor_repository.dart';

class DataScreen extends StatefulWidget {
  final String patientId;
  final TremorRepository tremorRepository;

  const DataScreen({
    super.key,
    required this.patientId,
    required this.tremorRepository,
  });

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  List<TremorReading> _readings = [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadReadings();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadReadings());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadReadings() async {
    try {
      final readings =
          await widget.tremorRepository.getReadings(widget.patientId);
      readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (mounted) setState(() { _readings = readings; _loading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to load readings. Check your connection and try again.';
          _loading = false;
        });
      }
    }
  }

  List<TremorReading> get _chartReadings =>
      _readings.length > 30 ? _readings.sublist(_readings.length - 30) : _readings;

  LineChartBarData _bar(List<FlSpot> spots, Color color) => LineChartBarData(
        spots: spots,
        color: color,
        barWidth: 2,
        isCurved: true,
        curveSmoothness: 0.25,
        dotData: FlDotData(show: _chartReadings.length <= 10),
        belowBarData: BarAreaData(
          show: true,
          color: color.withValues(alpha: 0.08),
        ),
      );

  Widget _bottomLabel(double value, TitleMeta meta) {
    final data = _chartReadings;
    if (data.isEmpty) return const SizedBox.shrink();
    final first = data.first.timestamp.toDouble();
    final last = data.last.timestamp.toDouble();
    final mid = data.length > 1 ? data[data.length ~/ 2].timestamp.toDouble() : first;
    final isLabeled = (value - first).abs() < 1 ||
        (value - last).abs() < 1 ||
        (value - mid).abs() < 1;
    if (!isLabeled) return const SizedBox.shrink();
    final dt = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return SideTitleWidget(
      meta: meta,
      child: Text(DateFormat('MMM d').format(dt), style: const TextStyle(fontSize: 10)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tremor Data'),
        centerTitle: true,
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(
                  message: _error!,
                  onRetry: () {
                    setState(() { _loading = true; _error = null; });
                    _loadReadings();
                  },
                )
              : _readings.isEmpty
                  ? const Center(child: Text('No readings available.'))
                  : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final data = _chartReadings;
    final latest = _readings.last;

    final barX = _bar(
      data.map((r) => FlSpot(r.timestamp.toDouble(), r.xPeakHz)).toList(),
      Colors.blue.shade600,
    );
    final barY = _bar(
      data.map((r) => FlSpot(r.timestamp.toDouble(), r.yPeakHz)).toList(),
      Colors.green.shade600,
    );
    final barZ = _bar(
      data.map((r) => FlSpot(r.timestamp.toDouble(), r.zPeakHz)).toList(),
      Colors.purple.shade600,
    );

    // Compute Y range from actual data so the axis scales dynamically
    final allHz = data.expand((r) => [r.xPeakHz, r.yPeakHz, r.zPeakHz]);
    final maxHz = allHz.fold(0.0, (m, v) => v > m ? v : m);
    final minHz = allHz.fold(double.infinity, (m, v) => v < m ? v : m);
    final yPadding = (maxHz - minHz) * 0.15;
    final minY = (minHz - yPadding).clamp(0.0, double.infinity);
    final maxY = maxHz + yPadding;
    // Round interval to a clean number based on range
    final range = maxY - minY;
    final interval = range <= 2 ? 0.5 : range <= 5 ? 1.0 : range <= 10 ? 2.0 : 5.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: Colors.blue.shade600, label: 'X-axis'),
              const SizedBox(width: 16),
              _LegendDot(color: Colors.green.shade600, label: 'Y-axis'),
              const SizedBox(width: 16),
              _LegendDot(color: Colors.purple.shade600, label: 'Z-axis'),
            ],
          ),

          const SizedBox(height: 12),

          // Frequency chart
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
              child: SizedBox(
                height: 260,
                child: LineChart(
                  LineChartData(
                    minY: minY,
                    maxY: maxY,
                    lineBarsData: [barX, barY, barZ],
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        axisNameWidget: const Text('Hz', style: TextStyle(fontSize: 11)),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (v, m) => SideTitleWidget(
                            meta: m,
                            child: Text(v.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 10)),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: _bottomLabel,
                        ),
                      ),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: interval,
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300),
                        left: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((s) {
                          final axis = ['X', 'Y', 'Z'][s.barIndex];
                          final color = [
                            Colors.blue.shade600,
                            Colors.green.shade600,
                            Colors.purple.shade600,
                          ][s.barIndex];
                          return LineTooltipItem(
                            '$axis: ${s.y.toStringAsFixed(1)} Hz',
                            TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Latest reading summary
          Text('Latest Reading',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            DateFormat('MMM d, yyyy  h:mm a')
                .format(DateTime.fromMillisecondsSinceEpoch(latest.timestamp)),
            style:
                theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                    axis: 'X', color: Colors.blue.shade600, hz: latest.xPeakHz),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                    axis: 'Y', color: Colors.green.shade600, hz: latest.yPeakHz),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                    axis: 'Z', color: Colors.purple.shade600, hz: latest.zPeakHz),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Text(
            'Showing last ${data.length} reading${data.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String axis;
  final Color color;
  final double hz;
  const _SummaryCard({required this.axis, required this.color, required this.hz});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(axis,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: color, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 6),
            Text('${hz.toStringAsFixed(1)} Hz',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: color)),
            Text('peak freq',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            const Text('Failed to load readings',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
