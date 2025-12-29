// Hybrid reminders service: manages local scheduling + server sync/ack.
// This is an initial bridge; integrate into app startup and reminder UI incrementally.

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'notification_service.dart';
import 'api_service.dart';
import 'reminder_store.dart';
import 'package:timezone/timezone.dart' as tz;

class HybridRemindersService {
  static const _serverMapKey = 'reminder_server_map_v1'; // localId -> serverId json map
  static Map<int,int> _localToServer = {};
  static bool _loaded = false;
  static bool serverOnly = false; // When true, skip local scheduling & rely on backend pushes.
  static bool enableSweep = false; // Disable missed-today auto ACK by default to avoid suppressing fallback.

  static Future<void> _persistMap() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_localToServer.map((k,v) => MapEntry(k.toString(), v)));
    await prefs.setString(_serverMapKey, encoded);
  }

  static Future<void> _restoreMap() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_serverMapKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final Map<String,dynamic> decoded = jsonDecode(raw);
        _localToServer = decoded.map((k, v) => MapEntry(int.tryParse(k) ?? 0, (v as num).toInt()))
          ..removeWhere((k, v) => k == 0);
      } catch (_) {}
    }
    _loaded = true;
  }

  static Future<void> initialize() async {
    // ignore: avoid_print
    print('[HybridRemindersService] initialize() serverOnly=$serverOnly enableSweep=$enableSweep');
    // Mark hybrid active so legacy store won't schedule directly
    ReminderStore.hybridActive = true;
    await _restoreMap();
    // Propagate server-only flag to notification layer so all scheduling APIs no-op
    NotificationService.serverOnlyMode = serverOnly; // propagate to notification layer
    if (!serverOnly) {
      // ignore: avoid_print
      print('[HybridRemindersService] NotificationService init & callback wiring');
      // If notification service already initialized by app startup we just set handler.
      try {
        NotificationService.setOnNotificationReceived((id) async {
          await acknowledgeLocalFire(id);
        });
      } catch (_) {}
      // Still call init (idempotent) to ensure plugin ready.
      await NotificationService.init(onNotificationReceived: (id) async {
        await acknowledgeLocalFire(id);
      });
      if (enableSweep) {
        // ignore: avoid_print
        print('[HybridRemindersService] enableSweep=true performing _sweepMissedToday');
        // Perform a sweep for any reminders that should have fired earlier today but app was closed.
        await _sweepMissedToday();
      }
    } else {
      // ignore: avoid_print
      print('[HybridRemindersService] serverOnly=true skipping NotificationService.init & local scheduling');
    }
    try {
      await debugDumpAll(label: 'post-initialize');
    } catch (e) {
      // ignore: avoid_print
      print('[HybridRemindersService] debugDumpAll skipped (init) error=$e');
    }
  }

  static Future<void> _sweepMissedToday() async {
    final local = await ReminderStore.load();
    final now = DateTime.now();
    for (final r in local) {
      if (!r.enabled) continue;
      final candidate = DateTime(now.year, now.month, now.day, r.hour, r.minute);
      // If the scheduled time is before now (with 10 min grace) we assume it likely fired; ack to suppress fallback
      if (candidate.isBefore(now.subtract(const Duration(minutes: 10)))) {
        await acknowledgeLocalFire(r.id);
      }
    }
  }

  static String _deviceTimezone() {
    try { return tz.local.name; } catch (_) { return 'UTC'; }
  }

  // Push local reminders to server (create or update) then pull canonical list and re-schedule locally.
  static Future<void> bidirectionalSync() async {
    // ignore: avoid_print
    print('[HybridRemindersService] bidirectionalSync() start');
    final local = await ReminderStore.load();
    final tzName = _deviceTimezone();
    // ignore: avoid_print
    print('[HybridRemindersService] localCount=${local.length} tz=$tzName mapSize=${_localToServer.length}');
    final payloadItems = <Map<String,dynamic>>[];
    for (final r in local) {
      final serverId = _localToServer[r.id];
      payloadItems.add({
        if (serverId != null) 'id': serverId,
        'title': r.title,
        'body': r.title,
        'hour': r.hour,
        'minute': r.minute,
        'timezone': tzName,
        'active': r.enabled,
        'grace_minutes': 0,
      });
    }
    final syncRes = await ApiService.syncReminders(payloadItems);
    if (syncRes == null) return;
    // ignore: avoid_print
    print('[HybridRemindersService] syncReminders response keys=${syncRes.keys}');
    final synced = (syncRes['synced'] as List?) ?? [];
    final newLocal = <Reminder>[];
    for (final item in synced) {
      if (item is! Map) continue;
      final id = item['id'] as int;
      final hour = item['hour'] as int; final minute = item['minute'] as int;
      final title = (item['title'] as String?) ?? 'Reminder';
      final active = item['active'] as bool? ?? true;
      int? localId = _localToServer.entries.firstWhere((e) => e.value == id, orElse: () => const MapEntry(-1,-1)).key;
      if (localId == -1) {
        localId = id;
        _localToServer[localId] = id;
        // ignore: avoid_print
        print('[HybridRemindersService] map add localId=$localId -> serverId=$id');
      }
      newLocal.add(Reminder(id: localId, title: title, hour: hour, minute: minute, enabled: active));
    }
    await _persistMap();
    await _replaceLocal(newLocal);
    try {
      await debugDumpAll(label: 'post-bidirectionalSync');
    } catch (e) {
      // ignore: avoid_print
      print('[HybridRemindersService] debugDumpAll skipped (sync) error=$e');
    }
  }

  static Future<void> _replaceLocal(List<Reminder> list) async {
    // ignore: avoid_print
    print('[HybridRemindersService] _replaceLocal count=${list.length} serverOnly=$serverOnly');
    await ReminderStore.replaceAll(list);
    if (serverOnly) return; // Skip scheduling in server-only mode.
    await NotificationService.cancelAllPending();
    for (final r in list) {
      if (r.enabled) {
        // ignore: avoid_print
        print('[HybridRemindersService] scheduling local reminder id=${r.id} ${r.hour}:${r.minute}');
        await NotificationService.scheduleDailyNotification(
          id: r.id,
          hour: r.hour,
          minute: r.minute,
          title: 'Reminder',
          body: r.title,
        );
      }
    }
  }

  // Public helper to force re-scheduling of all stored local reminders (e.g., after granting exact alarm permission)
  static Future<void> reScheduleAllDailyReminders() async {
    final list = await ReminderStore.load();
    print('[HybridRemindersService] reScheduleAllDailyReminders count=${list.length}');
    for (final r in list) {
      if (r.enabled) {
        await NotificationService.scheduleDailyNotification(
          id: r.id,
          hour: r.hour,
          minute: r.minute,
          title: 'Reminder',
          body: r.title,
        );
      }
    }
    try { await debugDumpAll(label: 'post-reScheduleAll'); } catch (_) {}
  }

  static Future<void> acknowledgeLocalFire(int localId) async {
    // ignore: avoid_print
    print('[HybridRemindersService] acknowledgeLocalFire localId=$localId');
    final serverId = _localToServer[localId];
    if (serverId == null) return; // not yet synced
    await ApiService.ackReminder(serverId);
  }

  // Central debug dump: local reminders + mapping + pending plugin notifications
  static Future<void> debugDumpAll({String? label}) async {
    final local = await ReminderStore.load();
    List pending = const [];
    try {
      pending = await NotificationService.pending();
    } catch (e) {
      // ignore: avoid_print
      print('[HybridRemindersService] debugDumpAll pending() fail: $e');
    }
    print('[HybridRemindersService][debugDumpAll] label=${label ?? '-'} platform=${tz.local.name} local=${local.length} pending=${pending.length} mapSize=${_localToServer.length}');
    for (final r in local) {
      print('  [local] id=${r.id} ${r.hour.toString().padLeft(2,'0')}:${r.minute.toString().padLeft(2,'0')} enabled=${r.enabled} serverId=${_localToServer[r.id]}');
    }
    for (final p in pending) {
      print('  [pending] id=${p.id} title=${p.title} payload=${p.payload}');
    }
  }
}
