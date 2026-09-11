import '../models/tremor_reading.dart';

abstract class TremorRepository {
  Future<List<TremorReading>> getReadings(String patientId);

  Future<List<TremorReading>> getReadingsByRange(
    String patientId,
    int fromMs,
    int toMs,
  );
}
