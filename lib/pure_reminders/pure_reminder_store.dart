import 'package:shared_preferences/shared_preferences.dart';
import 'pure_reminder_model.dart';

// DEPRECATION NOTICE:
// Legacy local-only storage for reminders (pre server migration).
// Not used by the current reminders UI. Retain briefly for potential data migration.

class PureReminderStore {
  static const _key = 'pure_reminders_v1';

  static Future<List<PureReminder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return PureReminder.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<PureReminder> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, PureReminder.encodeList(list));
  }

  static Future<void> upsert(PureReminder r) async {
    final list = await load();
    final idx = list.indexWhere((e) => e.id == r.id);
    if (idx >= 0) {
      list[idx] = r;
    } else {
      list.add(r);
    }
    await save(list);
  }

  static Future<void> bulkSave(List<PureReminder> updated) async {
    await save(updated);
  }

  static Future<void> remove(int id) async {
    final list = await load();
    list.removeWhere((e) => e.id == id);
    await save(list);
  }
}
