import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_state.dart';
import 'services/api_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/category_screen.dart';
import 'screens/home_screen.dart';
import 'screens/treatment_screen.dart';
import 'screens/pfd_instructions_screen.dart';
import 'screens/prd_instructions_screen.dart';
import 'auth_callbacks.dart';

// Add RouteObserver for navigation events (must be after all imports)
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appState = AppState();
  await appState.syncTokenFromPrefs();       // <-- Ensure token is loaded!
  await appState.loadUserDetails();          // Load user details (includes username)
  await appState.loadAllChecklists(username: appState.username); // Load persisted checklists for user
  await appState.loadInstructionLogs(username: appState.username); // Load user-scoped logs

  // Debug: Print token value on startup
  print('Token on startup: ${appState.token}');
  final prefs = await SharedPreferences.getInstance();
  print('Token in prefs: ${prefs.getString('token')}');

  runApp(
    ChangeNotifierProvider(
      create: (_) => appState,
      child: const ToothCareGuideApp(),
    ),
  );
}

// Utility function to parse "HH:mm:ss" or "HH:mm" string to TimeOfDay
TimeOfDay? parseTimeOfDay(dynamic timeStr) {
  if (timeStr == null) return null;
  final str = timeStr is String ? timeStr : timeStr.toString();
  final parts = str.split(":");
  if (parts.length < 2) return null;
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

class ToothCareGuideApp extends StatelessWidget {
  const ToothCareGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ToothCareGuide',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      navigatorObservers: [routeObserver],
      onGenerateRoute: (settings) {
        if (settings.name == '/instructions') {
          final args = settings.arguments as Map<String, dynamic>;
          final treatment = args['treatment'];
          final subtype = args['subtype'];
          final date = args['date'];

          if (treatment == 'Prosthesis' && subtype == 'Fixed') {
            return MaterialPageRoute(
              builder: (context) => PFDInstructionsScreen(date: date),
            );
          } else if (treatment == 'Prosthesis' && subtype == 'Removable') {
            return MaterialPageRoute(
              builder: (context) => PRDInstructionsScreen(date: date),
            );
          }
        }

        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Unknown route or arguments')),
          ),
        );
      },
      home: const AppEntryGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppEntryGate extends StatefulWidget {
  const AppEntryGate({super.key});
  @override
  State<AppEntryGate> createState() => _AppEntryGateState();
}

class _AppEntryGateState extends State<AppEntryGate> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final appState = Provider.of<AppState>(context, listen: false);

    // If user data exists (from shared prefs), skip login!
    if (appState.token != null && appState.username != null) {
      // If all info is present, go directly to HomeScreen or instructions
      if (appState.department != null &&
          appState.doctor != null &&
          appState.treatment != null &&
          appState.procedureDate != null &&
          appState.procedureTime != null &&
          appState.procedureCompleted == false) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
      if (appState.treatment == 'Prosthesis' && appState.treatmentSubtype == 'Fixed') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
        builder: (_) => PFDInstructionsScreen(date: DateTime.now()),
              ),
            );
          } else if (appState.treatment == 'Prosthesis' && appState.treatmentSubtype == 'Removable') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
        builder: (_) => PRDInstructionsScreen(date: DateTime.now()),
              ),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          }
        });
        return;
      }
      // If only category info is present, but treatment is missing
      if (appState.department != null &&
          appState.doctor != null &&
          (appState.treatment == null ||
              appState.procedureDate == null ||
              appState.procedureTime == null)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => TreatmentScreenMain(userName: appState.username ?? "User")),
          );
        });
        return;
      }
      // If nothing, go to category
      if (appState.department == null || appState.doctor == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CategoryScreen()),
          );
        });
        return;
      }

      setState(() => _loading = false);
      return;
    }

    // If not persisted, fallback to API check (for first run/after logout)
    final isLoggedIn = await ApiService.checkIfLoggedIn();
    if (!isLoggedIn) {
      setState(() => _loading = false);
      return;
    }

    final userDetails = await ApiService.getUserDetails();
    if (userDetails == null) {
      setState(() => _loading = false);
      return;
    }

    appState.setUserDetails(
      fullName: userDetails['name'],
      dob: DateTime.parse(userDetails['dob']),
      gender: userDetails['gender'],
      username: userDetails['username'],
      password: '', // Password not retrievable
      phone: userDetails['phone'],
      email: userDetails['email'],
    );
  // Load persisted data for this user
  await appState.loadAllChecklists(username: appState.username);
  await appState.loadInstructionLogs(username: appState.username);
    appState.setDepartment(userDetails['department']);
    appState.setDoctor(userDetails['doctor']);
    appState.setTreatment(userDetails['treatment'], subtype: userDetails['treatment_subtype']);
    appState.procedureDate = userDetails['procedure_date'] != null
        ? DateTime.parse(userDetails['procedure_date'])
        : null;
    appState.procedureTime = parseTimeOfDay(userDetails['procedure_time']);
    appState.procedureCompleted = userDetails['procedure_completed'] == true;

    // Repeat the same auto-skip logic after login
    if (appState.department != null &&
        appState.doctor != null &&
        appState.treatment != null &&
        appState.procedureDate != null &&
        appState.procedureTime != null &&
        appState.procedureCompleted == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
    if (appState.treatment == 'Prosthesis' && appState.treatmentSubtype == 'Fixed') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
      builder: (_) => PFDInstructionsScreen(date: DateTime.now()),
            ),
          );
        } else if (appState.treatment == 'Prosthesis' && appState.treatmentSubtype == 'Removable') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
      builder: (_) => PRDInstructionsScreen(date: DateTime.now()),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      });
      return;
    }

    if (appState.department != null &&
        appState.doctor != null &&
        (appState.treatment == null ||
            appState.procedureDate == null ||
            appState.procedureTime == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TreatmentScreenMain(userName: appState.username ?? "User")),
        );
      });
      return;
    }

    if (appState.department == null || appState.doctor == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CategoryScreen()),
        );
      });
      return;
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Fallback to WelcomeScreen if not auto-logged in
    return WelcomeScreen(
      onSignUp: (
          BuildContext context,
          String username,
          String password,
          String phone,
          String email,
          String name,
          String dob,
          String gender,
          VoidCallback switchToLogin,
          ) async {
        final error = await ApiService.register({
          'username': username,
          'password': password,
          'phone': phone,
          'email': email,
          'name': name,
          'dob': dob,
          'gender': gender,
        });

        if (error != null) {
          // Optionally, show error dialog here, or let WelcomeScreen handle it
          return error; // <-- Fix: Return the error to WelcomeScreen
        } else {
          final appState = Provider.of<AppState>(context, listen: false);
          final token = await ApiService.getSavedToken();
          if (token != null) {
            appState.setToken(token);
          }
          appState.setUserDetails(
            fullName: name,
            dob: DateTime.parse(dob),
            gender: gender,
            username: username,
            password: password,
            phone: phone,
            email: email,
          );
          // Optionally, show success snack bar, but let WelcomeScreen show dialog
          switchToLogin();
          return null; // <-- Fix: Return null to WelcomeScreen
        }
      },
      onLogin: (
          BuildContext context,
          String username,
          String password,
          ) async {
        print('Attempting login...');
  final error = await ApiService.login(username.trim(), password);
        print('Login response: $error');

        if (error != null) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Login Failed"),
              content: Text(error),
            ),
          );
        } else {
          final appState = Provider.of<AppState>(context, listen: false);
          // --- Ensure token is stored after login ---
          final token = await ApiService.getSavedToken();
          if (token != null) {
            appState.setToken(token);
          }

          // Fetch full user details using stored token
          final userDetails = await ApiService.getUserDetails();

          if (userDetails != null) {
            appState.setUserDetails(
              fullName: userDetails['name'],
              dob: DateTime.parse(userDetails['dob']),
              gender: userDetails['gender'],
              username: userDetails['username'],
              password: password,
              phone: userDetails['phone'],
              email: userDetails['email'],
            );
            // Load persisted data for this user
            await appState.loadAllChecklists(username: appState.username);
            await appState.loadInstructionLogs(username: appState.username);
            appState.setDepartment(userDetails['department']);
            appState.setDoctor(userDetails['doctor']);
            appState.setTreatment(userDetails['treatment'], subtype: userDetails['treatment_subtype']);
            appState.procedureDate = userDetails['procedure_date'] != null
                ? DateTime.parse(userDetails['procedure_date'])
                : null;
            appState.procedureTime = parseTimeOfDay(userDetails['procedure_time']);
            appState.procedureCompleted = userDetails['procedure_completed'] == true;
          }

          // Now repeat the auto-skip logic after login
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (appState.department != null &&
                appState.doctor != null &&
                appState.treatment != null &&
                appState.procedureDate != null &&
                appState.procedureTime != null &&
                appState.procedureCompleted == false) {
      if (appState.treatment == 'Prosthesis' && appState.treatmentSubtype == 'Fixed') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
        builder: (_) => PFDInstructionsScreen(date: DateTime.now()),
                  ),
                );
              } else if (appState.treatment == 'Prosthesis' && appState.treatmentSubtype == 'Removable') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
        builder: (_) => PRDInstructionsScreen(date: DateTime.now()),
                  ),
                );
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              }
            } else if (appState.department != null &&
                appState.doctor != null &&
                (appState.treatment == null ||
                    appState.procedureDate == null ||
                    appState.procedureTime == null)) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => TreatmentScreenMain(userName: appState.username ?? "User")),
              );
            } else if (appState.department == null || appState.doctor == null) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const CategoryScreen()),
              );
            }
          });
        }
      },
    );
  }
}