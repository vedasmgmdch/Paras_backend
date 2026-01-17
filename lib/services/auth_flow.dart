import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../screens/welcome_screen.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../widgets/auth_dialogs.dart';

class AuthFlow {
  static Future<String?> loginWithTakeoverPrompt({
    required BuildContext context,
    required String username,
    required String password,
  }) async {
    String? error = await ApiService.login(username, password);

    if (error != null && ApiService.lastLoginStatusCode == 409) {
      final takeover = await AuthDialogs.confirmSessionTakeover(context);
      if (takeover) {
        error = await ApiService.login(username, password, forceTakeover: true);
      }
    }

    return error;
  }

  static Future<String?> hydrateAfterLogin({
    required AppState appState,
    required String password,
    bool backgroundPush = true,
    bool backgroundHydration = true,
  }) async {
    final savedToken = await ApiService.getSavedToken();
    if (savedToken != null && savedToken.isNotEmpty) {
      await appState.setToken(savedToken);
    }

    if (backgroundPush) {
      unawaited(PushService.registerNow().timeout(const Duration(seconds: 6), onTimeout: () {}));
      unawaited(PushService.flushPendingIfAny().timeout(const Duration(seconds: 6), onTimeout: () {}));
    }

    final userDetails = await ApiService.getUserDetails();
    if (userDetails == null) {
      return ApiService.lastUserDetailsError ?? 'Login failed. Could not retrieve user details.';
    }

    appState.setUserDetails(
      patientId: userDetails['id'] is int ? userDetails['id'] : int.tryParse((userDetails['id'] ?? '').toString()),
      fullName: userDetails['name'],
      dob: DateTime.tryParse((userDetails['dob'] ?? '').toString()) ?? DateTime.now(),
      gender: userDetails['gender'],
      username: userDetails['username'],
      password: password,
      phone: userDetails['phone'],
      email: userDetails['email'],
    );

    await appState.applyThemeModeFromServer(userDetails['theme_mode']);
    appState.setDepartment(userDetails['department']);
    appState.setDoctor(userDetails['doctor']);
    appState.setTreatment(userDetails['treatment'], subtype: userDetails['treatment_subtype']);
    appState.procedureDate = DateTime.tryParse((userDetails['procedure_date'] ?? '').toString());
    appState.procedureTime = _safeParseTimeOfDay(userDetails['procedure_time']);
    appState.procedureCompleted = userDetails['procedure_completed'] == true;

    if (backgroundHydration) {
      unawaited(appState.loadAllChecklists(username: appState.username));
      unawaited(appState.loadInstructionLogs(username: appState.username, force: true));
      unawaited(appState.forceResyncInstructionLogs());
      unawaited(appState.pullInstructionStatusChanges());
    }

    return null;
  }

  static Future<void> signOut(BuildContext context) async {
    final rootNav = Navigator.of(context, rootNavigator: true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final appState = Provider.of<AppState>(context, listen: false);

    Future<void> bestEffort(Future<void> f) async {
      try {
        await f.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    Future<bool> bestEffortBool(Future<bool> f) async {
      try {
        return await f.timeout(const Duration(seconds: 4));
      } catch (_) {
        return false;
      }
    }

    // Stop future pushes for this user/device.
    unawaited(bestEffort(ApiService.unregisterAllDeviceTokens().then((_) {})));

    // Mark this device session inactive (enables login on another device).
    await bestEffortBool(ApiService.logoutCurrentDeviceSession());

    // Best-effort local cleanup.
    unawaited(bestEffort(NotificationService.cancelAllPending()));
    unawaited(bestEffort(PushService.onLogout()));

    await ApiService.clearToken();
    await appState.reset();

    rootNav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => WelcomeScreen()),
      (route) => false,
    );
  }

  static TimeOfDay? _safeParseTimeOfDay(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }
}
