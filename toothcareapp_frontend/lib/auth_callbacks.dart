import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'services/api_service.dart';
import 'screens/category_screen.dart';
import 'screens/home_screen.dart';
import 'screens/treatment_screen.dart';
import 'screens/pfd_instructions_screen.dart';
import 'screens/prd_instructions_screen.dart';

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
      dob: DateTime.parse(dob),
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
  final error = await ApiService.login(username, password);

  if (error != null) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Login Failed"),
        content: Text(error),
      ),
    );
    return error;
  } else {
    final appState = Provider.of<AppState>(context, listen: false);
    final token = await ApiService.getSavedToken();
    if (token != null) {
      await appState.setToken(token); // Await this!
    }

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
      appState.setDepartment(userDetails['department']);
      appState.setDoctor(userDetails['doctor']);
      appState.setTreatment(userDetails['treatment'], subtype: userDetails['treatment_subtype']);
      appState.procedureDate = userDetails['procedure_date'] != null
          ? DateTime.parse(userDetails['procedure_date'])
          : null;
      appState.procedureTime = TimeOfDay(
        hour: int.tryParse(userDetails['procedure_time']?.split(":")?[0] ?? "") ?? 0,
        minute: int.tryParse(userDetails['procedure_time']?.split(":")?[1] ?? "") ?? 0,
      );
      appState.procedureCompleted = userDetails['procedure_completed'] == true;
    }

    // Guarantee state is in sync with saved prefs after login
    await appState.loadUserDetails();

    return null;
  }
}