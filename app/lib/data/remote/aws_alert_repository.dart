import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/aws_config.dart';
import '../../models/alert.dart';
import '../../repositories/alert_repository.dart';
import 'aws_auth_repository.dart';

class AwsAlertRepository implements AlertRepository {
  final AwsAuthRepository _auth;

  AwsAlertRepository(this._auth);

  Future<Map<String, String>> _headers() async =>
      {'Authorization': await _auth.getIdToken()};

  @override
  Future<List<Alert>> getAlerts(String patientId) async {
    final uri = Uri.parse(
        '${AwsConfig.apiBaseUrl}/patients/$patientId/alerts');
    final response = await http.get(uri, headers: await _headers());
    _check(response);
    final data = jsonDecode(response.body) as List;
    return data
        .map((e) => Alert.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Alert>> getUnreadAlerts(String patientId) async {
    final uri = Uri.parse(
        '${AwsConfig.apiBaseUrl}/patients/$patientId/alerts?unread=true');
    final response = await http.get(uri, headers: await _headers());
    _check(response);
    final data = jsonDecode(response.body) as List;
    return data
        .map((e) => Alert.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> markAlertRead(String patientId, int timestamp) async {
    final uri = Uri.parse(
        '${AwsConfig.apiBaseUrl}/patients/$patientId/alerts/$timestamp');
    final response = await http.put(uri, headers: await _headers());
    _check(response);
  }

  void _check(http.Response r) {
    if (r.statusCode == 403) throw Exception('Access denied');
    if (r.statusCode != 200) throw Exception('API error ${r.statusCode}');
  }
}
