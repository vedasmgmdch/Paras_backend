import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
// Removed: android_alarm_manager_plus import (deprecated approach due to OEM headless isolate instability)
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
// Legacy pure_reminders removed

// ============================= IMPORTANT REFACTOR NOTE =============================
// AlarmManager + headless Dart isolate scheduling has been removed because many OEM
// ROMs (MIUI, Realme UI, One UI, etc.) aggressively kill or throttle the transient
// isolate before the MethodChannel call to actually display a notification completes.
// We now rely solely on flutter_local_notifications' native pre-scheduling with
// zonedSchedule() + matchDateTimeComponents for daily fixed-time reminders. This
// leverages Android's own alarm / job infrastructure without spinning up Dart at fire time.
// For future dynamic (network-derived) payloads, prefer either:
//   1. A native BroadcastReceiver that builds notification directly, OR
//   2. WorkManager for background fetch (accepting inexact windows), OR
//   3. Foreground service (only if truly long-lived ongoing processing is essential).
// ================================================================================

// Top-level background tap handler (must be a top-level or static entry point)
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  try {
    final id = response.id;
    if (id != null) {
      NotificationService.handleBackgroundTap(id);
    }
  } catch (_) {}
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool serverOnlyMode = false; // if true, skip all scheduling (placeholder for remote push mode)
  // Strict mode: schedule ONLY exact-time alarms (no 5-10s boundary or catch-up hedges)
  // Enabled by default to satisfy "no delay" preference.
  static bool strictExactMode = true;

  static const String _channelId = 'reminders_channel_alarm_v2';
  static const String _channelName = 'Reminders (Alarm)';
  static const String _channelDesc = 'Scheduled reminders for tooth-care app';

  // Legacy AlarmManager flag retained for API compatibility but always false now.
  static bool useAlarmManager = false;

  static const String _preferAlarmClockKey = 'prefer_alarm_clock_v1';
  static const String _firstRunExactAlarmKey = 'first_run_exact_alarm_requested_v1';
  static const String _migrationDoneKey = 'reminder_migration_simple_done_v1';
  static const String _diagPromptKey = 'exact_diag_prompted_v1';

  // Track last first-fire date we logged per id to suppress duplicate log spam
  static final Map<int, DateTime> _lastLoggedFirstFire = <int, DateTime>{};
  static bool _preferAlarmClock = true; // retained setting (affects ordering heuristics if re-expanded later)
  static final Map<int, DateTime> _lastDailyScheduleAttempt = <int, DateTime>{};
  static const int _catchUpGraceMinutes = 5; // window for catch-up one-off

  static void Function(int id)? _foregroundCallback;
  static void handleBackgroundTap(int id) {
    try { _foregroundCallback?.call(id); } catch (_) {}
  }

  static Future<void> init({bool requestPermission = true, void Function(int id)? onNotificationReceived}) async {
    if (serverOnlyMode) { _initialized = true; return; }
    if (_initialized) return;

    // Timezone init (single attempt)
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      debugPrint('[NotificationService] Timezone set to Asia/Kolkata');
    } catch (e) {
      try {
        final deviceTz = tz.local.name;
        tz.setLocalLocation(tz.getLocation(deviceTz));
        debugPrint('[NotificationService] Fallback timezone set to $deviceTz');
      } catch (e2) {
        debugPrint('[NotificationService] Timezone init failed: $e2');
      }
    }

    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    final settings = const InitializationSettings(android: androidInit, iOS: iosInit);

    _foregroundCallback = onNotificationReceived;
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        try {
          final id = resp.id;
            if (id != null) {
              _foregroundCallback?.call(id);
              _notifyFireObservers(id);
            }
        } catch (_) {}
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    debugPrint('[NotificationService] init plugin');

    // Android 13+ runtime permission
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      if (requestPermission) {
        final granted = await androidImpl.requestNotificationsPermission();
        debugPrint('[NotificationService] notifications permission granted=$granted');
      }
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
        ),
      );
      debugPrint('[NotificationService] channel ready');
    }

    _initialized = true;

    // Persisted preference load & one-time migration cleanup
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedPref = prefs.getBool(_preferAlarmClockKey);
      if (storedPref != null) _preferAlarmClock = storedPref; else await prefs.setBool(_preferAlarmClockKey, _preferAlarmClock);

      final migrated = prefs.getBool(_migrationDoneKey) ?? false;
      if (!migrated) {
        try { await _plugin.cancelAll(); } catch (e) { debugPrint('[NotificationService] migration cancelAll error: $e'); }
        await prefs.setBool(_migrationDoneKey, true);
      }

      if (Platform.isAndroid) {
        final firstReq = prefs.getBool(_firstRunExactAlarmKey) ?? false;
        if (!firstReq) {
          try {
            final canExact = await canScheduleExactNotifications();
            if (!canExact) {
              debugPrint('[NotificationService] requesting exact alarms (first run)');
              await requestExactAlarmsPermission();
            }
          } catch (e) { debugPrint('[NotificationService] exact alarm request error: $e'); }
          await prefs.setBool(_firstRunExactAlarmKey, true);
        }

        // Diagnostics: log current capabilities and optionally prompt once if strict mode is on
        try {
          final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
          final notifEnabled = androidImpl == null ? true : (await androidImpl.areNotificationsEnabled() ?? true);
          final canExactNow = await canScheduleExactNotifications();
          debugPrint('[NotificationService][diagnostics] strictExactMode=$strictExactMode notificationsEnabled=$notifEnabled canExact=$canExactNow');
          if (strictExactMode && !canExactNow) {
            final alreadyPrompted = prefs.getBool(_diagPromptKey) ?? false;
            if (!alreadyPrompted) {
              debugPrint('[NotificationService][diagnostics] Strict mode active but exact alarms not granted. Prompting once...');
              try {
                // Try system prompt (Android 13+); if still not granted, open settings screen.
                await requestExactAlarmsPermission();
              } catch (_) {}
              try {
                final recheck = await canScheduleExactNotifications();
                if (!recheck) {
                  await openExactAlarmsSettings();
                }
              } catch (_) {}
              await prefs.setBool(_diagPromptKey, true);
            }
          }
        } catch (e) {
          debugPrint('[NotificationService][diagnostics] error: $e');
        }
      }
    } catch (_) {}

    useAlarmManager = false; // enforced off
    debugPrint('[NotificationService] init complete (plugin-only)');
  }

  static String currentTimeZoneName() { try { return tz.local.name; } catch (_) { return 'unknown'; } }

  static void setAlarmManagerEnabled(bool enabled) { useAlarmManager = false; /* no-op */ }

  // NOTE: Payload storage helpers removed (AlarmManager path deprecated)

  static Future<bool> areNotificationsEnabled() async {
    await init();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) return await androidImpl.areNotificationsEnabled() ?? true;
    return true;
  }

  static Future<bool> canScheduleExactNotifications() async {
    await init();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) return await androidImpl.canScheduleExactNotifications() ?? false;
    return true;
  }

  static bool isUsingAlarmManager() => false;
  static bool isPreferringAlarmClock() => _preferAlarmClock;
  static Future<void> setPreferAlarmClock(bool value) async {
    _preferAlarmClock = value;
    try { final prefs = await SharedPreferences.getInstance(); await prefs.setBool(_preferAlarmClockKey, value); } catch (_) {}
  }

  static void setOnNotificationReceived(void Function(int id)? handler) {
    _foregroundCallback = handler;
    debugPrint('[NotificationService] setOnNotificationReceived handler=' + (handler == null ? 'null' : 'set'));
  }

  // Toggle strict mode at runtime if needed
  static void setStrictExactMode(bool value) {
    strictExactMode = value;
    debugPrint('[NotificationService] strictExactMode=$strictExactMode');
  }

  static Future<void> _notifyFireObservers(int id) async {
    try {
      // Legacy pure_reminders metadata update removed
    } catch (_) {}
  }

  static Future<bool> ensurePermissions() async {
    await init();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final granted = await androidImpl.requestNotificationsPermission() ?? true;
      return granted;
    }
    return true;
  }

  // Quick one-off test: schedule after X seconds
  static Future<void> scheduleInSeconds({required int id, required int seconds, required String title, required String body}) async {
    if (serverOnlyMode) { debugPrint('[NotificationService] serverOnlyMode skip scheduleInSeconds id=$id'); return; }
    await init();
    if (!Platform.isAndroid) { await showNow(id: id, title: title, body: body); return; }
    final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    try {
      final mode = strictExactMode ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.exactAllowWhileIdle;
      await _plugin.zonedSchedule(
        id, title, body, when, details,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: mode,
      );
      debugPrint('[NotificationService] scheduled short test (mode=$mode)');
    } catch (e) {
      debugPrint('[NotificationService] scheduleInSeconds exact failed: $e');
      try {
        await _plugin.zonedSchedule(
          id, title, body, when, details,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        debugPrint('[NotificationService] scheduled short test (inexact fallback)');
      } catch (e2) { debugPrint('[NotificationService] scheduleInSeconds failed both modes: $e2'); }
    }
  }

  static Future<void> scheduleNotification({required int id, required DateTime scheduledAt, required String title, required String body}) async {
    if (serverOnlyMode) { debugPrint('[NotificationService] serverOnlyMode skip one-off id=$id'); return; }
    await init();
    if (!Platform.isAndroid) { await showNow(id: id, title: title, body: body); return; }
    final when = tz.TZDateTime.from(scheduledAt, tz.local);
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    try {
      final mode = strictExactMode ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.exactAllowWhileIdle;
      await _plugin.zonedSchedule(
        id, title, body, when, details,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: mode,
      );
      debugPrint('[NotificationService] scheduled one-off (mode=$mode)');
    } catch (e) {
      debugPrint('[NotificationService] one-off exact failed: $e');
      try {
        await _plugin.zonedSchedule(
          id, title, body, when, details,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        debugPrint('[NotificationService] scheduled one-off (inexact fallback)');
      } catch (e2) { debugPrint('[NotificationService] one-off scheduling failed both modes: $e2'); }
    }
  }

  // Schedule a daily notification at a specific local time.
  // Simplified variant (no catch-up / grace) for basic reliable daily reminders.
  static Future<void> scheduleDailyBasic({required int id, required int hour, required int minute, required String title, required String body, bool forceStartTomorrow = false}) async {
    if (serverOnlyMode) return; await init(); if (!Platform.isAndroid) return;
    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime first = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    final deltaSecInitial = first.difference(now).inSeconds;
    debugPrint('[DailyBasic][debug] now=$now target=$first deltaSecInitial=$deltaSecInitial');
    if (forceStartTomorrow || !first.isAfter(now)) {
      first = first.add(const Duration(days: 1));
      debugPrint('[DailyBasic][debug] rolled to tomorrow first=$first');
    }
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    try {
      final mode = strictExactMode ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.exactAllowWhileIdle;
      await _plugin.zonedSchedule(
        id, title, body, first, details,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        androidScheduleMode: mode,
      );
      final last = _lastLoggedFirstFire[id];
      if (last == null || last != first) { debugPrint('[NotificationService] scheduled (daily-basic) id=$id firstFire=$first deltaFromNowSec=${first.difference(now).inSeconds} mode=$mode'); _lastLoggedFirstFire[id] = first; }
    } catch (e) {
      debugPrint('[NotificationService] scheduleDailyBasic exact failed id=$id error=$e');
      try {
        await _plugin.zonedSchedule(
          id, title, body, first, details,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        debugPrint('[NotificationService] scheduled (daily-basic) inexact fallback id=$id firstFire=$first');
      } catch (e2) {
        debugPrint('[NotificationService] scheduleDailyBasic failed both modes id=$id error=$e2');
      }
    }
  }

  // Unified reliable daily scheduler with first-occurrence & boundary hedging.
  // Behavior:
  // 1. If target time today is still > 45s in the future, schedule one-off EXACT at that time (offset id) + schedule repeating daily (base id -> tomorrow rolls automatically if needed).
  // 2. If target time is within [-5m, +45s] window around "now" (user just set or just missed), schedule a small confirmation one-off at now+10s (different offset) + repeating daily (roll to tomorrow if already passed).
  // 3. If target time already passed >5m ago, only schedule repeating daily (next day) – no immediate one-off.
  // Offset ID namespaces (avoid clashes with base id & legacy ones):
  //   base: id
  //   first-occurrence today: id + 600_000_000
  //   boundary confirmation:  id + 610_000_000
  //   boundary secondary (OEM hedge): id + 620_000_000 (fires later if 10s one suppressed)
  //   boundary extended (deep throttle hedge): id + 630_000_000 (120s)
  static Future<void> scheduleHybridDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    if (serverOnlyMode) { debugPrint('[NotificationService][hybrid] serverOnly skip id=$id'); return; }
    await init();
    final granted = await areNotificationsEnabled();
    if (!granted) { debugPrint('[NotificationService][hybrid] notifications disabled, attempting permission request'); await ensurePermissions(); }
    if (!Platform.isAndroid) { await showNow(id: id, title: title, body: body); return; }

    final now = DateTime.now();
    DateTime todayTarget = DateTime(now.year, now.month, now.day, hour, minute);
    int deltaSec = todayTarget.difference(now).inSeconds; // positive => future

    // Cancel any previous hybrid one-offs to prevent duplicates if user edits quickly.
    try {
      await _plugin.cancel(id + 600000000);
      await _plugin.cancel(id + 610000000);
      await _plugin.cancel(id + 620000000);
  await _plugin.cancel(id + 630000000);
    } catch (_) {}

  // Decide strategy
  // If we will schedule a one-off today (strict mode with future target), start repeating from tomorrow to avoid double fire.
  // Otherwise, schedule repeating normally (it will roll itself if past).

    // Decide strategy
    if (strictExactMode) {
      bool willOneOffToday = deltaSec > 0;
      await scheduleDailyBasic(id: id, hour: hour, minute: minute, title: title, body: body, forceStartTomorrow: willOneOffToday);
      // Strict: only schedule the precise one-off today if still in the future; otherwise, rely on daily repeating.
      if (deltaSec > 0) {
        final oneOffId = id + 600000000;
        debugPrint('[NotificationService][hybrid][strict] one-off exact id=$oneOffId fireInSec=$deltaSec');
        await scheduleNotification(id: oneOffId, scheduledAt: todayTarget, title: title, body: body);
      } else {
        debugPrint('[NotificationService][hybrid][strict] target passed (deltaSec=$deltaSec); relying on next daily occurrence');
      }
    } else {
      await scheduleDailyBasic(id: id, hour: hour, minute: minute, title: title, body: body);
      // Legacy hedged behavior (more resilient on aggressive OEMs)
      if (deltaSec > 45) {
        final oneOffId = id + 600000000;
        debugPrint('[NotificationService][hybrid] one-off first-occurrence id=$oneOffId fireInSec=$deltaSec');
        await scheduleNotification(id: oneOffId, scheduledAt: todayTarget, title: title, body: body);
      } else if (deltaSec >= -300) {
        final boundaryId = id + 610000000;
        debugPrint('[NotificationService][hybrid] boundary window deltaSec=$deltaSec scheduling confirmation id=$boundaryId in 10s');
        await scheduleInSeconds(id: boundaryId, seconds: 10, title: title, body: body);
        final boundaryFallbackId = id + 620000000;
        debugPrint('[NotificationService][hybrid] boundary secondary fallback id=$boundaryFallbackId in 40s');
        await scheduleInSeconds(id: boundaryFallbackId, seconds: 40, title: title, body: body);
        final boundaryExtendedId = id + 630000000;
        debugPrint('[NotificationService][hybrid] boundary extended fallback id=$boundaryExtendedId in 120s');
        await scheduleInSeconds(id: boundaryExtendedId, seconds: 120, title: title, body: body);
      } else {
        debugPrint('[NotificationService][hybrid] past window deltaSec=$deltaSec -> no immediate one-off (next daily covers)');
      }
    }

    // Auto debug dump (development only)
    assert(() {
      () async {
        try {
          final pendingList = await pending();
          debugPrint('[NotificationService][hybrid][dump] after schedule id=$id pendingCount=${pendingList.length}');
        } catch (_) {}
      }();
      return true;
    }());
  }

  // Helper to expose next fire date (same logic as scheduleDailyBasic) without scheduling.
  static DateTime computeNextDaily(int hour, int minute) {
    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day, hour, minute);
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));
    return first;
  }

  static Future<void> scheduleDailyNotification({required int id, required int hour, required int minute, required String title, required String body}) async {
    final nowMono = DateTime.now();
    final last = _lastDailyScheduleAttempt[id];
    if (last != null && nowMono.difference(last).inSeconds < 3) { debugPrint('[NotificationService] daily skip duplicate id=$id'); return; }
    _lastDailyScheduleAttempt[id] = nowMono;
    if (serverOnlyMode) { debugPrint('[NotificationService] skip daily (serverOnly) id=$id'); return; }
    await init();
    if (!Platform.isAndroid) return;

    final nowLocal = DateTime.now();
    DateTime todayTarget = DateTime(nowLocal.year, nowLocal.month, nowLocal.day, hour, minute);
    int initialDelta = todayTarget.difference(nowLocal).inSeconds;
    debugPrint('[DailySched][debug] now=$nowLocal target=$todayTarget initialDeltaSec=$initialDelta');
    bool rollToTomorrow = false;
    bool scheduleCatchUpOneOff = false;
    if (initialDelta < 0) {
      if (initialDelta.abs() <= _catchUpGraceMinutes * 60) { scheduleCatchUpOneOff = true; rollToTomorrow = true; }
      else { rollToTomorrow = true; }
    } else if (initialDelta <= 30) { scheduleCatchUpOneOff = true; }
    DateTime scheduledLocal = rollToTomorrow ? todayTarget.add(const Duration(days: 1)) : todayTarget;
    if (scheduledLocal.isBefore(nowLocal.subtract(const Duration(seconds: 5)))) scheduledLocal = scheduledLocal.add(const Duration(days: 1));
    final scheduledTz = tz.TZDateTime.from(scheduledLocal, tz.local);
    debugPrint('[DailySched][debug] finalScheduled=$scheduledTz finalDeltaSec=${scheduledTz.difference(tz.TZDateTime.now(tz.local)).inSeconds} catchUp=$scheduleCatchUpOneOff rollTomorrow=$rollToTomorrow');

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());

    try {
      final mode = strictExactMode ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.exactAllowWhileIdle;
      await _plugin.zonedSchedule(
        id, title, body, scheduledTz, details,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        androidScheduleMode: mode,
      );
      final delta = scheduledTz.difference(tz.TZDateTime.now(tz.local)).inMinutes;
      debugPrint('[NotificationService] scheduled daily (mode=$mode) id=$id firstFireInMin=$delta');
      if (scheduleCatchUpOneOff && !strictExactMode) {
        final oneOffId = id + 800000000;
        debugPrint('[DailySched][debug] scheduling catch-up oneOffId=$oneOffId in=15s');
        await scheduleInSeconds(id: oneOffId, seconds: 15, title: title, body: body);
      }
    } catch (e) {
      debugPrint('[NotificationService] daily exact failed: $e');
      try {
        await _plugin.zonedSchedule(
          id, title, body, scheduledTz, details,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        debugPrint('[NotificationService] scheduled daily (inexactAllowWhileIdle fallback) id=$id');
      } catch (e2) { debugPrint('[NotificationService] scheduleDailyNotification failed both modes: $e2'); }
    }
  }

  // Attempt to request exact alarm permission then run a provided rescheduler if granted
  static Future<void> ensureExactAlarmsAndReschedule(Future<void> Function() rescheduler) async {
    if (!Platform.isAndroid) return;
    try {
      final before = await canScheduleExactNotifications();
      debugPrint('[NotificationService] ensureExactAlarms before=$before');
      if (!before) { await requestExactAlarmsPermission(); }
      final after = await canScheduleExactNotifications();
      debugPrint('[NotificationService] ensureExactAlarms after=$after');
      if (after) { await rescheduler(); } else { debugPrint('[NotificationService] exact alarms still not permitted; using inexact'); }
    } catch (e) { debugPrint('[NotificationService] ensureExactAlarms error: $e'); }
  }

  // Public helper: returns current notification capabilities useful for UI or logs
  static Future<Map<String, dynamic>> getCapabilities() async {
    await init();
    bool notifEnabled = true;
    bool canExact = true;
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        notifEnabled = await androidImpl.areNotificationsEnabled() ?? true;
        canExact = await androidImpl.canScheduleExactNotifications() ?? false;
      }
    } catch (_) {}
    return <String, dynamic>{
      'strictExactMode': strictExactMode,
      'notificationsEnabled': notifEnabled,
      'canScheduleExact': canExact,
      'timeZone': currentTimeZoneName(),
    };
  }

  static Future<void> cancel(int id) => _plugin.cancel(id);
  static Future<void> cancelAll() => _plugin.cancelAll();
  static Future<void> cancelAllPending() => cancelAll();

  static Future<List<PendingNotificationRequest>> pending() async {
    try { await init(); if (!Platform.isAndroid) return <PendingNotificationRequest>[]; return _plugin.pendingNotificationRequests(); } catch (_) { return <PendingNotificationRequest>[]; }
  }

  static Future<bool> requestExactAlarmsPermission() async {
    await init();
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl == null) return false;
      final res = await androidImpl.requestExactAlarmsPermission();
      debugPrint('[NotificationService] requestExactAlarmsPermission result=$res');
      if (res is bool) return res;
    } catch (e) { debugPrint('[NotificationService] requestExactAlarmsPermission error: $e'); }
    return false;
  }

  // Open the app's notification settings page
  static Future<void> openAppNotificationSettings() async {
    try {
      if (Platform.isAndroid) {
        final intent = AndroidIntent(
          action: 'android.settings.APP_NOTIFICATION_SETTINGS',
          arguments: <String, dynamic>{
            'android.provider.extra.APP_PACKAGE': await _packageName(),
          },
        );
        await intent.launch();
      } else if (Platform.isIOS) {
        await launchUrl(Uri.parse('app-settings:'));
      }
    } catch (e) {
      debugPrint('[NotificationService] openAppNotificationSettings error: $e');
    }
  }

  // Open the Android exact alarm settings page for this app (where supported)
  static Future<void> openExactAlarmsSettings() async {
    if (!Platform.isAndroid) return;
    try {
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
        data: 'package:' + (await _packageName()),
      );
      await intent.launch();
    } catch (e) {
      debugPrint('[NotificationService] openExactAlarmsSettings error: $e');
    }
  }

  // Open battery optimization settings so user can exclude the app if needed
  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      final intent = AndroidIntent(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      );
      await intent.launch();
    } catch (e) {
      debugPrint('[NotificationService] openBatteryOptimizationSettings error: $e');
    }
  }

  static Future<String> _packageName() async {
    // Best-effort; without package_info_plus, try via method channel-less hint
    // Fallback to known app id if configured at build time. If not available, leave empty.
    // Consider adding package_info_plus for reliable package name if needed.
    return const String.fromEnvironment('APP_PACKAGE_NAME', defaultValue: 'com.example.tooth_care_app');
  }

  static Future<void> showNow({required int id, required String title, required String body}) async {
    await init();
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(id, title, body, details);
    _notifyFireObservers(id);
  }


  static Future<void> debugDumpPending() async {
    final list = await pending();
    debugPrint('[NotificationService][debugDumpPending] count=${list.length}');
    for (final p in list) { debugPrint('  -> id=${p.id} title=${p.title}'); }
  }

  static Future<void> watchdogRescheduleDailyIfMissing() async {
    final list = await pending();
    debugPrint('[NotificationService][watchdog] pendingCount=${list.length}');
    // Potential enhancement: cross-check with reminder store and re-schedule if any enabled reminders missing.
  }

  static String nextFireLabel(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    var dayWord = 'Today';
    if (!scheduled.isAfter(now)) { scheduled = scheduled.add(const Duration(days: 1)); dayWord = 'Tomorrow'; }
    final hh = scheduled.hour.toString().padLeft(2, '0');
    final mm = scheduled.minute.toString().padLeft(2, '0');
    return '$dayWord $hh:$mm';
  }

  static Future<List<String>> getAmLog() async {
    // Stub: AlarmManager removed; return empty list for legacy UI.
    return <String>[];
  }
  static Future<void> clearAmLog() async {
    // Stub no-op.
  }
  static Future<bool> forceAlarmManagerInSeconds({required int id, required int seconds, required String title, required String body}) async {
    // Stub: schedule via plugin instead and report 'false' to indicate AM not used.
    await scheduleInSeconds(id: id, seconds: seconds, title: title, body: body);
    return false; // indicates AlarmManager path not taken
  }
}

// AlarmManager callback removed (see refactor note above).
