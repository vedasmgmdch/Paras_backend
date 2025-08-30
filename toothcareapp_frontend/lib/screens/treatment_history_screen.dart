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
    final completed = t['procedure_completed'] == true;

    // Defensive fallback UI
    final displayTreatment = treatment.isNotEmpty ? treatment : "No Treatment";
    final displaySubtype = subtype.isNotEmpty ? " ($subtype)" : "";
    final displayDate = dateStr.isNotEmpty ? dateStr : "-";
    final displayTime = time.isNotEmpty ? time : "-";

    // Parse procedure_date
    DateTime? procedureDate;
    if (dateStr.isNotEmpty) {
      procedureDate = DateTime.tryParse(dateStr);
    }

    // Calculate if healing period is over (14 days)
    bool isHealingOver = false;
    if (procedureDate != null) {
      final healingEnd = procedureDate.add(const Duration(days: 14));
      if (DateTime.now().isAfter(healingEnd)) {
        isHealingOver = true;
      }
    }

    final actuallyCompleted = completed || isHealingOver;

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
            : const Text("Ongoing", style: TextStyle(color: Colors.orange)),
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
      ),
      body: FutureBuilder<List<dynamic>?>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Failed to load treatment history.'));
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
          // Separate ongoing and completed treatments for sectioned display
          final ongoingTreatments = treatments.where((t) =>
          (t['procedure_completed'] == false || t['procedure_completed'] == null)
          ).toList();
          final completedTreatments = treatments.where((t) =>
          t['procedure_completed'] == true
          ).toList();

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
                ...ongoingTreatments.map((t) => buildTreatmentCard(t as Map<String, dynamic>)),
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
                ...completedTreatments.map((t) => buildTreatmentCard(t as Map<String, dynamic>)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).pop();
        },
        icon: const Icon(Icons.add),
        label: const Text("Start New Treatment"),
        backgroundColor: Colors.blue,
      ),
    );
  }
}