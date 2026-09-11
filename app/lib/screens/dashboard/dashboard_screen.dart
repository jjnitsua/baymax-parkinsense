import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/tremor_reading.dart';
import '../../models/user.dart';
import '../../repositories/alert_repository.dart';
import '../../repositories/tremor_repository.dart';

class DashboardScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final User user;
  final TremorRepository tremorRepository;
  final AlertRepository alertRepository;
  final VoidCallback onSignOut;

  const DashboardScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.user,
    required this.tremorRepository,
    required this.alertRepository,
    required this.onSignOut,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  TremorReading? _latestReading;
  int _unreadAlertCount = 0;
  bool _loading = true;
  String? _error;
  Timer? _alertPollTimer;

  static const _pollInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _loadData();
    _alertPollTimer = Timer.periodic(_pollInterval, (_) => _pollUnreadAlerts());
  }

  @override
  void dispose() {
    _alertPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollUnreadAlerts() async {
    try {
      final unread =
          await widget.alertRepository.getUnreadAlerts(widget.patientId);
      if (mounted) setState(() => _unreadAlertCount = unread.length);
    } catch (_) {
      // Silent — don't overwrite the main error state for a background poll
    }
  }

  Future<void> _loadData() async {
    try {
      final readings =
          await widget.tremorRepository.getReadings(widget.patientId);
      final unread =
          await widget.alertRepository.getUnreadAlerts(widget.patientId);
      readings.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (mounted) {
        setState(() {
          _latestReading = readings.isNotEmpty ? readings.first : null;
          _unreadAlertCount = unread.length;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to load data. Check your connection and try again.';
          _loading = false;
        });
      }
    }
  }

  void _showProfile(BuildContext context) {
    final user = widget.user;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: colorScheme.primary,
                    child: Icon(Icons.person,
                        color: colorScheme.onPrimary, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        user.email,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 4),
                      _RoleBadge(role: user.role),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onSignOut();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _greetingLabel => switch (widget.user.role) {
        UserRole.patient => 'Welcome back,',
        UserRole.caretaker => 'Monitoring',
        UserRole.clinician => 'Patient',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ParkinSense'),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => _showProfile(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off, size: 48, color: Colors.red.shade400),
                        const SizedBox(height: 12),
                        const Text('Failed to load data', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); }, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: colorScheme.primary,
                            child: Icon(Icons.person,
                                color: colorScheme.onPrimary, size: 30),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _greetingLabel,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              Text(
                                widget.patientName,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Card(
                    color: _unreadAlertCount > 0
                        ? Colors.orange.shade50
                        : Colors.green.shade50,
                    child: ListTile(
                      leading: Icon(
                        _unreadAlertCount > 0
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                        color: _unreadAlertCount > 0
                            ? Colors.orange.shade700
                            : Colors.green.shade700,
                        size: 32,
                      ),
                      title: Text(
                        _unreadAlertCount > 0
                            ? '$_unreadAlertCount unread alert${_unreadAlertCount == 1 ? '' : 's'}'
                            : 'No unread alerts',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _unreadAlertCount > 0
                              ? Colors.orange.shade800
                              : Colors.green.shade800,
                        ),
                      ),
                      subtitle: Text(
                        _unreadAlertCount > 0
                            ? 'Tap Alerts tab to review'
                            : 'All caught up',
                        style: TextStyle(
                          color: _unreadAlertCount > 0
                              ? Colors.orange.shade600
                              : Colors.green.shade600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'Latest Tremor Reading',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  if (_latestReading == null)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No readings available.'),
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Recorded: ${DateFormat('MMM d, yyyy  h:mm a').format(DateTime.fromMillisecondsSinceEpoch(_latestReading!.timestamp))}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade600),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _AxisCard(
                            axis: 'X',
                            peakHz: _latestReading!.xPeakHz,
                            peakAmpG: _latestReading!.xPeakAmpG,
                            meanAmpG: _latestReading!.xMeanAmpG,
                            color: Colors.blue.shade600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AxisCard(
                            axis: 'Y',
                            peakHz: _latestReading!.yPeakHz,
                            peakAmpG: _latestReading!.yPeakAmpG,
                            meanAmpG: _latestReading!.yMeanAmpG,
                            color: Colors.green.shade600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AxisCard(
                            axis: 'Z',
                            peakHz: _latestReading!.zPeakHz,
                            peakAmpG: _latestReading!.zPeakAmpG,
                            meanAmpG: _latestReading!.zMeanAmpG,
                            color: Colors.purple.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final UserRole role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      UserRole.patient => ('Patient', Colors.blue),
      UserRole.clinician => ('Clinician', Colors.green),
      UserRole.caretaker => ('Caretaker', Colors.purple),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AxisCard extends StatelessWidget {
  final String axis;
  final double peakHz;
  final double peakAmpG;
  final double meanAmpG;
  final Color color;

  const _AxisCard({
    required this.axis,
    required this.peakHz,
    required this.peakAmpG,
    required this.meanAmpG,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  axis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${peakAmpG.toStringAsFixed(3)} G',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: color),
            ),
            Text(
              'peak amp',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              '${peakHz.toStringAsFixed(1)} Hz',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              'peak freq',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
