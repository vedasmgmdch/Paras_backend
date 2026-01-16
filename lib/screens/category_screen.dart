import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import 'package:http/http.dart' as http;
import '../app_state.dart';
import 'treatment_screen.dart';
import 'welcome_screen.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  // If this screen has instruction checklists, add log saving logic as in other instruction screens.
  final List<String> departments = [
    "Conservative Dentistry & Endodontics",
    "Oral & Maxillofacial Surgery",
    "Oral Medicine & Radiology",
    "Oral Pathology & Microbiology",
    "Orthodontics & Dentofacial Orthopedics",
    "Pediatric and Preventive Dentistry",
    "Periodontology",
    "Prosthodontics and Crown & Bridge",
    "Public Health Dentistry",
  ];

  final Map<String, List<String>> departmentDoctors = {
    "Periodontology": [
      "Dr. Vineet Kini",
      "Dr. Sarika Shetty",
      "Dr. Sujeet Khiste",
      "Dr. Bharat Gupta",
      "Dr. Trupti Naykodi",
      "Dr. Agraja Patil",
    ],
    "Conservative Dentistry & Endodontics": [
      "Dr. Sumanthini M. V.",
      "Dr. Anuradha Patil.",
      "Dr. Divya Naik",
      "Dr. Jayeeta Verma",
      "Dr. Shouvik Mandal",
      "Dr. Antara Ghosh",
      "Dr. Aditya Shinde",
      "Dr. Jimish Shah",
      "Dr. Tanvi Satpute",
      "Dr. Shreshtha Mukherjee",
      "Dr. Manasi Surwade",
      "Dr. Manisha Bhosle",
    ],
    "Oral & Maxillofacial Surgery": [
      "Dr. Srivalli Natarajan",
      "Dr. Usha Asnani",
      "Dr. Sunil Sidana",
      "Dr. Adil Gandevivala",
      "Dr. Suraj Ahuja",
      "Dr. Sneha Naware",
      "Dr. Nitesh Patkar",
      "Dr. Padmakar Baviskar",
      "Dr. Ruchita Balkawade",
      "Dr. Pareeksit Bagchi",
      "Dr Meghna Chandrachood",
      "Dr. Dr. Pranave P",
      "Dr. Varsha Patel",
    ],
    "Oral Medicine & Radiology": [
      "Dr. Rohit Gadda",
      "Dr. Neha Patil",
      "Dr. Priyanka Tidke",
      "Dr Isha Mishra",
      "Dr. Manjari Chaudhary",
      "Dr. Munitha Naik",
    ],
    "Oral Pathology & Microbiology": [
      "Dr. Shilpa C. Patel",
      "Dr. Jigna Pathak",
      "Dr. Kamlesh Dekate",
      "Dr. Niharika Swain",
      "Dr. Rashmi Hosalkar",
      "Dr. Shraddha Ghaisas",
      "Dr. Yogita Penkar",
    ],
    "Orthodontics & Dentofacial Orthopedics": [
      "Dr. Ravindranath V. K.",
      "Dr. Anjali Gheware",
      "Dr. Amol Mhatre",
      "Dr. Pradnya Korwar",
      "Dr. Neeraj Kolge",
      "Dr. Saurabh Waghchaure",
    ],
    "Pediatric and Preventive Dentistry": [
      "Dr. Shrirang Sevekar",
      "Dr. Jha Mihir Kumar",
      "Dr Sayli Vichare",
      "Dr Harsh Sachdev",
      "Dr. Ashwini Avanti",
      "Dr. Devanshi Shah",
      "Dr. Sujata Hirave",
      "Dr. Rupali Deshmukh",
    ],
    "Prosthodontics and Crown & Bridge": [
      "Dr. Jyoti Nadgere",
      "Dr. Janani Iyer",
      "Dr Neelam Ashok Salvi",
      "Dr. Saumil C. Sampat",
      "Dr. Anuradha Mohite",
      "Dr. Prachiti Terni",
      "Dr. Bhoomi Parmar",
      "Dr Pooja Sambhaji Kakade",
      "Dr. Madhura Titar",
      "Dr. Ragini Sanaye",
      "Dr. Shruti Potdukhe",
      "Dr. Kashmira pawar",
      "Dr. Kanchan S Sahwal",
      "Dr. Khizer Syed",
      "Dr. Mangesh Jadhav",
    ],
    "Public Health Dentistry": [
      "Dr. Vaibhav Pravin Thakkar",
      "Dr. Deeksha Shetty",
      "Dr. Pankaj Londhe",
      "Dr. Rafeeq Nalband",
      "Dr. Mausami Malgaonkar",
      "Dr. Kashmira Kadam",
    ],
  };

  String? selectedDepartment;
  String? selectedDoctor;

  bool get showDoctors => selectedDepartment != null && departmentDoctors.containsKey(selectedDepartment);

  bool get canContinue =>
      selectedDepartment != null &&
      selectedDoctor != null &&
      departmentDoctors[selectedDepartment!]!.contains(selectedDoctor);

  // Calls your backend to store department and doctor!
  Future<void> saveDepartmentDoctor(String username, String department, String doctor) async {
    final url = Uri.parse('https://paras-backend-0gwt.onrender.com/department-doctor');
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: '{"department": "$department", "doctor": "$doctor", "username": "$username"}',
    );
    if (response.statusCode != 200) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save department/doctor')),
        );
      }
    }
  }

  Future<void> _onContinue() async {
    final appState = Provider.of<AppState>(context, listen: false);
    appState.setDepartment(selectedDepartment);
    appState.setDoctor(selectedDoctor);

    // SAVE TO BACKEND
    final userName = appState.username ?? "User";
    await saveDepartmentDoctor(
      userName,
      selectedDepartment!,
      selectedDoctor!,
    );

    // Navigate to next screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TreatmentScreenMain(
          userName: userName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Username not used directly in this widget; saved on continue.

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Department'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final rootNav = Navigator.of(context, rootNavigator: true);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator()),
              );

              // Stop future pushes for this user/device.
              try {
                await ApiService.unregisterAllDeviceTokens();
              } catch (_) {}

              // Mark this device session inactive (enables login on another device).
              try {
                await ApiService.logoutCurrentDeviceSession();
              } catch (_) {}

              // Best-effort local cleanup.
              try {
                await NotificationService.cancelAllPending();
              } catch (_) {}
              try {
                await PushService.onLogout();
              } catch (_) {}

              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              // Clear all in-memory user/account state
              final appState = Provider.of<AppState>(context, listen: false);
              await appState.clearUserData();
              if (!mounted) return;
              // Replace the full stack (also removes the loading dialog route).
              rootNav.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Text(
              "Departments",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ...departments.map((department) {
              final isSelected = selectedDepartment == department;
              return ListTile(
                title: Text(department),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Colors.blue)
                    : const Icon(Icons.radio_button_unchecked),
                onTap: () {
                  setState(() {
                    selectedDepartment = department;
                    selectedDoctor = null;
                  });
                },
                selected: isSelected,
                selectedTileColor: Colors.blue.shade50,
              );
            }).toList(),
            if (showDoctors) ...[
              const SizedBox(height: 24),
              Text(
                "Doctors (${selectedDepartment!})",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ...departmentDoctors[selectedDepartment!]!.map((doctor) {
                final isDoctorSelected = selectedDoctor == doctor;
                return ListTile(
                  title: Text(doctor),
                  trailing: isDoctorSelected
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.radio_button_unchecked),
                  onTap: () {
                    setState(() {
                      selectedDoctor = doctor;
                    });
                  },
                  selected: isDoctorSelected,
                  selectedTileColor: Colors.green.shade50,
                );
              }).toList(),
            ],
          ],
        ),
      ),
      bottomNavigationBar: (showDoctors && canContinue)
          ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _onContinue,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                child: const Text("Continue"),
              ),
            )
          : null,
    );
  }
}
