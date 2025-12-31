import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../services/notification_service.dart';

/// Server-backed Reminder model mirroring backend ReminderResponse
class ServerReminder {
  final int id;
  final String title;
  final String body;
  final int hour;
  final int minute;
  final String timezone;
  final bool active;
  final int graceMinutes;
  final DateTime nextFireLocal;
  final DateTime nextFireUtc;
  final DateTime? lastSentUtc;
  final DateTime? lastAckLocalDate;

  ServerReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.hour,
    required this.minute,
    required this.timezone,
    required this.active,
    required this.graceMinutes,
    required this.nextFireLocal,
    required this.nextFireUtc,
    this.lastSentUtc,
    this.lastAckLocalDate,
  });

  factory ServerReminder.fromJson(Map<String, dynamic> m) => ServerReminder(
        id: m['id'] as int,
        title: m['title'] as String,
        body: m['body'] as String,
        hour: m['hour'] as int,
        minute: m['minute'] as int,
        timezone: m['timezone'] as String,
        active: m['active'] as bool,
        graceMinutes: m['grace_minutes'] as int,
        nextFireLocal: DateTime.parse(m['next_fire_local'] as String),
        nextFireUtc: DateTime.parse(m['next_fire_utc'] as String).toUtc(),
        lastSentUtc: m['last_sent_utc'] == null ? null : DateTime.parse(m['last_sent_utc'] as String).toUtc(),
        lastAckLocalDate: m['last_ack_local_date'] == null ? null : DateTime.parse(m['last_ack_local_date'] as String),
      );
}

class ReminderApi {
  static DateTime? _lastScheduleBatchTime;
  static const _scheduleDebounceMs = 1500;
  static const clientScheduleVersion = 'hybrid_v3';
  static const _cacheKey = 'server_reminders_cache_v1';
  static Uri _u(String path,[Map<String,String>? qp]) {
    final base = ApiService.baseUrl.endsWith('/') ? ApiService.baseUrl.substring(0, ApiService.baseUrl.length-1) : ApiService.baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: qp);
  }

  static Future<Map<String,String>> _authHeaders() async => await ApiService.getAuthHeaders();

  static Future<void> _saveCacheRaw(String rawJsonList) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, rawJsonList);
    } catch (_) {}
  }

  static Future<List<ServerReminder>> listCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return [];
      final data = jsonDecode(raw) as List<dynamic>;
      return data.map((e) => ServerReminder.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  // List reminders
  static Future<List<ServerReminder>> list() async {
    try {
      final res = await http.get(_u('/reminders'), headers: await _authHeaders());
      if (res.statusCode == 200) {
        await _saveCacheRaw(res.body);
        final data = jsonDecode(res.body) as List<dynamic>;
        return data.map((e)=>ServerReminder.fromJson(e as Map<String,dynamic>)).toList();
      }
      debugPrint('ReminderApi.list failed ${res.statusCode} ${res.body}');
    } catch (e) { debugPrint('ReminderApi.list error $e'); }
    return [];
  }

  // Prefer network, but fall back to cached list so we don't wipe schedules when offline.
  static Future<List<ServerReminder>> listWithCacheFallback() async {
    final fresh = await list();
    if (fresh.isNotEmpty) return fresh;
    final cached = await listCached();
    if (cached.isNotEmpty) {
      debugPrint('[ReminderApi] using cached reminders (count=${cached.length})');
    }
    return cached;
  }

  static Future<ServerReminder?> create({required String title, required String body, required int hour, required int minute, String timezone='Asia/Kolkata', bool active=true, int graceMinutes=20}) async {
    final payload = {
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'timezone': timezone,
      'active': active,
      'grace_minutes': graceMinutes,
    };
    try {
      final res = await http.post(_u('/reminders'), headers: await _authHeaders(), body: jsonEncode(payload));
      if (res.statusCode == 200) {
        return ServerReminder.fromJson(jsonDecode(res.body) as Map<String,dynamic>);
      }
      debugPrint('ReminderApi.create failed ${res.statusCode} ${res.body}');
    } catch (e) { debugPrint('ReminderApi.create error $e'); }
    return null;
  }

  static Future<ServerReminder?> update(int id, {String? title, String? body, int? hour, int? minute, String? timezone, bool? active, int? graceMinutes, bool? ackToday}) async {
    final patch = <String,dynamic>{};
    if (title != null) patch['title']=title;
    if (body != null) patch['body']=body;
    if (hour != null) patch['hour']=hour;
    if (minute != null) patch['minute']=minute;
    if (timezone != null) patch['timezone']=timezone;
    if (active != null) patch['active']=active;
    if (graceMinutes != null) patch['grace_minutes']=graceMinutes;
    if (ackToday == true) patch['ack_today']=true;
    try {
      final res = await http.patch(_u('/reminders/$id'), headers: await _authHeaders(), body: jsonEncode(patch));
      if (res.statusCode == 200) return ServerReminder.fromJson(jsonDecode(res.body) as Map<String,dynamic>);
      debugPrint('ReminderApi.update failed ${res.statusCode} ${res.body}');
    } catch (e) { debugPrint('ReminderApi.update error $e'); }
    return null;
  }

  static Future<bool> delete(int id) async {
    try {
      final res = await http.delete(_u('/reminders/$id'), headers: await _authHeaders());
      return res.statusCode == 200;
    } catch (e) { debugPrint('ReminderApi.delete error $e'); }
    return false;
  }

  // Schedule local notifications for active reminders (idempotent-ish) – simplistic: always reschedule daily id.
  static Future<void> scheduleLocally(List<ServerReminder> list) async {
    final now = DateTime.now();
    if (_lastScheduleBatchTime != null && now.difference(_lastScheduleBatchTime!).inMilliseconds < _scheduleDebounceMs) {
      debugPrint('[ReminderApi] scheduleLocally debounced (batch too soon)');
      return;
    }
    _lastScheduleBatchTime = now;
    debugPrint('[ReminderApi] scheduleLocally batch size=${list.length} version=$clientScheduleVersion at=$now');
    for (final r in list) {
      if (!r.active) {
        debugPrint('[ReminderApi.scheduleLocally] cancel inactive id=${r.id}');
        await NotificationService.cancel(r.id);
        continue;
      }
      debugPrint('[ReminderApi] schedule hybrid id=${r.id} ${r.hour.toString().padLeft(2,'0')}:${r.minute.toString().padLeft(2,'0')} "${r.title}"');
      await NotificationService.scheduleHybridDaily(
        id: r.id,
        hour: r.hour,
        minute: r.minute,
        title: r.title,
        body: r.body,
      );
    }
    // Diagnostic: dump count of pending (avoid enumerating all each time to reduce spam)
    try {
      final pending = await NotificationService.pending();
      debugPrint('[ReminderApi] pending after batch count=${pending.length}');
    } catch (_) {}
  }
}
