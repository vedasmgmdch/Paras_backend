import 'package:flutter/material.dart';
import 'pure_reminder_model.dart';
import 'pure_reminder_store.dart';
import 'pure_reminder_scheduler.dart';
import '../services/notification_service.dart';

class PureRemindersScreen extends StatefulWidget {
  const PureRemindersScreen({super.key});

  @override
  State<PureRemindersScreen> createState() => _PureRemindersScreenState();
}

class _PureRemindersScreenState extends State<PureRemindersScreen> {
  List<PureReminder> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await PureReminderScheduler.instance.init();
    await _reload();
  }

  Future<void> _reload() async {
    final l = await PureReminderStore.load();
    l.sort((a,b)=> (a.hour*60+a.minute).compareTo(b.hour*60+b.minute));
    if (mounted) setState(() { _list = l; _loading=false; });
  }

  Future<void> _addOrEdit({PureReminder? existing}) async {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    TimeOfDay time = existing==null ? TimeOfDay.now() : TimeOfDay(hour: existing.hour, minute: existing.minute);
    bool saving = false;
    await showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx){
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom+16,left:16,right:16,top:16),
        child: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min,children:[
            Text(existing==null? 'Add Reminder':'Edit Reminder', style: const TextStyle(fontSize:18,fontWeight: FontWeight.bold)),
            const SizedBox(height:12),
            TextFormField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText:'Title',border: OutlineInputBorder()),
              validator: (v)=> v==null||v.trim().isEmpty? 'Enter title':null,
            ),
            const SizedBox(height:12),
            OutlinedButton.icon(onPressed: () async {
              final res = await showTimePicker(context: ctx, initialTime: time);
              if(res!=null){ time=res; setState((){}); }
            }, icon: const Icon(Icons.access_time), label: Text(time.format(ctx))),
            const SizedBox(height:16),
            StatefulBuilder(builder:(c,setSB){
              return SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: saving? null : () async {
                  if(!formKey.currentState!.validate()) return; setSB(()=>saving=true);
                  final id = existing?.id ?? DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
                  final r = PureReminder(id: id, title: titleCtrl.text.trim(), hour: time.hour, minute: time.minute, enabled: true);
                  await PureReminderScheduler.instance.addOrUpdate(r);
                  if(!mounted) return; Navigator.pop(ctx); await _reload();
                },
                child: Text(saving? 'Saving...' : (existing==null? 'Save':'Update')),
              ));
            }),
            const SizedBox(height:8)
          ]),
        ),
      );
    });
  }

  String _pad(int v)=> v.toString().padLeft(2,'0');
  String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${_pad(local.hour)}:${_pad(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final sched = PureReminderScheduler.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Pure Reminders'), actions: [
        IconButton(onPressed: () async { await sched.forceRescheduleAll(); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Force rescheduled'))); }, icon: const Icon(Icons.refresh)),
        IconButton(onPressed: () async { await _reload(); }, icon: const Icon(Icons.sync)),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: ()=>_addOrEdit(), child: const Icon(Icons.add)),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: sched.selfTestPassing ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
            child: Row(children:[
              Icon(sched.selfTestPassing? Icons.check_circle: Icons.warning, color: sched.selfTestPassing? Colors.green: Colors.orange),
              const SizedBox(width:8),
              Expanded(child: Text(sched.selfTestLabel, style: const TextStyle(fontWeight: FontWeight.w600))),
              if(!sched.selfTestPassing) TextButton(onPressed: (){ sched.markSelfTestSuccess(); }, child: const Text('Mark OK'))
            ]),
          ),
          FutureBuilder<bool>(
            future: Future.value(NotificationService.isPreferringAlarmClock()),
            builder: (ctx,snap){
              final pref = snap.data ?? true;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal:12,vertical:6),
                child: Row(children:[
                  const Icon(Icons.alarm,color: Colors.blueGrey,size:18),
                  const SizedBox(width:6),
                  Expanded(child: Text('Prefer AlarmClock mode: $pref', style: const TextStyle(fontSize:13))),
                  Switch(value: pref, onChanged: (v) async { await NotificationService.setPreferAlarmClock(v); setState((){}); }),
                ]),
              );
            },
          ),
          Expanded(
            child: _list.isEmpty
                ? const Center(child: Text('No reminders'))
                : ListView.builder(
                    itemCount: _list.length,
                    itemBuilder: (c, i) {
                      final r = _list[i];
                      final miss = r.missedCount;
                      final last = _formatTime(r.lastFireUtc);
                      final metaLine = 'Daily ${_pad(r.hour)}:${_pad(r.minute)}  •  Last: $last  •  Misses: $miss';
                      final cardColor = miss > 0 ? const Color(0xFFFFF8E1) : null;
                      return Card(
                        color: cardColor,
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          title: Text(r.title),
                          subtitle: Text(metaLine, style: TextStyle(color: miss>0? Colors.orange[800]: Colors.black54, fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: r.enabled,
                                onChanged: (val) async {
                                  await PureReminderScheduler.instance.toggle(r.id, val);
                                  await _reload();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.info_outline),
                                tooltip: 'Schedule debug',
                                onPressed: () async {
                                  // Quick immediate hedge for this reminder (fire in 8s + backup show in 11s)
                                  final hedgeId = r.id + 720000000;
                                  await NotificationService.scheduleInSeconds(
                                    id: hedgeId,
                                    seconds: 8,
                                    title: 'Hedge: ' + r.title,
                                    body: 'Debug hedge for ' + r.title,
                                  );
                                  Future.delayed(const Duration(seconds: 11), () async {
                                    await NotificationService.showNow(
                                      id: hedgeId,
                                      title: 'Hedge Fallback',
                                      body: r.title,
                                    );
                                  });
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hedge scheduled (8s + fallback 11s)')));
                                },
                              ),
                              IconButton(icon: const Icon(Icons.edit), onPressed: () => _addOrEdit(existing: r)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await PureReminderScheduler.instance.delete(r.id);
                                  await _reload();
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12,0,12,12),
            child: Wrap(spacing:8, runSpacing:8, children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final id = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
                  await NotificationService.scheduleInSeconds(id: id, seconds: 10, title: '10s Test', body: 'Pure test');
                  // Hedge fallback show in case device suppresses scheduled one
                  Future.delayed(const Duration(seconds: 13), () async {
                    await NotificationService.showNow(id: id, title: '10s Test Fallback', body: 'Displayed via hedge');
                  });
                },
                icon: const Icon(Icons.flash_on),
                label: const Text('10s Test'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  // Temporarily force preferAlarmClock true for this run
                  await NotificationService.setPreferAlarmClock(true);
                  final id = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
                  await NotificationService.scheduleInSeconds(id: id, seconds: 10, title: '10s AlarmClock Test', body: 'AlarmClock first ordering');
                  Future.delayed(const Duration(seconds: 13), () async {
                    await NotificationService.showNow(id: id, title: '10s AlarmClock Fallback', body: 'Fallback (hedge)');
                  });
                },
                icon: const Icon(Icons.alarm_on),
                label: const Text('10s AlarmClock'),
              ),
              ElevatedButton.icon(onPressed: () async { await PureReminderScheduler.instance.forceRescheduleAll(); }, icon: const Icon(Icons.schedule), label: const Text('Resched All')),
              ElevatedButton.icon(onPressed: () async { await _addOrEdit(); }, icon: const Icon(Icons.add_alarm), label: const Text('Add Quickly')),
              ElevatedButton.icon(
                onPressed: () async {
                  // Purge test/self-test/hedge / 10s AlarmClock notifications
                  final pending = await NotificationService.pending();
                  int removed = 0;
                  for (final p in pending) {
                    final title = (p.title ?? '').toLowerCase();
                    final body = (p.body ?? '').toLowerCase();
                    final id = p.id;
                    final isDailyBase = _list.any((r)=> r.id == id);
                    final isDailyFallback = _list.any((r)=> r.id + 750000000 == id);
                    if (isDailyBase || isDailyFallback) continue; // preserve
                    final isTest = title.contains('10s test') || body.contains('10s test') || title.contains('self-test') || body.contains('self-test') || title.contains('alarmclock test') || body.contains('alarmclock');
                    final inHedgeSpace = _list.any((r)=> r.id + 720000000 == id);
                    final inCatchUpSpace = _list.any((r)=> r.id + 700000000 == id);
                    if (isTest || inHedgeSpace || inCatchUpSpace) {
                      await NotificationService.cancel(id);
                      removed++;
                    }
                  }
                  if (!mounted) return; await _reload();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Purged $removed test notifications')));
                },
                icon: const Icon(Icons.cleaning_services),
                label: const Text('Purge Tests'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final pending = await NotificationService.pending();
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Pending Notifications'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: SingleChildScrollView(
                          child: Text(pending.isEmpty
                              ? 'None'
                              : pending
                                  .map((e) => 'id=${e.id} title="${e.title}" body="${e.body}"')
                                  .join('\n')),
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.list_alt),
                label: const Text('Pending'),
              ),
            ]),
          )
        ],
      ),
    );
  }
}
