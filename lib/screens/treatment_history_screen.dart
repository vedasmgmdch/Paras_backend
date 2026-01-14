import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TreatmentHistoryScreen extends StatefulWidget {
  const TreatmentHistoryScreen({Key? key}) : super(key: key);

  @override
  State<TreatmentHistoryScreen> createState() => _TreatmentHistoryScreenState();
}

class _TreatmentHistoryScreenState extends State<TreatmentHistoryScreen> {
  // If this screen has instruction checklists, add log saving logic as in other instruction screens.
  late Future<List<dynamic>?> _historyFuture;

  DateTime? _tryParseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    // 1) ISO-8601 (server-friendly)
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;

    // 2) Common user-facing formats: dd/MM/yyyy or dd-MM-yyyy
    final normalized = s.replaceAll('-', '/');
    final parts = normalized.split('/');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        if (y >= 1900 && y <= 3000 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          return DateTime(y, m, d);
        }
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _historyFuture = ApiService.getEpisodeHistory();
  }

  Widget buildTreatmentCard(Map<String, dynamic> t) {
    final treatment = (t['treatment'] ?? '').toString().trim();
    final subtype = (t['treatment_subtype'] ?? t['subtype'] ?? '').toString().trim();
    final dateStr = (t['procedure_date'] ?? '').toString().trim();
    final time = (t['procedure_time'] ?? '').toString().trim();
    // Handle possible variations: true/false, 'true'/'false', 1/0
    final rawLocked = t['locked'];
    final isLocked =
        rawLocked == true || rawLocked == 1 || (rawLocked is String && rawLocked.toString().toLowerCase() == 'true');

    // Defensive fallback UI
    final displayTreatment = treatment.isNotEmpty ? treatment : "No Treatment";
    final displaySubtype = subtype.isNotEmpty ? " ($subtype)" : "";
    final displayDate = dateStr.isNotEmpty ? dateStr : "-";
    final displayTime = time.isNotEmpty ? time : "-";

    // Backend contract: locked=true indicates a past (completed) episode.
    // Use locked for card labeling to stay consistent with grouping below.
    final actuallyCompleted = isLocked;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: ListTile(
        leading: Icon(
          actuallyCompleted ? Icons.check_circle : Icons.timelapse,
          color: actuallyCompleted ? Colors.green : Colors.orange,
          size: 32,
        ),
        title: Text(
          displayTreatment + displaySubtype,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        subtitle: Text("Date: $displayDate\nTime: $displayTime"),
        trailing: actuallyCompleted
            ? const Text("Completed", style: TextStyle(color: Colors.green))
            : const Text("Current", style: TextStyle(color: Colors.orange)),
        onTap: () {
          // Optionally: navigate to treatment instructions or details
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Treatment History"),
        backgroundColor: Colors.blue,
        elevation: 2,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _historyFuture = ApiService.getEpisodeHistory();
              });
            },
          ),
          IconButton(
            tooltip: 'Rotate If Due',
            icon: const Icon(Icons.autorenew),
            onPressed: () async {
              final rotated = await ApiService.rotateIfDue();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(rotated ? 'Rotated: new episode opened' : 'No rotation: not yet due')),
              );
              setState(() {
                _historyFuture = ApiService.getEpisodeHistory();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>?>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final msg = snapshot.error?.toString() ?? 'Unknown error';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Failed to load treatment history.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            );
          }
          final treatments = snapshot.data;
          if (treatments == null || treatments.isEmpty) {
            // Show both section headers, but no cards
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    "Ongoing Treatment",
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    "Completed Treatments",
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            );
          }
          // Separate current vs completed using backend's locked flag.
          bool isLocked(dynamic t) {
            if (t is! Map) return false;
            final lc = t['locked'];
            return lc == true || lc == 1 || (lc is String && lc.toString().toLowerCase() == 'true');
          }

          final completedTreatments = treatments.where((t) => isLocked(t)).toList();
          final ongoingTreatments = treatments.where((t) => !isLocked(t)).toList();

          // Sort both groups by date descending (most recent first)
          int parseDate(dynamic t) {
            if (t is! Map) return 0;
            final ds = (t['procedure_date'] ?? '').toString();
            final dt = _tryParseDate(ds);
            return dt?.millisecondsSinceEpoch ?? 0;
          }

          ongoingTreatments.sort((a, b) => parseDate(b).compareTo(parseDate(a)));
          completedTreatments.sort((a, b) => parseDate(b).compareTo(parseDate(a)));

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  "Ongoing Treatment",
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
              // Show ongoing treatment cards if any
              if (ongoingTreatments.isNotEmpty)
                ...ongoingTreatments.map((t) {
                  final m = (t is Map) ? Map<String, dynamic>.from(t) : <String, dynamic>{};
                  return buildTreatmentCard(m);
                }),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  "Completed Treatments",
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
              // Show completed treatment cards if any
              if (completedTreatments.isNotEmpty)
                ...completedTreatments.map((t) {
                  final m = (t is Map) ? Map<String, dynamic>.from(t) : <String, dynamic>{};
                  return buildTreatmentCard(m);
                }),
            ],
          );
        },
      ),
      // No actions here to avoid confusion; History is read-only with refresh/rotate in the AppBar.
    );
  }
}
