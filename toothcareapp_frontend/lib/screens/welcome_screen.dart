import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'category_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import '../auth_callbacks.dart';
import '../services/api_service.dart';
import 'signup_otp_verification_screen.dart';

class WelcomeScreen extends StatefulWidget {
  final Future<String?> Function(
      BuildContext context,
      String username,
      String password,
      String phone,
      String email,
      String name,
      String dob,
      String gender,
      VoidCallback switchToLogin,
      )? onSignUp;

  final Future<String?> Function(
      BuildContext context,
      String username,
      String password,
      )? onLogin;

  const WelcomeScreen({
    super.key,
    this.onSignUp,
    this.onLogin,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _signUpFormKey = GlobalKey<FormState>();
  final _loginFormKey = GlobalKey<FormState>();

  // Use controllers for all signup fields to preserve input on error
  final TextEditingController _signupUsernameController = TextEditingController();
  final TextEditingController _signupPasswordController = TextEditingController();
  final TextEditingController _signupPhoneController = TextEditingController();
  final TextEditingController _signupEmailController = TextEditingController();
  final TextEditingController _signupNameController = TextEditingController();
  final TextEditingController _dobDayController = TextEditingController();
  final TextEditingController _dobMonthController = TextEditingController();
  final TextEditingController _dobYearController = TextEditingController();

  String _signupUsername = '';
  String _signupPassword = '';
  String _signupPhone = '';
  String _signupEmail = '';
  String _signupName = '';
  String _signupDob = '';
  String _signupGender = 'Male';

  String _loginUsername = '';
  String _loginPassword = '';

  bool _showSignUp = true;
  bool _isLoading = false;

  bool _agreedToHipaa = false;

  String? _usernameError;
  String? _emailError;
  String? _phoneError;
  String? _dobError;

  @override
  void dispose() {
    _signupUsernameController.dispose();
    _signupPasswordController.dispose();
    _signupPhoneController.dispose();
    _signupEmailController.dispose();
    _signupNameController.dispose();
    _dobDayController.dispose();
    _dobMonthController.dispose();
    _dobYearController.dispose();
    super.dispose();
  }

  void _toggleForm() {
    setState(() {
      _showSignUp = !_showSignUp;
      _signUpFormKey.currentState?.reset();
      _loginFormKey.currentState?.reset();
      _agreedToHipaa = false;
      _usernameError = null;
      _emailError = null;
      _phoneError = null;
      _dobError = null;
      // Do NOT clear controllers here!
    });
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  bool _isValidDate(String? y, String? m, String? d) {
    if (y == null || m == null || d == null || y.isEmpty || m.isEmpty ||
        d.isEmpty) return false;
    final year = int.tryParse(y);
    final month = int.tryParse(m);
    final day = int.tryParse(d);
    if (year == null || month == null || day == null) return false;
    try {
      final dt = DateTime(year, month, day);
      return dt.year == year && dt.month == month && dt.day == day;
    } catch (_) {
      return false;
    }
  }

  // Default login implementation if onLogin is not provided
  Future<String?> _defaultLogin(BuildContext context,
      String username,
      String password,) async {
    final error = await ApiService.login(username, password);

    if (error != null) {
      return error;
    }

    final appState = Provider.of<AppState>(context, listen: false);

    // Always clear all state before loading new user!
    appState.clearUserData();

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
      appState.setTreatment(
        userDetails['treatment'],
        subtype: userDetails['treatment_subtype'],
      );
      appState.procedureDate = userDetails['procedure_date'] != null
          ? DateTime.parse(userDetails['procedure_date'])
          : null;
      appState.procedureTime = userDetails['procedure_time'] != null
          ? _parseTimeOfDay(userDetails['procedure_time'])
          : null;
      appState.procedureCompleted =
          userDetails['procedure_completed'] == true;

      // Check if user has already selected a category
      if (appState.hasSelectedCategory) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomeScreen()),
              (route) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => CategoryScreen()),
              (route) => false,
        );
      }
      return null;
    }
    return "Login failed. Could not retrieve user details.";
  }

  // Default sign up implementation if onSignUp is not provided
  Future<String?> _defaultSignUp(BuildContext context,
      String username,
      String password,
      String phone,
      String email,
      String name,
      String dob,
      String gender,
      VoidCallback switchToLogin,) async {
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
      // Try to pass back error as a JSON string if possible
      return error;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    appState.setUserDetails(
      fullName: name,
      dob: DateTime.parse(dob),
      gender: gender,
      username: username,
      password: password,
      phone: phone,
      email: email,
    );
    switchToLogin();
    return null;
  }

  static TimeOfDay? _parseTimeOfDay(dynamic timeStr) {
    if (timeStr == null) return null;
    final str = timeStr is String ? timeStr : timeStr.toString();
    final parts = str.split(":");
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<String?> _handleSignUp() async {
    setState(() {
      _dobError = null;
      _usernameError = null;
      _emailError = null;
      _phoneError = null;
    });
    final day = _dobDayController.text;
    final month = _dobMonthController.text;
    final year = _dobYearController.text;
    if (!_isValidDate(year, month, day)) {
      setState(() => _dobError = "Please enter a valid date of birth.");
      return "Invalid DOB";
    }
    _signupDob =
        "${year.padLeft(4, '0')}-${month.padLeft(2, '0')}-${day.padLeft(2, '0')}";

    if (!_agreedToHipaa) {
      _showErrorDialog("Agreement Required",
          "You must agree to the HIPAA disclaimer before signing up.");
      return "Agreement Required";
    }
    if (_signUpFormKey.currentState?.validate() ?? false) {
  _signUpFormKey.currentState!.save();
  // Get values from controllers for actual signup data
  _signupUsername = _signupUsernameController.text.trim();
  _signupPassword = _signupPasswordController.text;
  _signupPhone = _signupPhoneController.text;
  _signupEmail = _signupEmailController.text.trim();
  _signupName = _signupNameController.text.trim();
      setState(() {
        _isLoading = true;
      });
      try {
        // 1. Register user (do not auto-login)
        final error = await ApiService.register({
          'username': _signupUsernameController.text.trim(),
          'password': _signupPasswordController.text,
          'phone': _signupPhoneController.text,
          'email': _signupEmailController.text.trim(),
          'name': _signupNameController.text.trim(),
          'dob': _signupDob,
          'gender': _signupGender,
        });
        if (error == null) {
          // 2. Request signup OTP
          final otpEmail = _signupEmailController.text.trim();
          print('DEBUG: Email before OTP request: ' + otpEmail);
          final otpResult = await ApiService.requestSignupOtp(otpEmail);
          print('DEBUG: Email before guard clause: ' + otpEmail);
          if (otpResult == true) {
            // 3. Navigate to OTP verification screen for signup
            print('Navigating to OTP screen with email: \x1b[32m' + otpEmail + '\x1b[0m');
            if (otpEmail.trim().isEmpty) {
              print('DEBUG: Blocked navigation due to empty email!');
              _showErrorDialog('Signup Error', 'Email is missing. Please enter your email and try again.');
              return null;
            }
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => SignupOtpVerificationScreen(
                    email: otpEmail,
                  ),
                ),
              );
            }
            // Reset form state
            _signUpFormKey.currentState?.reset();
            setState(() {
              _signupUsernameController.clear();
              _signupPasswordController.clear();
              _signupPhoneController.clear();
              _signupEmailController.clear();
              _signupNameController.clear();
              _signupUsername = '';
              _signupPassword = '';
              _signupPhone = '';
              _signupEmail = '';
              _signupName = '';
              _signupDob = '';
              _signupGender = 'Male';
              _agreedToHipaa = false;
              _usernameError = null;
              _emailError = null;
              _phoneError = null;
              _dobDayController.clear();
              _dobMonthController.clear();
              _dobYearController.clear();
              _dobError = null;
            });
            return null;
          } else {
            _showErrorDialog("OTP Error", otpResult is String ? otpResult : "Failed to send OTP. Please try again.");
            return otpResult is String ? otpResult : "Failed to send OTP. Please try again.";
          }
        } else {
          // Try to parse error as JSON for specific fields, fallback to string
          print("Raw error (as received): $error");
          Map<String, dynamic>? errorJson;
          try {
            errorJson = jsonDecode(error);
          } catch (_) {
            print("Failed to decode error as JSON.");
          }
          setState(() {
            _usernameError = null;
            _emailError = null;
            _phoneError = null;
            if (errorJson != null) {
              final detail = errorJson['detail'];
              if (detail is Map) {
                _usernameError = detail['username'];
                _emailError = detail['email'];
                _phoneError = detail['phone'];
              }
            } else {
              // fallback to string error
              if (error.toLowerCase().contains("username")) {
                _usernameError = error;
              }
              if (error.toLowerCase().contains("email")) {
                _emailError = error;
              }
              if (error.toLowerCase().contains("phone")) {
                _phoneError = error;
              }
            }
          });
          _showErrorDialog(
            "Sign Up Failed",
            (errorJson != null && errorJson['detail'] is Map)
                ? (errorJson['detail'] as Map)
                .values
                .whereType<String>()
                .join('\n')
                : error,
          );
          return error;
        }
      } catch (e) {
        _showErrorDialog(
            "Error", "An unexpected error occurred. Please try again.");
        return "Unknown Error";
      } finally {
        setState(() => _isLoading = false);
      }
    }
    return null;
  }



  Future<String?> _handleLogin() async {
    if (_loginFormKey.currentState?.validate() ?? false) {
      _loginFormKey.currentState!.save();
    // Normalize inputs
    _loginUsername = _loginUsername.trim();
      setState(() => _isLoading = true);
      try {
        final loginFunction = widget.onLogin ?? _defaultLogin;
        final error = await loginFunction(
          context,
      _loginUsername.trim(),
          _loginPassword,
        );
        if (error == null) {
          _loginFormKey.currentState?.reset();
          setState(() {
            _loginUsername = '';
            _loginPassword = '';
          });
          return null;
        } else {
          _showErrorDialog("Login Failed", error);
          return error;
        }
      } catch (e) {
        _showErrorDialog(
            "Error", "An unexpected error occurred. Please try again.");
        return "Unknown Error";
      } finally {
        setState(() => _isLoading = false);
      }
    }
    return null;
  }

  Widget _buildDobConnectedFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Date of Birth",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _dobDayController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: "DD",
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 2,
                  style: const TextStyle(fontSize: 16),
                  onChanged: (_) => setState(() {}),
                  buildCounter: (_,
                      {required currentLength, maxLength, required isFocused}) => null,
                ),
              ),
              Container(width: 1, height: 32, color: Colors.grey.shade400),
              Expanded(
                child: TextFormField(
                  controller: _dobMonthController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: "MM",
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 2,
                  style: const TextStyle(fontSize: 16),
                  onChanged: (_) => setState(() {}),
                  buildCounter: (_,
                      {required currentLength, maxLength, required isFocused}) => null,
                ),
              ),
              Container(width: 1, height: 32, color: Colors.grey.shade400),
              Expanded(
                child: TextFormField(
                  controller: _dobYearController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: "YYYY",
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 4,
                  style: const TextStyle(fontSize: 16),
                  onChanged: (_) => setState(() {}),
                  buildCounter: (_,
                      {required currentLength, maxLength, required isFocused}) => null,
                ),
              ),
            ],
          ),
        ),
        if (_dobError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(_dobError!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        const SizedBox(height: 16),
      ],
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Image.asset(
                      'assets/LOGO2.jpg',
                      width: 64,
                      height: 64,
                      fit: BoxFit.contain,
                    ),
                    Image.asset(
                      'assets/LOGO1.jpg',
                      width: 64,
                      height: 64,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  "Welcome to Post Dental Guide!",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _isLoading
                    ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.0),
                  child: CircularProgressIndicator(),
                )
                    : _showSignUp
                    ? _buildSignUpForm()
                    : _buildLoginForm(context),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _toggleForm,
                  child: Text(
                    _showSignUp
                        ? "Already have an account? Login"
                        : "Don't have an account? Sign up",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignUpForm() {
    return Form(
      key: _signUpFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _signupNameController,
            decoration: const InputDecoration(
              labelText: "Full Name",
              border: OutlineInputBorder(),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? "Enter full name" : null,
            onSaved: (v) => _signupName = v ?? '',
          ),
          const SizedBox(height: 16),
          _buildDobConnectedFields(),
          DropdownButtonFormField<String>(
            value: _signupGender,
            decoration: const InputDecoration(
              labelText: "Gender",
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: "Male", child: Text("Male")),
              DropdownMenuItem(value: "Female", child: Text("Female")),
              DropdownMenuItem(value: "Other", child: Text("Other")),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _signupGender = v);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _signupUsernameController,
            decoration: InputDecoration(
              labelText: "Username",
              border: const OutlineInputBorder(),
              errorText: _usernameError,
            ),
            validator: (v) => v == null || v.trim().isEmpty ? "Enter username" : null,
            onSaved: (v) => _signupUsername = (v ?? '').trim(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _signupPasswordController,
            decoration: const InputDecoration(
              labelText: "Password",
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            validator: (v) {
              if (v == null || v.isEmpty) return "Enter password";
              if (v.length < 6) return "Password must be at least 6 characters";
              return null;
            },
            onSaved: (v) => _signupPassword = v ?? '',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _signupPhoneController,
            decoration: InputDecoration(
              labelText: "Phone Number",
              border: const OutlineInputBorder(),
              errorText: _phoneError,
            ),
            keyboardType: TextInputType.phone,
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return "Enter phone number";
              if (!RegExp(r'^\d{10}$').hasMatch(t)) {
                return "Enter valid 10-digit phone number";
              }
              return null;
            },
            onSaved: (v) => _signupPhone = v ?? '',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _signupEmailController,
            decoration: InputDecoration(
              labelText: "Email Address",
              border: const OutlineInputBorder(),
              errorText: _emailError,
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return "Enter email address";
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w]{2,4}$').hasMatch(t)) {
                return "Enter valid email address";
              }
              return null;
            },
            onSaved: (v) => _signupEmail = v ?? '',
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            value: _agreedToHipaa,
            onChanged: (value) {
              setState(() {
                _agreedToHipaa = value ?? false;
              });
            },
            title: GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) =>
                      AlertDialog(
                        title: const Text('HIPAA Disclaimer'),
                        content: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                "Your privacy is important to us. We comply with the Health Insurance Portability and Accountability Act (HIPAA), which requires us to maintain the privacy and security of your health information.",
                              ),
                              SizedBox(height: 12),
                              Text(
                                "• All health information you provide is encrypted and securely stored.",
                              ),
                              SizedBox(height: 8),
                              Text(
                                "• We will not share your personal health information with anyone except as required by law or as necessary for your care.",
                              ),
                              SizedBox(height: 8),
                              Text(
                                "• You have the right to access, amend, and receive an accounting of disclosures of your health information.",
                              ),
                              SizedBox(height: 8),
                              Text(
                                "• For more details, please review our Privacy Policy.",
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                );
              },
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[800], size: 20),
                  const SizedBox(width: 6),
                  const Flexible(
                    child: Text(
                      'I agree to the HIPAA Disclaimer',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          const Text(
            'By signing up, you agree your data will be used in compliance with HIPAA and our Privacy Policy.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : () => _handleSignUp(),
            child: const Text("Sign Up"),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return Form(
      key: _loginFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            decoration: const InputDecoration(
              labelText: "Username",
              border: OutlineInputBorder(),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? "Enter username" : null,
            onSaved: (v) => _loginUsername = (v ?? '').trim(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            decoration: const InputDecoration(
              labelText: "Password",
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            validator: (v) => v == null || v.isEmpty ? "Enter password" : null,
            onSaved: (v) => _loginPassword = v ?? '',
          ),
          const SizedBox(height: 24),
          // Right-aligned Forgot Password (above Login)
          SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ForgotPasswordScreen(),
                    ),
                  );
                },
                child: const Text(
                  "Forgot Password?",
                  style: TextStyle(
                    color: Color(0xFF6C63FF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Centered Login Button (below)
          Center(
            child: ElevatedButton(
              onPressed: _isLoading ? null : () => _handleLogin(),
              child: const Text("Login"),
            ),
          ),
        ],
      ),
    );
  }
}

// Place these at the top or bottom of your Dart file, outside of any other class!

class InvalidCredentialsException implements Exception {}
class SignUpUsernameTakenException implements Exception {}
class SignUpPhoneTakenException implements Exception {}
class SignUpEmailTakenException implements Exception {}
class SignUpWeakPasswordException implements Exception {}
class SignUpInvalidEmailException implements Exception {}
class SignUpMissingFieldsException implements Exception {}
class SignUpInvalidInputException implements Exception {
  final String message;
  SignUpInvalidInputException([this.message = ""]);
}

class SignUpGenericServerException implements Exception {
  final String message;
  SignUpGenericServerException([this.message = ""]);
}



