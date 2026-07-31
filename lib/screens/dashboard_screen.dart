import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:employee_tracker_app/services/api_service.dart';
import 'package:employee_tracker_app/screens/login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:employee_tracker_app/screens/employee_profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const DashboardScreen({
    super.key,
    required this.user,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _ActivityItem {
  final String title;
  final String time;
  final bool isLogin;

  _ActivityItem({
    required this.title,
    required this.time,
    required this.isLogin,
  });
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const primaryBlue = Color(0xFF2F6FED);
  static const darkBlue = Color(0xFF1E4FB8);
  static const cardRadius = 16.0;
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  bool isTracking = false;
  double todaysDistanceKm = 0.0;
  Position? currentPosition;
  DateTime? lastUpdated;
  bool insideGeofence = true;
  int geofenceMeters = 200;
  List<Map<String, dynamic>> nearbyPlaces = [];
  bool isLoadingPlaces = false;
  String? nearbyPlacesError;
  List<ll.LatLng> myTodayRoute = [];
  String myRouteDuration = "--";
  final MapController liveMapController = MapController();
  List<Map<String, dynamic>> myTodayStops = [];
  bool isLoadingMyStops = false;
  List<Map<String, dynamic>> adminAllStops = [];
  bool isLoadingAdminStops = false;
  bool isStopsExpanded = false;
  List<Map<String, dynamic>> manualStops = [];
  List<Map<String, dynamic>> myManualStops = [];
  bool isLoadingMyManualStops = false;
  bool isLoadingManualStops = false;
  bool isSubmittingManualStop = false;

  // ---- Employees ----
  List<Map<String, dynamic>> allEmployees = [];
  bool isLoadingEmployees = false;
  bool isEmployeesExpanded = false;
  bool isAddingEmployee = false;
  String? employeesError;
  final MapController employeesMapController = MapController();
  Map<String, dynamic>? viewedEmployee;

  // ---- Role + Report ----
  String? userRole;
  List<Map<String, dynamic>> reportStops = [];
  List<Map<String, dynamic>> reportTrackingSessions = [];
  List<ll.LatLng> reportRoute = [];
  String reportRouteDuration = "--";
  List<Map<String, dynamic>> sessionAddresses = [];
  bool isTimelineExpanded = false;
  bool isStoppageExpanded = false;
  Map<String, dynamic>? reportSummary;
  bool isLoadingReport = false;
  String? reportError;
  int? selectedEmployeeId;
  String? selectedEmployeeName;
  DateTime selectedReportDate = DateTime.now();
  bool isExporting = false;

  Timer? _trackingTimer;
  Timer? _adminRefreshTimer;

  final List<_ActivityItem> activityTimeline = [];

  static String _formatNow() {
    final now = DateTime.now();
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? "PM" : "AM";
    return "${now.month}/${now.day}/${now.year}, $hour12:$minute $ampm";
  }

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
    _fetchUserRole();
    _fetchMyTodayStops();
    _fetchMyTodayRoute();
    _fetchMyManualStops();

    final isAdmin = widget.user["role"] == "ADMIN";
    activityTimeline.add(
      _ActivityItem(
        title: isAdmin ? "Login - Admin logged in" : "Login - Employee logged in",
        time: _formatNow(),
        isLogin: true,
      ),
    );
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _adminRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();

      if (!mounted) return;
      setState(() {
        currentPosition = position;
        lastUpdated = DateTime.now();
      });
    } catch (e) {
      print("Location Error: $e");
    }
  }
  Future<void> _refreshMapLocation() async {
    await _fetchCurrentLocation();
    if (currentPosition == null) return;
    liveMapController.move(
      ll.LatLng(currentPosition!.latitude, currentPosition!.longitude),
      16,
    );
  }

  Future<void> _fetchNearbyPlaces() async {
    if (currentPosition == null) {
      await _fetchCurrentLocation();
      if (currentPosition == null) {
        setState(() {
          nearbyPlacesError =
              "Could not get your current location. Please enable location and try again.";
        });
        return;
      }
    }

    setState(() {
      isLoadingPlaces = true;
      nearbyPlacesError = null;
    });

    try {
      final lat = currentPosition!.latitude;
      final lon = currentPosition!.longitude;
      final radius = geofenceMeters > 500 ? geofenceMeters : 1000;

      final query = """
        [out:json];
        (
          node["amenity"="school"](around:$radius,$lat,$lon);
          way["amenity"="school"](around:$radius,$lat,$lon);
          node["amenity"="college"](around:$radius,$lat,$lon);
          way["amenity"="college"](around:$radius,$lat,$lon);
          node["amenity"="university"](around:$radius,$lat,$lon);
          way["amenity"="university"](around:$radius,$lat,$lon);
        );
        out center 40;
      """;

      http.Response? response;
      Object? lastError;

      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          response = await http
              .post(
                Uri.parse("https://overpass-api.de/api/interpreter"),
                headers: {
                  "Content-Type": "application/x-www-form-urlencoded",
                  "Accept": "application/json",
                  "User-Agent": "employee_tracker_app/1.0",
                },
                body: {"data": query},
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) break;

          if (response.statusCode == 504 || response.statusCode == 429) {
            lastError = "status ${response.statusCode}";
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }

          break;
        } catch (e) {
          lastError = e;
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (response == null) {
        throw lastError ?? Exception("Failed to reach Overpass API");
      }
      final finalResponse = response;

      if (finalResponse.statusCode == 200) {
        final data = jsonDecode(finalResponse.body);
        final elements = data["elements"] as List;

        final places = elements
            .where((e) =>
                e["tags"] != null &&
                e["tags"]["name"] != null &&
                (e["lat"] != null || e["center"] != null))
            .map((e) => {
                  "name": e["tags"]["name"],
                  "type": e["tags"]["amenity"] ?? e["tags"]["shop"] ?? "place",
                  "lat": e["lat"] ?? e["center"]?["lat"],
                  "lon": e["lon"] ?? e["center"]?["lon"],
                })
            .toList();

        if (!mounted) return;
        setState(() {
          nearbyPlaces = List<Map<String, dynamic>>.from(places);
          isLoadingPlaces = false;
          if (nearbyPlaces.isEmpty) {
            nearbyPlacesError = "No nearby places found in this radius.";
          }
        });
      } else {
        print("Nearby Places Error Status: ${finalResponse.statusCode}");
        print("Nearby Places Error Body: ${finalResponse.body}");
        if (!mounted) return;
        setState(() {
          isLoadingPlaces = false;
          nearbyPlacesError =
              "Failed to load places (status ${finalResponse.statusCode}). Try again.";
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        isLoadingPlaces = false;
        nearbyPlacesError =
            "Request timed out. Check your internet and try again.";
      });
    } catch (e) {
      print("Nearby Places Error: $e");
      if (!mounted) return;
      setState(() {
        isLoadingPlaces = false;
        nearbyPlacesError = "Something went wrong: $e";
      });
    }
  }

  void _showNearbyPlacesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: nearbyPlaces.length,
              itemBuilder: (context, index) {
                final place = nearbyPlaces[index];
                return ListTile(
                  leading: const Icon(Icons.place, color: Colors.redAccent),
                  title: Text(place["name"]),
                  subtitle: Text(place["type"]),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.black38, size: 20),
                  onTap: () => _openInGoogleMaps(
                    place["lat"],
                    place["lon"],
                    place["name"],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
  Future<void> _openInGoogleMaps(double lat, double lon, String label) async {
    final url = Uri.parse(
        "https://www.google.com/maps/search/?api=1&query=$lat,$lon");
    try {
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not open maps for $label")),
        );
      }
    } catch (e) {
      print("Open Maps Error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not open maps for $label")),
      );
    }
  }

  // ---- Employees ----
  Future<void> _fetchAllEmployees() async {
    setState(() => isLoadingEmployees = true);
    try {
      final response = await ApiService.getAllEmployees();

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final employees = data.map((e) {
          final status = e["status"]; // ONLINE, MOVING, STOPPED, OFFLINE
          return {
            "id": e["id"],
            "fullName": e["fullName"],
            "isOnline": status == "ONLINE" || status == "MOVING",
            "lat": e["latitude"],
            "lon": e["longitude"],
          };
        }).toList();

        if (!mounted) return;
        setState(() {
          allEmployees = List<Map<String, dynamic>>.from(employees);
          isLoadingEmployees = false;
          employeesError = null;
        });
      } else if (response.statusCode == 401) {
        await _handleSessionExpired();
      } else {
        print("Employees Error Status: ${response.statusCode}");
        print("Employees Error Body: ${response.body}");
        if (!mounted) return;
        setState(() {
          isLoadingEmployees = false;
          employeesError = "Status ${response.statusCode}: ${response.body}";
        });
      }
    } catch (e) {
      print("Employees Fetch Error: $e");
      if (!mounted) return;
      setState(() {
        isLoadingEmployees = false;
        employeesError = "Something went wrong: $e";
      });
    }
  }
  Future<void> _fetchMyTodayStops() async {
    setState(() => isLoadingMyStops = true);
    try {
      final response = await ApiService.getTodayStops();

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> resolved = [];

        for (final stop in data) {
          final lat = stop["latitude"];
          final lon = stop["longitude"];
          String address = "Unknown";

          if (lat != null && lon != null) {
            try {
              final geoResponse = await http
                  .get(
                    Uri.parse(
                        "https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon"),
                    headers: {"User-Agent": "employee_tracker_app"},
                  )
                  .timeout(const Duration(seconds: 10));
              if (geoResponse.statusCode == 200) {
                final geoData = jsonDecode(geoResponse.body);
                address = geoData["display_name"] ?? "Unknown";
              }
            } catch (e) {
              print("My Stop Geocode Error: $e");
            }
          }

          resolved.add({
            "startTime": stop["startTime"],
            "endTime": stop["endTime"],
            "durationMinutes": stop["durationMinutes"],
            "ongoing": stop["ongoing"],
            "address": address,
          });
        }

        if (!mounted) return;
        setState(() {
          myTodayStops = resolved;
          isLoadingMyStops = false;
        });
      } else {
        if (!mounted) return;
        setState(() => isLoadingMyStops = false);
      }
    } catch (e) {
      print("My Today Stops Error: $e");
      if (!mounted) return;
      setState(() => isLoadingMyStops = false);
    }
  }
  String _computeDuration(List<ll.LatLng> points, List<DateTime> times) {
    if (times.length < 2) return "--";
    final duration = times.last.difference(times.first);
    if (duration.isNegative) return "--";
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return "${hours.toString().padLeft(2, '0')} hr ${minutes.toString().padLeft(2, '0')} min";
  }

  Future<void> _fetchMyTodayRoute() async {
    try {
      final response = await ApiService.getLocationHistory();

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final List<ll.LatLng> points = [];
        final List<DateTime> times = [];

        for (final loc in data) {
          final lat = loc["latitude"];
          final lon = loc["longitude"];
          final recordedAt = DateTime.tryParse(loc["recordedAt"]?.toString() ?? "");
          if (lat != null && lon != null && recordedAt != null) {
            points.add(ll.LatLng(lat, lon));
            times.add(recordedAt);
          }
        }

        if (!mounted) return;
        setState(() {
          myTodayRoute = points;
          myRouteDuration = _computeDuration(points, times);
        });
      } else if (response.statusCode == 401) {
        await _handleSessionExpired();
      }
    } catch (e) {
      print("My Route Fetch Error: $e");
    }
  }
  Future<void> _fetchAdminTodayStops() async {
    setState(() => isLoadingAdminStops = true);
    try {
      final response = await ApiService.getAllStopsToday();

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> resolved = [];

        for (final stop in data) {
          final lat = stop["latitude"];
          final lon = stop["longitude"];
          String address = "Unknown";

          if (lat != null && lon != null) {
            try {
              final geoResponse = await http
                  .get(
                    Uri.parse(
                        "https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon"),
                    headers: {"User-Agent": "employee_tracker_app"},
                  )
                  .timeout(const Duration(seconds: 10));
              if (geoResponse.statusCode == 200) {
                final geoData = jsonDecode(geoResponse.body);
                address = geoData["display_name"] ?? "Unknown";
              }
            } catch (e) {
              print("Admin Stop Geocode Error: $e");
            }
          }

          resolved.add({
            "employeeName": stop["employeeName"],
            "startTime": stop["startTime"],
            "endTime": stop["endTime"],
            "durationMinutes": stop["durationMinutes"],
            "ongoing": stop["ongoing"],
            "address": address,
          });
        }

        if (!mounted) return;
        setState(() {
          adminAllStops = resolved;
          isLoadingAdminStops = false;
        });
      } else {
        print("Admin Stops Error Status: ${response.statusCode}");
        print("Admin Stops Error Body: ${response.body}");
        if (!mounted) return;
        setState(() => isLoadingAdminStops = false);
      }
    } catch (e) {
      print("Admin Stops Fetch Error: $e");
      if (!mounted) return;
      setState(() => isLoadingAdminStops = false);
    }
  }
  Future<void> _fetchManualStops() async {
    setState(() => isLoadingManualStops = true);
    try {
      final response = await ApiService.getManualStops();
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          manualStops = List<Map<String, dynamic>>.from(data);
          isLoadingManualStops = false;
        });
      } else {
        if (!mounted) return;
        setState(() => isLoadingManualStops = false);
      }
    } catch (e) {
      print("Manual Stops Fetch Error: $e");
      if (!mounted) return;
      setState(() => isLoadingManualStops = false);
    }
  }
  Future<void> _fetchMyManualStops() async {
    setState(() => isLoadingMyManualStops = true);
    try {
      final response = await ApiService.getMyManualStops();
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          myManualStops = List<Map<String, dynamic>>.from(data);
          isLoadingMyManualStops = false;
        });
      } else {
        if (!mounted) return;
        setState(() => isLoadingMyManualStops = false);
      }
    } catch (e) {
      print("My Manual Stops Fetch Error: $e");
      if (!mounted) return;
      setState(() => isLoadingMyManualStops = false);
    }
  }

  Future<void> _showAddManualStopDialog({Map<String, dynamic>? existing}) async {
    DateTime selectedDate = DateTime.now();
    TimeOfDay? startTime;
    TimeOfDay? endTime;

    if (existing != null) {
      final d = DateTime.tryParse(existing["date"]?.toString() ?? "");
      if (d != null) selectedDate = d;
      final s = DateTime.tryParse(existing["startTime"]?.toString() ?? "");
      if (s != null) startTime = TimeOfDay(hour: s.hour, minute: s.minute);
      final e = DateTime.tryParse(existing["endTime"]?.toString() ?? "");
      if (e != null) endTime = TimeOfDay(hour: e.hour, minute: e.minute);
    }

    final addressController =
        TextEditingController(text: existing?["address"] ?? "");
    final reasonController =
        TextEditingController(text: existing?["reason"] ?? "");

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title:
                  Text(existing == null ? "Add Missed Stop" : "Edit Stop"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2024, 1, 1),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 16, color: primaryBlue),
                          const SizedBox(width: 8),
                          Text(
                              "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: startTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => startTime = picked);
                        }
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: 16, color: primaryBlue),
                          const SizedBox(width: 8),
                          Text(startTime == null
                              ? "Select Start Time"
                              : "Start: ${startTime!.format(context)}"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: endTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => endTime = picked);
                        }
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_filled,
                              size: 16, color: primaryBlue),
                          const SizedBox(width: 8),
                          Text(endTime == null
                              ? "Select End Time"
                              : "End: ${endTime!.format(context)}"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(
                          labelText: "Location / Address"),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                          labelText: "Reason (why you forgot to track)"),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: primaryBlue),
                  onPressed: isSubmittingManualStop
                      ? null
                      : () async {
                          if (startTime == null || endTime == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      "Please select start and end time")),
                            );
                            return;
                          }

                          setDialogState(() => isSubmittingManualStop = true);

                          final dateStr =
                              "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";
                          final startStr =
                              "${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}:00";
                          final endStr =
                              "${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}:00";

                          final fields = {
                            "date": dateStr,
                            "startTime": startStr,
                            "endTime": endStr,
                            "address": addressController.text.trim(),
                            "reason": reasonController.text.trim(),
                          };

                          try {
                            final response = existing == null
                                ? await ApiService.addManualStop(fields)
                                : await ApiService.updateManualStop(
                                    existing["id"], fields);

                            if (!mounted) return;

                            if (response.statusCode == 200) {
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(existing == null
                                        ? "Stop added successfully"
                                        : "Stop updated successfully")),
                              );
                              _fetchMyManualStops();
                            } else {
                              setDialogState(
                                  () => isSubmittingManualStop = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        "Failed to save (status ${response.statusCode})")),
                              );
                            }
                          } catch (e) {
                            setDialogState(
                                () => isSubmittingManualStop = false);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e")),
                            );
                          }
                        },
                  child: isSubmittingManualStop
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(existing == null ? "Submit" : "Update",
                          style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _fetchUserRole() async {
    try {
      final response = await ApiService.getCurrentUser();
      print("ROLE CHECK STATUS: ${response.statusCode}  BODY: ${response.body}");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() => userRole = data["role"]);

        if (userRole == "ADMIN") {
          _fetchAllEmployees();
          _fetchAdminTodayStops();
          _fetchManualStops();
          _adminRefreshTimer?.cancel();
          _adminRefreshTimer = Timer.periodic(
              const Duration(seconds: 15), (_) => _fetchAllEmployees());
        }
      } else if (response.statusCode == 401) {
        await _handleSessionExpired();
      }
    } catch (e) {
      print("Role Fetch Error: $e");
    }
  }

  Future<void> _fetchReport(int employeeId, String employeeName) async {
    setState(() {
      isLoadingReport = true;
      selectedEmployeeId = employeeId;
      selectedEmployeeName = employeeName;
      reportStops = [];
      reportTrackingSessions = [];
      bool isTimelineExpanded = false;
      reportSummary = null;
      reportError = null;
    });

    try {
      final dateStr =
          "${selectedReportDate.year}-${selectedReportDate.month.toString().padLeft(2, '0')}-${selectedReportDate.day.toString().padLeft(2, '0')}";

      final response =
          await ApiService.getReport(employeeId: employeeId, date: dateStr);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          reportSummary = {
            "totalDistanceKm": data["totalDistanceKm"],
            "trackingStartCount": data["trackingStartCount"],
            "trackingStopCount": data["trackingStopCount"],
            "loginTime": data["loginTime"],
            "logoutTime": data["logoutTime"],
          };
        });

        final List<dynamic> stops = data["stops"] ?? [];
        final List<Map<String, dynamic>> resolvedStops = [];

        for (final stop in stops) {
          final lat = stop["latitude"];
          final lon = stop["longitude"];
          String address = "Unknown";
          String pincode = "--";

          if (lat != null && lon != null) {
            try {
              final geoResponse = await http
                  .get(
                    Uri.parse(
                        "https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon"),
                    headers: {"User-Agent": "employee_tracker_app"},
                  )
                  .timeout(const Duration(seconds: 10));
              if (geoResponse.statusCode == 200) {
                final geoData = jsonDecode(geoResponse.body);
                address = geoData["display_name"] ?? "Unknown";
                pincode = geoData["address"]?["postcode"] ?? "--";
              }
            } catch (e) {
              print("Geocode Error: $e");
            }
          }

          resolvedStops.add({
            "startTime": stop["startTime"],
            "endTime": stop["endTime"],
            "durationMinutes": stop["durationMinutes"],
            "ongoing": stop["ongoing"],
            "address": address,
            "pincode": pincode,
          });
        }

        final List<dynamic> sessions = data["trackingSessions"] ?? [];
        final List<Map<String, dynamic>> resolvedSessions = sessions
            .map((s) => {
                  "startTime": s["startTime"],
                  "endTime": s["endTime"],
                  "ongoing": s["ongoing"],
                })
            .toList();
            final List<dynamic> locationsRaw = data["locations"] ?? [];
            final List<ll.LatLng> routePoints = [];
        final List<DateTime> routeTimes = [];
        for (final loc in locationsRaw) {
          final lat = loc["latitude"];
          final lon = loc["longitude"];
          final recordedAt = DateTime.tryParse(loc["recordedAt"]?.toString() ?? "");
          if (lat != null && lon != null && recordedAt != null) {
            routePoints.add(ll.LatLng(lat, lon));
            routeTimes.add(recordedAt);
          }
        }
        final List<Map<String, dynamic>> resolvedSessionAddresses = [];

        for (final session in sessions) {
          final sessionStart = DateTime.tryParse(
              session["startTime"]?.toString() ?? "");
          if (sessionStart == null) continue;

          // find the location point closest in time to this session's start
          Map<String, dynamic>? nearest;
          Duration? nearestDiff;
          for (final loc in locationsRaw) {
            final locTime =
                DateTime.tryParse(loc["recordedAt"]?.toString() ?? "");
            if (locTime == null) continue;
            final diff = locTime.difference(sessionStart).abs();
            if (nearestDiff == null || diff < nearestDiff) {
              nearestDiff = diff;
              nearest = loc;
            }
          }

          String address = "Unknown";
          String pincode = "--";

          if (nearest != null &&
              nearest["latitude"] != null &&
              nearest["longitude"] != null) {
            try {
              final geoResponse = await http
                  .get(
                    Uri.parse(
                        "https://nominatim.openstreetmap.org/reverse?format=json&lat=${nearest["latitude"]}&lon=${nearest["longitude"]}"),
                    headers: {"User-Agent": "employee_tracker_app"},
                  )
                  .timeout(const Duration(seconds: 10));
              if (geoResponse.statusCode == 200) {
                final geoData = jsonDecode(geoResponse.body);
                address = geoData["display_name"] ?? "Unknown";
                pincode = geoData["address"]?["postcode"] ?? "--";
              }
            } catch (e) {
              print("Session Geocode Error: $e");
            }
          }

          resolvedSessionAddresses.add({
            "startTime": session["startTime"],
            "endTime": session["endTime"],
            "ongoing": session["ongoing"],
            "address": address,
            "pincode": pincode,
          });
        }

        if (!mounted) return;
        setState(() {
          reportStops = resolvedStops;
          reportTrackingSessions = resolvedSessions;
          sessionAddresses = resolvedSessionAddresses;
          reportRoute = routePoints;                              // <-- add
          reportRouteDuration = _computeDuration(routePoints, routeTimes);
          isLoadingReport = false;
        });
      } else {
        print("Report Error Status: ${response.statusCode}");
        print("Report Error Body: ${response.body}");
        if (!mounted) return;
        setState(() {
          isLoadingReport = false;
          reportError = "Status ${response.statusCode}: ${response.body}";
        });
      }
    } catch (e) {
      print("Report Fetch Error: $e");
      if (!mounted) return;
      setState(() {
        isLoadingReport = false;
        reportError = "Something went wrong: $e";
      });
    }
  }

  void _toggleTracking() async {
    setState(() {
      isTracking = !isTracking;
    });

    if (isTracking) {
      try {
        final res = await ApiService.startTracking();
print("START TRACKING STATUS: ${res.statusCode}  BODY: ${res.body}");
      } catch (e) {
        print("Start Tracking Error: $e");
      }

      activityTimeline.insert(
        0,
        _ActivityItem(
          title: "Tracking started",
          time: _formatNow(),
          isLogin: true,
        ),
      );

      await _trackAndSendLocation();
      _trackingTimer = Timer.periodic(
          const Duration(seconds: 15), (_) => _trackAndSendLocation());
    } else {
      try {
        final res = await ApiService.stopTracking();
print("STOP TRACKING STATUS: ${res.statusCode}  BODY: ${res.body}");
      } catch (e) {
        print("Stop Tracking Error: $e");
      }

      activityTimeline.insert(
        0,
        _ActivityItem(
          title: "Tracking stopped",
          time: _formatNow(),
          isLogin: false,
        ),
      );
      _trackingTimer?.cancel();
    }
  }

  Future<void> _trackAndSendLocation() async {
  await _fetchCurrentLocation();
  if (currentPosition == null) return;
  try {
    final res = await ApiService.saveLocation(
      latitude: currentPosition!.latitude,
      longitude: currentPosition!.longitude,
    );
    print("SAVE LOCATION STATUS: ${res.statusCode}  BODY: ${res.body}");
    await _fetchMyTodayRoute();
  } catch (e) {
    print("Save Location Error: $e");
  }
}

  Future<void> _handleLogout() async {
    try {
      await ApiService.logout();
    } catch (e) {
      print("Logout Error: $e");
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("saved_user");
    await prefs.remove("session_cookie");

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _handleViewEmployee(Map<String, dynamic> emp) {
    setState(() {
      viewedEmployee = emp;
      isEmployeesExpanded = false;
    });

    if (emp["lat"] != null && emp["lon"] != null) {
      employeesMapController.move(
        ll.LatLng(emp["lat"], emp["lon"]),
        15,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "No location data available yet for ${emp["fullName"] ?? "this employee"}."),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  Future<void> _confirmDeleteEmployee(Map<String, dynamic> emp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Employee"),
        content: Text(
            "Are you sure you want to delete ${emp["fullName"] ?? "this employee"}? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await ApiService.deleteEmployee(emp["id"]);
      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${emp["fullName"]} deleted successfully")),
        );
        _fetchAllEmployees();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text("Failed to delete (status ${response.statusCode})")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }
  Future<void> _showAddEmployeeDialog() async {
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    final departmentController = TextEditingController();
    final designationController = TextEditingController();
    final mobileController = TextEditingController();
    final addressController = TextEditingController();
    DateTime? joiningDate;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Add Employee"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(labelText: "Full Name *"),
                    ),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: "Email *"),
                    ),
                    TextField(
                      controller: departmentController,
                      decoration: const InputDecoration(labelText: "Department"),
                    ),
                    TextField(
                      controller: designationController,
                      decoration: const InputDecoration(labelText: "Designation"),
                    ),
                    TextField(
                      controller: mobileController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: "Mobile"),
                    ),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: "Address"),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000, 1, 1),
                          lastDate: DateTime(2100, 12, 31),
                        );
                        if (picked != null) {
                          setDialogState(() => joiningDate = picked);
                        }
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 16, color: primaryBlue),
                          const SizedBox(width: 8),
                          Text(
                            joiningDate == null
                                ? "Joining Date (optional)"
                                : "${joiningDate!.year}-${joiningDate!.month.toString().padLeft(2, '0')}-${joiningDate!.day.toString().padLeft(2, '0')}",
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: primaryBlue),
                  onPressed: isAddingEmployee
                      ? null
                      : () async {
                          if (fullNameController.text.trim().isEmpty ||
                              emailController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text("Full name and email are required")),
                            );
                            return;
                          }

                          setDialogState(() => isAddingEmployee = true);

                          final fields = <String, dynamic>{
                            "fullName": fullNameController.text.trim(),
                            "email": emailController.text.trim(),
                            if (departmentController.text.trim().isNotEmpty)
                              "department": departmentController.text.trim(),
                            if (designationController.text.trim().isNotEmpty)
                              "designation": designationController.text.trim(),
                            if (mobileController.text.trim().isNotEmpty)
                              "mobile": mobileController.text.trim(),
                            if (addressController.text.trim().isNotEmpty)
                              "address": addressController.text.trim(),
                            if (joiningDate != null)
                              "joiningDate":
                                  "${joiningDate!.year}-${joiningDate!.month.toString().padLeft(2, '0')}-${joiningDate!.day.toString().padLeft(2, '0')}",
                          };

                          try {
                            final response = await ApiService.addEmployee(fields);
                            if (!mounted) return;

                            if (response.statusCode == 200) {
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        "Employee added. Credentials sent via email.")),
                              );
                              _fetchAllEmployees();
                            } else {
                              setDialogState(() => isAddingEmployee = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        "Failed to add employee (status ${response.statusCode})")),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isAddingEmployee = false);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e")),
                            );
                          }
                        },
                  child: isAddingEmployee
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text("Add", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationText = currentPosition != null
        ? "${currentPosition!.latitude.toStringAsFixed(5)}, ${currentPosition!.longitude.toStringAsFixed(5)}"
        : "--";

    final lastUpdatedText =
        lastUpdated != null ? _formatDateTime(lastUpdated!) : "--";

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FB),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchCurrentLocation,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---------- Header ----------
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryBlue, darkBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.location_on,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Employee Location Tracker",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(cardRadius),
                    boxShadow: cardShadow,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EmployeeProfileScreen(),
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 14,
                                backgroundColor: Color(0xFFEAEFFD),
                                child: Icon(Icons.person,
                                    size: 16, color: primaryBlue),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  "Welcome, ${widget.user["fullName"] ?? ""}",
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _handleLogout,
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text("Logout"),
                        style: TextButton.styleFrom(
                          foregroundColor: primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),

                // ---------- Stat cards ----------
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.5,
                    children: [
                      _buildStatusCard(),
                      _buildStatCard(
                        icon: Icons.route_outlined,
                        label: "TODAY'S DISTANCE",
                        value: "${todaysDistanceKm.toStringAsFixed(2)} km",
                      ),
                      _buildStatCard(
                        icon: Icons.my_location,
                        label: "CURRENT LOCATION",
                        value: locationText,
                        valueFontSize: 11,
                      ),
                      _buildStatCard(
                        icon: Icons.access_time,
                        label: "LAST UPDATED",
                        value: lastUpdatedText,
                        valueFontSize: 11,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ---------- Live Map section ----------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(cardRadius),
                      boxShadow: cardShadow,
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.map_outlined,
                                      color: primaryBlue, size: 18),
                                  const SizedBox(width: 6),
                                  const Text(
                                    "Live Map",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (myTodayRoute.length > 1)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: primaryBlue.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "Traveled: $myRouteDuration",
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: primaryBlue,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _fetchNearbyPlaces,
                                    icon: const Icon(Icons.my_location,
                                        size: 16, color: primaryBlue),
                                    label: const Text("Near Me"),
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      side: const BorderSide(
                                          color: primaryBlue, width: 1.2),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _refreshMapLocation,
                                    icon: const Icon(Icons.refresh,
                                        size: 18, color: Colors.white),
                                    tooltip: "Refresh Location",
                                    style: IconButton.styleFrom(
                                      backgroundColor: primaryBlue,
                                      padding: const EdgeInsets.all(8),
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                  // ---- Geofence dropdown styled as a textbox ----
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6F7FB),
                                      border: Border.all(
                                          color: const Color(0xFFE1E4ED)),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int>(
                                        value: geofenceMeters,
                                        icon: const Icon(
                                            Icons.arrow_drop_down,
                                            color: primaryBlue),
                                        items: const [200, 500, 1000]
                                            .map(
                                              (m) => DropdownMenuItem(
                                                value: m,
                                                child:
                                                    Text("Geofence: ${m}m"),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (value) {
                                          if (value != null) {
                                            setState(() {
                                              geofenceMeters = value;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: insideGeofence
                                          ? const Color(0xFF1E8449)
                                          : Colors.redAccent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      insideGeofence
                                          ? "Inside Geofence"
                                          : "Outside Geofence",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Map placeholder area
                        // Live Map
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(cardRadius)),
                          child: SizedBox(
                            height: 260,
                            width: double.infinity,
                            child: currentPosition == null
                                ? const Center(
                                    child: Text("Fetching location..."))
                                : FlutterMap(
                                    mapController: liveMapController,
                                    options: MapOptions(
                                      initialCenter: ll.LatLng(
                                        currentPosition!.latitude,
                                        currentPosition!.longitude,
                                      ),
                                      initialZoom: 16,
                                    ),
                                    children: [
                                      TileLayer(
                                        urlTemplate:
                                            "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                                        userAgentPackageName:
                                            "com.employeetracker.employee_tracker_app",
                                      ),
                                      CircleLayer(
                                        circles: [
                                          CircleMarker(
                                            point: ll.LatLng(
                                              currentPosition!.latitude,
                                              currentPosition!.longitude,
                                            ),
                                            radius: geofenceMeters.toDouble(),
                                            useRadiusInMeter: true,
                                            color: Colors.green
                                                .withOpacity(0.15),
                                            borderColor: Colors.green,
                                            borderStrokeWidth: 1.5,
                                          ),
                                        ],
                                      ),
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: ll.LatLng(
                                              currentPosition!.latitude,
                                              currentPosition!.longitude,
                                            ),
                                            width: 40,
                                            height: 40,
                                            child: const Icon(
                                              Icons.navigation,
                                              color: primaryBlue,
                                              size: 34,
                                            ),
                                            
                                          ),
                                          
                                        ],
                                        
                                      ),
                                      MarkerLayer(
                                        markers: nearbyPlaces.map((place) {
                                          return Marker(
                                            point: ll.LatLng(
                                                place["lat"], place["lon"]),
                                            width: 30,
                                            height: 30,
                                            child: const Icon(
                                              Icons.place,
                                              color: Colors.redAccent,
                                              size: 28,
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                      PolylineLayer(
                                      polylines: [
                                        Polyline(
                                          points: myTodayRoute,
                                          strokeWidth: 4,
                                          color: primaryBlue,
                                        ),
                                      ],
                                    ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ---------- Nearby Places summary card ----------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(cardRadius),
                      boxShadow: cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.place_outlined,
                                      color: primaryBlue, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      isLoadingPlaces
                                          ? "Loading nearby places..."
                                          : "Nearby Places (${nearbyPlaces.length} found)",
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: nearbyPlaces.isEmpty
                                  ? null
                                  : _showNearbyPlacesSheet,
                              style: TextButton.styleFrom(
                                  foregroundColor: primaryBlue),
                              child: const Text("View"),
                            ),
                          ],
                        ),
                        if (nearbyPlacesError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            nearbyPlacesError!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ---------- Today's Activity Timeline ----------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(cardRadius),
                      boxShadow: cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timeline_outlined,
                                color: primaryBlue, size: 18),
                            const SizedBox(width: 6),
                            const Text(
                              "Today's Activity Timeline",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ...activityTimeline.map(
                          (item) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.only(left: 12),
                            decoration: const BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: primaryBlue,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  item.isLogin
                                      ? Icons.lock_open
                                      : Icons.lock,
                                  size: 16,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        item.time,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                
                // ---------- Today's Stops ----------
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(cardRadius),
                      boxShadow: cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() {
                                    isStopsExpanded = !isStopsExpanded;
                                  });
                                },
                                child: Row(
                                  children: const [
                                    Icon(Icons.pause_circle_outline,
                                        color: primaryBlue, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      "Today's Stops",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (userRole != "ADMIN")
                              IconButton(
                                onPressed: _showAddManualStopDialog,
                                icon: const Icon(Icons.add_circle_outline,
                                    color: primaryBlue, size: 20),
                                tooltip: "Add missed stop",
                              ),
                            
                            if ((userRole == "ADMIN" &&
                                    adminAllStops.isNotEmpty) ||
                                (userRole != "ADMIN" &&
                                    myTodayStops.isNotEmpty))
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    if (userRole == "ADMIN") {
                                      adminAllStops = [];
                                    } else {
                                      myTodayStops = [];
                                    }
                                  });
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                ),
                                child: const Text("Clear"),
                              ),
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                setState(() {
                                  isStopsExpanded = !isStopsExpanded;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  isStopsExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: primaryBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isStopsExpanded) ...[
                        const SizedBox(height: 10),
                        if (userRole == "ADMIN") ...[
                          if (isLoadingAdminStops)
                            const Text(
                              "Loading...",
                              style: TextStyle(
                                  fontSize: 14, color: Colors.black54),
                            ),
                          if (!isLoadingAdminStops && adminAllStops.isEmpty)
                            const Text(
                              "No stops detected yet today.",
                              style: TextStyle(
                                  fontSize: 14, color: Colors.black54),
                            ),
                          if (!isLoadingAdminStops && adminAllStops.isNotEmpty)
                            ...adminAllStops.map(
                              (stop) => Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F7FB),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.person,
                                            size: 14, color: primaryBlue),
                                        const SizedBox(width: 6),
                                        Text(
                                          stop["employeeName"] ?? "--",
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time,
                                            size: 14,
                                            color: Colors.black45),
                                        const SizedBox(width: 6),
                                        Text(
                                          "${_formatIsoTime(stop["startTime"])} - ${stop["ongoing"] == true ? "Ongoing" : _formatIsoTime(stop["endTime"])}",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          "(${stop["durationMinutes"] ?? 0} min)",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                            Icons.location_on_outlined,
                                            size: 14,
                                            color: Colors.black45),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            stop["address"] ?? "--",
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (!isLoadingManualStops &&
                              manualStops.isNotEmpty)
                            ...manualStops.map(
                              (stop) => Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.orange.withOpacity(0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.person,
                                            size: 14, color: primaryBlue),
                                        const SizedBox(width: 6),
                                        Text(
                                          stop["employeeName"] ?? "--",
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange
                                                .withOpacity(0.2),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            "Manual",
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.deepOrange,
                                                fontWeight:
                                                    FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.event,
                                            size: 14,
                                            color: Colors.black45),
                                        const SizedBox(width: 6),
                                        Text(
                                          "${stop["date"]}",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time,
                                            size: 14,
                                            color: Colors.black45),
                                        const SizedBox(width: 6),
                                        Text(
                                          "${_formatIsoTime(stop["startTime"])} - ${_formatIsoTime(stop["endTime"])}",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          "(${stop["durationMinutes"] ?? 0} min)",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                    if ((stop["address"] ?? "")
                                        .toString()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                              Icons.location_on_outlined,
                                              size: 14,
                                              color: Colors.black45),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              stop["address"],
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54),
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if ((stop["reason"] ?? "")
                                        .toString()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.info_outline,
                                              size: 14,
                                              color: Colors.black45),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              "Reason: ${stop["reason"]}",
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54,
                                                  fontStyle:
                                                      FontStyle.italic),
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ] else ...[
                          if (isLoadingMyStops)
                            const Text(
                              "Loading...",
                              style: TextStyle(
                                  fontSize: 14, color: Colors.black54),
                            ),
                          if (!isLoadingMyStops && myTodayStops.isEmpty)
                            const Text(
                              "No stops detected yet today.",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                              ),
                            ),
                          if (!isLoadingMyStops && myTodayStops.isNotEmpty)
                            ...myTodayStops.map(
                              (stop) => Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F7FB),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time,
                                            size: 14, color: primaryBlue),
                                        const SizedBox(width: 6),
                                        Text(
                                          "${_formatIsoTime(stop["startTime"])} - ${stop["ongoing"] == true ? "Ongoing" : _formatIsoTime(stop["endTime"])}",
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          "(${stop["durationMinutes"] ?? 0} min)",
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                            Icons.location_on_outlined,
                                            size: 14,
                                            color: Colors.black45),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            stop["address"] ?? "--",
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                              ),
                            ),
                          ),
                          if (!isLoadingMyManualStops &&
                              myManualStops.isNotEmpty)
                            ...myManualStops.map(
                              (stop) => Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.orange.withOpacity(0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange
                                                .withOpacity(0.2),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            "Manual",
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.deepOrange,
                                                fontWeight:
                                                    FontWeight.w600),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () =>
                                              _showAddManualStopDialog(
                                                  existing: stop),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.edit_outlined,
                                                  size: 14,
                                                  color: primaryBlue),
                                              SizedBox(width: 4),
                                              Text(
                                                "Edit",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: primaryBlue,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.event,
                                            size: 14,
                                            color: Colors.black45),
                                        const SizedBox(width: 6),
                                        Text(
                                          "${stop["date"]}",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time,
                                            size: 14,
                                            color: Colors.black45),
                                        const SizedBox(width: 6),
                                        Text(
                                          "${_formatIsoTime(stop["startTime"])} - ${_formatIsoTime(stop["endTime"])}",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          "(${stop["durationMinutes"] ?? 0} min)",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                    if ((stop["address"] ?? "")
                                        .toString()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                              Icons.location_on_outlined,
                                              size: 14,
                                              color: Colors.black45),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              stop["address"],
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54),
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if ((stop["reason"] ?? "")
                                        .toString()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.info_outline,
                                              size: 14,
                                              color: Colors.black45),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              "Reason: ${stop["reason"]}",
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54,
                                                  fontStyle:
                                                      FontStyle.italic),
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ],
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                if (userRole == "ADMIN") ...[
                  // ---------- Employees list (expand/collapse) ----------
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(cardRadius),
                        boxShadow: cardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    setState(() {
                                      isEmployeesExpanded =
                                          !isEmployeesExpanded;
                                    });
                                  },
                                  child: Row(
                                    children: const [
                                      Icon(Icons.groups_outlined,
                                          color: primaryBlue, size: 18),
                                      SizedBox(width: 6),
                                      Text(
                                        "Employees",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _showAddEmployeeDialog,
                                icon: const Icon(Icons.person_add_alt_1,
                                    color: primaryBlue, size: 20),
                                tooltip: "Add Employee",
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  setState(() {
                                    isEmployeesExpanded =
                                        !isEmployeesExpanded;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    isEmployeesExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: primaryBlue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isEmployeesExpanded) ...[
                            const SizedBox(height: 8),
                            if (isLoadingEmployees)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  "Loading...",
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ),
                            if (!isLoadingEmployees && employeesError != null)
                              Text(
                                "Error: $employeesError",
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 12),
                              ),
                            if (!isLoadingEmployees &&
                                employeesError == null &&
                                allEmployees.isEmpty)
                              const Text(
                                "No employees found.",
                                style: TextStyle(color: Colors.black54),
                              ),
                            if (!isLoadingEmployees &&
                                allEmployees.isNotEmpty)
                              ...allEmployees.map(
                                (emp) => Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                          color: Color(0xFFF0F1F5)),
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 2),
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: emp["isOnline"] == true
                                          ? Colors.green.withOpacity(0.15)
                                          : Colors.grey.withOpacity(0.2),
                                      child: Icon(
                                        Icons.person,
                                        size: 16,
                                        color: emp["isOnline"] == true
                                            ? Colors.green[700]
                                            : Colors.black45,
                                      ),
                                    ),
                                    title: Text(
                                      emp["fullName"] ?? "",
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      emp["isOnline"] == true
                                          ? "Online"
                                          : "Offline",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: emp["isOnline"] == true
                                            ? Colors.green[700]
                                            : Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton(
                                          onPressed: () =>
                                              _handleViewEmployee(emp),
                                          style: TextButton.styleFrom(
                                            foregroundColor: primaryBlue,
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8),
                                          ),
                                          child: const Text("View"),
                                        ),
                                        IconButton(
                                          onPressed: () =>
                                              _confirmDeleteEmployee(emp),
                                          icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.redAccent,
                                              size: 20),
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints(),
                                          tooltip: "Delete",
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ---------- Employees status map ----------
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(cardRadius),
                        boxShadow: cardShadow,
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.map_outlined,
                                        color: primaryBlue, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      "Employees Map",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                if (viewedEmployee != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6F7FB),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 10,
                                          color:
                                              viewedEmployee!["isOnline"] ==
                                                      true
                                                  ? Colors.green
                                                  : Colors.grey,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          "${viewedEmployee!["fullName"]} - ${viewedEmployee!["isOnline"] == true ? "Online" : "Offline"}",
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (reportRoute.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    "Route duration: $reportRouteDuration",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: primaryBlue,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(cardRadius)),
                            child: SizedBox(
                              height: 260,
                              width: double.infinity,
                              child: FlutterMap(
                                mapController: employeesMapController,
                                options: MapOptions(
                                  initialCenter: currentPosition != null
                                      ? ll.LatLng(
                                          currentPosition!.latitude,
                                          currentPosition!.longitude,
                                        )
                                      : const ll.LatLng(20.5937, 78.9629),
                                  initialZoom: 4,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                                    userAgentPackageName:
                                        "com.employeetracker.employee_tracker_app",
                                  ),
                                  MarkerLayer(
                                    markers: allEmployees
                                        .where((e) =>
                                            e["lat"] != null &&
                                            e["lon"] != null)
                                        .map(
                                          (e) => Marker(
                                            point: ll.LatLng(
                                                e["lat"], e["lon"]),
                                            width: 30,
                                            height: 30,
                                            child: Icon(
                                              Icons.person_pin_circle,
                                              color: e["isOnline"] == true
                                                  ? Colors.green
                                                  : Colors.grey,
                                              size: 30,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                  PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: reportRoute,
                                      strokeWidth: 4,
                                      color: Colors.orange,
                                    ),
                                  ],
                                ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // ---------- Admin only: Employee Report ----------
                if (userRole == "ADMIN") ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(cardRadius),
                        boxShadow: cardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.assignment_outlined,
                                  color: primaryBlue, size: 18),
                              SizedBox(width: 6),
                              Text(
                                "Employee Report",
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // ---- Select Employee + Report Date ----
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Select Employee",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF6F7FB),
                                        border: Border.all(
                                            color: const Color(0xFFE1E4ED)),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<int>(
                                          hint: const Text("Choose"),
                                          value: selectedEmployeeId,
                                          isExpanded: true,
                                          items: allEmployees
                                              .where((e) => e["id"] != null)
                                              .map((e) => DropdownMenuItem<int>(
                                                    value: e["id"],
                                                    child: Text(
                                                        e["fullName"] ?? ""),
                                                  ))
                                              .toList(),
                                          onChanged: (value) {
                                            if (value != null) {
                                              final emp = allEmployees
                                                  .firstWhere((e) =>
                                                      e["id"] == value);
                                              _fetchReport(
                                                  value, emp["fullName"] ?? "");
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Report Date",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    InkWell(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      onTap: _pickReportDate,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF6F7FB),
                                          border: Border.all(
                                              color:
                                                  const Color(0xFFE1E4ED)),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment
                                                  .spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                _formatReportDate(
                                                    selectedReportDate),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                            const Icon(
                                              Icons.calendar_today_outlined,
                                              size: 16,
                                              color: primaryBlue,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // ---- Employee info row ----
                          if (selectedEmployeeId != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF6F7FB),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.person,
                                          size: 16, color: primaryBlue),
                                      const SizedBox(width: 6),
                                      Text(
                                        selectedEmployeeName ?? "--",
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.badge_outlined,
                                          size: 16, color: primaryBlue),
                                      const SizedBox(width: 6),
                                      Text(
                                        "ID: $selectedEmployeeId",
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.circle,
                                        size: 10,
                                        color: allEmployees.any((e) =>
                                                    e["id"] ==
                                                        selectedEmployeeId &&
                                                e["isOnline"] == true)
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        allEmployees.any((e) =>
                                                e["id"] == selectedEmployeeId &&
                                                e["isOnline"] == true)
                                            ? "Online"
                                            : "Offline",
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],

                          if (isLoadingReport) ...[
                            const SizedBox(height: 16),
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: CircularProgressIndicator(
                                    color: primaryBlue),
                              ),
                            ),
                          ],

                          if (!isLoadingReport && reportError != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                "Error: $reportError",
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 12),
                              ),
                            ),
                          ],

                          // ---- Summary Cards (2x2 grid) ----
                          if (!isLoadingReport && reportSummary != null) ...[
                            const SizedBox(height: 18),
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.35,
                              children: [
                                _summaryStatCard(
                                  icon: Icons.route_outlined,
                                  label: "Distance",
                                  value:
                                      "${(reportSummary!["totalDistanceKm"] ?? 0).toStringAsFixed(2)} km",
                                ),
                                _summaryStatCard(
                                  icon: Icons.play_circle_outline,
                                  label: "Starts",
                                  value:
                                      "${reportSummary!["trackingStartCount"] ?? 0}",
                                ),
                                _summaryStatCard(
                                  icon: Icons.pause_circle_outline,
                                  label: "Stops",
                                  value:
                                      "${reportSummary!["trackingStopCount"] ?? 0}",
                                ),
                                _summaryStatCard(
                                  icon: Icons.timer_outlined,
                                  label: "Working Time",
                                  value: _calculateWorkingTime(),
                                ),
                              ],
                            ),
                            // ---- Activity Overview Chart ----
                            const SizedBox(height: 18),
                            if (!isLoadingReport && reportSummary != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F7FB),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(Icons.bar_chart_rounded,
                                            color: primaryBlue, size: 18),
                                        SizedBox(width: 6),
                                        Text(
                                          "Activity Overview",
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: SizedBox(
                                            height: 140,
                                            child: BarChart(
                                              BarChartData(
                                                alignment:
                                                    BarChartAlignment.spaceAround,
                                                maxY: _chartMaxY(),
                                                barTouchData:
                                                    BarTouchData(enabled: false),
                                                titlesData: FlTitlesData(
                                                  leftTitles: const AxisTitles(
                                                      sideTitles: SideTitles(
                                                          showTitles: false)),
                                                  rightTitles: const AxisTitles(
                                                      sideTitles: SideTitles(
                                                          showTitles: false)),
                                                  topTitles: const AxisTitles(
                                                      sideTitles: SideTitles(
                                                          showTitles: false)),
                                                  bottomTitles: AxisTitles(
                                                    sideTitles: SideTitles(
                                                      showTitles: true,
                                                      getTitlesWidget:
                                                          (value, meta) {
                                                        const labels = [
                                                          "Starts",
                                                          "Stops"
                                                        ];
                                                        final idx =
                                                            value.toInt();
                                                        if (idx < 0 ||
                                                            idx >=
                                                                labels.length) {
                                                          return const SizedBox();
                                                        }
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(top: 6),
                                                          child: Text(
                                                            labels[idx],
                                                            style: const TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .black54),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                gridData:
                                                    const FlGridData(show: false),
                                                borderData:
                                                    FlBorderData(show: false),
                                                barGroups: [
                                                  BarChartGroupData(
                                                    x: 0,
                                                    barRods: [
                                                      BarChartRodData(
                                                        toY: (reportSummary![
                                                                    "trackingStartCount"] ??
                                                                0)
                                                            .toDouble(),
                                                        color: primaryBlue,
                                                        width: 28,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                      ),
                                                    ],
                                                  ),
                                                  BarChartGroupData(
                                                    x: 1,
                                                    barRods: [
                                                      BarChartRodData(
                                                        toY: (reportSummary![
                                                                    "trackingStopCount"] ??
                                                                0)
                                                            .toDouble(),
                                                        color: const Color(
                                                            0xFFEF6C4D),
                                                        width: 28,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            children: [
                                              SizedBox(
                                                height: 90,
                                                width: 90,
                                                child: Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    CircularProgressIndicator(
                                                      value:
                                                          _workingTimeProgress(),
                                                      strokeWidth: 8,
                                                      backgroundColor:
                                                          const Color(
                                                              0xFFE1E4ED),
                                                      color: primaryBlue,
                                                    ),
                                                    Text(
                                                      "${(_workingTimeProgress() * 100).toStringAsFixed(0)}%",
                                                      style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                "of 8 hr day",
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.black54),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                            // ---- Today's Timeline ----
                            const SizedBox(height: 22),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() {
                                  isTimelineExpanded = !isTimelineExpanded;
                                });
                              },
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.timeline_outlined,
                                          color: primaryBlue, size: 18),
                                      SizedBox(width: 6),
                                      Text(
                                        "Today's Timeline",
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  Icon(
                                    isTimelineExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: primaryBlue,
                                  ),
                                ],
                              ),
                            ),
                            if (isTimelineExpanded) ...[
                              const SizedBox(height: 12),
                              Builder(
                                builder: (context) {
                                  final events = _buildReportTimeline();
                                  if (events.isEmpty) {
                                    return Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF6F7FB),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        "No activity recorded today.",
                                        style: TextStyle(
                                            color: Colors.black54,
                                            fontSize: 13),
                                      ),
                                    );
                                  }
                                  return Column(
                                    children: [
                                      for (int i = 0; i < events.length; i++)
                                        _timelineEventTile(events[i],
                                            i == events.length - 1),
                                    ],
                                  );
                                },
                              ),
                            ],

                            // ---- Stoppage Details ----
                            const SizedBox(height: 10),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() {
                                  isStoppageExpanded = !isStoppageExpanded;
                                });
                              },
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.table_chart_outlined,
                                          color: primaryBlue, size: 18),
                                      SizedBox(width: 6),
                                      Text(
                                        "Stoppage Details",
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  Icon(
                                    isStoppageExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: primaryBlue,
                                  ),
                                ],
                              ),
                            ),
                            if (isStoppageExpanded) ...[
                            const SizedBox(height: 10),
                            if (sessionAddresses.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F7FB),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  "No stops recorded today.",
                                  style: TextStyle(
                                      color: Colors.black54, fontSize: 13),
                                ),
                              ),
                            if (sessionAddresses.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowColor:
                                        WidgetStateProperty.all(
                                            const Color(0xFFF6F7FB)),
                                    columns: const [
                                      DataColumn(label: Text("Start Time")),
                                      DataColumn(label: Text("End Time")),
                                      DataColumn(
                                          label: Text("Address with Area")),
                                      DataColumn(label: Text("Pincode")),
                                    ],
                                    rows: sessionAddresses
                                        .map(
                                          (row) => DataRow(cells: [
                                            DataCell(Text(_formatIsoTime(
                                                row["startTime"]))),
                                            DataCell(Text(row["ongoing"] ==
                                                    true
                                                ? "Ongoing"
                                                : _formatIsoTime(
                                                    row["endTime"]))),
                                            DataCell(SizedBox(
                                              width: 180,
                                              child: Text(
                                                row["address"] ?? "--",
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                maxLines: 2,
                                              ),
                                            )),
                                            DataCell(
                                                Text(row["pincode"] ?? "--")),
                                          ]),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                            ],

                            // ---- Bottom Actions ----
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: isExporting ? null : _exportPdf, 
                                    icon: const Icon(
                                        Icons.picture_as_pdf_outlined,
                                        size: 18,
                                        color: primaryBlue),
                                    label: const Text("Export PDF"),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: primaryBlue,
                                      side: const BorderSide(
                                          color: primaryBlue, width: 1.2),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: isExporting ? null : _exportExcel,
                                    icon: const Icon(Icons.table_view_outlined,
                                        size: 18, color: Colors.white),
                                    label: const Text("Export Excel"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryBlue,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(cardRadius),
        boxShadow: cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.wifi_tethering,
                size: 12,
                color: isTracking ? Colors.green[700] : Colors.black38,
              ),
              const SizedBox(width: 4),
              const Text(
                "STATUS",
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.black45,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isTracking
                  ? Colors.green.withOpacity(0.15)
                  : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isTracking ? "ONLINE" : "OFFLINE",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isTracking ? Colors.green[800] : Colors.black54,
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 28,
            child: ElevatedButton.icon(
              onPressed: _toggleTracking,
              icon: Icon(
                isTracking ? Icons.stop : Icons.play_arrow,
                size: 13,
                color: Colors.white,
              ),
              label: Text(
                isTracking ? "Stop" : "Start",
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isTracking ? Colors.redAccent : const Color(0xFF1E8449),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 0),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    double valueFontSize = 14,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(cardRadius),
        boxShadow: cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: primaryBlue),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.black45,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: primaryBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        "$label: $value",
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    return "${dt.month}/${dt.day}/${dt.year}, $hour12:$minute $ampm";
  }
  Widget _summaryStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: primaryBlue),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineEventTile(Map<String, dynamic> event, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              _formatIsoTime(event["time"]),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(event["icon"] as IconData,
                    size: 14, color: primaryBlue),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: const Color(0xFFE1E4ED),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: Text(
                event["title"] as String,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatIsoTime(dynamic isoValue) {
    if (isoValue == null) return "--";
    final dt = DateTime.tryParse(isoValue.toString());
    if (dt == null) return "--";
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    return "$hour12:$minute $ampm";
  }

  String _calculateWorkingTime() {
    if (reportSummary == null) return "--";
    final loginRaw = reportSummary!["loginTime"];
    if (loginRaw == null) return "--";
    final login = DateTime.tryParse(loginRaw.toString());
    if (login == null) return "--";

    final logoutRaw = reportSummary!["logoutTime"];
    final logout =
        logoutRaw != null ? DateTime.tryParse(logoutRaw.toString()) : null;
    final end = logout ?? DateTime.now();

    final duration = end.difference(login);
    if (duration.isNegative) return "--";

    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return "${hours.toString().padLeft(2, '0')} hr ${minutes.toString().padLeft(2, '0')} min";
  }
  Future<void> _handleSessionExpired() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("saved_user");
    await prefs.remove("session_cookie");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Session expired. Please login again.")),
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }
  String _pdfSafeText(String? input) {
    if (input == null) return "--";
    return input.replaceAll(RegExp(r'[^\x00-\x7F]'), '');
  }
  double _workingMinutes() {
    if (reportSummary == null) return 0;
    final loginRaw = reportSummary!["loginTime"];
    if (loginRaw == null) return 0;
    final login = DateTime.tryParse(loginRaw.toString());
    if (login == null) return 0;

    final logoutRaw = reportSummary!["logoutTime"];
    final logout =
        logoutRaw != null ? DateTime.tryParse(logoutRaw.toString()) : null;
    final end = logout ?? DateTime.now();

    final duration = end.difference(login);
    if (duration.isNegative) return 0;
    return duration.inMinutes.toDouble();
  }

  double _workingTimeProgress() {
    const fullDayMinutes = 8 * 60;
    final minutes = _workingMinutes();
    final progress = minutes / fullDayMinutes;
    return progress.clamp(0.0, 1.0);
  }

  double _chartMaxY() {
    final starts =
        (reportSummary?["trackingStartCount"] ?? 0).toDouble();
    final stops = (reportSummary?["trackingStopCount"] ?? 0).toDouble();
    final maxVal = starts > stops ? starts : stops;
    return maxVal <= 0 ? 4.0 : maxVal * 1.3;
  }
  Future<void> _exportExcel() async {
    if (selectedEmployeeId == null) return;
    setState(() => isExporting = true);
    try {
      final dateStr =
          "${selectedReportDate.year}-${selectedReportDate.month.toString().padLeft(2, '0')}-${selectedReportDate.day.toString().padLeft(2, '0')}";

      final response = await ApiService.exportReportExcel(
        employeeId: selectedEmployeeId!,
        date: dateStr,
      );

      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final fileName =
            "report_${selectedEmployeeName ?? 'employee'}_$dateStr.xlsx"
                .replaceAll(" ", "_");
        final file = File("${dir.path}/$fileName");
        await file.writeAsBytes(response.bodyBytes);

        await Share.shareXFiles([XFile(file.path)],
            text: "Employee Report - ${selectedEmployeeName ?? ''}");
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Failed to export (status ${response.statusCode})")),
        );
      }
    } catch (e) {
      print("Export Excel Error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Export failed: $e")),
      );
    } finally {
      if (mounted) setState(() => isExporting = false);
    }
  }

  Future<void> _exportPdf() async {
    if (selectedEmployeeId == null) return;
    setState(() => isExporting = true);
    try {
      final doc = pw.Document();
      final isOnline = allEmployees.any((e) =>
          e["id"] == selectedEmployeeId && e["isOnline"] == true);
      final dateStr =
          "${selectedReportDate.day}/${selectedReportDate.month}/${selectedReportDate.year}";
      final events = _buildReportTimeline();

      doc.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Text("Employee Report",
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text("Date: $dateStr"),
            pw.SizedBox(height: 12),
            pw.Text(
                "Employee: ${_pdfSafeText(selectedEmployeeName)}   |   ID: $selectedEmployeeId   |   Status: ${isOnline ? 'Online' : 'Offline'}"),
            pw.SizedBox(height: 16),
            pw.Text("Summary",
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Bullet(
                text:
                    "Distance: ${(reportSummary?["totalDistanceKm"] ?? 0).toStringAsFixed(2)} km"),
            pw.Bullet(
                text: "Starts: ${reportSummary?["trackingStartCount"] ?? 0}"),
            pw.Bullet(
                text: "Stops: ${reportSummary?["trackingStopCount"] ?? 0}"),
            pw.Bullet(text: "Working Time: ${_calculateWorkingTime()}"),
            pw.SizedBox(height: 16),
            pw.Text("Today's Timeline",
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (events.isEmpty) pw.Text("No activity recorded today."),
            if (events.isNotEmpty)
              pw.Table.fromTextArray(
                headers: ["Time", "Event"],
                data: events
                    .map((e) => [
                          _formatIsoTime(e["time"]),
                          e["title"].toString(),
                        ])
                    .toList(),
              ),
            pw.SizedBox(height: 16),
            pw.Text("Stoppage Details",
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (sessionAddresses.isEmpty)
              pw.Text("No stops recorded today."),
            if (sessionAddresses.isNotEmpty)
              pw.Table.fromTextArray(
                headers: [
                  "Start Time",
                  "End Time",
                  "Address with Area",
                  "Pincode"
                ],
                data: sessionAddresses
                    .map((row) => [
                          _formatIsoTime(row["startTime"]),
                          row["ongoing"] == true
                              ? "Ongoing"
                              : _formatIsoTime(row["endTime"]),
                          _pdfSafeText(row["address"]),
                          _pdfSafeText(row["pincode"]),
                        ])
                    .toList(),
              ),
          ],
        ),
      );

      final safeFileDate =
          "${selectedReportDate.year}-${selectedReportDate.month.toString().padLeft(2, '0')}-${selectedReportDate.day.toString().padLeft(2, '0')}";

      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            "report_${selectedEmployeeName ?? 'employee'}_$safeFileDate.pdf"
                .replaceAll(" ", "_")
                .replaceAll("/", "-"),
      );
    } catch (e) {
      print("Export PDF Error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("PDF export failed: $e")),
      );
    } finally {
      if (mounted) setState(() => isExporting = false);
    }
  }

  List<Map<String, dynamic>> _buildReportTimeline() {
    final List<Map<String, dynamic>> events = [];

    if (reportSummary != null && reportSummary!["loginTime"] != null) {
      events.add({
        "time": reportSummary!["loginTime"],
        "title": "Login",
        "icon": Icons.login,
      });
    }

    for (final session in reportTrackingSessions) {
      if (session["startTime"] != null) {
        events.add({
          "time": session["startTime"],
          "title": "Tracking Started",
          "icon": Icons.play_circle_outline,
        });
      }
      if (session["ongoing"] != true && session["endTime"] != null) {
        events.add({
          "time": session["endTime"],
          "title": "Tracking Stopped",
          "icon": Icons.pause_circle_outline,
        });
      }
    }

    if (reportSummary != null && reportSummary!["logoutTime"] != null) {
      events.add({
        "time": reportSummary!["logoutTime"],
        "title": "Logout",
        "icon": Icons.logout,
      });
    }

    events.sort((a, b) {
      final da = DateTime.tryParse(a["time"].toString()) ?? DateTime.now();
      final db = DateTime.tryParse(b["time"].toString()) ?? DateTime.now();
      return da.compareTo(db);
    });

    return events;
  }
  Future<void> _pickReportDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedReportDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryBlue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        selectedReportDate = picked;
      });
      if (selectedEmployeeId != null) {
        _fetchReport(selectedEmployeeId!, selectedEmployeeName ?? "");
      }
    }
  }

  String _formatReportDate(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    if (isToday) return "Today";

    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    return "${date.day} ${months[date.month - 1]} ${date.year}";
  }
}