import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading) return; // single-flight guard
    setState(() { _loading = true; _error = null; });
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/doctor/master-login');
      // Extended timeout: cold starts on Render/hosting can exceed 10s occasionally.
      final res = await http.post(
        uri,
        headers: { 'Content-Type': 'application/json' },
        body: jsonEncode({ 'password': _passwordController.text.trim() }),
      ).timeout(const Duration(seconds: 25));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final token = data['access_token']?.toString();
        if (token != null && token.isNotEmpty) {
            await ApiService.saveDoctorToken(token);
            if (!mounted) return;
            Navigator.of(context).pushReplacementNamed('/doctor-patients');
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
        } catch(_) {}
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
    if (mounted) setState(() { _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Doctor Login"), actions: [
        IconButton(
          tooltip: 'Clear saved doctor token',
          onPressed: () async { await ApiService.clearDoctorToken(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Doctor token cleared'))); },
          icon: const Icon(Icons.logout),
        )
      ]),
      body: SafeArea(
        child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Secure Master Access',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _passwordController,
                            decoration: const InputDecoration(labelText: 'Master Password', border: OutlineInputBorder()),
                            obscureText: true,
                            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 20),
                          if (_error != null) ...[
                            Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                            const SizedBox(height: 6),
                            const Text(
                              'Tips: Ensure server awake (first call can be slow). If repeated timeouts persist beyond 30s, backend may be sleeping or unreachable.',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              child: _loading
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Login'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}