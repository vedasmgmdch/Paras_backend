import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    // Initialize timezone database (idempotent)
    try { tzdata.initializeTimeZones(); } catch (_) {}
    // Leave tz.local as default (NotificationService may already set it elsewhere)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings,
        onDidReceiveNotificationResponse: (resp) {
          // TODO: handle tap (map payload -> reminder id, then ack via ReminderService)
        });
    _initialized = true;
  }

  static Future<int?> scheduleOnce({required int id, required DateTime when, required String title, required String body}) async {
    await init();
    final androidDetails = AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Daily reminder notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // daily
    );
    return id;
  }

  static Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }
}
