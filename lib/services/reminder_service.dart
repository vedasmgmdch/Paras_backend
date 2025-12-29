import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

// NOTE: Added verbose debug logging for reminder diagnosis. Prefix: [ReminderService]

/// Client-side representation of a server reminder.
class ReminderModel {
  final int? id; // null until created on server
  final String title;
  final String body;
  final int hour; // 0-23
  final int minute; // 0-59
  final String timezone; // IANA string
  final bool active;
  final int graceMinutes;
  final DateTime? nextFireLocal; // server computed (local date/time only)
  final DateTime? nextFireUtc; // server computed absolute
  final DateTime? lastSentUtc;
  final DateTime? lastAckLocalDate; // date-only meaning user acknowledged today

  // Local-only fields
  final int? localNotificationId; // mapping to flutter_local_notifications id
  final bool firedTodayLocally; // whether local notification callback fired today

  ReminderModel({
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
    required this.lastSentUtc,
    required this.lastAckLocalDate,
    this.localNotificationId,
    this.firedTodayLocally = false,
  });

  ReminderModel copyWith({
    int? id,
    String? title,
    String? body,
    int? hour,
    int? minute,
    String? timezone,
    bool? active,
    int? graceMinutes,
    DateTime? nextFireLocal,
    DateTime? nextFireUtc,
    DateTime? lastSentUtc,
    DateTime? lastAckLocalDate,
    int? localNotificationId,
    bool? firedTodayLocally,
  }) => ReminderModel(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    timezone: timezone ?? this.timezone,
    active: active ?? this.active,
    graceMinutes: graceMinutes ?? this.graceMinutes,
    nextFireLocal: nextFireLocal ?? this.nextFireLocal,
    nextFireUtc: nextFireUtc ?? this.nextFireUtc,
    lastSentUtc: lastSentUtc ?? this.lastSentUtc,
    lastAckLocalDate: lastAckLocalDate ?? this.lastAckLocalDate,
    localNotificationId: localNotificationId ?? this.localNotificationId,
    firedTodayLocally: firedTodayLocally ?? this.firedTodayLocally,
  );

  factory ReminderModel.fromJson(Map<String, dynamic> j) {
    DateTime? _parse(String k) => j[k] != null ? DateTime.tryParse(j[k]) : null;
    return ReminderModel(
      id: j['id'],
      title: j['title'] ?? '',
      body: j['body'] ?? '',
      hour: j['hour'] ?? 0,
      minute: j['minute'] ?? 0,
      timezone: j['timezone'] ?? 'UTC',
      active: j['active'] ?? true,
      graceMinutes: j['grace_minutes'] ?? 20,
      nextFireLocal: _parse('next_fire_local'),
      nextFireUtc: _parse('next_fire_utc'),
      lastSentUtc: _parse('last_sent_utc'),
      lastAckLocalDate: _parse('last_ack_local_date'),
    );
  }

  Map<String, dynamic> toCreateJson() => {
    'title': title,
    'body': body,
    'hour': hour,
    'minute': minute,
    'timezone': timezone,
    'active': active,
    'grace_minutes': graceMinutes,
  };

  Map<String, dynamic> toSyncJson({bool? ackToday}) => {
    if (id != null) 'id': id,
    'title': title,
    'body': body,
    'hour': hour,
    'minute': minute,
    'timezone': timezone,
    'active': active,
    'grace_minutes': graceMinutes,
    if (ackToday == true) 'ack_today': true,
  };
}

class ReminderService {
  static String get _base => ApiService.baseUrl;

  // List reminders
  static Future<List<ReminderModel>> list() async {
    // ignore: avoid_print
    print('[ReminderService] list() → requesting');
    final headers = await ApiService.getAuthHeaders();
    final res = await http.get(Uri.parse('$_base/reminders'), headers: headers);
    if (res.statusCode != 200) {
      // ignore: avoid_print
      print('[ReminderService] list() failed status=${res.statusCode} body=${res.body}');
      return [];
    }
    final data = jsonDecode(res.body) as List;
    // ignore: avoid_print
    print('[ReminderService] list() ← ${data.length} items');
    return data.map((e) => ReminderModel.fromJson(e)).toList();
  }

  // Create reminder
  static Future<ReminderModel?> create(ReminderModel r) async {
    // ignore: avoid_print
    print('[ReminderService] create() draft hour=${r.hour} minute=${r.minute} title="${r.title}"');
    final headers = await ApiService.getAuthHeaders();
    final res = await http.post(
      Uri.parse('$_base/reminders'),
      headers: headers,
      body: jsonEncode(r.toCreateJson()),
    );
    if (res.statusCode != 200) {
      // ignore: avoid_print
      print('[ReminderService] create() failed status=${res.statusCode} body=${res.body}');
      return null;
    }
    final parsed = ReminderModel.fromJson(jsonDecode(res.body));
    // ignore: avoid_print
    print('[ReminderService] create() ← id=${parsed.id} nextLocal=${parsed.nextFireLocal} active=${parsed.active}');
    return parsed;
  }

  // Update (partial)
  static Future<ReminderModel?> update(int id, Map<String, dynamic> patch) async {
    // ignore: avoid_print
    print('[ReminderService] update(id=$id) patchKeys=${patch.keys.toList()}');
    final headers = await ApiService.getAuthHeaders();
    final res = await http.patch(
      Uri.parse('$_base/reminders/$id'),
      headers: headers,
      body: jsonEncode(patch),
    );
    if (res.statusCode != 200) {
      // ignore: avoid_print
      print('[ReminderService] update(id=$id) failed status=${res.statusCode} body=${res.body}');
      return null;
    }
    final parsed = ReminderModel.fromJson(jsonDecode(res.body));
    // ignore: avoid_print
    print('[ReminderService] update(id=$id) ← nextLocal=${parsed.nextFireLocal} active=${parsed.active}');
    return parsed;
  }

  static Future<bool> delete(int id) async {
    // ignore: avoid_print
    print('[ReminderService] delete(id=$id)');
    final headers = await ApiService.getAuthHeaders();
    final res = await http.delete(Uri.parse('$_base/reminders/$id'), headers: headers);
    final ok = res.statusCode == 200;
    if (!ok) {
      // ignore: avoid_print
      print('[ReminderService] delete(id=$id) failed status=${res.statusCode} body=${res.body}');
    }
    return ok;
  }

  static Future<ReminderModel?> ack(int id) async {
    // ignore: avoid_print
    print('[ReminderService] ack(id=$id)');
    final headers = await ApiService.getAuthHeaders();
    final res = await http.post(Uri.parse('$_base/reminders/$id/ack'), headers: headers);
    if (res.statusCode != 200) {
      // ignore: avoid_print
      print('[ReminderService] ack(id=$id) failed status=${res.statusCode} body=${res.body}');
      return null;
    }
    final parsed = ReminderModel.fromJson(jsonDecode(res.body));
    // ignore: avoid_print
    print('[ReminderService] ack(id=$id) ← lastAckLocalDate=${parsed.lastAckLocalDate}');
    return parsed;
  }

  static Future<Map<String, dynamic>> sync(List<ReminderModel> locals, {bool pruneMissing = false}) async {
    // ignore: avoid_print
    print('[ReminderService] sync(pruneMissing=$pruneMissing) locals=${locals.length}');
    final headers = await ApiService.getAuthHeaders();
    final now = DateTime.now();
    final payloadItems = locals.map((r) {
      final firedToday = _inferFiredToday(r, now);
      return r.toSyncJson(ackToday: firedToday && r.lastAckLocalDate == null);
    }).toList();
    // ignore: avoid_print
    print('[ReminderService] sync() payloadItems=${payloadItems.length}');
    final res = await http.post(
      Uri.parse('$_base/reminders/sync'),
      headers: headers,
      body: jsonEncode({'items': payloadItems, 'prune_missing': pruneMissing}),
    );
    if (res.statusCode != 200) {
      // ignore: avoid_print
      print('[ReminderService] sync() failed status=${res.statusCode} body=${res.body}');
      return {'created':0,'updated':0,'pruned':0,'error':res.body};
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    // ignore: avoid_print
    print('[ReminderService] sync() ← created=${decoded['created']} updated=${decoded['updated']} pruned=${decoded['pruned']}');
    return decoded;
  }

  static Future<Map<String, dynamic>?> health() async {
    // ignore: avoid_print
    print('[ReminderService] health()');
    final headers = await ApiService.getAuthHeaders();
    final res = await http.get(Uri.parse('$_base/reminders/health'), headers: headers);
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ------------- Scheduling Helpers (Stubs) -------------
  // These are stubs so you can hook in flutter_local_notifications or awesome_notifications.
  // Implement real scheduling elsewhere and store returned local notification id.

  static Future<int?> scheduleLocal(ReminderModel r) async {
    // TODO: integrate with flutter_local_notifications
    // Example: compute next DateTime now or tomorrow
    // ignore: avoid_print
    print('[ReminderService] scheduleLocal(STUB) id=${r.id} hour=${r.hour} minute=${r.minute} active=${r.active}');
    return null; // return notification id
  }

  static Future<void> cancelLocal(int? localId) async {
    if (localId == null) return;
    // TODO: cancel with plugin
    // ignore: avoid_print
    print('[ReminderService] cancelLocal(STUB) localId=$localId');
  }

  static bool _inferFiredToday(ReminderModel r, DateTime now) {
    if (!r.active) return false;
    // naive inference: if current time is after scheduled hour/minute and before +6h window
    final local = DateTime(now.year, now.month, now.day, r.hour, r.minute);
    if (now.isBefore(local)) return false;
    if (now.difference(local).inHours > 6) return false; // outside plausible window
    final result = r.firedTodayLocally; // rely on stored flag
    // ignore: avoid_print
    print('[ReminderService] _inferFiredToday id=${r.id} firedTodayLocally=${r.firedTodayLocally} result=$result now=$now local=$local');
    return result; // rely on stored flag
  }

  // Persist a small local cache of reminders (ids + mapping) for offline use
  static Future<void> saveCache(List<ReminderModel> reminders) async {
    // ignore: avoid_print
    print('[ReminderService] saveCache count=${reminders.length}');
    final prefs = await SharedPreferences.getInstance();
    final list = reminders.map((r) => {
      'id': r.id,
      'title': r.title,
      'body': r.body,
      'hour': r.hour,
      'minute': r.minute,
      'timezone': r.timezone,
      'active': r.active,
      'grace_minutes': r.graceMinutes,
      'last_ack_local_date': r.lastAckLocalDate?.toIso8601String(),
      'next_fire_local': r.nextFireLocal?.toIso8601String(),
      'next_fire_utc': r.nextFireUtc?.toIso8601String(),
      'local_notification_id': r.localNotificationId,
    }).toList();
    await prefs.setString('reminders_cache', jsonEncode(list));
  }

  static Future<List<ReminderModel>> loadCache() async {
    // ignore: avoid_print
    print('[ReminderService] loadCache()');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('reminders_cache');
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw) as List;
      final list = data.map((e) => ReminderModel.fromJson(e)).toList();
      // ignore: avoid_print
      print('[ReminderService] loadCache() ← ${list.length}');
      return list;
    } catch (_) {
      // ignore: avoid_print
      print('[ReminderService] loadCache() decode error');
      return [];
    }
  }

  // Dump current cached reminders for diagnostics
  static Future<void> debugDumpCache() async {
    final list = await loadCache();
    print('[ReminderService][debugDumpCache] count=${list.length}');
    for (final r in list) {
      print('  -> id=${r.id} hour=${r.hour} minute=${r.minute} active=${r.active} nextLocal=${r.nextFireLocal} nextUtc=${r.nextFireUtc} firedToday=${r.firedTodayLocally}');
    }
  }
}
