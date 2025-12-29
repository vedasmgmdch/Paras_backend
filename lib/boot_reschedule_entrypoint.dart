/// Boot reschedule entrypoint
///
/// This top-level function is invoked by a native Android BroadcastReceiver
/// (listening to ACTION_BOOT_COMPLETED) via a headless FlutterEngine.
/// It re-initializes the notification plugin and re-schedules all enabled
/// daily reminders so they survive device reboot without the user having to
/// open the app manually.
///
/// Native receiver setup steps (summary):
/// 1. Add RECEIVE_BOOT_COMPLETED permission to AndroidManifest.xml
///    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
/// 2. Declare a receiver inside <application>:
///    <receiver
///        android:name=".BootCompletedReceiver"
///        android:exported="false"
///        android:enabled="true">
///      <intent-filter>
///        <action android:name="android.intent.action.BOOT_COMPLETED" />
///        <action android:name="android.intent.action.LOCKED_BOOT_COMPLETED" />
///      </intent-filter>
///    </receiver>
/// 3. Implement BootCompletedReceiver (Kotlin example in README-reminders-modern.md)
///    that builds a FlutterEngine and executes this Dart entrypoint name:
///      engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
///          loader.findAppBundlePath(), "bootRescheduleMain"))
/// 4. Keep work minimal: schedule only; avoid long I/O or network here.
///
/// NOTE: This file is safe even if never referenced on other platforms.

import 'package:flutter/widgets.dart';
import 'services/notification_service.dart';
import 'services/reminder_api.dart';

@pragma('vm:entry-point')
Future<void> bootRescheduleMain() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationService.init(requestPermission: false);
    // Fetch server-backed reminders and reschedule locally.
    // Note: Calls to network may be limited right after boot; we keep this minimal.
    final list = await ReminderApi.list();
    await ReminderApi.scheduleLocally(list);
    // ignore: avoid_print
    print('[BootReschedule] Rescheduled ${list.length} reminders');
  } catch (e) {
    // ignore: avoid_print
    print('[BootReschedule] Error during init: $e');
  }
}
