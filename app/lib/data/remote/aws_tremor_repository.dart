import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/aws_config.dart';
import '../../models/tremor_reading.dart';
import '../../repositories/tremor_repository.dart';
import 'aws_auth_repository.dart';

class AwsTremorRepository implements TremorRepository {
  final AwsAuthRepository _auth;

  AwsTremorRepository(this._auth);

  Future<Map<String, String>> _headers() async =>
      {'Authorization': await _auth.getIdToken()};

  @override
  Future<List<TremorReading>> getReadings(String patientId) async {
    final uri = Uri.parse(
        '${AwsConfig.apiBaseUrl}/patients/$patientId/readings');
    final response = await http.get(uri, headers: await _headers());
    _check(response);
    final data = jsonDecode(response.body) as List;
    return data
        .map((e) => TremorReading.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<TremorReading>> getReadingsByRange(
      String patientId, int fromMs, int toMs) async {
    final uri = Uri.parse(
        '${AwsConfig.apiBaseUrl}/patients/$patientId/readings?from=$fromMs&to=$toMs');
    final response = await http.get(uri, headers: await _headers());
    _check(response);
    final data = jsonDecode(response.body) as List;
    return data
        .map((e) => TremorReading.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _check(http.Response r) {
    if (r.statusCode == 403) throw Exception('Access denied');
    if (r.statusCode != 200) throw Exception('API error ${r.statusCode}');
  }
}
