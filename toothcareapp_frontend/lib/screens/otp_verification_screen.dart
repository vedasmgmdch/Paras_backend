import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:flutter/services.dart';
import 'login_screen.dart';
import 'set_new_password_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String emailOrPhone;
  const OtpVerificationScreen({super.key, required this.emailOrPhone});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}


class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  @override
  void initState() {
    super.initState();
    _otpController.addListener(() => setState(() {}));
    _startResendTimer();
  }
  String get _otp => _otpController.text;
  String _error = '';
  bool _loading = false;
  bool _resending = false;
  int _resendCooldown = 30;
  int _secondsLeft = 0;
  String _resendMessage = '';

  // Removed duplicate initState

  void _startResendTimer() {
    setState(() {
      _secondsLeft = _resendCooldown;
    });
    Future.doWhile(() async {
      if (_secondsLeft == 0) return false;
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _secondsLeft--;
        });
      }
      return _secondsLeft > 0;
    });
  }

  Future<void> _resendOtp() async {
    setState(() {
      _resending = true;
      _resendMessage = '';
    });
    final result = await ApiService.requestReset(widget.emailOrPhone);
    setState(() {
      _resending = false;
      if (result == true) {
        _resendMessage = 'OTP resent! Please check your email or phone.';
        _startResendTimer();
      } else {
        _resendMessage = result is String ? result : 'Failed to resend OTP.';
      }
    });
  }

  Future<void> _submitOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState!.save();

    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await ApiService.verifyOtp(widget.emailOrPhone, _otp);
    print('OTP verify result: ' + result.toString());

    setState(() {
      _loading = false;
    });

    if (result == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SetNewPasswordScreen(
            emailOrPhone: widget.emailOrPhone,
            otp: _otp,
          ),
        ),
      );
    } else {
      // If backend returns a list of errors, show the first error message
      String errorMsg = "OTP verification failed. Please try again.";
      if (result is List && result.isNotEmpty && result[0]['msg'] != null) {
        errorMsg = result[0]['msg'];
      } else if (result is String) {
        errorMsg = result;
      }
      setState(() {
        _error = errorMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OTP verify error: ' + errorMsg)),
      );
    }
  }
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _otpController = TextEditingController();

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Enter the OTP sent to your email or phone",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.left,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    labelText: 'Enter OTP',
                    border: OutlineInputBorder(),
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please enter OTP';
                    if (v.length != 6) return 'OTP must be 6 digits';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (val) {
                    if (val.length == 6) {
                      _submitOtp();
                    }
                  },
                ),
                const SizedBox(height: 8),
                _resending
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : TextButton(
                        onPressed: _secondsLeft == 0 ? _resendOtp : null,
                        child: Text(_secondsLeft == 0
                            ? "Resend OTP"
                            : "Resend OTP in $_secondsLeft s"),
                      ),
                const SizedBox(height: 24),
                _loading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: !_loading && _otpController.text.length == 6
                              ? () async {
                                  if (_formKey.currentState?.validate() ?? false) {
                                    await _submitOtp();
                                  }
                                }
                              : null,
                          child: const Text("Reset Password"),
                        ),
                      ),
                const SizedBox(height: 16),
                if (_resendMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _resendMessage,
                      style: TextStyle(
                        color: _resendMessage.startsWith('OTP resent')
                            ? Colors.green
                            : Colors.red,
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

                // Add navigation to LoginScreen
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}