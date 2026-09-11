class Patient {
  final String patientId;
  final String name;

  const Patient({required this.patientId, required this.name});

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      patientId: json['patient_id'] as String,
      name: json['name'] as String,
    );
  }
}
