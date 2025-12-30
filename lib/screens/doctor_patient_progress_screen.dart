import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/ui_safety.dart';
import 'chat_screen.dart';

class DoctorPatientProgressScreen extends StatefulWidget {
  final String username;
  const DoctorPatientProgressScreen({super.key, required this.username});

  @override
  State<DoctorPatientProgressScreen> createState() => _DoctorPatientProgressScreenState();
}

class _DoctorPatientProgressScreenState extends State<DoctorPatientProgressScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    final res = await ApiService.getPatientInstructionProgress(widget.username, days: 14);
    if (!mounted) return;
    setState(() {
      _data = res;
      _loading = false;
      _error = res == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Progress • ${widget.username}'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error || _data == null
                ? _ErrorState(onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      children: [
                        _HeaderCard(data: _data!),
                        const SizedBox(height: 16),
                        _SummaryPie(data: _data!),
                        const SizedBox(height: 16),
                        _DailyAdherenceList(data: _data!),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            final patient = (_data?['patient'] as Map<String, dynamic>?) ?? const {};
                            final displayName = (patient['name'] ?? '').toString();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  patientUsername: widget.username,
                                  asDoctor: true,
                                  patientDisplayName: displayName,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Chat with Patient'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _HeaderCard({required this.data});
  @override
  Widget build(BuildContext context) {
    final patient = data['patient'] as Map<String, dynamic>? ?? {};
    final treatment = (patient['treatment'] ?? '').toString();
    final subtype = (patient['subtype'] ?? '').toString();
    final procLabel = treatment.isEmpty
        ? ''
        : (subtype.isNotEmpty ? '$treatment ($subtype)' : treatment);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.person_outline, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: SafeText(
                procLabel.isEmpty
                    ? (patient['username'] ?? 'Unknown')
                    : '${patient['username'] ?? 'Unknown'} • $procLabel',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, children: [
            _Chip(label: 'Department: ${patient['department'] ?? '-'}'),
            _Chip(label: 'Doctor: ${patient['doctor'] ?? '-'}'),
          ])
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _SummaryPie extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SummaryPie({required this.data});
  @override
  Widget build(BuildContext context) {
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    final followed = (summary['followed'] ?? 0) as int;
    final unfollowed = (summary['unfollowed'] ?? 0) as int;
    final total = (summary['total'] ?? 0) as int;
    final ratio = total == 0 ? 0.0 : (followed / total);
    final pct = (ratio * 100).toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _DonutChart(followed: followed, unfollowed: unfollowed),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overall Adherence', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text('$pct% followed', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Followed: $followed'),
                  Text('Unfollowed: $unfollowed'),
                  Text('Total: $total'),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _DonutChart extends StatelessWidget {
  final int followed;
  final int unfollowed;
  const _DonutChart({required this.followed, required this.unfollowed});
  @override
  Widget build(BuildContext context) {
    final total = (followed + unfollowed).clamp(1, 999999);
    final fRatio = followed / total;
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: fRatio,
            strokeWidth: 10,
            backgroundColor: Colors.red.withValues(alpha: 0.25),
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
          ),
          Text('${(fRatio * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _DailyAdherenceList extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DailyAdherenceList({required this.data});
  @override
  Widget build(BuildContext context) {
    final daily = (data['daily'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            title: Text('14-Day Daily Adherence'),
            subtitle: Text('Followed vs Unfollowed per day'),
          ),
          const Divider(height: 1),
          if (daily.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No instruction data in this period'),
            )
          else
            ...daily.map((d) {
              final date = d['date'] as String? ?? '';
              final followed = d['followed'] ?? 0;
              final unfollowed = d['unfollowed'] ?? 0;
              final total = d['total'] ?? 0;
              final pct = total == 0 ? 0 : ((followed / (total == 0 ? 1 : total)) * 100).toStringAsFixed(0);
              return Column(
                children: [
                  ListTile(
                    dense: true,
                    title: Text(date, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      'Followed: $followed   Unfollowed: $unfollowed   Total: $total',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text('$pct%'),
                  ),
                  const Divider(height: 1),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
          const SizedBox(height: 12),
          const Text('Failed to load progress'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
