import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/alert.dart';
import '../../repositories/alert_repository.dart';

class AlertsScreen extends StatefulWidget {
  final String patientId;
  final AlertRepository alertRepository;

  const AlertsScreen({
    super.key,
    required this.patientId,
    required this.alertRepository,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  static const Duration _pollInterval = Duration(seconds: 5);

  List<Alert> _alerts = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _loadAlerts());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    final alerts = await widget.alertRepository.getAlerts(widget.patientId);
    alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (mounted) {
      setState(() {
        _alerts = alerts;
        _loading = false;
      });
    }
  }

  Future<void> _markRead(Alert alert) async {
    if (alert.read) return;
    await widget.alertRepository.markAlertRead(
        alert.patientId, alert.timestamp);
    if (!mounted) return;
    setState(() => alert.read = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _alerts.isEmpty
              ? const Center(child: Text('No alerts.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _alerts.length,
                  itemBuilder: (context, index) {
                    final alert = _alerts[index];
                    return _AlertTile(
                      alert: alert,
                      onTap: () => _markRead(alert),
                    );
                  },
                ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final Alert alert;
  final VoidCallback onTap;

  const _AlertTile({required this.alert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(alert.timestamp);
    final formattedDate = DateFormat('MMM d, yyyy  h:mm a').format(dt);
    final isUnread = !alert.read;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isUnread ? Colors.orange.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color:
                  isUnread ? Colors.orange.shade600 : Colors.grey.shade300,
              width: 4,
            ),
          ),
          boxShadow: [
            if (isUnread)
              BoxShadow(
                color: Colors.orange.withValues(alpha: 0.12),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isUnread
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: isUnread
                        ? Colors.orange.shade700
                        : Colors.grey.shade500,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.message,
                      style: TextStyle(
                        fontWeight: isUnread
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isUnread
                            ? Colors.orange.shade900
                            : Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (isUnread)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                formattedDate,
                style: TextStyle(
                    fontSize: 11,
                    color: isUnread
                        ? Colors.orange.shade700
                        : Colors.grey.shade500),
              ),
              if (alert.details.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...alert.details.map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.circle,
                            size: 5,
                            color: isUnread
                                ? Colors.orange.shade600
                                : Colors.grey.shade400),
                        const SizedBox(width: 6),
                        Text(
                          '${d.axis.toUpperCase()}-axis: '
                          '${d.peakAmpG.toStringAsFixed(3)} G  '
                          '@ ${d.peakHz.toStringAsFixed(1)} Hz',
                          style: TextStyle(
                            fontSize: 12,
                            color: isUnread
                                ? Colors.orange.shade800
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (isUnread)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Tap to mark as read',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade500,
                        fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
