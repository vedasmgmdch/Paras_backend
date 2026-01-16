import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

dynamic _jsonDecodeInBackground(String body) => jsonDecode(body);

class ApiService {
  static const Duration _slowEndpointTimeout = Duration(seconds: 60);
  static Future<dynamic> _decodeJson(String body) async {
    // Avoid isolate overhead for small payloads.
    if (body.length < 50 * 1024) {
      return jsonDecode(body);
    }
    return compute(_jsonDecodeInBackground, body);
  }

  // ---------------------------
  // ✅ Get server UTC time (from /diag/echo)
  // ---------------------------
  static Future<DateTime?> getServerUtcNow() async {
    try {
      final headers = await getAuthHeaders();
      final res = await http.get(Uri.parse('$baseUrl/diag/echo'), headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final utcStr = data['utc']?.toString();
        if (utcStr != null && utcStr.isNotEmpty) {
          // utcStr like 2025-10-19T12:34:56.123456Z; DateTime.parse handles Z
          return DateTime.parse(utcStr).toUtc();
        }
      }
    } catch (e) {
      // ignore and fallback to device time elsewhere
    }
    return null;
  }

  // ---------------------------
  // ✅ Mark Current Treatment as Complete
  // ---------------------------
  static Future<bool> markEpisodeComplete() async {
    try {
      final headers = await getAuthHeaders();
      final url = Uri.parse('$baseUrl/episodes/mark-complete');
      final body = jsonEncode({"procedure_completed": true});
      final response = await http.post(url, headers: headers, body: body).timeout(_slowEndpointTimeout);
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
      final response = await http
          .post(
            Uri.parse('$baseUrl/push/register-device'),
            headers: headers,
            body: jsonEncode({'platform': platform, 'token': token}),
          )
          .timeout(_slowEndpointTimeout);
      if (response.statusCode == 200) return true;
      // ignore: avoid_print
      print('registerDeviceToken failed: ${response.statusCode} -> ${response.body}');
      return false;
    } catch (e) {
      print('registerDeviceToken error: $e');
      return false;
    }
  }

  // --------------------------
  // ✅ List my registered device tokens (debug)
  // --------------------------
  static Future<List<Map<String, dynamic>>> listDeviceTokens() async {
    try {
      final headers = await getAuthHeaders();
      final res = await http.get(Uri.parse('$baseUrl/push/devices'), headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        }
      } else {
        print('listDeviceTokens failed: ${res.statusCode} -> ${res.body}');
      }
    } catch (e) {
      print('listDeviceTokens error: $e');
    }
    return [];
  }

  // --------------------------
  // ✅ Delete a registered device token by id
  // --------------------------
  static Future<bool> deleteDeviceToken(int deviceId) async {
    try {
      final headers = await getAuthHeaders();
      final res = await http
          .delete(Uri.parse('$baseUrl/push/devices/$deviceId'), headers: headers)
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) return true;
      print('deleteDeviceToken failed: ${res.statusCode} -> ${res.body}');
      return false;
    } catch (e) {
      print('deleteDeviceToken error: $e');
      return false;
    }
  }

  // --------------------------
  // ✅ Best-effort: unregister ALL my device tokens
  //
  // Call this BEFORE clearing auth token (logout), so the backend stops
  // dispatching scheduled pushes to this device when logged out.
  // --------------------------
  static Future<int> unregisterAllDeviceTokens() async {
    try {
      final devices = await listDeviceTokens();
      int deleted = 0;
      for (final d in devices) {
        final idVal = d['id'];
        final id = idVal is int ? idVal : int.tryParse(idVal?.toString() ?? '');
        if (id == null) continue;
        final ok = await deleteDeviceToken(id);
        if (ok) deleted += 1;
      }
      return deleted;
    } catch (e) {
      print('unregisterAllDeviceTokens error: $e');
      return 0;
    }
  }

  // --------------------------
  // ✅ Best-effort: logout THIS device session
  //
  // Call this BEFORE clearing auth token so the backend can mark the
  // current device as inactive, enabling login from another device.
  // --------------------------
  static Future<bool> logoutCurrentDeviceSession() async {
    try {
      final headers = await getAuthHeaders();
      final deviceId = await getOrCreateDeviceId();
      final res = await http
          .post(
            Uri.parse('$baseUrl/session/logout'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded', if (headers['Authorization'] != null) 'Authorization': headers['Authorization']!},
            body: {'device_id': deviceId},
          )
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) return true;
      print('logoutCurrentDeviceSession failed: ${res.statusCode} -> ${res.body}');
      return false;
    } catch (e) {
      print('logoutCurrentDeviceSession error: $e');
      return false;
    }
  }

  // --------------------------
  // ✅ Send test push (optional)
  // --------------------------
  static Future<bool> sendTestPush({required String title, required String body}) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/push/test'),
            headers: headers,
            body: jsonEncode({'title': title, 'body': body}),
          )
          .timeout(_slowEndpointTimeout);
      return response.statusCode == 200;
    } catch (e) {
      print('sendTestPush error: $e');
      return false;
    }
  }

  // --------------------------
  // ✅ Schedule a server push (convert to UTC, strip timezone)
  // --------------------------
  static Future<bool> schedulePush({required String title, required String body, required DateTime sendAtLocal}) async {
    try {
      final headers = await getAuthHeaders();
      // Convert local time to UTC, format as yyyy-MM-ddTHH:mm:ss without 'Z'
      final utc = sendAtLocal.toUtc();
      final iso = utc.toIso8601String();
      final trimmed = iso.endsWith('Z') ? iso.substring(0, iso.length - 1) : iso;
      final payload = {'title': title, 'body': body, 'send_at': trimmed};
      final res = await http
          .post(Uri.parse('$baseUrl/push/schedule'), headers: headers, body: jsonEncode(payload))
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) return true;
      print('schedulePush failed: ${res.statusCode} → ${res.body}');
      return false;
    } catch (e) {
      print('schedulePush error: $e');
      return false;
    }
  }

  // --------------------------
  // ✅ Dispatch due pushes for current user
  // --------------------------
  static Future<Map<String, dynamic>?> dispatchMine() async {
    try {
      final headers = await getAuthHeaders();
      final res = await http
          .post(Uri.parse('$baseUrl/push/dispatch-mine'), headers: headers, body: jsonEncode({}))
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      print('dispatchMine failed: ${res.statusCode} → ${res.body}');
      return null;
    } catch (e) {
      print('dispatchMine error: $e');
      return null;
    }
  }

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
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_slowEndpointTimeout);
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
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_slowEndpointTimeout);
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

  static const String baseUrl = 'https://paras-backend-0gwt.onrender.com';

  // --------------------------
  // ✅ Step 1: Verify OTP Only (no password reset)
  // --------------------------
  static Future<dynamic> verifyOtp(String emailOrPhone, String otp) async {
    final url = Uri.parse('https://paras-backend-0gwt.onrender.com/auth/verify-otp');
    final Map<String, dynamic> body = {};
    if (emailOrPhone.contains('@')) {
      body['email'] = emailOrPhone;
    } else {
      body['phone'] = emailOrPhone;
    }
    body['otp'] = otp;
    print('VERIFY OTP BODY: ' + jsonEncode(body));
    try {
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_slowEndpointTimeout);
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
    final url = Uri.parse('https://paras-backend-0gwt.onrender.com/auth/reset-password');
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
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_slowEndpointTimeout);
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
  // 🔐 Doctor Token Handling (separate from patient token)
  // --------------------------
  static Future<void> saveDoctorToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('doctor_token', token);
  }

  static Future<String?> getDoctorToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('doctor_token');
  }

  static Future<void> clearDoctorToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('doctor_token');
  }

  static Future<Map<String, String>> getDoctorAuthHeaders() async {
    final token = await getDoctorToken();
    final Map<String, String> h = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer ' + token;
    }
    return h;
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
      final response = await http
          .post(
            Uri.parse('$baseUrl/signup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(normalized),
          )
          .timeout(_slowEndpointTimeout);

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
        body: {'username': normalizedUsername, 'password': password},
      ).timeout(_slowEndpointTimeout);

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

  // Map backend login errors to user-friendly messages
  static String _mapLoginError(String? detail) {
    if (detail == null) return "Login failed. Please try again.";
    if (detail.contains("Incorrect username or password")) {
      return "Incorrect username or password.";
    }
    return detail;
  }

  // --------------------------
  // ✅ Auth Header Helper
  // --------------------------
  static Future<Map<String, String>> getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  // --------------------------
  // 💬 Chat (patient + doctor)
  // --------------------------
  static Future<List<dynamic>?> getChatThread() async {
    try {
      final headers = await getAuthHeaders();
      final res = await http.get(Uri.parse('$baseUrl/chat/thread'), headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final decoded = await _decodeJson(res.body);
        if (decoded is List) return decoded;
      }
      // ignore: avoid_print
      print('getChatThread failed: ${res.statusCode} -> ${res.body}');
    } catch (e) {
      // ignore: avoid_print
      print('getChatThread error: $e');
    }
    return null;
  }

  static Future<bool> sendChatMessage(String message) async {
    try {
      final headers = await getAuthHeaders();
      final res = await http
          .post(
            Uri.parse('$baseUrl/chat/thread'),
            headers: headers,
            body: jsonEncode({'message': message}),
          )
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200 || res.statusCode == 201) return true;
      // ignore: avoid_print
      print('sendChatMessage failed: ${res.statusCode} -> ${res.body}');
    } catch (e) {
      // ignore: avoid_print
      print('sendChatMessage error: $e');
    }
    return false;
  }

  static Future<List<dynamic>?> getDoctorChatThread(String patientUsername) async {
    try {
      final headers = await getDoctorAuthHeaders();
      final res = await http
          .get(Uri.parse('$baseUrl/doctor/patients/$patientUsername/chat'), headers: headers)
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final decoded = await _decodeJson(res.body);
        if (decoded is List) return decoded;
      }
      // ignore: avoid_print
      print('getDoctorChatThread failed: ${res.statusCode} -> ${res.body}');
    } catch (e) {
      // ignore: avoid_print
      print('getDoctorChatThread error: $e');
    }
    return null;
  }

  static Future<bool> sendDoctorChatMessage(String patientUsername, String message) async {
    try {
      final headers = await getDoctorAuthHeaders();
      final res = await http
          .post(
            Uri.parse('$baseUrl/doctor/patients/$patientUsername/chat'),
            headers: headers,
            body: jsonEncode({'message': message}),
          )
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200 || res.statusCode == 201) return true;
      // ignore: avoid_print
      print('sendDoctorChatMessage failed: ${res.statusCode} -> ${res.body}');
    } catch (e) {
      // ignore: avoid_print
      print('sendDoctorChatMessage error: $e');
    }
    return false;
  }

  // --------------------------
  // ✅ Get Current Patient Details After Login
  // --------------------------
  static Future<Map<String, dynamic>?> getUserDetails() async {
    try {
      final headers = await getAuthHeaders();
      final response =
          await http.get(Uri.parse('$baseUrl/patients/me'), headers: headers).timeout(_slowEndpointTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // --------------------------
  // ✅ Hybrid Reminder Endpoints
  // --------------------------
  static Future<List<Map<String, dynamic>>> listReminders() async {
    try {
      // ignore: avoid_print
      print('[ApiService] listReminders() → GET /reminders');
      final headers = await getAuthHeaders();
      final res = await http.get(Uri.parse('$baseUrl/reminders'), headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is List) {
          // ignore: avoid_print
          print('[ApiService] listReminders() ← ${body.length} items');
          return body.cast<Map<String, dynamic>>();
        }
      } else {
        print('listReminders failed: ${res.statusCode} → ${res.body}');
      }
    } catch (e) {
      print('listReminders error: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> createReminder({
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String timezone,
    bool active = true,
    int graceMinutes = 20,
  }) async {
    try {
      // ignore: avoid_print
      print('[ApiService] createReminder() hour=$hour minute=$minute title="$title"');
      final headers = await getAuthHeaders();
      final payload = jsonEncode({
        'title': title,
        'body': body,
        'hour': hour,
        'minute': minute,
        'timezone': timezone,
        'active': active,
        'grace_minutes': graceMinutes,
      });
      final res = await http
          .post(Uri.parse('$baseUrl/reminders'), headers: headers, body: payload)
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body) as Map<String, dynamic>;
        // ignore: avoid_print
        print('[ApiService] createReminder() ← id=${parsed['id']} next_fire_local=${parsed['next_fire_local']}');
        return parsed;
      }
      print('createReminder failed: ${res.statusCode} → ${res.body}');
    } catch (e) {
      print('createReminder error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> updateReminder(int id, Map<String, dynamic> patch) async {
    try {
      // ignore: avoid_print
      print('[ApiService] updateReminder(id=$id) keys=${patch.keys.toList()}');
      final headers = await getAuthHeaders();
      final res = await http
          .patch(Uri.parse('$baseUrl/reminders/$id'), headers: headers, body: jsonEncode(patch))
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body) as Map<String, dynamic>;
        // ignore: avoid_print
        print(
          '[ApiService] updateReminder(id=$id) ← next_fire_local=${parsed['next_fire_local']} active=${parsed['active']}',
        );
        return parsed;
      }
      print('updateReminder failed: ${res.statusCode} → ${res.body}');
    } catch (e) {
      print('updateReminder error: $e');
    }
    return null;
  }

  static Future<bool> deleteReminder(int id) async {
    try {
      // ignore: avoid_print
      print('[ApiService] deleteReminder(id=$id)');
      final headers = await getAuthHeaders();
      final res =
          await http.delete(Uri.parse('$baseUrl/reminders/$id'), headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) return true;
      print('deleteReminder failed: ${res.statusCode} → ${res.body}');
    } catch (e) {
      print('deleteReminder error: $e');
    }
    return false;
  }

  static Future<bool> ackReminder(int id) async {
    try {
      // ignore: avoid_print
      print('[ApiService] ackReminder(id=$id)');
      final headers = await getAuthHeaders();
      final res = await http
          .post(
            Uri.parse('$baseUrl/reminders/ack'),
            headers: headers,
            body: jsonEncode({'reminder_id': id}),
          )
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) return true;
      print('ackReminder failed: ${res.statusCode} → ${res.body}');
    } catch (e) {
      print('ackReminder error: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>?> syncReminders(List<Map<String, dynamic>> items) async {
    try {
      // ignore: avoid_print
      print('[ApiService] syncReminders(count=${items.length})');
      final headers = await getAuthHeaders();
      final res = await http
          .post(
            Uri.parse('$baseUrl/reminders/sync'),
            headers: headers,
            body: jsonEncode({'items': items}),
          )
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final parsed = jsonDecode(res.body) as Map<String, dynamic>;
        // ignore: avoid_print
        print('[ApiService] syncReminders() ← keys=${parsed.keys}');
        return parsed;
      }
      print('syncReminders failed: ${res.statusCode} → ${res.body}');
    } catch (e) {
      print('syncReminders error: $e');
    }
    return null;
  }

  // --------------------------
  // ✅ Optional debug/test route
  // --------------------------
  static Future<http.Response> getProfile() async {
    final headers = await getAuthHeaders();
    return await http.get(Uri.parse('$baseUrl/patients/me'), headers: headers).timeout(_slowEndpointTimeout);
  }

  // --------------------------
  // ✅ Submit Progress Feedback
  // --------------------------
  static Future<bool> submitProgress(String message) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/progress'),
            headers: headers,
            body: jsonEncode({'message': message}),
          )
          .timeout(_slowEndpointTimeout);

      if (response.statusCode == 200) {
        return true;
      } else {
        print('Progress submission failed: ${response.statusCode} → ${response.body}');
        return false;
      }
    } catch (e) {
      print('Progress submission error: $e');
      return false;
    }
  }

  // --------------------------
  // ✅ Rotate Episode If Due (15+ days)
  // --------------------------
  static Future<bool> rotateIfDue() async {
    try {
      final headers = await getAuthHeaders();
      final response =
          await http.post(Uri.parse('$baseUrl/episodes/rotate-if-due'), headers: headers).timeout(_slowEndpointTimeout);
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
  // ✅ Get All Progress Entries
  // --------------------------
  static Future<List<dynamic>?> getProgressEntries() async {
    try {
      final headers = await getAuthHeaders();
      final uri = Uri.parse('$baseUrl/progress');
      print('[Api] → GET $uri');
      final response = await http.get(uri, headers: headers).timeout(_slowEndpointTimeout);
      print('[Api] ← ${response.statusCode} (${response.body.length} bytes) for /progress');
      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          if (data is List) return data;
          print('[Api][warn] /progress expected list got ${data.runtimeType}');
          return null;
        } catch (e) {
          print('[Api][error] /progress decode failed: $e');
          return null;
        }
      } else {
        print('[Api][error] /progress failed: ${response.statusCode} → ${response.body}');
      }
    } on TimeoutException {
      print('[Api][timeout] /progress >${_slowEndpointTimeout.inSeconds}s');
    } on SocketException catch (e) {
      print('[Api][net] /progress network error: $e');
    } catch (e) {
      print('[Api][unexpected] /progress error: $e');
    }
    return null;
  }

  // ---------------------------
  // ✅ Save Department & Doctor
  // ---------------------------
  static Future<bool> saveDepartmentDoctor({required String department, required String doctor}) async {
    try {
      final headers = await getAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/department-doctor'),
            headers: headers,
            body: jsonEncode({'department': department, 'doctor': doctor}),
          )
          .timeout(_slowEndpointTimeout);
      if (response.statusCode == 200) {
        return true;
      } else {
        print('Save department/doctor failed: ${response.statusCode} → ${response.body}');
        return false;
      }
    } catch (e) {
      print('Save department/doctor error: $e');
      return false;
    }
  }

  static Future<List<dynamic>?> getEpisodeHistory() async {
    final headers = await getAuthHeaders();
    final response =
        await http.get(Uri.parse('$baseUrl/episodes/history'), headers: headers).timeout(_slowEndpointTimeout);
    if (response.statusCode == 200) {
      final decoded = await _decodeJson(response.body);
      if (decoded is List) return decoded;
      throw FormatException('Get episode history unexpected payload: ${decoded.runtimeType}');
    }

    // Surface auth/server errors to the caller so the UI can display them (e.g. 401 Unauthorized).
    final body = response.body;
    final snippet = body.length > 300 ? body.substring(0, 300) : body;
    throw HttpException('Get episode history failed: ${response.statusCode} → $snippet');
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
      final headers = {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
      final url = Uri.parse('$baseUrl/treatment-info');
      final body = {
        'username': username,
        'treatment': treatment,
        'subtype': subtype,
        'procedure_date': procedureDate.toIso8601String().substring(0, 10),
        'procedure_time':
            '${procedureTime.hour.toString().padLeft(2, '0')}:${procedureTime.minute.toString().padLeft(2, '0')}',
      };
      final response = await http.post(url, headers: headers, body: jsonEncode(body)).timeout(_slowEndpointTimeout);
      if (response.statusCode == 200) {
        return true;
      } else {
        print('Failed to save treatment info: ${response.statusCode} → ${response.body}');
        return false;
      }
    } catch (e) {
      print('Save treatment info error: $e');
      return false;
    }
  }

  // ---------------------------
  // ✅ Replace current treatment (reset progress)
  // ---------------------------
  static Future<bool> replaceTreatmentEpisode({
    required String treatment,
    String? subtype,
    required DateTime procedureDate,
    required TimeOfDay procedureTime,
  }) async {
    try {
      final headers = await getAuthHeaders();
      final url = Uri.parse('$baseUrl/episodes/replace-treatment');
      final body = {
        'treatment': treatment,
        'subtype': subtype,
        'procedure_date': procedureDate.toIso8601String().substring(0, 10),
        'procedure_time':
            '${procedureTime.hour.toString().padLeft(2, '0')}:${procedureTime.minute.toString().padLeft(2, '0')}',
      };
      final res = await http.post(url, headers: headers, body: jsonEncode(body)).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) return true;
      print('replaceTreatmentEpisode failed: ${res.statusCode} → ${res.body}');
      return false;
    } catch (e) {
      print('replaceTreatmentEpisode error: $e');
      return false;
    }
  }

  static Future<dynamic> requestReset(String emailOrPhone) async {
    final url = Uri.parse('https://paras-backend-0gwt.onrender.com/auth/request-reset');
    final Map<String, dynamic> body = {};
    if (emailOrPhone.contains('@')) {
      body['email'] = emailOrPhone;
    } else {
      body['phone'] = emailOrPhone;
    }
    print('REQUEST RESET BODY: ' + jsonEncode(body));

    try {
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_slowEndpointTimeout);
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

  // --------------------------
  // ✅ DOCTOR LOGIN
  // --------------------------
  static Future<String?> doctorLogin(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/doctor-login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': username.trim(), 'password': password},
      ).timeout(_slowEndpointTimeout);
      if (response.statusCode == 200) {
        final resBody = jsonDecode(response.body);
        final token = resBody['access_token'];
        if (token != null) {
          await saveDoctorToken(token);
        }
        return null;
      } else {
        try {
          final detail = jsonDecode(response.body)['detail'];
          return detail ?? 'Doctor login failed';
        } catch (_) {
          return 'Doctor login failed';
        }
      }
    } on SocketException {
      return 'Network error. Please check your connection.';
    } catch (_) {
      return 'Unexpected error. Please try again.';
    }
  }

  // --------------------------
  // ✅ Get Patients by Doctor
  // --------------------------
  static Future<List<Map<String, dynamic>>> getPatientsByDoctor(String doctor) async {
    try {
      // Doctor endpoints require doctor token (separate from patient token)
      final headers = await getDoctorAuthHeaders();
      final uri = Uri.parse('$baseUrl/patients/by-doctor').replace(queryParameters: {'doctor': doctor});
      print('[Api] → GET $uri');
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      print('[Api] ← ${response.statusCode} (${response.body.length} bytes) for /patients/by-doctor');
      if (response.statusCode == 200) {
        final bodyText = response.body;
        try {
          final data = jsonDecode(bodyText);
          if (data is List) {
            return data.cast<Map<String, dynamic>>();
          } else {
            print('[Api][warn] Expected list, got ${data.runtimeType}: $bodyText');
          }
        } catch (decodeErr) {
          print('[Api][error] JSON decode failed: $decodeErr body="$bodyText"');
        }
      } else {
        print('[Api][error] getPatientsByDoctor failed: ${response.statusCode} → ${response.body}');
      }
    } on TimeoutException catch (_) {
      print('[Api][timeout] getPatientsByDoctor >10s');
    } on SocketException catch (e) {
      print('[Api][net] getPatientsByDoctor network error: $e');
    } catch (e) {
      print('[Api][unexpected] getPatientsByDoctor error: $e');
    }
    return const [];
  }

  static Future<List<Map<String, dynamic>>> getPatientEpisodesByDoctor(String doctor) async {
    try {
      final uri = Uri.parse('$baseUrl/patients/by-doctor-episodes').replace(queryParameters: {'doctor': doctor});
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      print('[Api] ← ${response.statusCode} (${response.body.length} bytes) for /patients/by-doctor-episodes');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        }
        return [];
      }
      print('[Api][error] getPatientEpisodesByDoctor failed: ${response.statusCode} → ${response.body}');
      return [];
    } on TimeoutException {
      print('[Api][timeout] getPatientEpisodesByDoctor >10s');
      return [];
    } catch (e) {
      print('[Api][net] getPatientEpisodesByDoctor network error: $e');
      return [];
    }
  }

  // --------------------------
  // ✅ Get Patient Instruction Progress
  // --------------------------
  static Future<Map<String, dynamic>?> getPatientInstructionProgress(String username, {int days = 14}) async {
    try {
      final headers = await getDoctorAuthHeaders();
      final uri = Uri.parse('$baseUrl/doctor/patients/$username/instruction-progress?days=$days');
      final res = await http.get(uri, headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      print('getPatientInstructionProgress failed: ${res.statusCode} → ${res.body}');
    } catch (e) {
      print('getPatientInstructionProgress error: $e');
    }
    return null;
  }

  // --------------------------
  // ✅ Doctor: Get Patient Instruction Status logs (date range optional)
  // --------------------------
  static Future<List<Map<String, dynamic>>> doctorGetPatientInstructionStatus(
    String username, {
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final headers = await getDoctorAuthHeaders();
      final qp = <String, String>{};
      if (dateFrom != null) qp['date_from'] = dateFrom;
      if (dateTo != null) qp['date_to'] = dateTo;
      final base = '$baseUrl/doctor/patients/$username/instruction-status';
      final uri = qp.isEmpty ? Uri.parse(base) : Uri.parse(base).replace(queryParameters: qp);
      final res = await http.get(uri, headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      } else {
        print('doctorGetPatientInstructionStatus failed: ${res.statusCode} → ${res.body}');
      }
    } catch (e) {
      print('doctorGetPatientInstructionStatus error: $e');
    }
    return [];
  }

  // --------------------------
  // ✅ Doctor: Get Patient Progress entries
  // --------------------------
  static Future<List<Map<String, dynamic>>> doctorGetPatientProgressEntries(String username) async {
    try {
      final headers = await getDoctorAuthHeaders();
      final uri = Uri.parse('$baseUrl/doctor/patients/$username/progress');
      final res = await http.get(uri, headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      } else {
        print('doctorGetPatientProgressEntries failed: ${res.statusCode} → ${res.body}');
      }
    } catch (e) {
      print('doctorGetPatientProgressEntries error: $e');
    }
    return [];
  }

  // --------------------------
  // ✅ Save / Upsert Instruction Status (bulk)
  // --------------------------
  static Future<bool> saveInstructionStatus(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return true; // nothing to send
    try {
      final headers = await getAuthHeaders();
      final List<Map<String, dynamic>> normalized = [];
      for (final m in items) {
        final rawDate = (m['date'] ?? '').toString();
        if (rawDate.isEmpty) continue; // skip invalid
        final datePart = rawDate.contains('T') ? rawDate.split('T').first : rawDate;
        final instr = ((m['instruction_text'] ?? m['instruction'] ?? m['note']) ?? '').toString().trim();
        if (instr.isEmpty) continue; // skip blank instruction to avoid polluting DB
        final group = (m['type'] ?? m['group'] ?? '').toString().trim();
        final idx = m['instruction_index'] ?? m['index'] ?? 0;
        normalized.add({
          'date': datePart,
          'treatment': (m['treatment'] ?? '').toString(),
          'subtype': m['subtype'],
          'group': group,
          'instruction_index': idx,
          'instruction_text': instr,
          'followed': m['followed'] ?? false,
        });
      }
      if (normalized.isEmpty) return true; // nothing valid
      final body = jsonEncode({'items': normalized});
      final res = await http
          .post(Uri.parse('$baseUrl/instruction-status'), headers: headers, body: body)
          .timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        return true;
      }
      debugPrint('saveInstructionStatus failed: ${res.statusCode} → ${res.body}');
      return false;
    } catch (e) {
      debugPrint('saveInstructionStatus error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> doctorGetPatientInfo(String username) async {
    try {
      final headers = await getDoctorAuthHeaders();
      final uri = Uri.parse('$baseUrl/doctor/patients/$username/info');
      final res = await http.get(uri, headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      debugPrint('doctorGetPatientInfo failed: ${res.statusCode} → ${res.body}');
    } catch (e) {
      debugPrint('doctorGetPatientInfo error: $e');
    }
    return null;
  }

  // --------------------------
  // ✅ Doctor: Get Patient Episode History
  // --------------------------
  static Future<List<Map<String, dynamic>>> doctorGetPatientEpisodes(String username) async {
    try {
      final headers = await getDoctorAuthHeaders();
      final uri = Uri.parse('$baseUrl/doctor/patients/$username/episodes');
      final res = await http.get(uri, headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      } else {
        debugPrint('doctorGetPatientEpisodes failed: ${res.statusCode} → ${res.body}');
      }
    } catch (e) {
      debugPrint('doctorGetPatientEpisodes error: $e');
    }
    return const [];
  }

  // --------------------------
  // ✅ Doctor: Combined full instruction status (raw + summary)
  // --------------------------
  static Future<Map<String, dynamic>?> doctorGetPatientInstructionStatusFull(
    String username, {
    int days = 14,
    String? treatment,
    String? subtype,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final headers = await getDoctorAuthHeaders();
      final qp = <String, String>{'days': days.toString()};
      if (treatment != null && treatment.trim().isNotEmpty) qp['filter_treatment'] = treatment;
      if (subtype != null && subtype.trim().isNotEmpty) qp['filter_subtype'] = subtype;
      if (dateFrom != null && dateFrom.trim().isNotEmpty) qp['date_from'] = dateFrom;
      if (dateTo != null && dateTo.trim().isNotEmpty) qp['date_to'] = dateTo;
      final uri = Uri.parse('$baseUrl/doctor/patients/$username/instruction-status/full').replace(queryParameters: qp);
      final res = await http.get(uri, headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final decoded = await _decodeJson(res.body);
        if (decoded is Map<String, dynamic>) return decoded;
        // ignore: avoid_print
        print('doctorGetPatientInstructionStatusFull unexpected payload: ${decoded.runtimeType}');
      } else {
        debugPrint('doctorGetPatientInstructionStatusFull failed: ${res.statusCode} → ${res.body}');
      }
    } catch (e) {
      debugPrint('doctorGetPatientInstructionStatusFull error: $e');
    }
    return null;
  }

  // --------------------------
  // ✅ Doctor: Enhanced per-day instruction status (includes placeholders)
  // --------------------------
  static Future<Map<String, dynamic>?> doctorGetPatientInstructionStatusEnhanced(
    String username, {
    int days = 14,
    String? treatment,
    String? subtype,
    String? dateFrom,
    String? dateTo,
    bool includeUnfollowedPlaceholders = true,
  }) async {
    try {
      final headers = await getDoctorAuthHeaders();
      final qp = <String, String>{
        'days': days.toString(),
        'include_unfollowed_placeholders': includeUnfollowedPlaceholders ? 'true' : 'false',
      };
      if (treatment != null && treatment.trim().isNotEmpty) qp['filter_treatment'] = treatment;
      if (subtype != null && subtype.trim().isNotEmpty) qp['filter_subtype'] = subtype;
      if (dateFrom != null && dateFrom.trim().isNotEmpty) qp['date_from'] = dateFrom;
      if (dateTo != null && dateTo.trim().isNotEmpty) qp['date_to'] = dateTo;
      final uri = Uri.parse('$baseUrl/doctor/patients/$username/instruction-status/enhanced').replace(
        queryParameters: qp,
      );
      final res = await http.get(uri, headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      debugPrint('doctorGetPatientInstructionStatusEnhanced failed: ${res.statusCode} → ${res.body}');
    } catch (e) {
      debugPrint('doctorGetPatientInstructionStatusEnhanced error: $e');
    }
    return null;
  }

  // --------------------------
  // 🔄 Incremental Instruction Status Changes (multi-device sync)
  // --------------------------
  static Future<List<Map<String, dynamic>>?> fetchInstructionStatusChanges({required String sinceIso}) async {
    try {
      final headers = await getAuthHeaders();
      final uri = Uri.parse('$baseUrl/instruction-status/changes').replace(queryParameters: {'since': sinceIso});
      final res = await http.get(uri, headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
        debugPrint('fetchInstructionStatusChanges unexpected payload type: ${data.runtimeType}');
        return const [];
      }
      debugPrint('fetchInstructionStatusChanges failed: ${res.statusCode} → ${res.body}');
      return null; // signal failure so caller can fallback
    } on TimeoutException {
      debugPrint('[Api][timeout] fetchInstructionStatusChanges');
      return null;
    } catch (e) {
      debugPrint('fetchInstructionStatusChanges error: $e');
      return null;
    }
    // unreachable
    // ignore: dead_code
    return const [];
  }

  // --------------------------
  // 📅 Patient: List instruction-status by date range (fallback path)
  // --------------------------
  static Future<List<Map<String, dynamic>>?> listInstructionStatus({String? dateFrom, String? dateTo}) async {
    try {
      final headers = await getAuthHeaders();
      final qp = <String, String>{};
      if (dateFrom != null && dateFrom.isNotEmpty) qp['date_from'] = dateFrom;
      if (dateTo != null && dateTo.isNotEmpty) qp['date_to'] = dateTo;
      final base = '$baseUrl/instruction-status';
      final uri = qp.isEmpty ? Uri.parse(base) : Uri.parse(base).replace(queryParameters: qp);
      final res = await http.get(uri, headers: headers).timeout(_slowEndpointTimeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
        debugPrint('listInstructionStatus unexpected payload type: ${data.runtimeType}');
        return const [];
      }
      debugPrint('listInstructionStatus failed: ${res.statusCode} → ${res.body}');
      return null;
    } on TimeoutException {
      debugPrint('[Api][timeout] listInstructionStatus');
      return null;
    } catch (e) {
      debugPrint('listInstructionStatus error: $e');
      return null;
    }
  }
}
