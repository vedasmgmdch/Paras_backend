import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../widgets/no_animation_page_route.dart';
import 'doctor_select_screen.dart';

// Master password only UI: single password box posts to /doctor/master-login.
// Backend must set env DOCTOR_MASTER_PASSWORD (and optional DOCTOR_MASTER_USERNAME).

class DoctorLoginScreen extends StatefulWidget {
  const DoctorLoginScreen({super.key});

  @override
  State<DoctorLoginScreen> createState() => _DoctorLoginScreenState();
}

class _DoctorLoginScreenState extends State<DoctorLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showPassword = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading) return; // single-flight guard
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/doctor/master-login');
      // Extended timeout: cold starts on Render/hosting can exceed 10s occasionally.
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'password': _passwordController.text.trim()}),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final token = data['access_token']?.toString();
        if (token != null && token.isNotEmpty) {
          await ApiService.saveDoctorToken(token);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(NoAnimationPageRoute(builder: (_) => const DoctorSelectScreen()));
          return;
        }
        _error = 'Token missing in response';
      } else {
        // Granular error mapping
        String friendly = 'Login failed (${res.statusCode})';
        try {
          final data = jsonDecode(res.body);
          final detail = data['detail']?.toString();
          if (detail != null) {
            if (detail.contains('Invalid master password')) {
              friendly = 'Incorrect master password';
            } else if (detail.contains('disabled')) {
              friendly = 'Master login disabled on server';
            } else {
              friendly = detail;
            }
          }
        } catch (_) {}
        _error = friendly;
      }
    } on TimeoutException {
      _error = 'Server did not respond (timeout). Try again in a few seconds.';
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('HandshakeException') || msg.contains('CERT')) {
        _error = 'Network TLS/Handshake issue. Check internet or try later.';
      } else if (msg.contains('SocketException')) {
        _error = 'Network error. Check your connection.';
      } else {
        _error = 'Unexpected error: $e';
      }
    }
    if (mounted)
      setState(() {
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Safety: if this route can't pop for any reason, always return to root.
        if (!didPop) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text("Doctor Login"),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'Clear saved doctor token',
              onPressed: () async {
                await ApiService.clearDoctorToken();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Doctor token cleared')));
                }
              },
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: SafeArea(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        colorScheme.surface,
                        colorScheme.surfaceContainerLow,
                      ]
                    : const [
                        Color(0xFFF8FAFF),
                        Colors.white,
                      ],
              ),
            ),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    elevation: 10,
                    shadowColor: Colors.black.withValues(alpha: 0.10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.10),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.admin_panel_settings_outlined,
                                  color: colorScheme.primary,
                                  size: 28,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Secure Master Access',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Enter the master password to continue.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Master Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                                  onPressed: () => setState(() => _showPassword = !_showPassword),
                                  icon: Icon(
                                    _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  ),
                                ),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              obscureText: !_showPassword,
                              enableSuggestions: false,
                              autocorrect: false,
                              textInputAction: TextInputAction.done,
                              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 14),
                            if (_error != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.red.withValues(alpha: 0.22)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(Icons.error_outline, color: Colors.red, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(color: Colors.red, height: 1.2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Continue'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Tip: First login can be slow if the server is waking up.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
