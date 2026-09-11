import '../models/alert.dart';

abstract class AlertRepository {
  Future<List<Alert>> getAlerts(String patientId);

  Future<List<Alert>> getUnreadAlerts(String patientId);

  Future<void> markAlertRead(String patientId, int timestamp);
}
