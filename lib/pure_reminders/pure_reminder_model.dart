import 'dart:convert';

// DEPRECATION NOTICE:
// This PureReminder model belonged to the legacy local-only reminder system.
// The reminders screen has been migrated to server-backed reminders (ReminderApi).
// Retained temporarily for potential migration/rollback; plan to remove after validation.

class PureReminder {
  final int id; // stable id
  final String title;
  final int hour; // 0-23
  final int minute; // 0-59
  final bool enabled;
  final DateTime? nextFireUtc; // cached next fire instant in UTC
  final DateTime? lastFireUtc; // last time we observed fire (UTC)
  final int missedCount; // consecutive detected misses

  PureReminder({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    required this.enabled,
    this.nextFireUtc,
    this.lastFireUtc,
    this.missedCount = 0,
  });

  PureReminder copyWith({
    String? title,
    int? hour,
    int? minute,
    bool? enabled,
    DateTime? nextFireUtc,
    DateTime? lastFireUtc,
    int? missedCount,
  }) => PureReminder(
        id: id,
        title: title ?? this.title,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        enabled: enabled ?? this.enabled,
        nextFireUtc: nextFireUtc ?? this.nextFireUtc,
        lastFireUtc: lastFireUtc ?? this.lastFireUtc,
        missedCount: missedCount ?? this.missedCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'hour': hour,
        'minute': minute,
        'enabled': enabled,
        'nextFireUtc': nextFireUtc?.toIso8601String(),
        'lastFireUtc': lastFireUtc?.toIso8601String(),
        'missedCount': missedCount,
      };

  static PureReminder fromJson(Map<String, dynamic> m) => PureReminder(
        id: m['id'] as int,
        title: m['title'] as String,
        hour: m['hour'] as int,
        minute: m['minute'] as int,
        enabled: m['enabled'] as bool,
        nextFireUtc: m['nextFireUtc'] == null ? null : DateTime.parse(m['nextFireUtc'] as String).toUtc(),
        lastFireUtc: m['lastFireUtc'] == null ? null : DateTime.parse(m['lastFireUtc'] as String).toUtc(),
        missedCount: (m['missedCount'] as num?)?.toInt() ?? 0,
      );

  static String encodeList(List<PureReminder> list) => jsonEncode(list.map((e) => e.toJson()).toList());
  static List<PureReminder> decodeList(String raw) {
    final data = jsonDecode(raw) as List<dynamic>;
    return data.map((e) => fromJson(e as Map<String, dynamic>)).toList();
  }
}
