import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import '../widgets/no_animation_page_route.dart';
import '../theme/semantic_colors.dart';
import '../instruction_catalog.dart';
import '../utils/instruction_log_materializer.dart';

// This doctor view is a read-only mirror of the patient's ProgressScreen, showing:
// - Recovery Dashboard (day of recovery + progress bar)
// - Recovery Progress heading card (same as patient)
// - Summary (days since procedure & expected healing window)
// - Pie chart of general/specific followed and not followed
// - Instructions Log with identical date dropdown behavior
// - Patient Progress Entries (feedback entries submitted by patient)
// Differences: no ability to submit feedback or modify logs; purely observational.

class _ProgressStatus {
  final String label;
  final String sublabel;
  final double score;
  final Color color;

  const _ProgressStatus({required this.label, required this.sublabel, required this.score, required this.color});
}

class DoctorPatientFullProgressScreen extends StatefulWidget {
  final String username;
  final String? initialProcedureDate; // YYYY-MM-DD
  final String? initialTreatment;
  final String? initialSubtype;

  const DoctorPatientFullProgressScreen({
    super.key,
    required this.username,
    this.initialProcedureDate,
    this.initialTreatment,
    this.initialSubtype,
  });

  @override
  State<DoctorPatientFullProgressScreen> createState() => _DoctorPatientFullProgressScreenState();
}

class _DoctorPatientFullProgressScreenState extends State<DoctorPatientFullProgressScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _instructionStatus = [];
  List<Map<String, dynamic>> _progressEntries = [];
  String _selectedDateForInstructionsLog = '';
  String? _debugStatusMessage; // diagnostics when empty
  DateTime? _lastRefreshed;
  Map<String, dynamic>? _patientInfo; // view meta (may be for selected episode)
  Map<String, dynamic>? _chatInfo; // current patient meta (for chat lock/banner)
  List<Map<String, dynamic>> _episodes = [];
  bool _lastUsedSubtypeFallback = false; // track if fallback applied for current selection (for rebuild messages)
  // NOTE: This screen aims for strict parity with the patient ProgressScreen:
  // - Uses the same expected instruction catalog
  // - Uses stable IDs + canonicalization to dedupe logs reliably
  // - Materializes missing expected items as synthetic "Not Followed" entries
  // - Dates list derives from procedure_date (if missing -> message)

  // Derived recovery stats
  int? _daysSinceProcedure;
  int? _dayOfRecovery; // patient screen: days since + 1
  int _totalRecoveryDays = 14; // same constant used on patient screen
  int? _progressPercent; // computed from dayOfRecovery / totalRecoveryDays

  _ProgressStatus _computeProgressStatus() {
    final procDateStr = (_patientInfo?['procedure_date'] ?? '').toString();
    if (procDateStr.isEmpty) {
      return const _ProgressStatus(
        label: 'No data yet',
        sublabel: 'Set procedure date to compute progress status',
        score: 0,
        color: Colors.blueGrey,
      );
    }

    DateTime from;
    try {
      final d = DateTime.parse(procDateStr);
      from = DateTime(d.year, d.month, d.day);
    } catch (_) {
      return const _ProgressStatus(
        label: 'No data yet',
        sublabel: 'Set procedure date to compute progress status',
        score: 0,
        color: Colors.blueGrey,
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final filtered = _instructionStatus.where((raw) {
      final dateStr = (raw['date'] ?? '').toString();
      if (dateStr.isEmpty) return false;
      DateTime d;
      try {
        d = DateTime.parse(dateStr);
      } catch (_) {
        return false;
      }
      final dateOnly = DateTime(d.year, d.month, d.day);
      if (dateOnly.isBefore(from) || dateOnly.isAfter(today)) return false;
      return _isAllowedForPfdFixed(raw);
    }).toList();

    final latest = InstructionLogMaterializer.dedupeLatestByDateTypeInstruction(
      filtered.map((e) => Map<String, dynamic>.from(e)).toList(),
    );
    if (latest.isEmpty) {
      return const _ProgressStatus(
        label: 'No data yet',
        sublabel: 'Follow instructions to build progress status',
        score: 0,
        color: Colors.blueGrey,
      );
    }

    int total = 0;
    int followed = 0;
    for (final raw in latest) {
      total++;
      final isFollowed = raw['followed'] == true || raw['followed']?.toString() == 'true';
      if (isFollowed) followed++;
    }

    if (total == 0) {
      return const _ProgressStatus(
        label: 'No data yet',
        sublabel: 'Follow instructions to build progress status',
        score: 0,
        color: Colors.blueGrey,
      );
    }

    final ratio = (followed / total).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();
    if (ratio >= 0.80) {
      return _ProgressStatus(
        label: 'Good',
        sublabel: 'Since procedure • $pct% instructions followed',
        score: ratio,
        color: const Color(0xFF22B573),
      );
    }
    if (ratio >= 0.50) {
      return _ProgressStatus(
        label: 'Alright',
        sublabel: 'Since procedure • $pct% instructions followed',
        score: ratio,
        color: const Color(0xFF2196F3),
      );
    }
    return _ProgressStatus(
      label: 'Needs attention',
      sublabel: 'Since procedure • $pct% instructions followed',
      score: ratio,
      color: Colors.orange,
    );
  }

  Widget _buildProgressStatusBar() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _computeProgressStatus();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? cs.outlineVariant : Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Progress Status',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(fontWeight: FontWeight.bold, color: status.color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: status.score.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: isDark ? cs.onSurfaceVariant.withValues(alpha: 0.18) : Colors.blueGrey.shade50,
              color: status.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            status.sublabel,
            style: TextStyle(
              color: isDark ? cs.onSurfaceVariant : Colors.black54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _debugStatusMessage = null;
    });
    try {
      // Legacy behavior: skip auth requirement, attempt patient info; if not available just continue.
      final info = await ApiService.doctorGetPatientInfo(widget.username); // may be null if backend now requires auth
      if (!mounted) return;
      _chatInfo = info;

      // Build view metadata: base patient info.
      final view = <String, dynamic>{...info ?? const <String, dynamic>{}};

      // If opened from a specific dashboard entry, load the matching historical entry
      // by procedure_date (and treatment/subtype when available).
      final initialProcDate = (widget.initialProcedureDate ?? '').toString().trim();
      final initialTreatment = (widget.initialTreatment ?? '').toString().trim();
      final initialSubtype = (widget.initialSubtype ?? '').toString().trim();
      if (initialProcDate.isNotEmpty) {
        final episodes = await ApiService.doctorGetPatientEpisodes(widget.username);
        if (!mounted) return;
        _episodes = episodes;

        Map<String, dynamic>? selectedEp;
        for (final e in _episodes) {
          final pd = (e['procedure_date'] ?? '').toString().trim();
          if (pd != initialProcDate) continue;
          if (initialTreatment.isNotEmpty) {
            final t = (e['treatment'] ?? '').toString().trim();
            if (t != initialTreatment) continue;
          }
          if (initialSubtype.isNotEmpty) {
            final st = (e['subtype'] ?? '').toString().trim();
            if (st != initialSubtype) continue;
          }
          selectedEp = e;
          break;
        }

        if (selectedEp != null) {
          view['treatment'] = selectedEp['treatment'];
          view['subtype'] = selectedEp['subtype'];
          view['procedure_date'] = selectedEp['procedure_date'];
          view['procedure_time'] = selectedEp['procedure_time'];
          view['procedure_completed'] = selectedEp['procedure_completed'];
          view['locked'] = selectedEp['locked'];
        }
      }

      _patientInfo = view.isEmpty ? null : view;

      final treatment = (_patientInfo?['treatment'] ?? '').toString();
      final subtype = (_patientInfo?['subtype'] ?? '').toString();
      // Use ENHANCED endpoint so missing-day rows become explicit "Not Followed" placeholders.
      int dynamicDays = 30;
      String? dateFrom;
      String? dateTo;
      final procStr = (_patientInfo?['procedure_date'] ?? '').toString();
      if (procStr.isNotEmpty) {
        try {
          final pd = DateTime.parse(procStr);
          final from = DateTime(pd.year, pd.month, pd.day);
          final today = DateTime.now();
          final todayOnly = DateTime(today.year, today.month, today.day);
          final maxTo = from.add(const Duration(days: 13));
          final effectiveTo = maxTo.isBefore(todayOnly) ? maxTo : todayOnly;
          dateFrom = _formatYMD(from);
          dateTo = _formatYMD(effectiveTo);
          final diff = effectiveTo.difference(from).inDays + 1;
          dynamicDays = diff.clamp(1, 14);
        } catch (_) {}
      }
      Map<String, dynamic>? enhanced = await ApiService.doctorGetPatientInstructionStatusEnhanced(
        widget.username,
        days: dynamicDays,
        treatment: treatment.trim().isEmpty ? null : treatment,
        subtype: subtype.trim().isEmpty ? null : subtype,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      if (!mounted) return;
      List<Map<String, dynamic>> status = [];
      if (enhanced != null && enhanced['days'] is List) {
        final days = (enhanced['days'] as List).cast<Map<String, dynamic>>();
        int rowCount = 0;
        for (final d in days) {
          final instr =
              (d['instructions'] is List) ? (d['instructions'] as List).cast<Map<String, dynamic>>() : const [];
          rowCount += instr.length;
          for (final r in instr) {
            String rawDate = (r['date'] is String ? r['date'] : r['date']?.toString()) ?? '';
            if (rawDate.contains('T')) rawDate = rawDate.split('T').first;
            final parts = rawDate.split('-');
            if (parts.length >= 3) {
              rawDate =
                  '${parts[0].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[2].substring(0, 2).padLeft(2, '0')}';
            }
            status.add({
              ...r,
              'type': _normType((r['group'] ?? r['type'] ?? '').toString()),
              'instruction': InstructionLogMaterializer.canonicalInstructionText(
                (r['instruction_text'] ?? r['instruction'] ?? r['note'] ?? '').toString(),
              ),
              'followed': (r['followed'] == true || r['followed']?.toString() == 'true'),
              'date': rawDate,
              'instruction_index': InstructionLogMaterializer.stableInstructionIndex(
                _normType((r['group'] ?? r['type'] ?? '').toString()),
                (r['instruction_text'] ?? r['instruction'] ?? r['note'] ?? '').toString(),
              ),
              'synthetic': (r['synthetic'] == true || r['synthetic']?.toString() == 'true'),
            });
          }
        }
        debugPrint('[DoctorProgress] enhanced endpoint rows=$rowCount');
      } else {
        // Fallback to legacy basic endpoint
        final rawStatus = await ApiService.doctorGetPatientInstructionStatus(widget.username);
        if (!mounted) return;
        debugPrint('[DoctorProgress] legacy status rows=${rawStatus.length}');
        status = rawStatus.map((r) {
          String rawDate = (r['date'] ?? '').toString();
          if (rawDate.contains('T')) rawDate = rawDate.split('T').first;
          final parts = rawDate.split('-');
          if (parts.length >= 3) {
            rawDate =
                '${parts[0].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[2].substring(0, 2).padLeft(2, '0')}';
          }
          return {
            ...r,
            'type': _normType((r['group'] ?? r['type'] ?? '').toString()),
            'instruction': InstructionLogMaterializer.canonicalInstructionText(
              (r['instruction_text'] ?? r['instruction'] ?? r['note'] ?? '').toString(),
            ),
            'followed': (r['followed'] == true || r['followed']?.toString() == 'true'),
            'date': rawDate,
            'instruction_index': InstructionLogMaterializer.stableInstructionIndex(
              _normType((r['group'] ?? r['type'] ?? '').toString()),
              (r['instruction_text'] ?? r['instruction'] ?? r['note'] ?? '').toString(),
            ),
            'synthetic': (r['synthetic'] == true || r['synthetic']?.toString() == 'true'),
          };
        }).toList();
      }
      _instructionStatus = status; // raw set (includes followed & not followed)
      if (_instructionStatus.isEmpty) {
        _debugStatusMessage = 'No instruction-status rows returned.';
      }
      _progressEntries = await ApiService.doctorGetPatientProgressEntries(widget.username);
      if (!mounted) return;
      _computeRecoveryStats();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lastRefreshed = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _debugStatusMessage = 'Error loading data: $e';
        _lastRefreshed = DateTime.now();
      });
    }
  }

  void _computeRecoveryStats() {
    final procDateStr = _patientInfo != null ? _patientInfo!['procedure_date'] as String? : null;
    if (procDateStr == null || procDateStr.isEmpty) {
      _daysSinceProcedure = null;
      _dayOfRecovery = null;
      _progressPercent = null;
      return;
    }
    try {
      final d = DateTime.parse(procDateStr);
      final now = DateTime.now();
      _daysSinceProcedure = now.difference(DateTime(d.year, d.month, d.day)).inDays + 1; // patient adds +1 for day-of
      _dayOfRecovery = _daysSinceProcedure; // same meaning in patient screen
      _progressPercent = ((_dayOfRecovery! / _totalRecoveryDays) * 100).clamp(0, 100).toInt();
    } catch (_) {
      _daysSinceProcedure = null;
      _dayOfRecovery = null;
      _progressPercent = null;
    }
  }

  // --- Instruction log helpers (shared with patient screen) ---
  String _normType(String s) => InstructionLogMaterializer.canonicalGroup(s);

  bool _isAllowedForPfdFixed(Map<String, dynamic> log) {
    final treatment = (_patientInfo?['treatment'] ?? '').toString();
    final subtype = (_patientInfo?['subtype'] ?? '').toString();
    if (!(treatment == 'Prosthesis Fitted' && subtype == 'Fixed Dentures')) return true;

    final type = _normType((log['type'] ?? '').toString());
    final instruction = (log['instruction'] ?? log['note'] ?? '').toString();
    final n = InstructionLogMaterializer.normalizedInstructionKeyText(instruction);

    const pfdGeneralEn = [
      'Whenever local anesthesia is used, avoid chewing on your teeth until the numbness has worn off.',
      'Proper brushing, flossing, and regular cleanings are necessary to maintain the restoration.',
      'Pay special attention to your gumline.',
      'Avoid very hot or hard foods.',
    ];
    const pfdGeneralMr = [
      'स्थानिक भूल दिल्यानंतर, सुन्नपणा जाईपर्यंत दातांवर चावणे टाळा.',
      'पुनर्स्थापना टिकवण्यासाठी योग्य ब्रशिंग, फ्लॉसिंग आणि नियमित स्वच्छता आवश्यक आहे.',
      'तुमच्या हिरड्यांच्या सीमेकडे विशेष लक्ष द्या.',
      'अतिशय गरम किंवा कडक अन्न टाळा.',
    ];
    const pfdSpecificEn = [
      'If your bite feels high or uncomfortable, contact your dentist for an adjustment.',
      'If the restoration feels loose or comes off, keep it safe and contact your dentist. Do not try to glue it yourself.',
      'Clean carefully around the restoration and gumline; use floss/interdental aids as advised by your dentist.',
      'If you notice persistent pain, swelling, or bleeding, contact your dentist.',
    ];
    const pfdSpecificMr = [
      'चावताना दात उंच वाटत असतील किंवा अस्वस्थ वाटत असेल, समायोजनासाठी दंतवैद्याशी संपर्क साधा.',
      'पुनर्स्थापना सैल वाटली किंवा निघाली तर ती सुरक्षित ठेवा आणि दंतवैद्याशी संपर्क साधा. स्वतः चिकटवण्याचा प्रयत्न करू नका.',
      'पुनर्स्थापना व हिरड्यांच्या सीमेजवळ नीट स्वच्छता ठेवा; दंतवैद्याने सांगितल्याप्रमाणे फ्लॉस/इंटरडेंटल साधने वापरा.',
      'दुखणे, सूज किंवा रक्तस्राव सतत राहिल्यास दंतवैद्याशी संपर्क साधा.',
    ];

    final allowedGeneral =
        {...pfdGeneralEn, ...pfdGeneralMr}.map(InstructionLogMaterializer.normalizedInstructionKeyText).toSet();
    final allowedSpecific =
        {...pfdSpecificEn, ...pfdSpecificMr}.map(InstructionLogMaterializer.normalizedInstructionKeyText).toSet();

    if (type == 'general') return allowedGeneral.contains(n);
    if (type == 'specific') return allowedSpecific.contains(n);
    return true;
  }

  String _formatDisplayDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) return '${parts[2]}-${parts[1]}-${parts[0]}';
      return dateStr;
    } catch (_) {
      return dateStr;
    }
  }

  String _todayStr() {
    final now = DateTime.now();
    return _formatYMD(now);
  }

  String _formatYMD(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Patient screen only derives date list from procedure date (no synthetic expansion if missing)
    List<String> allDates = [];
    bool missingProcedureDate = false;
    if (_patientInfo != null) {
      final pd = (_patientInfo!['procedure_date'] ?? '').toString();
      if (pd.isNotEmpty) {
        try {
          final base = DateTime.parse(pd);
          final today = DateTime.now();
          final totalDays = today.difference(DateTime(base.year, base.month, base.day)).inDays + 1;
          final cappedDays = totalDays.clamp(1, 14);
          allDates = List.generate(cappedDays, (i) {
            final dt = DateTime(base.year, base.month, base.day).add(Duration(days: i));
            return _formatYMD(dt);
          });
        } catch (_) {
          missingProcedureDate = true;
        }
      } else {
        missingProcedureDate = true;
      }
    } else {
      missingProcedureDate = true;
    }
    if (_selectedDateForInstructionsLog.isEmpty && allDates.isNotEmpty) {
      _selectedDateForInstructionsLog = allDates.contains(_todayStr()) ? _todayStr() : allDates.last;
    }
    // Ensure selection remains valid if underlying list changed
    if (_selectedDateForInstructionsLog.isNotEmpty && !allDates.contains(_selectedDateForInstructionsLog)) {
      _selectedDateForInstructionsLog =
          allDates.isNotEmpty ? (allDates.contains(_todayStr()) ? _todayStr() : allDates.last) : '';
    }

    final treatment = (_patientInfo?['treatment'] ?? '').toString();
    final subtype = (_patientInfo?['subtype'] ?? _patientInfo?['treatment_subtype'] ?? '').toString();
    final expected = InstructionCatalog.getExpected(treatment: treatment, subtype: subtype);
    final generalCatalog =
        (expected?['general'] ?? const []).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    final specificCatalog =
        (expected?['specific'] ?? const []).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();

    final filteredAllowedLogs =
        _instructionStatus.where(_isAllowedForPfdFixed).map((e) => Map<String, dynamic>.from(e)).toList();

    // Parity with patient ProgressScreen: materialize expected instructions for the day.
    final logsForSelectedDate = (_selectedDateForInstructionsLog.isEmpty)
        ? <Map<String, dynamic>>[]
        : InstructionLogMaterializer.materializeForSelectedDate(
            filteredLogs: filteredAllowedLogs,
            selectedDate: _selectedDateForInstructionsLog,
            generalCatalog: generalCatalog,
            specificCatalog: specificCatalog,
          );
    bool usedSubtypeFallbackLocal = false;
    // Subtype fallback no longer needs latest collapse; just reuse matches (already done above).
    _lastUsedSubtypeFallback = usedSubtypeFallbackLocal;
    final stats = InstructionLogMaterializer.computeStatsAcrossDates(
      filteredLogs: filteredAllowedLogs,
      allDates: allDates,
      generalCatalog: generalCatalog,
      specificCatalog: specificCatalog,
    );
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(() {
          final treatment = (_patientInfo?['treatment'] ?? '').toString();
          final subtype = (_patientInfo?['subtype'] ?? '').toString();
          final proc = treatment.isEmpty ? '' : (subtype.isNotEmpty ? ' • $treatment ($subtype)' : ' • $treatment');
          return 'Patient Progress • ${widget.username}$proc';
        }()),
        actions: [IconButton(onPressed: _loading ? null : _loadAll, icon: const Icon(Icons.refresh))],
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadAll,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_debugStatusMessage != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? cs.surfaceContainerLow : Colors.amber[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: (isDark ? cs.primary : Colors.amber.shade300)),
                            ),
                            child: Text(
                              _debugStatusMessage!,
                              style: TextStyle(fontSize: 13, color: cs.onSurface),
                            ),
                          ),
                        if (_lastRefreshed != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              'Last refreshed: ' + _lastRefreshed!.toIso8601String().substring(11, 19),
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ),
                        _treatmentLabelSection(),
                        _recoveryDashboardSection(),
                        _recoveryProgressHeadingCard(),
                        _summaryCard(),
                        _pieChartSection(stats),
                        _instructionsLogSection(
                          allDates,
                          logsForSelectedDate,
                          missingProcedureDate: missingProcedureDate,
                        ),
                        _progressEntriesSection(),
                        _buildProgressStatusBar(),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? cs.primary : Colors.deepPurple,
                              foregroundColor: isDark ? cs.onPrimary : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                            ),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text(
                              'Chat with Patient',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            onPressed: _loading
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      NoAnimationPageRoute(
                                        builder: (_) => ChatScreen(
                                          patientUsername: widget.username,
                                          asDoctor: true,
                                          patientDisplayName:
                                              (_chatInfo?['name'] ?? _patientInfo?['name'] ?? '').toString(),
                                          readOnly: (_chatInfo?['procedure_completed'] == true),
                                          bannerText: (_chatInfo?['procedure_completed'] == true)
                                              ? 'Treatment completed'
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
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

  // --- UI subsections mirroring patient screen ---
  Widget _treatmentLabelSection() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final treatment = (_patientInfo?['treatment'] ?? '').toString().trim();
    final subtype = (_patientInfo?['subtype'] ?? _patientInfo?['treatment_subtype'] ?? '').toString().trim();
    final procDate = (_patientInfo?['procedure_date'] ?? '').toString().trim();

    final label = treatment.isEmpty
        ? 'Treatment: -'
        : (subtype.isNotEmpty ? 'Treatment: $treatment ($subtype)' : 'Treatment: $treatment');
    final datePart = procDate.isEmpty ? '' : ' • $procDate';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? cs.outlineVariant : Colors.blueGrey.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.medical_information, color: isDark ? cs.primary : Colors.black54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$label$datePart',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? cs.onSurface : Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recoveryDashboardSection() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dayOfRecovery = _dayOfRecovery ?? 0;
    final progressPercent = _progressPercent ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : const Color(0xFF2196F3),
        borderRadius: BorderRadius.circular(20),
        border: isDark ? Border.all(color: cs.outlineVariant) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recovery Dashboard',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? cs.onSurface : Colors.white,
                  ),
                ),
              ),
              Icon(Icons.favorite_border, color: isDark ? cs.primary : Colors.white),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _dayOfRecovery != null ? 'Day $dayOfRecovery of recovery' : 'Procedure date not set',
            style: TextStyle(fontSize: 16, color: isDark ? cs.onSurfaceVariant : Colors.white),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (_dayOfRecovery ?? 0) / _totalRecoveryDays,
            backgroundColor: isDark ? cs.onSurfaceVariant.withValues(alpha: 0.18) : Colors.white24,
            color: isDark ? cs.primary : Colors.white,
            minHeight: 5,
          ),
          const SizedBox(height: 6),
          Text(
            'Recovery Progress: $progressPercent%',
            style: TextStyle(color: isDark ? cs.onSurfaceVariant : Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _recoveryProgressHeadingCard() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(22),
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : const Color(0xFF2196F3),
        borderRadius: BorderRadius.circular(20),
        border: isDark ? Border.all(color: cs.outlineVariant) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recovery Progress',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? cs.onSurface : Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Monitor your recovery day by day',
            style: TextStyle(fontSize: 15, color: isDark ? cs.onSurfaceVariant : Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 28),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Text('Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ),
            _summaryRow(
              'Days since procedure',
              (_daysSinceProcedure ?? 0).toString(),
              'days',
              const Color(0xFFE8F0FE),
              const Color(0xFF2196F3),
            ),
            const SizedBox(height: 10),
            _summaryRow('Expected healing', '7-14', 'days', const Color(0xFFF2FBF3), const Color(0xFF22B573)),
          ],
        ),
      ),
    );
  }

  Widget _pieChartSection(Map<String, int> stats) {
    final cs = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final generalCount = stats['GeneralFollowed'] ?? 0;
    final specificCount = stats['SpecificFollowed'] ?? 0;
    final notGeneral = stats['GeneralNotFollowed'] ?? 0;
    final notSpecific = stats['SpecificNotFollowed'] ?? 0;
    final total = generalCount + specificCount + notGeneral + notSpecific;
    if (total == 0) {
      return Padding(
        padding: EdgeInsets.only(bottom: 16.0),
        child: Text(
          'No instruction logs available for selected treatment/subtype.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    final notFollowedTotal = notGeneral + notSpecific;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        children: [
          Text(
            'Instructions Followed',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: cs.onSurface),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(
                    value: generalCount.toDouble(),
                    color: semantic.success,
                    title: generalCount > 0 ? 'General\n$generalCount' : '',
                    radius: 55,
                    titleStyle: TextStyle(color: semantic.onSuccess, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  PieChartSectionData(
                    value: specificCount.toDouble(),
                    color: semantic.info,
                    title: specificCount > 0 ? 'Specific\n$specificCount' : '',
                    radius: 55,
                    titleStyle: TextStyle(color: semantic.onInfo, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  PieChartSectionData(
                    value: notFollowedTotal.toDouble(),
                    color: cs.error,
                    title: notFollowedTotal > 0 ? 'Not\n$notFollowedTotal' : '',
                    radius: 55,
                    titleStyle: TextStyle(color: cs.onError, fontWeight: FontWeight.bold, fontSize: 14),
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
              _Legend(color: semantic.success, label: 'General Followed'),
              _Legend(color: semantic.info, label: 'Specific Followed'),
              _Legend(color: cs.error, label: 'Not Followed'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  '$generalCount General, $specificCount Specific, $notFollowedTotal Not followed',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: cs.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _instructionsLogSection(
    List<String> allDates,
    List<Map<String, dynamic>> logsForSelectedDate, {
    bool missingProcedureDate = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final semantic = AppSemanticColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? cs.outlineVariant : Colors.blueGrey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (missingProcedureDate) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Instructions Log',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? cs.onSurface : Colors.blueGrey,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Flexible(
                    fit: FlexFit.tight,
                    child: Text(
                      'Instructions Log',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? cs.onSurface : Colors.blueGrey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (allDates.length > 1) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.5, minWidth: 80),
                      child: DropdownButton<String>(
                        value: _selectedDateForInstructionsLog,
                        isDense: true,
                        isExpanded: true,
                        items: allDates
                            .map(
                              (d) => DropdownMenuItem(
                                value: d,
                                child: Text(
                                  _formatDisplayDate(d),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() => _selectedDateForInstructionsLog = v ?? _selectedDateForInstructionsLog);
                        },
                        underline: Container(
                          height: 1,
                          color: isDark ? cs.outlineVariant : Colors.blueGrey[100],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (missingProcedureDate)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? cs.surfaceContainerHighest : Colors.yellow[50],
                borderRadius: BorderRadius.circular(8),
                border: isDark ? Border(left: BorderSide(color: cs.error, width: 3)) : null,
              ),
              child: Text(
                'Please set up treatment and procedure date first.',
                style: TextStyle(color: isDark ? cs.onSurfaceVariant : Colors.black54, fontSize: 15),
              ),
            )
          else ...[
            if (logsForSelectedDate.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? cs.surfaceContainerHighest : Colors.yellow[50],
                  borderRadius: BorderRadius.circular(8),
                  border: isDark ? Border(left: BorderSide(color: cs.error, width: 3)) : null,
                ),
                child: Builder(
                  builder: (_) {
                    // Provide debug info about available dates when empty to help diagnose mismatches.
                    final uniqueDates = _instructionStatus
                        .map((e) => e['date']?.toString() ?? '')
                        .where((d) => d.isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort();
                    return Text(
                      'No instructions recorded for this day. (Have ${_instructionStatus.length} rows total across ${uniqueDates.length} dates)',
                      style: TextStyle(color: isDark ? cs.onSurfaceVariant : Colors.black54, fontSize: 15),
                    );
                  },
                ),
              )
            else if (_lastUsedSubtypeFallback)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? cs.surfaceContainerHighest : Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? cs.outlineVariant : Colors.blueGrey[100]!),
                ),
                child: Text(
                  'Subtype-specific logs empty; showing subtype-agnostic entries for this date.',
                  style: TextStyle(fontSize: 12, color: isDark ? cs.onSurface : Colors.black87),
                ),
              ),
            ...logsForSelectedDate.map((log) {
              final instruction = (log['instruction'] ?? log['note'] ?? '').toString();
              final type = (log['type'] ?? '').toString().toLowerCase();
              final followed = log['followed'] == true || log['followed']?.toString() == 'true';
              final Color? baseColor = type == 'general'
                  ? Colors.green[100]
                  : type == 'specific'
                      ? Colors.red[100]
                      : Colors.blue[100];
              final color = followed ? baseColor : Colors.grey[200];
              final label = followed ? 'Followed' : 'Not Followed';
              final accent = followed ? semantic.success : cs.error;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        instruction,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                          color: isDark ? cs.onSurface : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        followed ? Icons.check_circle : Icons.cancel,
                        size: 18,
                        color: isDark ? accent : (followed ? Colors.green : Colors.black38),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? cs.surfaceContainerHighest : color,
                        borderRadius: BorderRadius.circular(8),
                        border: isDark ? Border.all(color: accent.withValues(alpha: 0.35)) : null,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isDark ? accent : Colors.black54,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _progressEntriesSection() {
    if (_progressEntries.isEmpty) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
          child: Text(
            "Patient Progress Entries",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: cs.onSurface),
          ),
        ),
        ..._progressEntries.map((e) {
          final msg = (e['message'] ?? '').toString();
          final ts = (e['timestamp'] ?? '').toString().split('T').first;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? cs.surfaceContainerLow : const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? cs.outlineVariant : Colors.blueGrey[100]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Entry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(height: 4)
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    msg,
                    style: TextStyle(color: isDark ? cs.onSurface : Colors.black87, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Flexible(
                  child: Text(
                    ts,
                    style: TextStyle(
                      color: isDark ? cs.onSurfaceVariant : Colors.black54,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _summaryRow(String label, String value, String unit, Color bgColor, Color textColor) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHighest : bgColor,
        borderRadius: BorderRadius.circular(10),
        border: isDark ? Border(left: BorderSide(color: textColor.withValues(alpha: 0.85), width: 4)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: isDark ? cs.onSurface : Colors.black87, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: isDark ? cs.onSurface : textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                  ),
                ),
              ],
            ),
          ),
          Text(unit, style: TextStyle(color: isDark ? cs.onSurfaceVariant : Colors.black54)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.70)),
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}
