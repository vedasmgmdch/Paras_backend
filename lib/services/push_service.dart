import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PushService {
  static bool _initialized = false;
  static bool _pendingRegistration = false; // set when we have a token but no auth yet

  static Future<void> initializeAndRegister() async {
    if (_initialized) return;
    // Only enable push on Android; skip Firebase for Windows/macOS to avoid build-time SDK download
    if (!Platform.isAndroid) {
      _initialized = true;
      if (kDebugMode) {
        print('PushService: skipping Firebase init on non-Android platform');
      }
      return;
    }
    try {
      await Firebase.initializeApp();
      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('Firebase init error: $e');
      }
    }

    final messaging = FirebaseMessaging.instance;

    if (Platform.isAndroid) {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (kDebugMode) {
        print('Notification permission: ${settings.authorizationStatus}');
      }
    }

    try {
      final token = await messaging.getToken();
      if (kDebugMode) {
        print('FCM token: $token');
      }
      if (token != null) {
        final loggedIn = await ApiService.checkIfLoggedIn();
        final prefs = await SharedPreferences.getInstance();
        final lastToken = prefs.getString('push.lastToken');
        if (loggedIn) {
          // Avoid re-registering on every cold start; only if token changed or we have a pending flag
          if (lastToken == token) {
            if (kDebugMode) print('PushService: token unchanged; skip auto-register');
            _pendingRegistration = false;
          } else {
            if (kDebugMode) print('PushService: token changed; will register after-auth');
            _pendingRegistration = true;
          }
        } else {
          if (kDebugMode) print('Skip device register (not logged in yet)');
          _pendingRegistration = true;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error obtaining FCM token: $e');
      }
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (kDebugMode) {
        print('FCM token refreshed: $newToken');
      }
      final loggedIn = await ApiService.checkIfLoggedIn();
      if (!loggedIn) {
        if (kDebugMode) print('Token refresh: defer register (not logged in)');
        _pendingRegistration = true;
        return;
      }
      final ok = await ApiService.registerDeviceToken(platform: 'android', token: newToken);
      if (!ok) {
        _pendingRegistration = true;
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('push.lastToken', newToken);
        _pendingRegistration = false;
      }
    });

    // Suppress foreground popups to avoid burst notifications on app reopen.
    // Background notifications (system handled) will still appear if the message carries a notification payload.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (kDebugMode) {
        print('FCM foreground message received (suppressed): title="${message.notification?.title}" body="${message.notification?.body}" data=${message.data}');
      }
    });
  }

  // Explicitly (re)register the current FCM token with the backend.
  // Use this right after a user logs in or when a saved token is loaded,
  // ensuring the Authorization header is present on the request.
  static Future<void> registerNow() async {
    if (!Platform.isAndroid) return;
    try {
      final loggedIn = await ApiService.checkIfLoggedIn();
      if (!loggedIn) {
        if (kDebugMode) print('registerNow: skipped (not logged in)');
        _pendingRegistration = true;
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) {
        print('PushService.registerNow() FCM token: $token');
      }
      if (token != null) {
        // If we already registered this token and no pending flag, skip
        try {
          final prefs = await SharedPreferences.getInstance();
          final lastToken = prefs.getString('push.lastToken');
          if (lastToken == token && !_pendingRegistration) {
            if (kDebugMode) print('registerNow: token unchanged and not pending; skip');
            return;
          }
        } catch (_) {}
        final ok = await ApiService.registerDeviceToken(platform: 'android', token: token);
        if (kDebugMode) {
          print('registerDeviceToken after-auth → ${ok ? 'OK' : 'FAILED'}');
        }
        if (ok) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('push.lastToken', token);
        }
        _pendingRegistration = !ok;
      }
    } catch (e) {
      if (kDebugMode) {
        print('registerNow error: $e');
      }
    }
  }

  // Call this right after successful login to flush any pending registration
  static Future<void> flushPendingIfAny() async {
    if (_pendingRegistration) {
      await registerNow();
    }
  }
}