import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // NOTE: This runs in a background Dart isolate.
  // Keep it minimal and avoid UI/navigation work.
  if (!Platform.isAndroid) return;
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // If the message contains a notification payload, Android will display it automatically
  // while the app is backgrounded. Avoid duplicates.
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
      final kind = (message.data['kind'] ?? message.data['type'])?.toString();
      final title = message.notification?.title;
      final body = message.notification?.body;

      // Important: Android does NOT display FCM notification messages while the app is in the foreground.
      // We only surface reminders here to avoid "burst" popups for other message types.
      if (kind == 'reminder' && title != null && body != null) {
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
      } else {
        if (kDebugMode) {
          print('FCM foreground message received (suppressed): title="${title ?? ''}" body="${body ?? ''}" data=${message.data}');
        }
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
      if (_registeredThisSession) {
        if (kDebugMode) print('registerNow: already registered this session; skip');
        _pendingRegistration = false;
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
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