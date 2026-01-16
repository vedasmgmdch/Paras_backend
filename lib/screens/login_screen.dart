import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../app_state.dart';
import 'category_screen.dart';
import 'home_screen.dart';
import 'treatment_screen.dart';
import '../services/push_service.dart';
import 'welcome_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _username = '';
  String _password = '';
  String _error = '';
  bool _loading = false;

  // For forgot password dialog flow
  String _forgotField = '';
  String _otp = '';
  String _newPassword = '';
  String _forgotError = '';
  bool _forgotLoading = false;
  bool _showOtpStep = false;

  TimeOfDay? _parseTimeOfDay(dynamic timeStr) {
    if (timeStr == null) return null;
    final str = timeStr is String ? timeStr : timeStr.toString();
    final parts = str.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _persistLoginToken(String username, String token) async {
    final prefs = await SharedPreferences.getInstance();
    // Store under the same key ApiService uses
    await prefs.setString('token', token);
    await prefs.setString('username', username);
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState!.save();

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    final appState = Provider.of<AppState>(context, listen: false);
    final result = await ApiService.login(_username, _password);

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _error = result;
        _loading = false;
      });
      return;
    }

    String? token = await ApiService.getSavedToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() {
        _error = 'Login failed: token not found';
        _loading = false;
      });
      return;
    }

    // Persist and sync token immediately so the rest of the app sees it
    await _persistLoginToken(_username, token);
    await appState.setToken(token);
    // Ensure this account owns the device token on the backend
    await PushService.registerNow();
    await PushService.flushPendingIfAny();

    if (!mounted) return;

    final userDetails = await ApiService.getUserDetails();
    if (!mounted) return;
    if (userDetails != null) {
      try {
        appState.setUserDetails(
          patientId: userDetails['id'] is int ? userDetails['id'] : int.tryParse((userDetails['id'] ?? '').toString()),
          fullName: userDetails['name'] ?? '',
          dob: DateTime.tryParse(userDetails['dob'] ?? '') ?? DateTime.now(),
          gender: userDetails['gender'] ?? '',
          username: (userDetails['username'] ?? _username).toString(),
          password: _password,
          phone: userDetails['phone'] ?? '',
          email: userDetails['email'] ?? '',
        );

        await appState.applyThemeModeFromServer(userDetails['theme_mode']);

        // Hydrate selection info so this device matches the account.
        appState.setDepartment(userDetails['department']?.toString());
        appState.setDoctor(userDetails['doctor']?.toString());
        appState.setTreatment(
          userDetails['treatment']?.toString(),
          subtype: userDetails['treatment_subtype']?.toString(),
        );
        final procDate = userDetails['procedure_date']?.toString();
        if (procDate != null && procDate.isNotEmpty) {
          appState.procedureDate = DateTime.tryParse(procDate);
        }
        final procTime = userDetails['procedure_time'];
        final parsedTime = _parseTimeOfDay(procTime);
        if (parsedTime != null) appState.procedureTime = parsedTime;
        appState.procedureCompleted = userDetails['procedure_completed'] == true;

        // Pull server-side instruction ticks (non-blocking).
        // Instruction screens will reflect these once loaded.
        unawaited(appState.pullInstructionStatusChanges());
        // Reminders are server-only (push) and follow the account across devices.
        // Route based on what’s already stored for this account.
        if (appState.department != null &&
            appState.doctor != null &&
            appState.treatment != null &&
            appState.procedureDate != null &&
            appState.procedureTime != null &&
            appState.procedureCompleted == false) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          return;
        } else if (appState.department != null &&
            appState.doctor != null &&
            (appState.treatment == null || appState.procedureDate == null || appState.procedureTime == null)) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => TreatmentScreenMain(userName: appState.username ?? 'User')),
          );
          return;
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CategoryScreen()));
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Failed to load user details: $e';
          _loading = false;
        });
        return;
      }
    } else {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load user details';
        _loading = false;
      });
      return;
    }
  }

  void _showForgotPasswordDialog() {
    _forgotField = '';
    _otp = '';
    _newPassword = '';
    _forgotError = '';
    _forgotLoading = false;
    _showOtpStep = false;

    showDialog(
      context: context,
      barrierDismissible: !_forgotLoading,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> requestOtp() async {
              setState(() {
                _forgotLoading = true;
                _forgotError = '';
              });
              final result = await ApiService.requestReset(_forgotField.trim());
              setState(() {
                _forgotLoading = false;
                if (result == true) {
                  _showOtpStep = true;
                } else {
                  _forgotError = result ?? "Failed to send OTP. Try again.";
                }
              });
            }

            Future<void> verifyOtpAndReset() async {
              setState(() {
                _forgotLoading = true;
                _forgotError = '';
              });
              final result = await ApiService.resetPassword(_forgotField.trim(), _otp.trim(), _newPassword.trim());
              setState(() {
                _forgotLoading = false;
              });
              if (result == true) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("Password reset successful! Please login.")));
              } else {
                setState(() {
                  _forgotError = result ?? "OTP verification failed. Try again.";
                });
              }
            }

            return AlertDialog(
              title: Text(_showOtpStep ? "Enter OTP & New Password" : "Forgot Password"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_showOtpStep) ...[
                    TextFormField(
                      enabled: !_forgotLoading,
                      decoration: const InputDecoration(labelText: "OTP", border: OutlineInputBorder()),
                      onChanged: (v) => _otp = v,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      enabled: !_forgotLoading,
                      decoration: const InputDecoration(labelText: "New Password", border: OutlineInputBorder()),
                      obscureText: true,
                      onChanged: (v) => _newPassword = v,
                    ),
                  ] else ...[
                    TextFormField(
                      enabled: !_forgotLoading,
                      decoration: const InputDecoration(labelText: "Email or Phone", border: OutlineInputBorder()),
                      onChanged: (v) => _forgotField = v,
                    ),
                  ],
                  if (_forgotError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(_forgotError, style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
              actions: <Widget>[
                if (!_forgotLoading)
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
                TextButton(
                  onPressed: _forgotLoading
                      ? null
                      : () {
                          if (_showOtpStep) {
                            if (_otp.isEmpty || _newPassword.isEmpty) {
                              setState(() {
                                _forgotError = "Enter OTP and new password.";
                              });
                            } else {
                              verifyOtpAndReset();
                            }
                          } else {
                            if (_forgotField.trim().isEmpty) {
                              setState(() {
                                _forgotError = "Enter your email or phone.";
                              });
                            } else {
                              requestOtp();
                            }
                          }
                        },
                  child: _forgotLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_showOtpStep ? "Reset Password" : "Send OTP"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final linkColor = isDark ? cs.primary : const Color(0xFF6C63FF);

    return Scaffold(
      backgroundColor: isDark ? cs.surface : const Color(0xFFF8FAFF),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 40),
                  const Text(
                    "Welcome to Post Dental Guide!",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: "Username (not email/phone)",
                      helperText: "Use the username you created during signup.",
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? "Enter username" : null,
                    onSaved: (v) => _username = (v ?? '').trim(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()),
                    obscureText: true,
                    validator: (v) => v == null || v.isEmpty ? "Enter password" : null,
                    onSaved: (v) => _password = (v ?? ''),
                  ),
                  const SizedBox(height: 24),
                  // Forgot Password (right aligned)
                  SizedBox(
                    width: double.infinity,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading ? null : _showForgotPasswordDialog,
                        child: Text(
                          "Forgot Password?",
                          style: TextStyle(color: linkColor, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Login button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _handleLogin,
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text("Login"),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Sign up link directly below Login
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                            );
                          },
                    child: Text(
                      "Don't have an account? Sign up",
                      style: TextStyle(color: linkColor, decoration: TextDecoration.underline),
                    ),
                  ),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_error, style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
