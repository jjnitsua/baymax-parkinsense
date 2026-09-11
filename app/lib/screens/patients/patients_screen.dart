import 'package:flutter/material.dart';

import '../../models/patient.dart';

class PatientsScreen extends StatelessWidget {
  final List<Patient> patients;
  final String selectedPatientId;
  final void Function(String patientId) onSelect;

  const PatientsScreen({
    super.key,
    required this.patients,
    required this.selectedPatientId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Patients'),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: patients.length,
        itemBuilder: (context, index) {
          final patient = patients[index];
          final isSelected = patient.patientId == selectedPatientId;

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isSelected
                  ? colorScheme.primary
                  : colorScheme.primaryContainer,
              child: Text(
                patient.name[0],
                style: TextStyle(
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              patient.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              patient.patientId,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            trailing: isSelected
                ? Icon(Icons.check_circle, color: colorScheme.primary)
                : const Icon(Icons.chevron_right),
            onTap: () => onSelect(patient.patientId),
          );
        },
      ),
    );
  }
}
