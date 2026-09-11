import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/aws_config.dart';
import '../../models/patient.dart';
import '../../repositories/patients_repository.dart';
import 'aws_auth_repository.dart';

class AwsPatientsRepository implements PatientsRepository {
  final AwsAuthRepository _auth;

  AwsPatientsRepository(this._auth);

  @override
  Future<List<Patient>> getPatients() async {
    final uri = Uri.parse('${AwsConfig.apiBaseUrl}/clinician/patients');
    final headers = {'Authorization': await _auth.getIdToken()};
    final response = await http.get(uri, headers: headers);
    if (response.statusCode == 403) throw Exception('Access denied');
    if (response.statusCode != 200) {
      throw Exception('API error ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as List;
    return data
        .map((e) => Patient.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
