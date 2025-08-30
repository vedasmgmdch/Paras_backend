import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../app_state.dart';
import '../services/api_service.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart'; // Import for global routeObserver

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> with RouteAware {
  bool _loading = false;
  String _selectedDateForInstructionsLog = "";

  String get _username =>
      Provider.of<AppState>(context, listen: false).username ?? "default";
  String? get _treatment =>
      Provider.of<AppState>(context, listen: false).treatment;
  String? get _subtype =>
      Provider.of<AppState>(context, listen: false).treatmentSubtype;


  @override
  void initState() {
    super.initState();
    // Always use a valid username
    final username = _username.isNotEmpty ? _username : 'default';
    _initializeProgress(username);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes using the global routeObserver
    final modalRoute = ModalRoute.of(context);
    if (modalRoute is PageRoute) {
      routeObserver.subscribe(this, modalRoute);
    }
  }

  @override
  void dispose() {
    // Unsubscribe from route changes using the global routeObserver
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when coming back to this screen
    final username = _username.isNotEmpty ? _username : 'default';
    _initializeProgress(username);
  }

  Future<void> _initializeProgress(String username) async {
    await _loadLocalProgress();
    await Provider.of<AppState>(context, listen: false)
        .loadInstructionLogs(username: username);
    // Debug print to verify logs are loaded
    final logs = Provider.of<AppState>(context, listen: false).instructionLogs;
    print('Loaded instruction logs for $username: count = \\${logs.length}');
    await fetchProgressEntries();
  }

  Future<void> _loadLocalProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final appState = Provider.of<AppState>(context, listen: false);

    final saved = prefs.getString('progress_feedback_${_username}');
    if (saved != null) {
      try {
        final List<dynamic> list = jsonDecode(saved);
        appState.clearProgressFeedback();
        for (final item in list) {
          appState.addProgressFeedback(
            item['title']?.toString() ?? '',
            item['note']?.toString() ?? '',
            date: item['date']?.toString(),
          );
        }
        setState(() {});
      } catch (_) {}
    }
  }

  Future<void> _saveLocalProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final appState = Provider.of<AppState>(context, listen: false);
    await prefs.setString('progress_feedback_${_username}',
        jsonEncode(appState.progressFeedback));
  }

  Future<void> fetchProgressEntries() async {
    setState(() {
      _loading = true;
    });

    final appState = Provider.of<AppState>(context, listen: false);
    List<dynamic>? response;
    try {
      response = await ApiService.getProgressEntries();
    } catch (e) {
      response = null;
    }

    appState.clearProgressFeedback();

    if (response != null) {
      for (var entry in response) {
        final message = entry["message"]?.toString() ?? "";
        final timestamp = entry["timestamp"]?.toString().split("T")[0] ?? "";
        appState.addProgressFeedback("Entry", message, date: timestamp);
      }
    }

    await _saveLocalProgress();
    setState(() {
      _loading = false;
    });
  }

  Future<void> submitFeedback(String message) async {
    setState(() {
      _loading = true;
    });

    bool success = false;
    try {
      success = await ApiService.submitProgress(message);
    } catch (e) {
      success = false;
    }

    if (success) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.addProgressFeedback(
          "Entry",
          message,
          date: DateTime.now().toIso8601String().split("T")[0]);
      await _saveLocalProgress();
      await fetchProgressEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Feedback submitted successfully"),
              backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Failed to submit feedback"),
              backgroundColor: Colors.red),
        );
      }
    }
    setState(() {
      _loading = false;
    });
  }

  List<dynamic> _filterInstructionLogs(
      List<dynamic> logs, {
        required String username,
        String? treatment,
        String? subtype,
      }) {
    return logs.where((log) {
      if ((log['username'] ?? log['user'] ?? "default") != username) return false;
      if (treatment != null && treatment.isNotEmpty) {
        if ((log['treatment'] ?? "") != treatment) return false;
      }
      if (subtype != null && subtype.isNotEmpty) {
        if ((log['subtype'] ?? "") != subtype) return false;
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _getLatestInstructionLogs(List<dynamic> instructionLogs) {
    final Map<String, Map<String, dynamic>> latestLogs = {};
    for (var log in instructionLogs) {
      final date = log['date']?.toString() ?? '';
      final type = log['type']?.toString() ?? '';
      final instruction = log['instruction']?.toString() ?? log['note']?.toString() ?? '';
      final key = '$date|$type|$instruction';
      latestLogs[key] = log;
    }
    return latestLogs.values.toList();
  }

  Map<String, int> _getInstructionStats(List<dynamic> instructionLogs) {
    int generalFollowed = 0;
    int specificFollowed = 0;
    int notFollowedGeneral = 0;
    int notFollowedSpecific = 0;
    for (var log in _getLatestInstructionLogs(instructionLogs)) {
      final type = log['type']?.toString().toLowerCase() ?? '';
      final followed =
          log['followed'] == true || log['followed']?.toString() == 'true';
      if (type == 'general') {
        if (followed) {
          generalFollowed++;
        } else {
          notFollowedGeneral++;
        }
      } else if (type == 'specific') {
        if (followed) {
          specificFollowed++;
        } else {
          notFollowedSpecific++;
        }
      }
    }
    return {
      'GeneralFollowed': generalFollowed,
      'SpecificFollowed': specificFollowed,
      'GeneralNotFollowed': notFollowedGeneral,
      'SpecificNotFollowed': notFollowedSpecific,
    };
  }

  Widget _buildInstructionsFollowedBox(List<dynamic> instructionLogs) {
    final appState = Provider.of<AppState>(context, listen: false);
    final procedureDate = appState.procedureDate;
    if (procedureDate == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Text("Please set up your treatment and procedure date first."),
      );
    }

    final filteredLogs = _filterInstructionLogs(
      instructionLogs,
      username: _username,
      treatment: _treatment,
      subtype: _subtype,
    );
    final latestLogs = _getLatestInstructionLogs(filteredLogs)
        .where((log) => log['followed'] == true || log['followed']?.toString() == 'true')
        .toList();

    final today = DateTime.now();
    final int days = today.difference(DateTime(procedureDate.year, procedureDate.month, procedureDate.day)).inDays + 1;
    final List<String> allDates = List.generate(days, (i) {
      final d = procedureDate.add(Duration(days: i));
      return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    });

    if (_selectedDateForInstructionsLog.isEmpty && allDates.isNotEmpty) {
      _selectedDateForInstructionsLog = allDates.contains(_getTodayDate())
          ? _getTodayDate()
          : allDates.last;
    }

    final logsForSelectedDate = latestLogs
        .where((log) => log['date']?.toString() == _selectedDateForInstructionsLog)
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    fit: FlexFit.tight,
                    child: Text(
                      "Instructions Log",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blueGrey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (allDates.length > 1) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.5,
                        minWidth: 10,
                      ),
                      child: DropdownButton<String>(
                        value: _selectedDateForInstructionsLog,
                        isDense: true,
                        isExpanded: true,
                        items: allDates
                            .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(
                              _formatDisplayDate(d),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16),
                            )))
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedDateForInstructionsLog = val ?? "";
                          });
                        },
                        style: const TextStyle(fontSize: 16, color: Colors.black87),
                        underline: Container(height: 1, color: Colors.blueGrey[100]),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (logsForSelectedDate.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.yellow[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "No instructions followed for this day.",
                style: TextStyle(color: Colors.black54, fontSize: 15),
              ),
            )
          else
            ...logsForSelectedDate.map((log) {
              final date = log['date']?.toString() ?? '';
              final instruction = log['instruction']?.toString() ?? log['note']?.toString() ?? '';
              final type = log['type']?.toString().toLowerCase();
              final color = type == "general"
                  ? Colors.green[100]
                  : type == "specific"
                  ? Colors.red[100]
                  : Colors.blue[100];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        instruction,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _formatDisplayDate(date),
                        style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  String _getTodayDate() {
    final now = DateTime.now();
    return "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  String _formatDisplayDate(String dateStr) {
    // Converts "2025-08-04" to "04-08-2025"
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        return "${parts[2]}-${parts[1]}-${parts[0]}";
      }
      return dateStr;
    } catch (e) {
      return dateStr;
    }
  }

  Widget _buildPieChart(List<dynamic> instructionLogs) {
    final filteredLogs = _filterInstructionLogs(
      instructionLogs,
      username: _username,
      treatment: _treatment,
      subtype: _subtype,
    );

    final stats = _getInstructionStats(filteredLogs);

    final generalCount = stats['GeneralFollowed'] ?? 0;
    final specificCount = stats['SpecificFollowed'] ?? 0;
    final notFollowedGeneralCount = stats['GeneralNotFollowed'] ?? 0;
    final notFollowedSpecificCount = stats['SpecificNotFollowed'] ?? 0;

    final total = generalCount + specificCount + notFollowedGeneralCount + notFollowedSpecificCount;
    if (total == 0) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16.0),
        child: Text(
            "No instruction logs available for selected treatment/subtype.",
            style: TextStyle(color: Colors.black54)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        children: [
          const Text(
            "Instructions Followed",
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueGrey),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(
                    value: generalCount.toDouble(),
                    color: Colors.green,
                    title: generalCount > 0 ? 'General\n$generalCount' : '',
                    radius: 55,
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                  PieChartSectionData(
                    value: specificCount.toDouble(),
                    color: Colors.red,
                    title: specificCount > 0 ? 'Specific\n$specificCount' : '',
                    radius: 55,
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                  PieChartSectionData(
                    value: (notFollowedGeneralCount + notFollowedSpecificCount).toDouble(),
                    color: Colors.blue,
                    title: (notFollowedGeneralCount + notFollowedSpecificCount) > 0
                        ? 'Not\n${notFollowedGeneralCount + notFollowedSpecificCount}'
                        : '',
                    radius: 55,
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ],
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: [
              _buildPieLegend(Colors.green, "General Followed"),
              _buildPieLegend(Colors.red, "Specific Followed"),
              _buildPieLegend(Colors.blue, "Not Followed"),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  "$generalCount General, $specificCount Specific, ${notFollowedGeneralCount + notFollowedSpecificCount} Not followed",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPieLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final procedureDate = appState.procedureDate ?? DateTime.now();
    final today = DateTime.now();
    final int daysSinceProcedure = today
        .difference(DateTime(procedureDate.year, procedureDate.month,
        procedureDate.day))
        .inDays +
        1;

    final int totalRecoveryDays = 14;
    final int dayOfRecovery = daysSinceProcedure;
    final int progressPercent =
    ((dayOfRecovery / totalRecoveryDays) * 100).clamp(0, 100).toInt();

    final entries = appState.progressFeedback;

    return Scaffold(
      backgroundColor: Colors.white,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 20.0, horizontal: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Recovery Dashboard',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const Icon(Icons.favorite_border,
                                color: Colors.white),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Day $dayOfRecovery of recovery',
                          style: const TextStyle(
                              fontSize: 16, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value:
                          (dayOfRecovery / totalRecoveryDays).clamp(0, 1),
                          backgroundColor: Colors.white24,
                          color: Colors.white,
                          minHeight: 5,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Recovery Progress: $progressPercent%',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(22),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Recovery Progress',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        SizedBox(height: 6),
                        Text(
                          "Monitor your recovery day by day",
                          style:
                          TextStyle(fontSize: 15, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.only(bottom: 28),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10.0),
                            child: Text(
                              'Summary',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20),
                            ),
                          ),
                          _buildSummaryRow(
                              'Days since procedure',
                              '$daysSinceProcedure',
                              'days',
                              const Color(0xFFE8F0FE),
                              const Color(0xFF2196F3)),
                          const SizedBox(height: 10),
                          _buildSummaryRow(
                              'Expected healing',
                              '7-14',
                              'days',
                              const Color(0xFFF2FBF3),
                              const Color(0xFF22B573)),
                        ],
                      ),
                    ),
                  ),
                  _buildPieChart(appState.instructionLogs),
                  _buildInstructionsFollowedBox(appState.instructionLogs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding:
                      const EdgeInsets.only(bottom: 8.0, left: 4.0),
                      child: Text(
                        "Your Progress Entries",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.blueGrey[900]),
                      ),
                    ),
                  ),
                  if (entries.isEmpty)
                    Container(
                      padding:
                      const EdgeInsets.symmetric(vertical: 36.0),
                      child: const Text(
                        "No progress entries yet.\nAdd your first entry below!",
                        style:
                        TextStyle(color: Colors.black54, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ...entries.map((entry) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blueGrey[100]!),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry["title"] ?? "",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                const SizedBox(height: 4),
                                Text(entry["note"] ?? "",
                                    style: const TextStyle(
                                        color: Colors.black87, fontSize: 15)),
                              ],
                            ),
                          ),
                          Text(entry["date"] ?? "",
                              style: const TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ],
                      ),
                    )),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding:
                        const EdgeInsets.symmetric(vertical: 15),
                      ),
                      icon: const Icon(Icons.feedback),
                      label: const Text(
                        "Patient's Feedback",
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      onPressed:
                      _loading ? null : () => _showFeedbackDialog(),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, String unit, Color bgColor,
      Color textColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.black87, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                  ),
                ),
              ],
            ),
          ),
          Text(unit, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  void _showFeedbackDialog() {
    final feedbackController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Patient's Feedback"),
          content: TextField(
            controller: feedbackController,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: "Enter patient's feedback on your progress...",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final message = feedbackController.text.trim();
                if (message.isNotEmpty) {
                  Navigator.of(context).pop();
                  submitFeedback(message);
                }
              },
              child: const Text("Submit"),
            ),
          ],
        );
      },
    );
  }
}