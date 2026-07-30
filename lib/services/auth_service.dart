import 'dart:convert';
import 'package:employee_tracker_app/services/api_service.dart';

class AuthService {
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await ApiService.login(
      username: username,
      password: password,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
          "Status: ${response.statusCode}\nResponse: ${response.body}");
    }
  }

  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
  }) async {
    final response = await ApiService.register(
      fullName: fullName,
      username: username,
      email: email,
      password: password,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
          "Status: ${response.statusCode}\nResponse: ${response.body}");
    }
  }
}
