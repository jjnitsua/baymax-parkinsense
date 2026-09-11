import 'package:flutter/material.dart';

import '../../models/patient.dart';
import '../../models/user.dart';
import '../../repositories/alert_repository.dart';
import '../../repositories/patients_repository.dart';
import '../../repositories/tremor_repository.dart';
import '../alerts/alerts_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../data/data_screen.dart';
import '../patients/patients_screen.dart';

class ShellScreen extends StatefulWidget {
  final User user;
  final TremorRepository tremorRepository;
  final AlertRepository alertRepository;
  final PatientsRepository patientsRepository;
  final VoidCallback onSignOut;

  const ShellScreen({
    super.key,
    required this.user,
    required this.tremorRepository,
    required this.alertRepository,
    required this.patientsRepository,
    required this.onSignOut,
  });

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _selectedIndex = 0;
  late String _selectedPatientId;
  List<Patient> _patients = [];

  @override
  void initState() {
    super.initState();
    _selectedPatientId = _defaultPatientId();
    if (_isClinician) {
      // Seed list with IDs so the screen is never empty while loading
      _patients = widget.user.assignedPatientIds
          .map((id) => Patient(patientId: id, name: id))
          .toList();
      _loadPatients();
    }
  }

  Future<void> _loadPatients() async {
    try {
      final patients = await widget.patientsRepository.getPatients();
      if (mounted) setState(() => _patients = patients);
    } catch (_) {
      // Keep the seeded list on failure
    }
  }

  String _defaultPatientId() => switch (widget.user.role) {
        UserRole.patient || UserRole.caretaker => widget.user.patientId!,
        UserRole.clinician => widget.user.assignedPatientIds.first,
      };

  bool get _isClinician => widget.user.role == UserRole.clinician;

  String get _selectedPatientName {
    for (final p in _patients) {
      if (p.patientId == _selectedPatientId) return p.name;
    }
    return _selectedPatientId;
  }

  void _onPatientSelected(String patientId) {
    setState(() {
      _selectedPatientId = patientId;
      _selectedIndex = _isClinician ? 1 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = DashboardScreen(
      patientId: _selectedPatientId,
      patientName: _selectedPatientName,
      user: widget.user,
      tremorRepository: widget.tremorRepository,
      alertRepository: widget.alertRepository,
      onSignOut: widget.onSignOut,
    );
    final data = DataScreen(
      patientId: _selectedPatientId,
      tremorRepository: widget.tremorRepository,
    );
    final alerts = AlertsScreen(
      patientId: _selectedPatientId,
      alertRepository: widget.alertRepository,
    );

    final List<Widget> screens;
    final List<NavigationDestination> destinations;

    if (_isClinician) {
      screens = [
        PatientsScreen(
          patients: _patients,
          selectedPatientId: _selectedPatientId,
          onSelect: _onPatientSelected,
        ),
        dashboard,
        data,
        alerts,
      ];
      destinations = const [
        NavigationDestination(
          icon: Icon(Icons.people_outlined),
          selectedIcon: Icon(Icons.people),
          label: 'Patients',
        ),
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: 'Data',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_outlined),
          selectedIcon: Icon(Icons.notifications),
          label: 'Alerts',
        ),
      ];
    } else {
      screens = [
        dashboard,
        data,
        alerts,
      ];
      destinations = const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: 'Data',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_outlined),
          selectedIcon: Icon(Icons.notifications),
          label: 'Alerts',
        ),
      ];
    }

    return Scaffold(
      body: IndexedStack(
        key: ValueKey(_selectedPatientId),
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: destinations,
      ),
    );
  }
}
