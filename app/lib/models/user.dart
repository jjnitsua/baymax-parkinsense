enum UserRole { patient, clinician, caretaker }

class User {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  // null for clinician; own patient ID for patient; monitored patient ID for caretaker
  final String? patientId;
  // populated for clinician only
  final List<String> assignedPatientIds;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.patientId,
    this.assignedPatientIds = const [],
  });

  // Maps Cognito attributes: sub, name, email, custom:role,
  // custom:patient_id, custom:assigned_patients (comma-separated)
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['sub'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      role: UserRole.values.firstWhere(
        (r) => r.name == (json['custom:role'] as String? ?? 'patient'),
        orElse: () => UserRole.patient,
      ),
      patientId: json['custom:patient_id'] as String?,
      assignedPatientIds: (json['custom:assigned_patients'] as String? ?? '')
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }
}
