import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/reminder_api.dart';
import '../widgets/ui_safety.dart';
import '../widgets/reliability_tips_card.dart';

// Server-backed reminders screen.
// Migrated from local ReminderStore to backend ReminderApi (CRUD) + local scheduling for reliability.
// Local scheduling: after each successful fetch we reconcile local plugin schedules.

class RemindersScreen extends StatefulWidget {
  final bool openEditorOnOpen;
  const RemindersScreen({Key? key, this.openEditorOnOpen = false}) : super(key: key);

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  // Rationale (2025-10): When creating a reminder we pass graceMinutes=0 so the backend
  // will consider sending a push immediately at the scheduled time (no 20m grace deferral).
  // Locally we already hedge: scheduleDailyBasic (next occurrence) PLUS a one-off (15s or 20s)
  // when the user creates/edits near or just after the target time, giving quick feedback.
  // This dual path improves reliability in aggressive OEM scenarios while avoiding double
  // daily repeats because one-off IDs use a large offset.
  List<ServerReminder> _reminders = [];
  String _filter = 'all'; // all | on | off
  bool _notifEnabled = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
    _checkPermissions();
    // If navigated from Dashboard's Add button, open editor right away
    if (widget.openEditorOnOpen) {
      // Delay to ensure build context is ready for bottom sheet
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showEditor();
      });
    }
    // Early proactive permission + exact alarm request to reduce first-run misses.
    () async {
      final granted = await NotificationService.ensurePermissions();
      if (!granted && mounted) setState(() => _notifEnabled = false);
      try {
        final canExact = await NotificationService.canScheduleExactNotifications();
        if (!canExact) {
          await NotificationService.requestExactAlarmsPermission();
        }
      } catch (_) {}
    }();
  }

  Future<void> _checkPermissions() async {
    final ok = await NotificationService.areNotificationsEnabled();
    if (mounted) setState(() => _notifEnabled = ok);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await ReminderApi.list();
    list.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    setState(() {
      _reminders = list;
      _loading = false;
    });
    await ReminderApi.scheduleLocally(list); // keep local schedules aligned
  }

  Future<void> _toggle(ServerReminder r, bool enabled) async {
    await ReminderApi.update(r.id, active: enabled);
    await _load();
  }

  Future<void> _delete(ServerReminder r) async {
    await ReminderApi.delete(r.id);
    await _load();
  }

  Future<void> _showEditor({ServerReminder? existing}) async {
    final rootContext = context; // capture before opening sheet
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final bodyCtrl = TextEditingController(text: existing?.body ?? '');
    TimeOfDay time = existing != null
        ? TimeOfDay(hour: existing.hour, minute: existing.minute)
        : TimeOfDay.now();
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null ? 'Add Reminder' : 'Edit Reminder',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Please enter a title'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: bodyCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Body / Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: StatefulBuilder(
                          builder: (context, setTimeState) {
                            return OutlinedButton.icon(
                              icon: const Icon(Icons.access_time),
                              label: Text(time.format(context)),
                              onPressed: () async {
                                final res = await showTimePicker(
                                  context: context,
                                  initialTime: time,
                                );
                                if (res != null) {
                                  time = res;
                                  setTimeState(() {});
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  StatefulBuilder(
                    builder: (context, setModalState) {
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save),
                          label: Text(saving ? 'Saving...' : (existing == null ? 'Save' : 'Update')),
                          onPressed: saving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setModalState(() => saving = true);
                                  final title = titleCtrl.text.trim();
                                  final body = bodyCtrl.text.trim().isEmpty ? title : bodyCtrl.text.trim();
                                  final hasPerm = await NotificationService.ensurePermissions();
                                  if (existing == null) {
                                    final created = await ReminderApi.create(
                                      title: title,
                                      body: body,
                                      hour: time.hour,
                                      minute: time.minute,
                                      graceMinutes: 5,
                                    );
                                    if (created != null) {
                                      // no-op
                                    }
                                  } else {
                                    await ReminderApi.update(
                                      existing.id,
                                      title: title,
                                      body: body,
                                      hour: time.hour,
                                      minute: time.minute,
                                    );
                                  }
                                  if (!mounted) return;
                                  if (Navigator.canPop(ctx)) {
                                    Navigator.pop(ctx);
                                  }
                                  await _load();
                                  try {
                                    if (!hasPerm) {
                                      ScaffoldMessenger.of(rootContext).showSnackBar(
                                        const SnackBar(content: Text('Notification permission not granted — reminders may not fire.')),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(rootContext).showSnackBar(
                                        SnackBar(content: Text(existing == null ? 'Reminder added (server)' : 'Reminder updated')),
                                      );
                                    }
                                  } catch (_) {}
                                },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // (Legacy helper removed: _rescheduleAllReminders was unused after migration.)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Reminders'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'enable_all') {
                for (final r in _reminders.where((e) => !e.active)) {
                  await ReminderApi.update(r.id, active: true);
                }
                await _load();
              } else if (v == 'disable_all') {
                for (final r in _reminders.where((e) => e.active)) {
                  await ReminderApi.update(r.id, active: false);
                }
                await _load();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem<String>(value: 'enable_all', child: Text('Enable all')),
              PopupMenuItem<String>(value: 'disable_all', child: Text('Disable all')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditor(),
            tooltip: 'Add Reminder',
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_notifEnabled)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC80)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_off, color: Colors.deepOrange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Notifications are disabled. Enable permissions to receive reminders.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final granted = await NotificationService.ensurePermissions();
                      if (mounted) setState(() => _notifEnabled = granted);
                    },
                    child: const Text('Enable'),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await NotificationService.scheduleInSeconds(
                          id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
                          seconds: 5,
                          title: 'Reminder Test',
                          body: 'If you receive this, notifications work.',
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Test scheduled in 5s')),
                        );
                      } catch (e) {
                        final msg = e.toString();
                        if (msg.contains('exact_alarms_not_permitted')) {
                          final go = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Allow Exact Alarms'),
                              content: const Text('Your device is blocking exact alarms. Enable "Alarms & reminders" in system settings so reminders fire on time.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open Settings')),
                              ],
                            ),
                          );
                          if (go == true) {
                            await NotificationService.requestExactAlarmsPermission();
                          }
                        } else {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to schedule: $e')),
                          );
                        }
                      }
                    },
                    child: const Text('Test'),
                  ),
                ],
              ),
            ),
          // Guidance card to improve delivery reliability on aggressive ROMs
          const ReliabilityTipsCard(),
          ChipStrip(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _filter == 'all',
                onSelected: (_) => setState(() => _filter = 'all'),
              ),
              ChoiceChip(
                label: const Text('On'),
                selected: _filter == 'on',
                onSelected: (_) => setState(() => _filter = 'on'),
              ),
              ChoiceChip(
                label: const Text('Off'),
                selected: _filter == 'off',
                onSelected: (_) => setState(() => _filter = 'off'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _reminders.isEmpty
                    ? const Center(child: Text('No reminders yet. Tap + to add.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        itemCount: _filteredReminders.length,
                        itemBuilder: (ctx, i) {
                          final r = _filteredReminders[i];
                          final time = TimeOfDay(hour: r.hour, minute: r.minute);
                          final timeLabel = time.format(context);
                          final on = r.active;
                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              onTap: () => _showEditor(existing: r),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: on ? const Color(0xFFE8F5E9) : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: on ? const Color(0xFF22B573) : Colors.grey.shade300),
                                ),
                                child: Center(
                                  child: Text(
                                    _compactTime(timeLabel),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: on ? const Color(0xFF22B573) : Colors.black54,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              // Two-line subtitle: static schedule + computed next fire
                              isThreeLine: true,
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Every day at $timeLabel'),
                                  Builder(builder: (ctx) {
                                    final next = _computeNextFire(r.hour, r.minute);
                                    final now = DateTime.now();
                                    final delta = next.difference(now);
                                    String friendly;
                                    if (delta.inMinutes.abs() < 1) {
                                      friendly = '${delta.inSeconds}s';
                                    } else if (delta.inHours < 1) {
                                      final mins = delta.inMinutes;
                                      final secsR = delta.inSeconds - mins * 60;
                                      friendly = '${mins}m ${secsR}s';
                                    } else if (delta.inHours < 6) {
                                      final hrs = delta.inHours;
                                      final minsR = delta.inMinutes - hrs * 60;
                                      friendly = '${hrs}h ${minsR}m';
                                    } else {
                                      friendly = '${delta.inHours}h';
                                    }
                                    final dayWord = _isToday(next) ? 'Today' : 'Tomorrow';
                                    final hh = next.hour.toString().padLeft(2,'0');
                                    final mm = next.minute.toString().padLeft(2,'0');
                                    return Text('Next: $dayWord $hh:$mm (in $friendly)');
                                  }),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () => _toggle(r, !on),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: on ? const Color(0xFF22B573) : Colors.grey.shade400,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        on ? 'On' : 'Off',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Edit',
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _showEditor(existing: r),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (dCtx) => AlertDialog(
                                          title: const Text('Delete reminder?'),
                                          content: const Text('This will remove the reminder and its schedule.'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                                            ElevatedButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Delete')),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await _delete(r);
                                        }
                                      },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }

  List<ServerReminder> get _filteredReminders {
    if (_filter == 'on') {
      return _reminders.where((r) => r.active).toList();
    } else if (_filter == 'off') {
      return _reminders.where((r) => !r.active).toList();
    }
    return _reminders;
  }

  String _compactTime(String label) {
    // Turn '10:05 PM' into '10:05\nPM' for a compact square display.
    final parts = label.split(' ');
    if (parts.length == 2) return '${parts[0]}\n${parts[1]}';
    return label;
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return now.year == dt.year && now.month == dt.month && now.day == dt.day;
  }

  DateTime _computeNextFire(int hour, int minute) {
    final now = DateTime.now();
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 1));
    return candidate;
  }
}
