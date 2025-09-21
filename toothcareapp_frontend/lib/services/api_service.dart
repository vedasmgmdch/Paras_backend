import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class ApiService {

<<<<<<< HEAD
  // ---------------------------
  // ✅ Mark Current Treatment as Complete
  // ---------------------------
  static Future<bool> markEpisodeComplete() async {
    try {
      final headers = await getAuthHeaders();
      final url = Uri.parse('$baseUrl/episodes/mark-complete');
      final body = jsonEncode({"procedure_completed": true});
      final response = await http.post(
        url,
        headers: headers,
        body: body,
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        print('Mark episode complete failed: \\${response.statusCode} → \\${response.body}');
        return false;
      }
    } catch (e) {
      print('Mark episode complete error: \\${e}');
      return false;
    }
  }

  // --------------------------
  // ✅ Register device token (FCM)
  // --------------------------
  static Future<bool> registerDeviceToken({required String platform, required String token}) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/push/register-device'),
        headers: headers,
        body: jsonEncode({
          'platform': platform,
          'token': token,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('registerDeviceToken error: $e');
      return false;
    }
  }

  // --------------------------
  // ✅ Send test push (optional)
  // --------------------------
  static Future<bool> sendTestPush({required String title, required String body}) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/push/test'),
        headers: headers,
        body: jsonEncode({'title': title, 'body': body}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('sendTestPush error: $e');
      return false;
    }
  }

=======
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
  // --------------------------
  // ✅ Request Signup OTP
  // --------------------------
  static Future<dynamic> requestSignupOtp(String emailOrPhone) async {
    final url = Uri.parse('$baseUrl/auth/request-signup-otp');
    final Map<String, dynamic> body = {};
    if (emailOrPhone.contains('@')) {
      body['email'] = emailOrPhone;
    } else {
      body['phone'] = emailOrPhone;
    }
    print('REQUEST SIGNUP OTP BODY: ' + jsonEncode(body));
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        try {
          final res = jsonDecode(response.body);
          return res['detail'] ?? res['message'] ?? "Failed to send signup OTP. Please try again.";
        } catch (_) {
          return "Failed to send signup OTP. Please try again.";
        }
      }
    } catch (_) {
      return "Network error. Please check your connection and try again.";
    }
  }

  // --------------------------
  // ✅ Verify Signup OTP
  // --------------------------
  static Future<dynamic> verifySignupOtp(String emailOrPhone, String otp) async {
    final url = Uri.parse('$baseUrl/auth/verify-signup-otp');
    final Map<String, dynamic> body = {};
    if (emailOrPhone.contains('@')) {
      body['email'] = emailOrPhone;
    } else {
      body['phone'] = emailOrPhone;
    }
    body['otp'] = otp;
    print('VERIFY SIGNUP OTP BODY: ' + jsonEncode(body));
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        final res = jsonDecode(response.body);
        return res['detail'] ?? res['message'] ?? 'Signup OTP verification failed';
      }
    } catch (e) {
      return 'Signup OTP verification failed: $e';
    }
  }
<<<<<<< HEAD
  static const String baseUrl = 'https://paras-backend-0gwt.onrender.com';
=======
  static const String baseUrl = 'https://tooth-care-app.onrender.com';
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec

  // --------------------------
  // ✅ Step 1: Verify OTP Only (no password reset)
  // --------------------------
  static Future<dynamic> verifyOtp(String emailOrPhone, String otp) async {
<<<<<<< HEAD
  final url = Uri.parse('https://paras-backend-0gwt.onrender.com/auth/verify-otp');
=======
    final url = Uri.parse('https://tooth-care-app.onrender.com/auth/verify-otp');
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
    final Map<String, dynamic> body = {};
    if (emailOrPhone.contains('@')) {
      body['email'] = emailOrPhone;
    } else {
      body['phone'] = emailOrPhone;
    }
    body['otp'] = otp;
    print('VERIFY OTP BODY: ' + jsonEncode(body));
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        final res = jsonDecode(response.body);
        return res['detail'] ?? res['message'] ?? 'OTP verification failed';
      }
    } catch (e) {
      return 'OTP verification failed: $e';
    }
  }

  // --------------------------
  // ✅ Step 2: Reset Password (requires OTP)
  // --------------------------
  static Future<dynamic> resetPassword(String emailOrPhone, String otp, String newPassword) async {
<<<<<<< HEAD
  final url = Uri.parse('https://paras-backend-0gwt.onrender.com/auth/reset-password');
=======
    final url = Uri.parse('https://tooth-care-app.onrender.com/auth/reset-password');
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
    final Map<String, dynamic> body = {};
    if (emailOrPhone.contains('@')) {
      body['email'] = emailOrPhone;
    } else {
      body['phone'] = emailOrPhone;
    }
    body['otp'] = otp;
    body['new_password'] = newPassword;
    print('RESET PASSWORD BODY: ' + jsonEncode(body));
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        final res = jsonDecode(response.body);
        return res['detail'] ?? res['message'] ?? 'Password reset failed';
      }
    } catch (e) {
      return 'Password reset failed: $e';
    }
  }


  // --------------------------
  // ✅ Save Token Helper
  // --------------------------
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  // --------------------------
  // ✅ Get Token Helper (for persistent login)
  // --------------------------
  static Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // --------------------------
  // ✅ Clear Token Helper
  // --------------------------
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  // --------------------------
  // ✅ Check If Logged In
  // --------------------------
  static Future<bool> checkIfLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('token');
  }

  // --------------------------
  // ✅ SIGNUP (Improved)
  // --------------------------
  static Future<String?> register(Map<String, dynamic> data) async {
    try {
      // Normalize payload to avoid trailing/leading whitespace issues
      final normalized = {
        ...data,
        if (data.containsKey('username')) 'username': (data['username'] ?? '').toString().trim(),
        if (data.containsKey('email')) 'email': (data['email'] ?? '').toString().trim(),
        if (data.containsKey('name')) 'name': (data['name'] ?? '').toString().trim(),
      };
      final response = await http.post(
        Uri.parse('$baseUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(normalized),
      );

      if (response.statusCode == 200) {
        final resBody = jsonDecode(response.body);
        final token = resBody['access_token'];
        if (token != null) {
          await saveToken(token);
        }
        return null;
      } else {
        // Always return the raw backend error body so UI can decode and use it
        return response.body;
      }
    } on SocketException {
      return "Unable to connect. Please check your internet connection.";
    } catch (e) {
      return "An unexpected error occurred. Please try again.";
    }
  }

  // --------------------------
  // ✅ LOGIN (Improved)
  // --------------------------
  static Future<String?> login(String username, String password) async {
    try {
    final normalizedUsername = username.trim();
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
      'username': normalizedUsername,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final resBody = jsonDecode(response.body);
        final token = resBody['access_token'];
        if (token != null) {
          await saveToken(token);
        }
        return null;
      } else {
        try {
          final detail = jsonDecode(response.body)['detail'];
          return _mapLoginError(detail);
        } catch (_) {
          return "Login failed. Please try again.";
        }
      }
    } on SocketException {
      return "Unable to connect. Please check your internet connection.";
    } catch (_) {
      return "An unexpected error occurred. Please try again.";
    }
  }

<<<<<<< HEAD
=======
  // Helper: Map backend signup errors to user-friendly messages
  static String _mapSignupError(String? detail) {
    if (detail == null) return "Signup failed. Please try again.";
    if (detail.contains("Username already exists"))
      return "This username is already taken. Please choose another.";
    if (detail.contains("email already exists"))
      return "This email is already registered. Try logging in or use another email.";
    if (detail.toLowerCase().contains("weak password"))
      return "Password is too weak. Please choose a stronger password.";
    return detail;
  }
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec

  // Helper: Map backend login errors to user-friendly messages
  static String _mapLoginError(String? detail) {
    if (detail == null) return "Login failed. Please try again.";
    if (detail.contains("Incorrect username or password"))
      return "Incorrect username or password.";
    return detail;
  }

  // --------------------------
  // ✅ Auth Header Helper
  // --------------------------
  static Future<Map<String, String>> getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // --------------------------
  // ✅ Get Current Patient Details After Login
  // --------------------------
  static Future<Map<String, dynamic>?> getUserDetails() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
          Uri.parse('$baseUrl/patients/me'), headers: headers);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // --------------------------
  // ✅ Optional debug/test route
  // --------------------------
  static Future<http.Response> getProfile() async {
    final headers = await getAuthHeaders();
    return await http.get(Uri.parse('$baseUrl/patients/me'), headers: headers);
  }

  // --------------------------
  // ✅ Submit Progress Feedback
  // --------------------------
  static Future<bool> submitProgress(String message) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/progress'),
        headers: headers,
        body: jsonEncode({'message': message}),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print('Progress submission failed: ${response.statusCode} → ${response
            .body}');
        return false;
      }
    } catch (e) {
      print('Progress submission error: $e');
      return false;
    }
  }

  // --------------------------
<<<<<<< HEAD
  // ✅ Rotate Episode If Due (15+ days)
  // --------------------------
  static Future<bool> rotateIfDue() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/episodes/rotate-if-due'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['rotated'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // --------------------------
=======
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
  // ✅ Get All Progress Entries
  // --------------------------
  static Future<List<dynamic>?> getProgressEntries() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
          Uri.parse('$baseUrl/progress'), headers: headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ---------------------------
  // ✅ Save Department & Doctor
  // ---------------------------
  static Future<bool> saveDepartmentDoctor({
    required String department,
    required String doctor,
  }) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/department-doctor'),
        headers: headers,
        body: jsonEncode({
          'department': department,
          'doctor': doctor,
        }),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        print(
            'Save department/doctor failed: ${response.statusCode} → ${response
                .body}');
        return false;
      }
    } catch (e) {
      print('Save department/doctor error: $e');
      return false;
    }
  }

  static Future<List<dynamic>?> getEpisodeHistory() async {
    try {
      final headers = await getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/episodes/history'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Get episode history failed: ${response.statusCode} → ${response
            .body}');
        return null;
      }
    } catch (e) {
      print('Get episode history error: $e');
      return null;
    }
  }

  // ---------------------------
  // ✅ Save Treatment Info
  // ---------------------------
  static Future<bool> saveTreatmentInfo({
    required String username,
    required String treatment,
    String? subtype,
    required DateTime procedureDate,
    required TimeOfDay procedureTime,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final url = Uri.parse('$baseUrl/treatment-info');
      final body = {
        'username': username,
        'treatment': treatment,
        'subtype': subtype,
        'procedure_date': procedureDate.toIso8601String().substring(0, 10),
        'procedure_time': '${procedureTime.hour.toString().padLeft(
            2, '0')}:${procedureTime.minute.toString().padLeft(2, '0')}',
      };
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        print(
            'Failed to save treatment info: ${response.statusCode} → ${response
                .body}');
        return false;
      }
    } catch (e) {
      print('Save treatment info error: $e');
      return false;
    }
  }


  static Future<dynamic> requestReset(String emailOrPhone) async {
<<<<<<< HEAD
  final url = Uri.parse('https://paras-backend-0gwt.onrender.com/auth/request-reset');
=======
    final url = Uri.parse('https://tooth-care-app.onrender.com/auth/request-reset');
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
    final Map<String, dynamic> body = {};
    if (emailOrPhone.contains('@')) {
      body['email'] = emailOrPhone;
    } else {
      body['phone'] = emailOrPhone;
    }
    print('REQUEST RESET BODY: ' + jsonEncode(body));

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        // Try to decode error, fallback to generic message
        try {
          final res = jsonDecode(response.body);
          // Only show a friendly message, not the whole exception
          return res['detail'] ?? res['message'] ?? "Failed to send OTP. Please try again.";
        } catch (_) {
          return "Failed to send OTP. Please try again.";
        }
      }
    } catch (_) {
      // Do not show exception details
      return "Network error. Please check your connection and try again.";
    }
  }

}
<<<<<<< HEAD
=======



// Add this inside your ApiService class
>>>>>>> dee5a0178bd2fcc3468c62fa4f2e7372c5fc83ec
