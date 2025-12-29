import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import '../services/notification_service.dart';
import 'pure_reminder_model.dart';
import 'pure_reminder_store.dart';

/// Isolated minimal scheduler with:
/// - exact daily scheduling
/// - catch-up one-off
/// - self-test at startup
/// - watchdog recheck
class PureReminderScheduler with ChangeNotifier {
  static final PureReminderScheduler instance = PureReminderScheduler._();
  PureReminderScheduler._();

  bool _initialized = false;
  bool _selfTestPassing = false;
  String? _selfTestStatusMsg;

  bool get selfTestPassing => _selfTestPassing;
  String get selfTestLabel {
    if (_selfTestStatusMsg != null) return _selfTestStatusMsg!;
    if (_selfTestPassing) return 'Scheduling OK';
    return 'Not tested';
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await NotificationService.init();
    await _runSelfTest();
    await watchdog();
  }

  Future<List<PureReminder>> load() => PureReminderStore.load();

  Future<void> addOrUpdate(PureReminder r) async {
    // Persist immediate state; scheduling metadata updated after scheduling.
    await PureReminderStore.upsert(r);
    if (r.enabled) {
      final updated = await _scheduleDailyWithMeta(r);
      await _maybeCatchUp(updated);
    } else {
      await NotificationService.cancel(r.id);
      // Cancel any legacy catch-up/cascade ids (previous implementation used large offsets)
      await NotificationService.cancel(r.id + 700000000);
      await NotificationService.cancel(r.id + 750000000);
      await NotificationService.cancel(r.id + 800000000);
    }
    notifyListeners();
  }

  Future<void> delete(int id) async {
    await NotificationService.cancel(id);
    // Clean any derived ids from prior versions
    await NotificationService.cancel(id + 700000000);
    await NotificationService.cancel(id + 750000000);
    await NotificationService.cancel(id + 800000000);
    await PureReminderStore.remove(id);
    notifyListeners();
  }

  Future<void> toggle(int id, bool enabled) async {
    final list = await load();
    final r = list.firstWhere((e) => e.id == id);
    final updated = r.copyWith(enabled: enabled);
    await addOrUpdate(updated);
  }

  Future<PureReminder> _scheduleDailyWithMeta(PureReminder r) async {
    // Single daily schedule using plugin zonedSchedule (matchDateTimeComponents) without
    // secondary fallback. Empirical testing shows duplicate staggered alarms can trigger
    // OEM heuristic suppression. Simplicity improves reliability.
    final now = tz.TZDateTime.now(tz.local);
    var fire = tz.TZDateTime(tz.local, now.year, now.month, now.day, r.hour, r.minute);
    if (!fire.isAfter(now)) fire = fire.add(const Duration(days: 1));
    await NotificationService.scheduleDailyBasic(
      id: r.id,
      hour: r.hour,
      minute: r.minute,
      title: 'Reminder',
      body: r.title,
    );
    final withMeta = r.copyWith(nextFireUtc: fire.toUtc());
    await PureReminderStore.upsert(withMeta);
    debugPrint('[PureReminder] scheduled daily id=${r.id} firstLocal=$fire');
    return withMeta;
  }

  Future<void> _maybeCatchUp(PureReminder r) async {
    // Catch-up logic retained but simplified: if within 2h window after scheduled time today,
    // emit a one-off 15s later. Uses large offset id to avoid collision with primary.
    final now = DateTime.now();
    final todayLocal = DateTime(now.year, now.month, now.day, r.hour, r.minute);
    final diffSec = now.difference(todayLocal).inSeconds;
    if (diffSec > 0 && diffSec <= 7200) {
      final oneOffId = r.id + 700000000; // legacy space reused intentionally
      await NotificationService.scheduleInSeconds(
        id: oneOffId,
        seconds: 15,
        title: 'Reminder (catch-up)',
        body: r.title,
      );
      debugPrint('[PureReminder] catch-up scheduled base=${r.id} fireIn=15s missed=${diffSec}s');
    }
  }

  Future<void> watchdog() async {
    final list = await load();
    final nowUtc = DateTime.now().toUtc();
    bool changed = false;
    final updated = <PureReminder>[];
    for (final r in list) {
      if (!r.enabled || r.nextFireUtc == null) { updated.add(r); continue; }
      // If 20m past expected fire and not recorded as fired, treat as missed and reschedule.
      if (nowUtc.isAfter(r.nextFireUtc!.add(const Duration(minutes: 20))) && (r.lastFireUtc == null || r.lastFireUtc!.isBefore(r.nextFireUtc!))) {
        final missed = r.missedCount + 1;
        debugPrint('[PureReminder][watchdog] missed id=${r.id} count=$missed');
        final rescheduled = await _scheduleDailyWithMeta(r.copyWith(missedCount: missed));
        updated.add(rescheduled);
        changed = true;
      } else {
        updated.add(r);
      }
    }
    if (changed) await PureReminderStore.bulkSave(updated);
  }

  Future<void> forceRescheduleAll() async {
    final list = await load();
    await NotificationService.cancelAllPending();
    for (final r in list.where((e) => e.enabled)) {
      final u = await _scheduleDailyWithMeta(r);
      await _maybeCatchUp(u);
    }
    debugPrint('[PureReminder] forceRescheduleAll done');
  }

  // Self test: schedule a one-off 25s ahead; if fires call markSelfTestSuccess.
  static const _selfTestIdBase = 880000000;
  Future<void> _runSelfTest() async {
    final id = _selfTestIdBase + Random().nextInt(100000);
    try {
      await NotificationService.scheduleInSeconds(
        id: id,
        seconds: 25,
        title: 'Self-Test',
        body: 'Scheduler validation',
      );
      _selfTestStatusMsg = 'Self-test scheduled';
      notifyListeners();
      Future.delayed(const Duration(seconds: 40), () async {
        // We cannot automatically detect fire without a callback; rely on user observation for now.
        if (!_selfTestPassing) {
          _selfTestStatusMsg = 'Self-test pending (ensure notification arrived)';
          notifyListeners();
        }
      });
    } catch (e) {
      _selfTestStatusMsg = 'Self-test failed to schedule: $e';
      notifyListeners();
    }
  }

  void markSelfTestSuccess() {
    _selfTestPassing = true;
    _selfTestStatusMsg = 'Scheduling OK';
    notifyListeners();
  }
}
