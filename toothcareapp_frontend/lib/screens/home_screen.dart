import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'calendar_screen.dart';
<<<<<<< HEAD
import 'reminders_screen.dart';
=======
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
import 'tto_instructions_screen.dart';
import 'pfd_instructions_screen.dart';
import 'prd_instructions_screen.dart';
import 'root_canal_instructions_screen.dart';
import 'ifs_instructions_screen.dart';
import 'iss_instructions_screen.dart';
import 'braces_instructions_screen.dart';
import 'filling_instructions_screen.dart';
import 'tc_instructions_screen.dart';
import 'tw_instructions_screen.dart';
import 'gs_instructions_screen.dart';
import 'v_l_instructions_screen.dart';
import 'progress_screen.dart';
import 'profile_screen.dart';
import 'category_screen.dart';
import 'treatment_screen.dart';
<<<<<<< HEAD
import 'package:flutter/services.dart';
import 'treatment_history_screen.dart';
// Removed debug/test imports
=======
import 'package:url_launcher/url_launcher.dart';
import 'treatment_history_screen.dart';
import '../auth_callbacks.dart'; // <-- ADD THIS IMPORT
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomeMainContent(),
      CalendarScreen(),
      const SizedBox(), // Will be replaced dynamically
      ProgressScreen(),
      ProfileScreen(
        onCheckRecoveryCalendar: () {
          setState(() {
            _selectedIndex = 1; // Calendar tab
          });
        },
        onViewCareInstructions: () {
          setState(() {
            _selectedIndex = 2; // Instructions tab
          });
        },

      ),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _getInstructionsScreen(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final String? treatment = appState.treatment;
    final String? subtype = appState.treatmentSubtype;
    final DateTime today = DateTime.now();

    if (treatment == "Tooth Taken Out") {
      return TTOInstructionsScreen(date: today);
    }
    if (treatment == "Prosthesis Fitted") {
      if (subtype == "Fixed Dentures") {
        return PFDInstructionsScreen(date: today);
      } else if (subtype == "Removable Dentures") {
        return PRDInstructionsScreen(date: today);
      }
    }
    if (treatment == "Root Canal/Filling") {
      return RootCanalInstructionsScreen(date: today);
    }
    if (treatment == "Implant") {
      if (subtype == "First Stage") {
        return IFSInstructionsScreen(date: today);
      } else if (subtype == "Second Stage") {
        return ISSInstructionsScreen(date: today);
      }
    }

    if (treatment == "Braces") {
      return BracesInstructionsScreen(date: today);
    }
    if (treatment == "Tooth Fracture") {
      if (subtype == "Filling") {
        return FillingInstructionsScreen(date: today);
      }
      else if (subtype == "Teeth Cleaning") {
        return TCInstructionsScreen(date: today);
      }
      else if (subtype == "Teeth Whitening") {
        return TWInstructionsScreen(date: today);
      }
      else if (subtype == "Gum Surgery") {
        return GSInstructionsScreen(date: today);
      }
      else if (subtype == "Veneers/Laminates") {
        return VLInstructionsScreen(date: today);
      }
      return const _NoInstructionsSelected();
    }
    // This line fixes the error!
    return const _NoInstructionsSelected();
  }
  @override
  Widget build(BuildContext context) {
    List<Widget> pages = List<Widget>.from(_pages);
    pages[2] = _getInstructionsScreen(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (BuildContext context) {
                  return const TreatmentOptionsSheet();
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history), // <-- Add history icon
            tooltip: 'Treatment History',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TreatmentHistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey[600],
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'Instructions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'Progress',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _NoInstructionsSelected extends StatelessWidget {
  const _NoInstructionsSelected();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book, color: Colors.blue, size: 48),
            const SizedBox(height: 20),
            const Text(
              "No Instructions Available",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            const Text(
              "Please select your treatment and subtype using the menu in the top right to view care instructions.",
              style: TextStyle(fontSize: 16, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.medical_services),
              label: const Text("Select Treatment"),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const TreatmentScreenMain(userName: "User"),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class TreatmentOptionsSheet extends StatelessWidget {
  const TreatmentOptionsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Treatment Options",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.medical_services, color: Colors.blue),
            title: const Text("Tooth Taken Out"),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const TreatmentScreenMain(userName: "User"),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.view_module, color: Colors.green),
            title: const Text("Prosthesis Fitted"),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const TreatmentScreenMain(userName: "User"),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.healing, color: Colors.orange),
            title: const Text("Root Canal/Filling"),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const TreatmentScreenMain(userName: "User"),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border, color: Colors.red),
            title: const Text("Implant"),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const TreatmentScreenMain(userName: "User"),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.broken_image, color: Colors.purple),
            title: const Text("Tooth Fracture"),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const TreatmentScreenMain(userName: "User"),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.emoji_people, color: Colors.teal),
            title: const Text("Braces"),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const TreatmentScreenMain(userName: "User"),
              ));
            },
          ),
        ],
      ),
    );
  }
}

class HomeMainContent extends StatelessWidget {
  const HomeMainContent({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    final name = appState.username ?? "";
    final procedureDate = appState.procedureDate;
    final String? department = appState.department;
    final String? doctor = appState.doctor;
    final String? treatment = appState.treatment;
    final String? subtype = appState.treatmentSubtype;

    if (department == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text(
                "Missing Department",
                style: TextStyle(
                    fontSize: 22,
                    color: Colors.red,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Please select your department on the previous screen.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const CategoryScreen()),
                  );
                },
                child: const Text("Go Back"),
              )
            ],
          ),
        ),
      );
    }

<<<<<<< HEAD
  // final today = DateTime.now();
=======
    final today = DateTime.now();
    final int totalRecoveryDays = 14;
    final actualProcedureDate = procedureDate ?? today;
    final int dayOfRecovery = today
        .difference(DateTime(actualProcedureDate.year,
        actualProcedureDate.month, actualProcedureDate.day))
        .inDays +
        1;
    final int progressPercent =
    ((dayOfRecovery / totalRecoveryDays) * 100).clamp(0, 100).toInt();
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec

    final activities = [
      {
        'title': 'Gentle Brushing',
        'icon': Icons.medical_services,
        'desc': '',
        'duration': '2 min',
        'bgColor': const Color(0xFFE6F0FB),
      },
      {
        'title': 'Salt Water Rinse',
        'icon': Icons.opacity,
        'desc': '',
        'duration': '2 min',
        'bgColor': const Color(0xFFE5F7F1),
      },
      {
        'title': 'Ice Application',
        'icon': Icons.ac_unit,
        'desc': '',
        'duration': '2 min',
        'bgColor': const Color(0xFFF2EBFD),
      },
      {
        'title': 'Soft Foods',
        'icon': Icons.restaurant,
        'desc': '',
        'duration': '2 min',
        'bgColor': const Color(0xFFFFF2E5),
      },
    ];

    // Responsive aspect ratio for grid
    double screenWidth = MediaQuery.of(context).size.width;
    double aspectRatio = screenWidth < 400 ? 0.90 : 0.78; // Give more vertical space on narrow screens

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
            child: Column(
              children: [
                if (name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Hello, $name!',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.local_hospital, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Department: $department",
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (doctor != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.medical_services, color: Colors.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Doctor: $doctor",
                            style: const TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (treatment != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.healing, color: Colors.deepOrange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Tooltip(
                            message:
                                "Treatment: $treatment${(subtype != null && subtype.isNotEmpty) ? " ($subtype)" : ""}",
                            child: Text(
                              "Treatment: $treatment${(subtype != null && subtype.isNotEmpty) ? " ($subtype)" : ""}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
<<<<<<< HEAD
                // Recovery Dashboard (blue theme to match Progress screen)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(20),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5),
=======
                Container(
                  margin: const EdgeInsets.only(top: 16, bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3),
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Recovery Dashboard',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
<<<<<<< HEAD
                          Chip(
                            label: Text(
                              appState.procedureCompleted == true
                                  ? 'Marked Complete'
                                  : 'In Recovery',
                            ),
                            backgroundColor: Colors.white70,
                            labelStyle: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                            shape: StadiumBorder(side: BorderSide(color: Colors.white, width: 1)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (procedureDate != null) ...[
                        Builder(builder: (context) {
                          final now = DateTime.now();
                          final todayOnly = DateTime(now.year, now.month, now.day);
                          final procOnly = DateTime(procedureDate.year, procedureDate.month, procedureDate.day);
                          final daysSince = todayOnly.difference(procOnly).inDays.clamp(0, 9999);
                          const int totalRecoveryDays = 14;
                          final int dayOfRecovery = (daysSince + 1).clamp(1, totalRecoveryDays);
                          final int progressPercent = ((dayOfRecovery / totalRecoveryDays) * 100).clamp(0, 100).toInt();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Day $dayOfRecovery of recovery',
                                style: const TextStyle(fontSize: 16, color: Colors.white),
                              ),
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                value: (dayOfRecovery / totalRecoveryDays).clamp(0, 1),
                                backgroundColor: Colors.white38,
                                color: Colors.white,
                                minHeight: 6,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Recovery Progress: $progressPercent%',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ],
                          );
                        }),
                      ] else ...[
                        const Text(
                          'No procedure date set yet.',
                          style: TextStyle(fontSize: 14, color: Colors.white),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            icon: const Icon(Icons.calendar_today),
                            label: const Text('View Calendar'),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => CalendarScreen()),
                              );
                            },
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            icon: const Icon(Icons.menu_book),
                            label: const Text('Care Instructions'),
                            onPressed: () {
                              final String? t = treatment;
                              final String? sub = subtype;
                              final dt = DateTime.now();
                              Widget? screen;
                              if (t == "Tooth Taken Out") {
                                screen = TTOInstructionsScreen(date: dt);
                              } else if (t == "Prosthesis Fitted") {
                                if (sub == "Fixed Dentures") {
                                  screen = PFDInstructionsScreen(date: dt);
                                } else if (sub == "Removable Dentures") {
                                  screen = PRDInstructionsScreen(date: dt);
                                }
                              } else if (t == "Root Canal/Filling") {
                                screen = RootCanalInstructionsScreen(date: dt);
                              } else if (t == "Implant") {
                                if (sub == "First Stage") {
                                  screen = IFSInstructionsScreen(date: dt);
                                } else if (sub == "Second Stage") {
                                  screen = ISSInstructionsScreen(date: dt);
                                }
                              } else if (t == "Braces") {
                                screen = BracesInstructionsScreen(date: dt);
                              } else if (t == "Tooth Fracture") {
                                if (sub == "Filling") {
                                  screen = FillingInstructionsScreen(date: dt);
                                } else if (sub == "Teeth Cleaning") {
                                  screen = TCInstructionsScreen(date: dt);
                                } else if (sub == "Teeth Whitening") {
                                  screen = TWInstructionsScreen(date: dt);
                                } else if (sub == "Gum Surgery") {
                                  screen = GSInstructionsScreen(date: dt);
                                } else if (sub == "Veneers/Laminates") {
                                  screen = VLInstructionsScreen(date: dt);
                                }
                              }
                              if (screen != null) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => screen!),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('No instructions available for current selection.')),
                                );
                              }
                            },
                          ),
                        ],
=======
                          const Icon(Icons.favorite_border, color: Colors.white),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Day $dayOfRecovery of recovery',
                        style: const TextStyle(
                            fontSize: 16, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: (dayOfRecovery / totalRecoveryDays).clamp(0, 1),
                        backgroundColor: Colors.white24,
                        color: Colors.white,
                        minHeight: 5,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Recovery Progress: $progressPercent%',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
                      ),
                    ],
                  ),
                ),
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
<<<<<<< HEAD
=======
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: Color(0xFF2196F3)),
                            const SizedBox(width: 10),
                            const Text(
                              'Recovery Progress',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildCalendarGrid(actualProcedureDate, dayOfRecovery,
                            totalRecoveryDays),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildLegendDot(const Color(0xFFFFE0E6)),
                            const SizedBox(width: 4),
                            const Text('Procedure',
                                style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 16),
                            _buildLegendDot(const Color(0xFFB5E0D3)),
                            const SizedBox(width: 4),
                            const Text('Completed',
                                style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 16),
                            _buildLegendDot(const Color(0xFF2196F3)),
                            const SizedBox(width: 4),
                            const Text('Today', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notifications_none, color: Colors.amber[700]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('Reminders',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20)),
                                  const Spacer(),
                                  GestureDetector(
<<<<<<< HEAD
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const RemindersScreen(),
                                        ),
                                      );
                                    },
=======
                                    onTap: () {},
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
                                    child: const Text(
                                      '+ Add',
                                      style: TextStyle(
                                          color: Color(0xFF2196F3),
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No reminders set. Click "Add" to create your first reminder.',
                                style: TextStyle(
                                    fontSize: 15, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.favorite_border, color: Colors.green[400]),
                            const SizedBox(width: 10),
                            const Text(
                              'Daily Care Activities',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: aspectRatio,
                          children: activities.map((activity) {
                            return GestureDetector(
                              onTap: () {
<<<<<<< HEAD
                                String? url;
                                if (activity['title'] == 'Gentle Brushing') {
                                  url = 'https://www.youtube.com/watch?v=mJ3t9w6h9rE';
                                } else if (activity['title'] == 'Soft Foods') {
                                  url = 'https://www.youtube.com/watch?v=Oj3BGyGW2Tw';
                                }
                                if (url != null) {
                                  Clipboard.setData(ClipboardData(text: url));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Link copied to clipboard: $url')),
=======
                                if (activity['title'] == 'Gentle Brushing') {
                                  launchUrl(
                                    Uri.parse('https://www.youtube.com/watch?v=mJ3t9w6h9rE'),
                                    mode: LaunchMode.externalApplication,
                                  );
                                } else if (activity['title'] == 'Soft Foods') {
                                  launchUrl(
                                    Uri.parse('https://www.youtube.com/watch?v=Oj3BGyGW2Tw'),
                                    mode: LaunchMode.externalApplication,
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
                                  );
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: activity['bgColor'] as Color,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Colors.white,
                                      radius: 22,
                                      child: Icon(
                                        activity['icon'] as IconData,
                                        color: Colors.blue,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      activity['title'] as String,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15),
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        width: double.infinity,
                                        child: Column(
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Icon(Icons.play_arrow,
                                                    color: Colors.white, size: 24),
                                                const Spacer(),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white12,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    activity['duration'] as String,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Flexible(
                                              fit: FlexFit.loose,
                                              child: Text(
                                                (activity['desc'] as String).split('\n')[0],
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w400),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                            Flexible(
                                              fit: FlexFit.loose,
                                              child: Text(
                                                (activity['desc'] as String).split('\n').length > 1
                                                    ? (activity['desc'] as String).split('\n')[1]
                                                    : '',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w400),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
<<<<<<< HEAD
=======
  Widget _buildCalendarGrid(
      DateTime procedureDate, int dayOfRecovery, int recoveryDays) {
    DateTime now = DateTime.now();
    DateTime firstDayOfMonth = DateTime(now.year, now.month, 1);
    int daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    List<Widget> rows = [];
    List<Widget> week = [];
    int weekdayOfFirst = firstDayOfMonth.weekday;
    for (int i = 1; i < weekdayOfFirst; i++) {
      week.add(Container());
    }

    for (int d = 1; d <= daysInMonth; d++) {
      DateTime date = DateTime(now.year, now.month, d);
      Color? dotColor;
      if (date.year == procedureDate.year &&
          date.month == procedureDate.month &&
          date.day == procedureDate.day) {
        dotColor = const Color(0xFFFFE0E6); // Procedure
      } else if (date.isBefore(now)) {
        dotColor = const Color(0xFFB5E0D3); // Completed
      } else if (date.day == now.day) {
        dotColor = const Color(0xFF2196F3); // Today
      }
      week.add(
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: Container(
            decoration: BoxDecoration(
              color: dotColor ?? const Color(0xFFF5F6FA),
              borderRadius: BorderRadius.circular(8),
            ),
            width: 32,
            height: 32,
            child: Center(
              child: Text(
                '$d',
                style: TextStyle(
                    color: (dotColor != null &&
                        dotColor != const Color(0xFFF5F6FA))
                        ? Colors.black
                        : Colors.grey[700],
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      );
      if ((week.length) == 7) {
        rows.add(Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: week));
        week = [];
      }
    }
    if (week.isNotEmpty) {
      while (week.length < 7) week.add(Container());
      rows.add(Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: week));
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
              .map((e) => Expanded(
              child: Center(
                child: Text(e,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              )))
              .toList(),
        ),
        const SizedBox(height: 4),
        ...rows,
      ],
    );
  }

  Widget _buildLegendDot(Color color) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
    );
  }
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
}