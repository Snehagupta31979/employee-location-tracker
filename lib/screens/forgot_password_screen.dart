import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:employee_tracker_app/services/api_service.dart';
import 'dart:async';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const primaryBlue = Color(0xFF2F6FED);

  int step = 1; // 1 = email, 2 = otp, 3 = new password

  final emailController = TextEditingController();
  final otpController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  String? errorText;
  Timer? _otpTimer;
int remainingSeconds = 300; // 5 minutes

  @override
void dispose() {
  emailController.dispose();
  otpController.dispose();
  newPasswordController.dispose();
  confirmPasswordController.dispose();
  _otpTimer?.cancel();
  super.dispose();
}

  void _showError(String msg) {
    setState(() => errorText = msg);
  }
  void _startOtpTimer() {
  _otpTimer?.cancel();
  setState(() => remainingSeconds = 300);
  _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (remainingSeconds == 0) {
      timer.cancel();
    } else {
      setState(() => remainingSeconds--);
    }
  });
}

String get _formattedTime {
  final minutes = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (remainingSeconds % 60).toString().padLeft(2, '0');
  return "$minutes:$seconds";
}

  Future<void> _sendOtp() async {
    if (emailController.text.trim().isEmpty) {
      _showError("Please enter your email");
      return;
    }
    setState(() {
      isLoading = true;
      errorText = null;
    });
    try {
      final response = await ApiService.forgotPassword(emailController.text.trim());
      if (response.statusCode == 200) {
        setState(() => step = 2);
        _startOtpTimer();
      } else {
        _showError(jsonDecode(response.body)["message"] ?? "Failed to send OTP");
      }
    } catch (e) {
      _showError("Something went wrong: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (otpController.text.trim().isEmpty) {
      _showError("Please enter the OTP");
      return;
    }
    setState(() {
      isLoading = true;
      errorText = null;
    });
    try {
      final response = await ApiService.verifyOtp(
        emailController.text.trim(),
        otpController.text.trim(),
      );
      if (response.statusCode == 200) {
        setState(() => step = 3);
      } else {
        _showError(jsonDecode(response.body)["message"] ?? "Invalid OTP");
      }
    } catch (e) {
      _showError("Something went wrong: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (newPasswordController.text.trim().isEmpty ||
        confirmPasswordController.text.trim().isEmpty) {
      _showError("Please fill both password fields");
      return;
    }
    if (newPasswordController.text.trim() != confirmPasswordController.text.trim()) {
      _showError("Passwords do not match");
      return;
    }
    setState(() {
      isLoading = true;
      errorText = null;
    });
    try {
      final response = await ApiService.resetPassword(
        emailController.text.trim(),
        otpController.text.trim(),
        newPasswordController.text.trim(),
      );
      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password reset successful. Please login.")),
        );
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        _showError(jsonDecode(response.body)["message"] ?? "Failed to reset password");
      }
    } catch (e) {
      _showError("Something went wrong: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  InputDecoration _decoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF3F5FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryBlue,
        title: const Text("Forgot Password"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (step == 1) ...[
                const Text("Enter your registered email",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _decoration("Email", Icons.email_outlined),
                ),
              ],
              if (step == 2) ...[
                const Text("Enter the OTP sent to your email",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  decoration: _decoration("6-digit OTP", Icons.lock_clock_outlined),
                ),
                const SizedBox(height: 12),
Text(
  remainingSeconds > 0
      ? "OTP expires in $_formattedTime"
      : "OTP expired",
  style: TextStyle(
    color: remainingSeconds > 0 ? Colors.black54 : Colors.red,
    fontSize: 13,
  ),
),
const SizedBox(height: 8),
Align(
  alignment: Alignment.centerRight,
  child: TextButton(
    onPressed: remainingSeconds == 0 && !isLoading ? _sendOtp : null,
    child: const Text("Resend OTP"),
  ),
),
              ],
              if (step == 3) ...[
                const Text("Set your new password",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: _decoration("New Password", Icons.lock_outline),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: _decoration("Confirm Password", Icons.lock_outline),
                ),
              ],
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isLoading
                      ? null
                      : () {
                          if (step == 1) _sendOtp();
                          if (step == 2) _verifyOtp();
                          if (step == 3) _resetPassword();
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(
                          step == 1
                              ? "Send OTP"
                              : step == 2
                                  ? "Verify OTP"
                                  : "Reset Password",
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}