import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Note: We intentionally do not add any "late" suffix (Android already shows time).

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // NOTE: This runs in a background Dart isolate.
  // Keep it minimal and avoid UI/navigation work.
  if (!Platform.isAndroid) return;

  // If the user is logged out, do not surface reminder pushes.
  // (Backend token cleanup on logout should prevent most pushes, but this
  // guards against stale tokens or race windows.)
  try {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.containsKey('token');
    if (!loggedIn) return;
  } catch (_) {}

  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // If a notification payload is present, Android will display it automatically while backgrounded.
  // Only handle data-only reminder pushes here (fallback path) to avoid duplicates.
  if (message.notification != null) return;

  final data = message.data;
  final kind = (data['kind'] ?? data['type'])?.toString();
  if (kind != 'reminder') return;

  final title = data['title']?.toString();
  final body = data['body']?.toString();
  if (title == null || body == null) return;

  int id = DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
  final rid = data['reminder_id']?.toString();
  if (rid != null) {
    final parsed = int.tryParse(rid);
    if (parsed != null) id = parsed;
  }

  try {
    final plugin = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await plugin.initialize(initSettings);

    final androidImpl = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          'reminders_channel_alarm_v2',
          'Reminders (Alarm)',
          description: 'Scheduled reminders for tooth-care app',
          importance: Importance.max,
        ),
      );
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders_channel_alarm_v2',
        'Reminders (Alarm)',
        channelDescription: 'Scheduled reminders for tooth-care app',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        autoCancel: false,
      ),
    );
    await plugin.show(id, title, body, details);
  } catch (_) {}
}

class PushService {
  static bool _initialized = false;
  static bool _pendingRegistration = false; // set when we have a token but no auth yet
  static bool _registeredThisSession = false;

  static void registerBackgroundHandler() {
    if (!Platform.isAndroid) return;
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (_) {}
  }

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
        // Important: don't rely on local prefs to decide whether backend has this token.
        // Backend tokens can be missing (DB reset/pruned), so always attempt register once per app session.
        _pendingRegistration = !loggedIn;
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
      // If logged out, suppress all foreground reminder popups.
      // (Should be rare because token registration is tied to auth.)
      try {
        final prefs = await SharedPreferences.getInstance();
        final loggedIn = prefs.containsKey('token');
        if (!loggedIn) return;
      } catch (_) {}

      final kind = (message.data['kind'] ?? message.data['type'])?.toString();
      final title = message.notification?.title ?? message.data['title']?.toString();
      final body = message.notification?.body ?? message.data['body']?.toString();

      // Important: Android does NOT display FCM notification messages while the app is in the foreground.
      // We surface:
      //  - reminders (data-only) via local notifications
      //  - adherence nudges (a.k.a. progress/instruction status notifications) via local notifications
      if (title == null || body == null) {
        if (kDebugMode) {
          print('FCM foreground message received without title/body; suppressed: data=${message.data}');
        }
        return;
      }

      if (kind == 'reminder') {
        int id = DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
        final rid = message.data['reminder_id']?.toString();
        if (rid != null) {
          final parsed = int.tryParse(rid);
          if (parsed != null) id = parsed;
        }
        try {
          await NotificationService.showNow(id: id, title: title, body: body);
        } catch (e) {
          if (kDebugMode) {
            print('Foreground reminder local-notification error: $e');
          }
        }
        return;
      }

      // Adherence nudges: backend sends type=adherence_nudge/adherence_ok.
      // Surface them in foreground so users actually see them.
      if (kind == 'adherence_nudge' || kind == 'adherence_ok') {
        final id = DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
        try {
          await NotificationService.showNow(id: id, title: title, body: body);
        } catch (e) {
          if (kDebugMode) {
            print('Foreground adherence local-notification error: $e');
          }
        }
        return;
      } else {
        if (kDebugMode) {
          print('FCM foreground message received (suppressed): title="$title" body="$body" data=${message.data}');
        }
      }
    });
  }

  // Call on logout (best-effort). This prevents future pushes being delivered
  // if the backend still has a stale token, and forces a new token on next login.
  static Future<void> onLogout() async {
    _pendingRegistration = false;
    _registeredThisSession = false;
    if (!Platform.isAndroid) return;
    try {
      if (!_initialized) {
        try {
          await Firebase.initializeApp();
          _initialized = true;
        } catch (_) {}
      }
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    } catch (_) {}
  }

  // Explicitly (re)register the current FCM token with the backend.
  // Use this right after a user logs in or when a saved token is loaded,
  // ensuring the Authorization header is present on the request.
  static Future<void> registerNow() async {
    if (!Platform.isAndroid) return;
    try {
      // In some flows registerNow can be called before initializeAndRegister.
      // Ensure Firebase is initialized.
      if (!_initialized) {
        try {
          await Firebase.initializeApp();
          _initialized = true;
        } catch (_) {}
      }

      final loggedIn = await ApiService.checkIfLoggedIn();
      if (!loggedIn) {
        if (kDebugMode) print('registerNow: skipped (not logged in)');
        _pendingRegistration = true;
        return;
      }
      if (_registeredThisSession) {
        if (kDebugMode) print('registerNow: already registered this session; skip');
        _pendingRegistration = false;
        return;
      }
      String? token;
      // After logout we may deleteToken(); allow a short window for a new token.
      for (int attempt = 0; attempt < 3; attempt++) {
        token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      if (kDebugMode) {
        print('PushService.registerNow() FCM token: $token');
      }
      if (token != null) {
        final ok = await ApiService.registerDeviceToken(platform: 'android', token: token);
        if (kDebugMode) {
          print('registerDeviceToken after-auth → ${ok ? 'OK' : 'FAILED'}');
        }
        if (ok) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('push.lastToken', token);
          _registeredThisSession = true;
        }
        _pendingRegistration = !ok;
      } else {
        // Token unavailable; try again later.
        _pendingRegistration = true;
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
