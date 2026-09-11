import '../models/patient.dart';

abstract class PatientsRepository {
  Future<List<Patient>> getPatients();
}
