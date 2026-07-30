import 'dart:convert';
import 'package:http/http.dart' as http;
import 'client_web.dart' if (dart.library.io) 'client_stub.dart' as platform;

class ApiService {
  /// Change this according to your Spring Boot server IP
  /// Example:
  /// Emulator -> 10.0.2.2
  /// Physical Phone -> 192.168.x.x
  /// Web (Chrome) -> localhost
  static const String baseUrl =
    "https://employee-location-tracker-backend-production.up.railway.app";

  static const Map<String, String> headers = {
    "Content-Type": "application/json",
  };

  static final http.Client _client = platform.createClient();

  /// ==========================
  /// LOGIN
  /// POST /api/auth/login
  /// ==========================
  static Future<http.Response> login({
    required String username,
    required String password,
  }) async {
    final url = Uri.parse("$baseUrl/api/auth/login");

    print("========== LOGIN ==========");
    print("URL : $url");
    print("Username : $username");

    try {
      final response = await _client.post(
        url,
        headers: headers,
        body: jsonEncode({
          "username": username,
          "password": password,
        }),
      );

      print("Status Code : ${response.statusCode}");
      print("Response : ${response.body}");

      return response;
    } catch (e) {
      print("Login Error : $e");
      rethrow;
    }
  }

  /// ==========================
  /// REGISTER
  /// POST /api/auth/register
  /// ==========================
  static Future<http.Response> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
  }) async {
    final url = Uri.parse("$baseUrl/api/auth/register");

    try {
      final response = await _client.post(
        url,
        headers: headers,
        body: jsonEncode({
          "username": username,
          "password": password,
          "fullName": fullName,
          "email": email,
        }),
      );

      print("Register Status Code : ${response.statusCode}");
      print("Register Response : ${response.body}");

      return response;
    } catch (e) {
      print("Register Error : $e");
      rethrow;
    }
  }

  /// ==========================
  /// LOGOUT
  /// POST /api/auth/logout
  /// ==========================
  static Future<http.Response> logout() async {
    final url = Uri.parse("$baseUrl/api/auth/logout");

    print("========== LOGOUT ==========");
    print("URL : $url");

    try {
      final response = await _client.post(
        url,
        headers: headers,
      );

      print("Status Code : ${response.statusCode}");
      print("Response : ${response.body}");

      return response;
    } catch (e) {
      print("Logout Error : $e");
      rethrow;
    }
  }

  /// ==========================
  /// CURRENT LOGGED-IN USER
  /// GET /api/auth/me
  /// ==========================
  static Future<http.Response> getCurrentUser() async {
    final url = Uri.parse("$baseUrl/api/auth/me");

    print("========== CURRENT USER ==========");
    print("URL : $url");

    try {
      final response = await _client.get(
        url,
        headers: headers,
      );

      print("Status Code : ${response.statusCode}");
      print("Response : ${response.body}");

      return response;
    } catch (e) {
      print("Current User Error : $e");
      rethrow;
    }
  }

  /// ==========================
  /// ALL EMPLOYEES (Admin)
  /// GET /api/admin/employees
  /// ==========================
  static Future<http.Response> getAllEmployees() async {
    final url = Uri.parse("$baseUrl/api/admin/employees");

    try {
      final response = await _client.get(url, headers: headers);

      print("Employees Status Code: ${response.statusCode}");
      print("Employees Response: ${response.body}");

      return response;
    } catch (e) {
      print("Employees Error : $e");
      rethrow;
    }
  }

  /// ==========================
  /// EMPLOYEE REPORT (Admin)
  /// GET /api/admin/report?employeeId=..&date=..
  /// ==========================
  static Future<http.Response> getReport({
    required int employeeId,
    required String date, // format: yyyy-MM-dd
  }) async {
    final url = Uri.parse(
        "$baseUrl/api/admin/report?employeeId=$employeeId&date=$date");

    try {
      final response = await _client.get(url, headers: headers);

      print("Report Status Code: ${response.statusCode}");
      print("Report Response: ${response.body}");

      return response;
    } catch (e) {
      print("Report Error : $e");
      rethrow;
    }
  }
  /// ==========================
  /// EXPORT REPORT (Excel) - Admin
  /// GET /api/admin/report/export?employeeId=..&date=..
  /// ==========================
  static Future<http.Response> exportReportExcel({
    required int employeeId,
    required String date,
  }) async {
    final url = Uri.parse(
        "$baseUrl/api/admin/report/export?employeeId=$employeeId&date=$date");

    try {
      final response = await _client.get(url, headers: headers);
      print("Export Excel Status: ${response.statusCode}");
      return response;
    } catch (e) {
      print("Export Excel Error : $e");
      rethrow;
    }
  }
  static Future<http.Response> forgotPassword(String email) async {
    final url = Uri.parse("$baseUrl/api/auth/forgot-password");
    return await _client.post(url, headers: headers, body: jsonEncode({"email": email}));
  }

  static Future<http.Response> verifyOtp(String email, String otp) async {
    final url = Uri.parse("$baseUrl/api/auth/verify-otp");
    return await _client.post(url, headers: headers,
        body: jsonEncode({"email": email, "otp": otp}));
  }

  static Future<http.Response> resetPassword(String email, String otp, String newPassword) async {
    final url = Uri.parse("$baseUrl/api/auth/reset-password");
    return await _client.post(url, headers: headers,
        body: jsonEncode({"email": email, "otp": otp, "newPassword": newPassword}));
  }
  /// ==========================
  /// START TRACKING
  /// POST /api/location/tracking/start
  /// ==========================
  static Future<http.Response> startTracking() async {
    final url = Uri.parse("$baseUrl/api/location/tracking/start");
    return await _client.post(url, headers: headers);
  }

  /// ==========================
  /// STOP TRACKING
  /// POST /api/location/tracking/stop
  /// ==========================
  static Future<http.Response> stopTracking() async {
    final url = Uri.parse("$baseUrl/api/location/tracking/stop");
    return await _client.post(url, headers: headers);
  }

  /// ==========================
  /// SAVE LOCATION
  /// POST /api/location/save
  /// ==========================
  static Future<http.Response> saveLocation({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse("$baseUrl/api/location/save");
    return await _client.post(
      url,
      headers: headers,
      body: jsonEncode({
        "latitude": latitude,
        "longitude": longitude,
      }),
    );
  }
  /// ==========================
  /// MY TODAY'S STOPS
  /// GET /api/location/stops
  /// ==========================
  static Future<http.Response> getTodayStops() async {
    final url = Uri.parse("$baseUrl/api/location/stops");
    return await _client.get(url, headers: headers);
  }
  /// ==========================
  /// ALL EMPLOYEES' STOPS TODAY (Admin)
  /// GET /api/admin/stops/today
  /// ==========================
  static Future<http.Response> getAllStopsToday() async {
    final url = Uri.parse("$baseUrl/api/admin/stops/today");
    return await _client.get(url, headers: headers);
  }
  /// ==========================
  /// GET EMPLOYEE PROFILE
  /// GET /api/employee/profile
  /// ==========================
  static Future<http.Response> getProfile() async {
    final url = Uri.parse("$baseUrl/api/employee/profile");
    return await _client.get(url, headers: headers);
  }

  /// ==========================
  /// UPDATE EMPLOYEE PROFILE
  /// PUT /api/employee/profile
  /// ==========================
  /// ==========================
  /// UPDATE EMPLOYEE PROFILE
  /// PUT /api/employee/profile
  /// ==========================
  static Future<http.Response> updateProfile(Map<String, dynamic> fields) async {
    final url = Uri.parse("$baseUrl/api/employee/profile");
    return await _client.put(
      url,
      headers: headers,
      body: jsonEncode(fields),
    );
  }

  /// ==========================
  /// ADD EMPLOYEE (Admin)
  /// POST /api/admin/employees/add
  /// ==========================
  static Future<http.Response> addEmployee(Map<String, dynamic> fields) async {
    final url = Uri.parse("$baseUrl/api/admin/employees/add");
    final response = await _client.post(
      url,
      headers: headers,
      body: jsonEncode(fields),
    );
    print("ADD EMPLOYEE STATUS: ${response.statusCode}  BODY: ${response.body}");
    return response;
  }
  /// ==========================
  /// DELETE EMPLOYEE (Admin)
  /// DELETE /api/admin/employees/{id}
  /// ==========================
  static Future<http.Response> deleteEmployee(int employeeId) async {
    final url = Uri.parse("$baseUrl/api/admin/employees/$employeeId");
    return await _client.delete(url, headers: headers);
  }
  /// ==========================
  /// ADD MANUAL STOP (Employee)
  /// POST /api/location/stops/manual
  /// ==========================
  static Future<http.Response> addManualStop(Map<String, dynamic> fields) async {
    final url = Uri.parse("$baseUrl/api/location/stops/manual");
    final response = await _client.post(
      url,
      headers: headers,
      body: jsonEncode(fields),
    );
    print("ADD MANUAL STOP STATUS: ${response.statusCode}  BODY: ${response.body}");
    return response;
  }
  /// ==========================
  /// GET MY MANUAL STOPS (Employee)
  /// GET /api/location/stops/manual
  /// ==========================
  static Future<http.Response> getMyManualStops() async {
    final url = Uri.parse("$baseUrl/api/location/stops/manual");
    return await _client.get(url, headers: headers);
  }

  /// ==========================
  /// UPDATE MANUAL STOP (Employee)
  /// PUT /api/location/stops/manual/{id}
  /// ==========================
  static Future<http.Response> updateManualStop(
      int id, Map<String, dynamic> fields) async {
    final url = Uri.parse("$baseUrl/api/location/stops/manual/$id");
    return await _client.put(
      url,
      headers: headers,
      body: jsonEncode(fields),
    );
  }

  /// ==========================
  /// GET MANUAL STOPS (Admin)
  /// GET /api/admin/stops/manual
  /// ==========================
  static Future<http.Response> getManualStops() async {
    final url = Uri.parse("$baseUrl/api/admin/stops/manual");
    return await _client.get(url, headers: headers);
  }
}

