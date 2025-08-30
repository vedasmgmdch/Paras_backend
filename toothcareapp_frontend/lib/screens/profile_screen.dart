import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/api_service.dart';
import 'welcome_screen.dart'; // <-- Adjust this path if needed!
import '../auth_callbacks.dart';
import 'calendar_screen.dart';


class ProfileScreen extends StatelessWidget {
  final VoidCallback? onCheckRecoveryCalendar; // For Calendar tab switch
  final VoidCallback? onViewCareInstructions;  // For Instructions tab switch

  const ProfileScreen({
    super.key,
    this.onCheckRecoveryCalendar,
    this.onViewCareInstructions,
  });

  // --- Fixed sign out method ---
  Future<void> _signOut(BuildContext context) async {
    final appState = Provider.of<AppState>(context, listen: false);
    await ApiService.clearToken();
    await appState.reset();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => WelcomeScreen(),
        ),
            (route) => false,
      );
    });
  }

  // Utility for parsing time string to TimeOfDay
  static TimeOfDay? _parseTimeOfDay(dynamic timeStr) {
    if (timeStr == null) return null;
    final str = timeStr is String ? timeStr : timeStr.toString();
    final parts = str.split(":");
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final patientId = "#1";
    final fullName = appState.fullName ?? "Not specified";
    final dob = appState.dob != null
        ? "${appState.dob!.day}/${appState.dob!.month}/${appState.dob!.year}"
        : "Not specified";
    final gender = appState.gender ?? "Not specified";
    final username = appState.username ?? "Not specified";
    final phone = appState.phone ?? "Not specified";
    final email = appState.email ?? "Not specified";
    final procedureDate = appState.procedureDate;
    final today = DateTime.now();
    final recoveryDay = procedureDate != null
        ? (today
        .difference(DateTime(procedureDate.year, procedureDate.month, procedureDate.day))
        .inDays +
        1)
        : 0;

    final dosList = [
      ...appState.currentDos,
      "Eat soft cold foods for at least 2 days.",
      "Use warm salt water rinse as instructed.",
      "Eat your medicine as prescribed by your dentist.",
      "Drink plenty of fluids (without using a straw).",
      "Take medicines as prescribed by your doctor."
    ];
    final checks = appState.getChecklistForDate(today);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // --- Sign Out Button at top right ---
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 18),
                        ),
                        icon: const Icon(Icons.exit_to_app),
                        label: const Text(
                          "Sign Out",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _signOut(context),
                      ),
                    ),
                  ),
                  // Header
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(22),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Patient Profile',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        SizedBox(height: 6),
                        Text(
                          "Your recovery information",
                          style: TextStyle(fontSize: 15, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  // Personal Information Card
                  Card(
                    margin: const EdgeInsets.only(bottom: 20),
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.person_outline, color: Color(0xFF2196F3)),
                                  SizedBox(width: 8),
                                  Text('Personal Information',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () {
                                  _showEditBottomSheet(context, appState);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Icon(Icons.account_circle, size: 54, color: Colors.blueGrey),
                          const SizedBox(height: 8),
                          Text(fullName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                          Text('Patient ID: $patientId',
                              style: const TextStyle(color: Colors.grey, fontSize: 15)),
                          const SizedBox(height: 16),

                          _infoTile(Icons.badge, 'Full Name', fullName, Colors.blue[50]!),
                          _infoTile(Icons.cake, 'Date of Birth', dob, Colors.blue[50]!),
                          _infoTile(Icons.person, 'Gender', gender, Colors.blue[50]!),
                          _infoTile(Icons.account_circle, 'Username', username, Colors.blue[50]!),
                          _infoTile(Icons.phone, 'Phone', phone, Colors.blue[50]!),
                          _infoTile(Icons.email, 'Email', email, Colors.blue[50]!, isEmail: true),
                          const SizedBox(height: 16),
                          _infoTile(
                            Icons.calendar_today,
                            'Procedure Date',
                            procedureDate != null
                                ? "${procedureDate.day}/${procedureDate.month}/${procedureDate.year}"
                                : "-",
                            const Color(0xFFE8F0FE),
                          ),
                          _infoTile(
                            Icons.bar_chart,
                            'Recovery Day',
                            "Day $recoveryDay",
                            const Color(0xFFFFF6E5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Emergency Contact
                  _buildEmergencyContact(),
                  // Today's Checklist
                  _buildChecklist(dosList, checks),
                  // Quick Actions
                  _buildQuickActions(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _showEditBottomSheet(BuildContext context, AppState appState) {
    final nameController = TextEditingController(text: appState.fullName ?? "");
    final emailController = TextEditingController(text: appState.email ?? "");
    final phoneController = TextEditingController(text: appState.phone ?? "");
    String gender = appState.gender ?? "Not specified";
    DateTime? selectedDob = appState.dob;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Edit Personal Information",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Full Name"),
                  ),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: "Email"),
                  ),
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(labelText: "Phone"),
                  ),
                  DropdownButtonFormField<String>(
                    value: (gender != "Not specified") ? gender : null,
                    items: const ["Male", "Female", "Other"]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    decoration: const InputDecoration(labelText: "Gender"),
                    onChanged: (val) {
                      setState(() {
                        gender = val ?? "Not specified";
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        selectedDob != null
                            ? "DOB: ${selectedDob!.day}/${selectedDob!.month}/${selectedDob!.year}"
                            : "Select DOB",
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: selectedDob ?? DateTime(2000),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setState(() {
                              selectedDob = date;
                            });
                          }
                        },
                        child: const Text("Pick Date"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      appState.updatePersonalInfo(
                        fullName: nameController.text,
                        email: emailController.text,
                        phone: phoneController.text,
                        gender: gender,
                        dob: selectedDob,
                      );
                      Navigator.pop(ctx);
                    },
                    child: const Text("Save"),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
        );
      },
    );
  }

  static Widget _infoTile(IconData icon, String label, String value, Color color, {bool isEmail = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: isEmail ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.blueGrey[700], size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500, fontSize: 15)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 15),
              overflow: TextOverflow.visible,
              softWrap: true,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildEmergencyContact() {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.local_phone, color: Colors.redAccent),
                SizedBox(width: 8),
                Text("Emergency Contact",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE6E6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Dental Office",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                          fontSize: 16)),
                  const SizedBox(height: 4),
                  Row(
                    children: const [
                      Icon(Icons.phone, size: 18, color: Colors.redAccent),
                      SizedBox(width: 6),
                      // Not const because of TextStyle
                      Text("022-27433404 , 022-27437992", style: TextStyle(fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: const [
                      Icon(Icons.email, size: 18, color: Colors.redAccent),
                      SizedBox(width: 6),
                      // Not const because of TextStyle
                      Text("mgmmcnb@gmail.com", style: TextStyle(fontSize: 15)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Call immediately if you experience:",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              "• Severe pain not relieved by medication\n"
                  "• Excessive bleeding after 24 hours\n"
                  "• Signs of infection (fever, pus, severe swelling)\n"
                  "• Numbness lasting more than 24 hours",
              style: TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklist(List<String> dosList, List<bool> checks) {
    // Compute completion status inside the function
    final allCompleted = checks.isNotEmpty && checks.every((c) => c);

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Today's Checklist",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 14),
            ...List.generate(dosList.length, (i) {
              final checked = i < checks.length ? checks[i] : false;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Icon(
                      checked ? Icons.check_box : Icons.check_box_outline_blank,
                      color: checked ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dosList[i],
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              );
            }),
            // --- New warning message after last checklist item ---
            const SizedBox(height: 12),
            if (!allCompleted)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDEDED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    // Red exclamation icon
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.red,
                      child: const Icon(Icons.error_outline, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Please Complete Your Today's Checklist By Clicking On View Care Instructions, If Not Completed.",
                        style: TextStyle(
                          color: Colors.red[800],
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Quick Actions",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  if (onViewCareInstructions != null) {
                    onViewCareInstructions!();
                  } else {
                    // fallback navigation if desired
                    // (replace with your instructions screen navigation if needed)
                  }
                },
                child: const Text("View Care Instructions",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  if (onCheckRecoveryCalendar != null) {
                    onCheckRecoveryCalendar!();
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CalendarScreen()),
                    );
                  }
                },
                child: const Text("Check Recovery Calendar",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}