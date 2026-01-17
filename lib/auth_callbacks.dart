import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'services/api_service.dart';
import 'services/auth_flow.dart';
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
  final error = await AuthFlow.loginWithTakeoverPrompt(context: context, username: username, password: password);

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
    final hydrateError = await AuthFlow.hydrateAfterLogin(appState: appState, password: password);
    if (hydrateError != null) {
      final msg = hydrateError;
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

    return null;
  }
}
