import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'calendar_screen.dart';
import 'reminders_screen.dart';
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
import 'treatment_history_screen.dart';
import 'package:url_launcher/url_launcher.dart';
// Removed debug/test imports
import '../services/reminder_api.dart';
import '../services/notification_service.dart';
import '../widgets/responsive_header_row.dart';
import '../widgets/ui_safety.dart';
import '../services/api_service.dart';

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
                isScrollControlled: true,
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
          // Pure Reminders debug entry removed
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
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
    Future<void> openInstructionsFor(AppState appState) async {
      final String? treatment = appState.treatment;
      final String? subtype = appState.treatmentSubtype;
      final DateTime today = DateTime.now();
      Widget? screen;
      if (treatment == "Tooth Taken Out") {
        screen = TTOInstructionsScreen(date: today);
      } else if (treatment == "Prosthesis Fitted") {
        if (subtype == "Fixed Dentures") {
          screen = PFDInstructionsScreen(date: today);
        } else if (subtype == "Removable Dentures") {
          screen = PRDInstructionsScreen(date: today);
        }
      } else if (treatment == "Root Canal/Filling") {
        screen = RootCanalInstructionsScreen(date: today);
      } else if (treatment == "Implant") {
        if (subtype == "First Stage") {
          screen = IFSInstructionsScreen(date: today);
        } else if (subtype == "Second Stage") {
          screen = ISSInstructionsScreen(date: today);
        }
      } else if (treatment == "Braces") {
        screen = BracesInstructionsScreen(date: today);
      } else if (treatment == "Tooth Fracture") {
        if (subtype == "Filling") {
          screen = FillingInstructionsScreen(date: today);
        } else if (subtype == "Teeth Cleaning") {
          screen = TCInstructionsScreen(date: today);
        } else if (subtype == "Teeth Whitening") {
          screen = TWInstructionsScreen(date: today);
        } else if (subtype == "Gum Surgery") {
          screen = GSInstructionsScreen(date: today);
        } else if (subtype == "Veneers/Laminates") {
          screen = VLInstructionsScreen(date: today);
        }
      }
      if (screen != null) {
        final nav = Navigator.of(context);
        // Close the sheet first, then navigate
        nav.pop();
        await Future.microtask(() => nav.push(MaterialPageRoute(builder: (_) => screen!)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No instructions available for this selection.')),
        );
      }
    }

    Future<TimeOfDay?> _pickTime(BuildContext ctx, TimeOfDay initial) async {
      return await showTimePicker(context: ctx, initialTime: initial);
    }

    Future<DateTime?> _pickDate(BuildContext ctx, DateTime initialDate) async {
      final now = DateTime.now();
      return await showDatePicker(
        context: ctx,
        initialDate: initialDate,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 2),
      );
    }

    Future<void> _promptDateTimeAndSave(AppState appState) async {
      // Ask for procedure date and time; this is a fresh start, not a completion.
      final today = DateTime.now();
      final pickedDate = await _pickDate(context, today);
      if (pickedDate == null) return; // cancelled
      final pickedTime = await _pickTime(context, TimeOfDay.now());
      if (pickedTime == null) return;

      // Save to backend (if endpoint available) and to AppState
      final username = appState.username ?? '';
      final treatment = appState.treatment ?? '';
      final subtype = appState.treatmentSubtype;
      bool ok = true;
      try {
        // Persist to backend if token present and endpoint implemented
        ok = await ApiService.saveTreatmentInfo(
          username: username,
          treatment: treatment,
          subtype: subtype,
          procedureDate: pickedDate,
          procedureTime: pickedTime,
        );
      } catch (_) {}

      // Update local state regardless to ensure UI reflects choice immediately
      appState.setTreatment(treatment, subtype: subtype, procedureDate: pickedDate);
      appState.setProcedureDateTime(pickedDate, pickedTime);
      appState.procedureCompleted = false; // fresh start, not completed

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved locally. Server save failed or unavailable.')),
        );
      }
    }

    Future<bool> _confirmTreatmentReplacement({
      required BuildContext ctx,
      required String oldTreatment,
      required String oldSubtype,
      required String newTreatment,
      required String newSubtype,
    }) async {
      if (oldTreatment.isEmpty) return true;
      if (oldTreatment == newTreatment && oldSubtype == newSubtype) return true;

      final res = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (dctx) {
          return AlertDialog(
            title: const Text('Change treatment?'),
            content: Text(
              'You selected a different treatment.\n\n'
              'Changing treatment will reset your ONGOING recovery progress (not completed history) and replace your current ongoing treatment on the server. '
              'Completed treatments in Treatment History will remain.\n\n'
              'Current: ${oldTreatment.isNotEmpty ? oldTreatment : '-'}${oldSubtype.isNotEmpty ? ' ($oldSubtype)' : ''}\n'
              'New: $newTreatment${newSubtype.isNotEmpty ? ' ($newSubtype)' : ''}',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Change')),
            ],
          );
        },
      );
      return res == true;
    }

    Future<void> _promptDateTimeAndReplaceTreatment(AppState appState, {required String treatment, String? subtype}) async {
      // Ask for procedure date and time, then call server replace endpoint.
      final today = DateTime.now();
      final pickedDate = await _pickDate(context, today);
      if (pickedDate == null) return;
      final pickedTime = await _pickTime(context, TimeOfDay.now());
      if (pickedTime == null) return;

      final ok = await ApiService.replaceTreatmentEpisode(
        treatment: treatment,
        subtype: subtype,
        procedureDate: pickedDate,
        procedureTime: pickedTime,
      );
      if (!ok) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to change treatment on server. Please try again.')),
        );
        return;
      }

      // Reset local caches so UI starts clean.
      await appState.resetLocalStateForTreatmentReplacement(username: appState.username);

      // Update local state to match server.
      appState.setTreatment(treatment, subtype: subtype, procedureDate: pickedDate);
      appState.setProcedureDateTime(pickedDate, pickedTime);
      appState.procedureCompleted = false;
    }

    Future<void> selectTreatment({required String treatment, String? subtype}) async {
      final appState = Provider.of<AppState>(context, listen: false);
      final oldTreatment = (appState.treatment ?? '').toString();
      final oldSubtype = (appState.treatmentSubtype ?? '').toString();
      final newSubtype = (subtype ?? '').toString();

      final confirmed = await _confirmTreatmentReplacement(
        ctx: context,
        oldTreatment: oldTreatment,
        oldSubtype: oldSubtype,
        newTreatment: treatment,
        newSubtype: newSubtype,
      );
      if (!confirmed) return;

      if (oldTreatment.isNotEmpty && (oldTreatment != treatment || oldSubtype != newSubtype)) {
        await _promptDateTimeAndReplaceTreatment(appState, treatment: treatment, subtype: subtype);
      } else {
        // First-time selection or no change: keep the existing save behavior.
        appState.setTreatment(treatment, subtype: subtype);
        await _promptDateTimeAndSave(appState);
      }
      await openInstructionsFor(appState);
    }

    Future<void> selectWithSubtype(String treatment, List<String> subtypes) async {
      // Show a nested sheet to pick the subtype
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Text('Select subtype', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...subtypes.map((s) => ListTile(
                        leading: const Icon(Icons.chevron_right),
                        title: Text(s),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          await selectTreatment(treatment: treatment, subtype: s);
                        },
                      )),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    }

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
            onTap: () => selectTreatment(treatment: "Tooth Taken Out"),
          ),
          ListTile(
            leading: const Icon(Icons.view_module, color: Colors.green),
            title: const Text("Prosthesis Fitted"),
            onTap: () => selectWithSubtype("Prosthesis Fitted", const ["Fixed Dentures", "Removable Dentures"]),
          ),
          ListTile(
            leading: const Icon(Icons.healing, color: Colors.orange),
            title: const Text("Root Canal/Filling"),
            onTap: () => selectTreatment(treatment: "Root Canal/Filling"),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border, color: Colors.red),
            title: const Text("Implant"),
            onTap: () => selectWithSubtype("Implant", const ["First Stage", "Second Stage"]),
          ),
          ListTile(
            leading: const Icon(Icons.broken_image, color: Colors.purple),
            title: const Text("Tooth Fracture"),
            onTap: () => selectWithSubtype("Tooth Fracture", const [
              "Filling",
              "Teeth Cleaning",
              "Teeth Whitening",
              "Gum Surgery",
              "Veneers/Laminates",
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.emoji_people, color: Colors.teal),
            title: const Text("Braces"),
            onTap: () => selectTreatment(treatment: "Braces"),
          ),
        ],
      ),
    );
  }
}

class HomeMainContent extends StatefulWidget {
  const HomeMainContent({super.key});

  @override
  State<HomeMainContent> createState() => _HomeMainContentState();
}

class _HomeMainContentState extends State<HomeMainContent> {
  int _remindersCount = 0;
  String? _nextReminderLabel;
  bool _loadingReminders = false;

  @override
  void initState() {
    super.initState();
    _loadRemindersSummary();
  }

  Future<void> _loadRemindersSummary() async {
    setState(() => _loadingReminders = true);
    try {
      // Lazy import to avoid top-level import churn
      // ignore: depend_on_referenced_packages
      final list = await ReminderApi.list();
      list.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      String? label;
      if (list.isNotEmpty) {
        final first = list.first;
        label = NotificationService.nextFireLabel(first.hour, first.minute);
      }
      if (mounted) setState(() { _remindersCount = list.length; _nextReminderLabel = label; });
    } catch (_) {
      if (mounted) setState(() { _remindersCount = 0; _nextReminderLabel = null; });
    } finally {
      if (mounted) setState(() => _loadingReminders = false);
    }
  }

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

    // final today = DateTime.now();

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
                        Expanded(child: SafeText('Hello, $name!', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.local_hospital, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Expanded(child: SafeText("Department: $department", style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16))),
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
                        Expanded(child: SafeText("Doctor: $doctor", style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16))),
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
                            child: SafeText(
                              "Treatment: $treatment${(subtype != null && subtype.isNotEmpty) ? " ($subtype)" : ""}",
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Recovery Dashboard (blue theme to match Progress screen)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(20),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5),
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
                                  SizedBox(
                                    height: 36,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF2196F3),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.add_alert, size: 18),
                                      label: const Text('Add Reminder', style: TextStyle(fontWeight: FontWeight.w600)),
                                      onPressed: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const RemindersScreen(openEditorOnOpen: true),
                                          ),
                                        );
                                        // Refresh summary when returning
                                        _loadRemindersSummary();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_loadingReminders) ...[
                                Row(
                                  children: const [
                                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Checking your reminders...',
                                        style: TextStyle(fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                )
                              ] else if (_remindersCount == 0) ...[
                                const Text(
                                  'Set a daily reminder to get a gentle nudge at your preferred time.',
                                  style: TextStyle(fontSize: 15, color: Colors.black87),
                                ),
                                const SizedBox(height: 6),
                                TextButton(
                                  onPressed: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const RemindersScreen(openEditorOnOpen: true),
                                      ),
                                    );
                                    _loadRemindersSummary();
                                  },
                                  child: const Text('Create your first reminder'),
                                ),
                              ] else ...[
                                ResponsiveHeaderRow(
                                  icon: Icons.schedule,
                                  label: _nextReminderLabel != null
                                      ? 'Next reminder: ${_nextReminderLabel!}'
                                      : 'You have $_remindersCount reminder(s) set',
                                  action: TextButton(
                                    onPressed: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const RemindersScreen(),
                                        ),
                                      );
                                      _loadRemindersSummary();
                                    },
                                    child: const Text('Manage'),
                                  ),
                                ),
                              ],
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
                              onTap: () async {
                                String? url;
                                if (activity['title'] == 'Gentle Brushing') {
                                  url = 'https://www.youtube.com/watch?v=mJ3t9w6h9rE';
                                } else if (activity['title'] == 'Soft Foods') {
                                  url = 'https://www.youtube.com/watch?v=Oj3BGyGW2Tw';
                                }
                                if (url != null) {
                                  final uri = Uri.parse(url);
                                  try {
                                    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    if (!ok) {
                                      // Fallback: try default mode
                                      await launchUrl(uri);
                                    }
                                  } catch (_) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Could not open the video.')),
                                    );
                                  }
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
}