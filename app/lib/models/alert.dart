class AlertDetail {
  final String axis;
  final double peakHz;
  final double peakAmpG;

  const AlertDetail({
    required this.axis,
    required this.peakHz,
    required this.peakAmpG,
  });

  factory AlertDetail.fromJson(Map<String, dynamic> json) {
    return AlertDetail(
      axis: json['axis'] as String,
      peakHz: (json['peak_hz'] as num).toDouble(),
      peakAmpG: (json['peak_amp_g'] as num).toDouble(),
    );
  }
}

class Alert {
  final String patientId;
  final int timestamp; // Unix ms
  final String alertType;
  final String severity;
  final String message;
  final List<AlertDetail> details;
  bool read;

  Alert({
    required this.patientId,
    required this.timestamp,
    required this.alertType,
    required this.severity,
    required this.message,
    required this.details,
    required this.read,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      patientId: json['patient_id'] as String,
      timestamp: (json['timestamp'] as num).toInt(),
      alertType: json['alert_type'] as String,
      severity: json['severity'] as String,
      message: json['message'] as String,
      details: (json['details'] as List)
          .map((e) => AlertDetail.fromJson(e as Map<String, dynamic>))
          .toList(),
      read: json['read'] as bool,
    );
  }
}
