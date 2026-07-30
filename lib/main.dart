import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const EmployeeTrackerApp());
}

class EmployeeTrackerApp extends StatelessWidget {
  const EmployeeTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Employee Location Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const SplashScreen(),
    );
  }
}