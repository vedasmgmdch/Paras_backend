import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../app_state.dart';
import 'category_screen.dart';

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

  Future<void> _persistLoginToken(String username, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_token', token);
    await prefs.setString('username', username);
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState!.save();

    setState(() {
      _loading = true;
      _error = '';
    });

    final appState = Provider.of<AppState>(context, listen: false);
    final result = await ApiService.login(_username, _password);

    if (result != null && result is String) {
      setState(() {
        _error = result;
        _loading = false;
      });
      return;
    }

    String? token = await ApiService.getSavedToken();
    if (token == null || token.isEmpty) {
      setState(() {
        _error = 'Login failed: token not found';
        _loading = false;
      });
      return;
    }

    await _persistLoginToken(_username, token);

    final userDetails = await ApiService.getUserDetails();
    if (userDetails != null) {
      try {
        appState.setUserDetails(
          fullName: userDetails['name'] ?? '',
          dob: DateTime.tryParse(userDetails['dob'] ?? '') ?? DateTime.now(),
          gender: userDetails['gender'] ?? '',
          username: userDetails['username'] ?? '',
          password: _password,
          phone: userDetails['phone'] ?? '',
          email: userDetails['email'] ?? '',
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CategoryScreen()),
        );
      } catch (e) {
        setState(() {
          _error = 'Failed to load user details: $e';
          _loading = false;
        });
      }
    } else {
      setState(() {
        _error = 'Failed to load user details';
        _loading = false;
      });
    }
    setState(() {
      _loading = false;
    });
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
              final result =
              await ApiService.requestReset(_forgotField.trim());
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
              final result = await ApiService.resetPassword(
                _forgotField.trim(),
                _otp.trim(),
                _newPassword.trim(),
              );
              setState(() {
                _forgotLoading = false;
              });
              if (result == true) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Password reset successful! Please login.")),
                );
              } else {
                setState(() {
                  _forgotError = result ?? "OTP verification failed. Try again.";
                });
              }
            }

            return AlertDialog(
              title: Text(_showOtpStep
                  ? "Enter OTP & New Password"
                  : "Forgot Password"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_showOtpStep) ...[
                    TextFormField(
                      enabled: !_forgotLoading,
                      decoration: const InputDecoration(
                        labelText: "OTP",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => _otp = v,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      enabled: !_forgotLoading,
                      decoration: const InputDecoration(
                        labelText: "New Password",
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      onChanged: (v) => _newPassword = v,
                    ),
                  ] else ...[
                    TextFormField(
                      enabled: !_forgotLoading,
                      decoration: const InputDecoration(
                        labelText: "Email or Phone",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => _forgotField = v,
                    ),
                  ],
                  if (_forgotError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _forgotError,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              actions: <Widget>[
                if (!_forgotLoading)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Cancel"),
                  ),
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
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
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
                      labelText: "Username",
                      border: OutlineInputBorder(),
                    ),
          validator: (v) =>
            v == null || v.trim().isEmpty ? "Enter username" : null,
          onSaved: (v) => _username = (v ?? '').trim(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: "Password",
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
          validator: (v) =>
            v == null || v.isEmpty ? "Enter password" : null,
          onSaved: (v) => _password = (v ?? ''),
                  ),
                  const SizedBox(height: 24),
                  // ------------- BUTTONS ROW (100% working) -------------
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: _handleLogin,
                          child: const Text("Login"),
                        ),
                        const SizedBox(width: 16),
                        TextButton(
                          onPressed: _showForgotPasswordDialog,
                          child: const Text(
                            "Forgot Password?",
                            style: TextStyle(
                              color: Color(0xFF6C63FF),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // -------------------------------------------------------
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      // Navigate to your signup screen here
                      // Navigator.push(context, MaterialPageRoute(builder: (_) => SignupScreen()));
                    },
                    child: const Text(
                      "Don't have an account? Sign up",
                      style: TextStyle(
                        color: Color(0xFF6C63FF),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error,
                        style: const TextStyle(color: Colors.red),
                      ),
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