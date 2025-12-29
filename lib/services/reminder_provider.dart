import 'package:flutter/foundation.dart';
import 'reminder_service.dart';

class ReminderProvider extends ChangeNotifier {
  List<ReminderModel> _reminders = [];
  bool _loading = false;
  bool _initialized = false;
  String? _error;

  List<ReminderModel> get reminders => List.unmodifiable(_reminders);
  bool get loading => _loading;
  bool get initialized => _initialized;
  String? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    // ignore: avoid_print
    print('[ReminderProvider] load() start');
    _loading = true; _error = null; notifyListeners();
    try {
      final cached = await ReminderService.loadCache();
      // ignore: avoid_print
      print('[ReminderProvider] load() cachedCount=${cached.length}');
      _reminders = cached;
      notifyListeners();
      final fresh = await ReminderService.list();
      // ignore: avoid_print
      print('[ReminderProvider] load() freshCount=${fresh.length}');
      _reminders = fresh;
      await ReminderService.saveCache(fresh);
      _initialized = true;
    } catch (e) {
      _error = 'Failed to load reminders: $e';
      // ignore: avoid_print
      print('[ReminderProvider] load() error=$e');
    } finally {
      _loading = false; notifyListeners();
      // ignore: avoid_print
      print('[ReminderProvider] load() done initialized=$_initialized');
    }
  }

  Future<void> sync({bool prune = false}) async {
    // ignore: avoid_print
    print('[ReminderProvider] sync(prune=$prune) start currentCount=${_reminders.length}');
    try {
      await ReminderService.sync(_reminders, pruneMissing: prune);
      final latest = await ReminderService.list();
      // ignore: avoid_print
      print('[ReminderProvider] sync() latestCount=${latest.length}');
      _reminders = latest;
      await ReminderService.saveCache(latest);
      notifyListeners();
    } catch (e) {
      _error = 'Sync error: $e'; notifyListeners();
      // ignore: avoid_print
      print('[ReminderProvider] sync() error=$e');
    }
  }

  Future<void> add(ReminderModel draft) async {
    // ignore: avoid_print
    print('[ReminderProvider] add() title="${draft.title}" time=${draft.hour}:${draft.minute}');
    final created = await ReminderService.create(draft);
    if (created != null) {
      _reminders.add(created);
      await ReminderService.saveCache(_reminders);
      notifyListeners();
      // ignore: avoid_print
      print('[ReminderProvider] add() success id=${created.id}');
    }
  }

  Future<void> update(ReminderModel updated) async {
    if (updated.id == null) return;
    // ignore: avoid_print
    print('[ReminderProvider] update(id=${updated.id})');
    final res = await ReminderService.update(updated.id!, {
      'title': updated.title,
      'body': updated.body,
      'hour': updated.hour,
      'minute': updated.minute,
      'timezone': updated.timezone,
      'active': updated.active,
      'grace_minutes': updated.graceMinutes,
    });
    if (res != null) {
      final idx = _reminders.indexWhere((r) => r.id == res.id);
      if (idx != -1) _reminders[idx] = res; else _reminders.add(res);
      await ReminderService.saveCache(_reminders);
      notifyListeners();
      // ignore: avoid_print
      print('[ReminderProvider] update(id=${res.id}) success');
    }
  }

  Future<void> ack(int id) async {
    // ignore: avoid_print
    print('[ReminderProvider] ack(id=$id)');
    final res = await ReminderService.ack(id);
    if (res != null) {
      final idx = _reminders.indexWhere((r) => r.id == res.id);
      if (idx != -1) _reminders[idx] = res; else _reminders.add(res);
      await ReminderService.saveCache(_reminders);
      notifyListeners();
      // ignore: avoid_print
      print('[ReminderProvider] ack(id=$id) success');
    }
  }

  Future<void> remove(int id) async {
    // ignore: avoid_print
    print('[ReminderProvider] remove(id=$id)');
    final ok = await ReminderService.delete(id);
    if (ok) {
      _reminders.removeWhere((r) => r.id == id);
      await ReminderService.saveCache(_reminders);
      notifyListeners();
      // ignore: avoid_print
      print('[ReminderProvider] remove(id=$id) success');
    }
  }
}
