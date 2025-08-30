import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'welcome_screen.dart';

class SignupOtpVerificationScreen extends StatefulWidget {
  final String email;
  const SignupOtpVerificationScreen({Key? key, required this.email}) : super(key: key);

  @override
  State<SignupOtpVerificationScreen> createState() => SignupOtpVerificationScreenState();
}

class SignupOtpVerificationScreenState extends State<SignupOtpVerificationScreen> {
  @override
  void initState() {
    super.initState();
    // If email is missing, show error and redirect to WelcomeScreen
    if (widget.email.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const WelcomeScreen(),
            settings: const RouteSettings(arguments: 'Missing email. Please sign up again.'),
          ),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing email. Please sign up again.')),
        );
      });
    }
    _otpController.addListener(() => setState(() {}));
    _startResendTimer();
  }
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _otpController = TextEditingController();
  String _error = '';
  bool _loading = false;
  bool _resending = false;
  int _resendCooldown = 30;
  int _secondsLeft = 0;
  String _resendMessage = '';

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
    final result = await ApiService.requestSignupOtp(widget.email);
    setState(() {
      _resending = false;
      if (result == true) {
        _resendMessage = 'OTP resent! Please check your email.';
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

    print('Verifying signup OTP with email: [32m${widget.email}[0m');
    final result = await ApiService.verifySignupOtp(widget.email, _otpController.text);
    setState(() {
      _loading = false;
    });

    if (result == true) {
      // Show success and go to login
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Verification Successful'),
            content: const Text('Your email has been verified. You can now log in.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    (route) => false,
                  );
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } else {
      String errorMsg = "OTP verification failed. Please try again.";
      if (result is String) errorMsg = result;
      setState(() {
        _error = errorMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OTP verify error: ' + errorMsg)),
      );
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Signup OTP')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Enter the OTP sent to your email",
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
                          child: const Text("Verify"),
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
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
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
