import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';

class SystemAlarmService {
  // Opens system Clock app UI to create an alarm at hour:minute with a label.
  // This uses the public AlarmClock intent, so no special permissions required.
  static Future<bool> setAlarm({
    required int hour,
    required int minute,
    String label = 'Tooth-care reminder',
    bool skipUi = false,
    List<int>? days, // 1=Sunday..7=Saturday per Android docs
  }) async {
    if (!Platform.isAndroid) return false;

    final args = <String, dynamic>{
      'android.intent.extra.HOUR': hour,
      'android.intent.extra.MINUTES': minute,
      'android.intent.extra.MESSAGE': label,
      'android.intent.extra.SKIP_UI': skipUi,
    };
    if (days != null && days.isNotEmpty) {
      args['android.intent.extra.DAYS'] = days;
    }

    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_ALARM',
        arguments: args,
      );
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  // Opens Clock app alarm list for user to review/manage existing alarms
  static Future<void> openAlarmList() async {
    if (!Platform.isAndroid) return;
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SHOW_ALARMS',
      );
      await intent.launch();
    } catch (_) {}
  }
}
