import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'services/api_service.dart';
import 'services/push_service.dart';
// (imports of UI screens removed as they are not used here)

Future<String?> handleSignUp(
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
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Sign Up Failed"),
        content: Text(error),
      ),
    );
    return error;
  } else {
    final appState = Provider.of<AppState>(context, listen: false);
    final token = await ApiService.getSavedToken();
    if (token != null) {
      appState.setToken(token);
    }
    appState.setUserDetails(
      fullName: name,
      dob: DateTime.tryParse(dob) ?? DateTime.now(),
      gender: gender,
      username: username,
      password: password,
      phone: phone,
      email: email,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Sign up successful! Please login.")),
    );
    switchToLogin();
    return null;
  }
}

Future<String?> handleLogin(
  BuildContext context,
  String username,
  String password,
) async {
  String? error = await ApiService.login(username, password);

  if (error != null && ApiService.lastLoginStatusCode == 409) {
    final takeover = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Account in use'),
        content: const Text(
          'This account is currently active on another device. Do you want to login here and sign out the other device?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Login here')),
        ],
      ),
    );
    if (takeover == true) {
      error = await ApiService.login(username, password, forceTakeover: true);
    }
  }

  if (error != null) {
    final String msg = error;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Login Failed"),
        content: Text(msg),
      ),
    );
    return msg;
  } else {
    final appState = Provider.of<AppState>(context, listen: false);
    final token = await ApiService.getSavedToken();
    if (token != null) {
      await appState.setToken(token); // Await this!
    }

    final userDetails = await ApiService.getUserDetails();

    if (userDetails != null) {
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
    } else {
      final msg = ApiService.lastUserDetailsError ?? 'Login failed. Could not retrieve user details.';
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Login Failed'),
          content: Text(msg),
        ),
      );
      return msg;
    }

    // Guarantee state is in sync with saved prefs after login
    await appState.loadUserDetails();

    // Ensure the device token is registered immediately after login
    try {
      // Best-effort; don't block navigation on slow FCM calls.
      unawaited(PushService.initializeAndRegister().timeout(const Duration(seconds: 8), onTimeout: () {}));
    } catch (_) {}

    return null;
  }
}

TimeOfDay? _safeParseTimeOfDay(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString();
  final parts = s.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}
