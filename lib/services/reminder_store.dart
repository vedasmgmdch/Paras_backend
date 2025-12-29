import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

class Reminder {
  final int id;
  String title;
  int hour;
  int minute;
  bool enabled;

  Reminder({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.enabled = true,
  });

  factory Reminder.newFor({
    required String title,
    required int hour,
    required int minute,
  }) {
    final id = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    return Reminder(id: id, title: title, hour: hour, minute: minute);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'hour': hour,
        'minute': minute,
        'enabled': enabled,
      };

  static Reminder fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'] as int,
        title: j['title'] as String,
        hour: j['hour'] as int,
        minute: j['minute'] as int,
        enabled: (j['enabled'] as bool?) ?? true,
      );
}

class ReminderStore {
  static const _key = 'daily_reminders_v1';
  // When true (hybrid mode), CRUD still persists but scheduling/cancel operations are skipped (hybrid layer manages scheduling)
  static bool hybridActive = false;

  static Future<List<Reminder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List)
        .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
        .toList();
    return list;
  }

  static Future<void> _save(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(reminders.map((e) => e.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  // Replace entire stored list (used by hybrid sync). This will not schedule notifications;
  // caller is responsible for (re)creating plugin schedules after invoking this.
  static Future<void> replaceAll(List<Reminder> reminders) async {
    await _save(reminders);
  }

  static Future<void> add(Reminder r) async {
    final list = await load();
    list.add(r);
    await _save(list);
    if (r.enabled && !hybridActive) {
      try {
        print('[ReminderStore] (basic) schedule id=${r.id} ${r.hour}:${r.minute}');
        await NotificationService.scheduleDailyBasic(
          id: r.id,
          hour: r.hour,
          minute: r.minute,
          title: 'Reminder',
          body: r.title,
        );
        _maybeScheduleCatchUp(r);
      } catch (e) {
        print('[ReminderStore] scheduleDailyNotification failed: $e');
      }
    }
  }

  static Future<void> update(Reminder updated) async {
    final list = await load();
    final idx = list.indexWhere((e) => e.id == updated.id);
    if (idx == -1) return;
    list[idx] = updated;
    await _save(list);
    // Re-schedule safely
    if (!hybridActive) {
      try {
        print('[ReminderStore] Cancel existing schedule id=${updated.id}');
        await NotificationService.cancel(updated.id);
      } catch (e) {
        print('[ReminderStore] cancel failed: $e');
      }
    }
    if (updated.enabled && !hybridActive) {
      try {
        print('[ReminderStore] (basic) re-schedule id=${updated.id} ${updated.hour}:${updated.minute}');
        await NotificationService.scheduleDailyBasic(
          id: updated.id,
          hour: updated.hour,
          minute: updated.minute,
          title: 'Reminder',
          body: updated.title,
        );
        _maybeScheduleCatchUp(updated);
      } catch (e) {
        print('[ReminderStore] reschedule failed: $e');
      }
    }
  }

  static Future<void> remove(int id) async {
    final list = await load();
    list.removeWhere((e) => e.id == id);
    await _save(list);
    if (!hybridActive) {
      try {
        print('[ReminderStore] Cancel schedule id=$id');
        await NotificationService.cancel(id);
      } catch (e) {
        print('[ReminderStore] cancel failed: $e');
      }
    }
  }

  static Future<void> toggle(int id, bool enabled) async {
    final list = await load();
    final idx = list.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final r = list[idx];
    r.enabled = enabled;
    await _save(list);
    if (!hybridActive) {
      if (enabled) {
        try {
          print('[ReminderStore] (basic) toggle ON id=${r.id} ${r.hour}:${r.minute}');
          await NotificationService.scheduleDailyBasic(
            id: r.id,
            hour: r.hour,
            minute: r.minute,
            title: 'Reminder',
            body: r.title,
          );
          _maybeScheduleCatchUp(r);
        } catch (e) {
          print('[ReminderStore] toggle schedule failed: $e');
        }
      } else {
        try {
          print('[ReminderStore] Toggle OFF id=${r.id}');
          await NotificationService.cancel(r.id);
        } catch (e) {
          print('[ReminderStore] toggle cancel failed: $e');
        }
      }
    }
  }
}

// Internal helper: schedule a one-off catch-up if time already passed today but within grace window.
Future<void> _maybeScheduleCatchUp(Reminder r) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, r.hour, r.minute);
  final diff = now.difference(today).inSeconds; // positive if now after reminder time
  // Conditions:
  // 1. Past (diff > 0)
  // 2. Within 2 hours (7200s) OR (almost upcoming: -diff <= 60 for near boundary)
  // 3. We already scheduled dailyBasic which will handle tomorrow; this is just immediate feedback.
  if (diff > 0 && diff <= 7200) {
    final oneOffId = r.id + 500000000; // distinct id space
    // fire in 15 seconds for user feedback
    try {
      print('[ReminderStore] catch-up oneOff schedule baseId=${r.id} oneOffId=$oneOffId in=15s (missed ${diff}s ago)');
      await NotificationService.scheduleInSeconds(
        id: oneOffId,
        seconds: 15,
        title: 'Reminder',
        body: r.title,
      );
    } catch (e) {
      print('[ReminderStore] catch-up scheduling failed id=${r.id} error=$e');
    }
  } else if (diff <= 0 && diff >= -60) {
    // Very near in the future (< 60s ahead) add small hedge one-off to reduce boundary miss risk
    final oneOffId = r.id + 500000000;
    try {
      print('[ReminderStore] boundary hedge oneOff schedule baseId=${r.id} oneOffId=$oneOffId in=20s (target ~${-diff}s ahead)');
      await NotificationService.scheduleInSeconds(
        id: oneOffId,
        seconds: 20,
        title: 'Reminder',
        body: r.title,
      );
    } catch (e) {
      print('[ReminderStore] boundary hedge failed id=${r.id} error=$e');
    }
  }
}
