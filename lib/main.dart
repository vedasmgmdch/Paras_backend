import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_state.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
// Removed hybrid reminders & server push for simplified local reminder system.
import 'services/reminder_store.dart';
import 'services/reminder_api.dart';
import 'screens/welcome_screen.dart';
import 'screens/category_screen.dart';
import 'screens/home_screen.dart';
import 'screens/treatment_screen.dart';
import 'screens/pfd_instructions_screen.dart';
import 'screens/prd_instructions_screen.dart';
import 'screens/user_screen.dart';
import 'screens/doctor_login_screen.dart';
import 'screens/doctors_patients_list_screen.dart';
import 'screens/doctor_select_screen.dart';
// ignore_for_file: avoid_print
// Firebase messaging handled centrally in PushService.
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:firebase_core/firebase_core.dart';

// Add RouteObserver for navigation events (must be after all imports)
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    print('[FlutterError] ${details.exceptionAsString()}');
    if (details.stack != null) {
      print(details.stack);
    }
  };

  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    print('[Uncaught] $error');
    print(stack);
    return true; // handled
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Avoid a blank screen in release; show a minimal fallback.
    return Material(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Something went wrong. Please go back and try again.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };

  // Render ASAP: do not block first frame on network/plugin init.
  final appState = AppState();
  runApp(ChangeNotifierProvider(create: (_) => appState, child: const ToothCareGuideApp()));
  unawaited(_postStartupInit(appState));
}

Future<void> _postStartupInit(AppState appState) async {
  // Let the first frame render before doing heavy startup work.
  await Future<void>.delayed(Duration.zero);
  try {
    // AlarmManager initialization removed: we rely on plugin pre-scheduled daily notifications.
    await NotificationService.init();
    // Disable legacy local store scheduling; we will schedule from server list only
    ReminderStore.hybridActive = true;
    // Log current notification capabilities for diagnostics
    try {
      final caps = await NotificationService.getCapabilities();
      print('[Startup][notifCaps] $caps');
    } catch (_) {}

    // Ensure persisted auth/user state is hydrated quickly (no bulk sync here).
    await appState.loadUserDetails(runBulkSync: false);
    await appState.syncTokenFromPrefs();

    // Centralized push (Firebase + token registration + foreground handling)
    await PushService.initializeAndRegister();

    // Fetch server UTC now so day calculations use server time (network; safe post-frame)
    try {
      await appState.syncServerTime();
    } catch (_) {}

    // Re-register device token now that Authorization header exists (if any)
    await PushService.registerNow();
    await PushService.flushPendingIfAny();

    // Remove any stale schedules left from older versions, then schedule from server list.
    try {
      await NotificationService.cancelAllPending();
    } catch (e) {
      print('Startup cancelAllPending failed: $e');
    }

    // After token is ready, fetch server reminders and schedule locally.
    try {
      final list = await ReminderApi.list();
      await ReminderApi.scheduleLocally(list);
    } catch (e) {
      print('Server-backed reschedule at startup failed: $e');
    }

    // Load persisted per-user data without blocking the first frame.
    await appState.loadAllChecklists(username: appState.username);
    await appState.loadInstructionLogs(username: appState.username);

    // Pull server-side instruction status so ticks are correct across devices.
    unawaited(appState.pullInstructionStatusChanges());

    // Bulk sync instruction logs (network) can be expensive; keep it post-frame.
    await appState.maybeBulkSyncInstructionLogs();

    // Debug: Print token value on startup
    print('Token on startup: ${appState.token}');
    final prefs = await SharedPreferences.getInstance();
    print("Token in prefs: ${prefs.getString('token')}");
  } catch (e) {
    print('Post-startup init failed: $e');
  }
}

// Utility function to parse "HH:mm:ss" or "HH:mm" string to TimeOfDay
TimeOfDay? parseTimeOfDay(dynamic timeStr) {
  if (timeStr == null) return null;
  final str = timeStr is String ? timeStr : timeStr.toString();
  final parts = str.split(":");
  if (parts.length < 2) return null;
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

class ToothCareGuideApp extends StatelessWidget {
  const ToothCareGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ToothCareGuide',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _NoTransitionsBuilder(),
            TargetPlatform.iOS: _NoTransitionsBuilder(),
            TargetPlatform.windows: _NoTransitionsBuilder(),
            TargetPlatform.macOS: _NoTransitionsBuilder(),
            TargetPlatform.linux: _NoTransitionsBuilder(),
          },
        ),
      ),
      navigatorObservers: [routeObserver],
      routes: {
        // Root route now decides dynamically: if a patient is already logged in (token + username)
        // we bypass the role selection UserScreen and continue straight to patient flow via AppEntryGate.
        '/': (_) => const RootDecider(),
        '/doctor-login': (_) => const DoctorLoginScreen(),
        '/doctor-select': (_) => const DoctorSelectScreen(),
        '/doctor-patients': (_) => const DoctorsPatientsListScreen(),
        '/patient': (_) => const AppEntryGate(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/instructions') {
          final args = settings.arguments as Map<String, dynamic>;
          final treatment = args['treatment'];
          final subtype = args['subtype'];
          final date = args['date'];

          if ((treatment == 'Prosthesis' || treatment == 'Prosthesis Fitted') &&
              (subtype == 'Fixed' || subtype == 'Fixed Dentures')) {
            return MaterialPageRoute(builder: (context) => PFDInstructionsScreen(date: date));
          } else if ((treatment == 'Prosthesis' || treatment == 'Prosthesis Fitted') &&
              (subtype == 'Removable' || subtype == 'Removable Dentures')) {
            return MaterialPageRoute(builder: (context) => PRDInstructionsScreen(date: date));
          }
        }

        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: Center(child: Text('Unknown route or arguments'))),
        );
      },
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
    // Watchdog: never stay on a spinner forever.
    unawaited(
      Future<void>.delayed(const Duration(seconds: 25)).then((_) {
        if (!mounted) return;
        if (_loading) setState(() => _loading = false);
      }),
    );

    try {
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
          // After restart/hot-restart, always land on the dashboard (bottom navigation).
          // The user can open the instruction screen from Home as needed.
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        });
        return;
      }
      // If only category info is present, but treatment is missing
      if (appState.department != null &&
          appState.doctor != null &&
          (appState.treatment == null || appState.procedureDate == null || appState.procedureTime == null)) {
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
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CategoryScreen()));
        });
        return;
      }

      setState(() => _loading = false);
      return;
    }

      // If not persisted, fallback to API check (for first run/after logout)
      final isLoggedIn = await ApiService.checkIfLoggedIn();
      if (!isLoggedIn) {
        if (mounted) setState(() => _loading = false);
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
        // After restart/hot-restart, always land on the dashboard (bottom navigation).
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      });
      return;
    }

    if (appState.department != null &&
        appState.doctor != null &&
        (appState.treatment == null || appState.procedureDate == null || appState.procedureTime == null)) {
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
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CategoryScreen()));
      });
      return;
    }

      setState(() => _loading = false);
    } catch (e) {
      // Last-resort: do not get stuck on loading if something unexpected happens.
      print('[AppEntryGate] auto-login error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Fallback to WelcomeScreen if not auto-logged in
    return WelcomeScreen(
      onSignUp:
          (
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

              // Register push token as soon as logged in so backend catch-up can run
              await PushService.registerNow();
              await PushService.flushPendingIfAny();
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
      onLogin: (BuildContext context, String username, String password) async {
        print('Attempting login...');
        final error = await ApiService.login(username.trim(), password);
        print('Login response: $error');

        if (error != null) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(title: const Text("Login Failed"), content: Text(error)),
          );
          return error; // satisfy Future<String?>
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
              // After restart/hot-restart, always land on the dashboard (bottom navigation).
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
            } else if (appState.department != null &&
                appState.doctor != null &&
                (appState.treatment == null || appState.procedureDate == null || appState.procedureTime == null)) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => TreatmentScreenMain(userName: appState.username ?? "User")),
              );
            } else if (appState.department == null || appState.doctor == null) {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CategoryScreen()));
            }
          });
          return null; // Ensure Future<String?> completes
        }
      },
    );
  }
}

/// Decides which first screen to show:
/// - If a patient token + username already stored, go directly to patient flow (`/patient`).
/// - Otherwise show the role selection `UserScreen`.
class RootDecider extends StatefulWidget {
  const RootDecider({super.key});
  @override
  State<RootDecider> createState() => _RootDeciderState();
}

class _RootDeciderState extends State<RootDecider> {
  bool _checking = true;
  bool _hasPatient = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      // Ensure any persisted user details + token are loaded
      await appState.loadUserDetails(runBulkSync: false);
      await appState.syncTokenFromPrefs();
      // If a token exists, defer details fetch to AppEntryGate and skip UserScreen
      _hasPatient = appState.token != null;
    } catch (_) {}
    if (mounted)
      setState(() {
        _checking = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Render target directly to avoid any route flicker
    return _hasPatient ? const AppEntryGate() : const UserScreen();
  }
}
