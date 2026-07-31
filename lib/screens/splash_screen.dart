import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:employee_tracker_app/services/api_service.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final minSplashTime = Future.delayed(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    final savedUserJson = prefs.getString("saved_user");

    Widget nextScreen = const LoginScreen();

    if (savedUserJson != null) {
      try {
        final response = await ApiService.getCurrentUser();
        if (response.statusCode == 200) {
          final user = jsonDecode(savedUserJson) as Map<String, dynamic>;
          nextScreen = DashboardScreen(user: user);
        } else {
          await prefs.remove("saved_user");
        }
      } catch (e) {
        print("Session Check Error: $e");
      }
    }

    await minSplashTime;

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1565C0),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_on,
              color: Colors.white,
              size: 100,
            ),

            SizedBox(height: 20),

            Text(
              "Employee Location Tracker",
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 10),

            Text(
              "Powered by Saral Erp Complexity and Solutions",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),

            SizedBox(height: 50),

            CircularProgressIndicator(
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}