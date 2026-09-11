class TremorReading {
  final String patientId;
  final int timestamp; // Unix ms
  final List<double> bandHz; // 2-element [low, high], e.g. [4.0, 7.0]

  // X-axis
  final double xPeakHz;
  final double xPeakAmpG;
  final double xMeanAmpG;

  // Y-axis
  final double yPeakHz;
  final double yPeakAmpG;
  final double yMeanAmpG;

  // Z-axis
  final double zPeakHz;
  final double zPeakAmpG;
  final double zMeanAmpG;

  const TremorReading({
    required this.patientId,
    required this.timestamp,
    required this.bandHz,
    required this.xPeakHz,
    required this.xPeakAmpG,
    required this.xMeanAmpG,
    required this.yPeakHz,
    required this.yPeakAmpG,
    required this.yMeanAmpG,
    required this.zPeakHz,
    required this.zPeakAmpG,
    required this.zMeanAmpG,
  });

  factory TremorReading.fromJson(Map<String, dynamic> json) {
    double _d(String key) => (json[key] as num?)?.toDouble() ?? 0.0;
    return TremorReading(
      patientId: json['patient_id'] as String,
      timestamp: (json['timestamp'] as num).toInt(),
      bandHz: (json['band_hz'] as List?)
              ?.map((e) => (e as num?)?.toDouble() ?? 0.0)
              .toList() ??
          [0.0, 0.0],
      xPeakHz: _d('x_peak_hz'),
      xPeakAmpG: _d('x_peak_amp_g'),
      xMeanAmpG: _d('x_mean_amp_g'),
      yPeakHz: _d('y_peak_hz'),
      yPeakAmpG: _d('y_peak_amp_g'),
      yMeanAmpG: _d('y_mean_amp_g'),
      zPeakHz: _d('z_peak_hz'),
      zPeakAmpG: _d('z_peak_amp_g'),
      zMeanAmpG: _d('z_mean_amp_g'),
    );
  }
}
