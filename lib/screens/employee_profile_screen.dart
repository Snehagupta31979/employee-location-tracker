import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:employee_tracker_app/services/api_service.dart';

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({super.key});

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  static const primaryBlue = Color(0xFF2F6FED);

  bool isLoading = true;
  String? error;
  Map<String, dynamic>? profile;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() {
      isLoading = true;
      error = null;
    });
    try {
      final response = await ApiService.getProfile();
      if (response.statusCode == 200) {
        setState(() {
          profile = jsonDecode(response.body);
          isLoading = false;
        });
      } else {
        setState(() {
          error = "Failed to load profile (status ${response.statusCode})";
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = "Something went wrong: $e";
        isLoading = false;
      });
    }
  }

  Future<void> _editField(String key, String label, String? currentValue) async {
    final controller = TextEditingController(text: currentValue ?? "");

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(currentValue == null || currentValue.isEmpty
              ? "Add $label"
              : "Edit $label"),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: label),
            keyboardType: key == "mobile"
                ? TextInputType.phone
                : TextInputType.text,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text("Save", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return;

    try {
      final response = await ApiService.updateProfile({key: result});
      if (response.statusCode == 200) {
        setState(() {
          profile = jsonDecode(response.body);
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save (status ${response.statusCode})")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save: $e")),
      );
    }
  }
  Future<void> _editDateField(String key, String label, String? currentValue) async {
    DateTime initialDate = DateTime.now();
    if (currentValue != null && currentValue.isNotEmpty) {
      final parsed = DateTime.tryParse(currentValue);
      if (parsed != null) initialDate = parsed;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: primaryBlue),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    final isoDate =
        "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";

    try {
      final response = await ApiService.updateProfile({key: isoDate});
      if (response.statusCode == 200) {
        setState(() {
          profile = jsonDecode(response.body);
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save (status ${response.statusCode})")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save: $e")),
      );
    }
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return "?";
    final parts = name.trim().split(RegExp(r"\s+"));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  String _formatDisplayDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return "";
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return isoDate;
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FB),
      appBar: AppBar(
        backgroundColor: primaryBlue,
        title: const Text("Profile"),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryBlue))
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchProfile,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: CircleAvatar(
                            radius: 44,
                            backgroundColor: primaryBlue.withOpacity(0.15),
                            child: Text(
                              _initials(profile?["fullName"]),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: primaryBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            profile?["fullName"] ?? "--",
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Center(
                          child: Text(
                            profile?["designation"] ?? "--",
                            style: const TextStyle(
                                fontSize: 14, color: Colors.black54),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: profile?["status"] == "Active"
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.grey.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle,
                                    size: 8,
                                    color: profile?["status"] == "Active"
                                        ? Colors.green
                                        : Colors.grey),
                                const SizedBox(width: 6),
                                Text(profile?["status"] ?? "--",
                                    style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _profileCard([
                          _fieldRow(Icons.badge_outlined, "Employee ID",
                              profile?["employeeCode"], null, false),
                          _fieldRow(Icons.apartment_outlined, "Department",
                              profile?["department"], "department", true),
                          _fieldRow(Icons.work_outline, "Designation",
                              profile?["designation"], "designation", true),
                          _fieldRow(
                              Icons.event_outlined,
                              "Joining Date",
                              _formatDisplayDate(profile?["joiningDate"]),
                              "joiningDate",
                              true),
                        ]),
                        const SizedBox(height: 16),
                        _profileCard([
                          _fieldRow(Icons.phone_outlined, "Mobile",
                              profile?["mobile"], "mobile", true),
                          _fieldRow(Icons.email_outlined, "Email",
                              profile?["email"], null, false),
                          _fieldRow(Icons.home_outlined, "Address",
                              profile?["address"], "address", true),
                        ]),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _profileCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }

  Widget _fieldRow(IconData icon, String label, String? value,
      String? editKey, bool editable) {
    final hasValue = value != null && value.toString().trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F1F5))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black45)),
                const SizedBox(height: 2),
                Text(
                  hasValue ? value.toString() : "Not added",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: hasValue ? Colors.black87 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          if (editable)
            TextButton(
              onPressed: () => editKey == "joiningDate"
                  ? _editDateField(editKey!, label, value?.toString())
                  : _editField(editKey!, label, value?.toString()),
              child: Text(hasValue ? "Edit" : "+ Add"),
            ),
        ],
      ),
    );
  }
}