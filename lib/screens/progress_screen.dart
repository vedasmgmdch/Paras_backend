import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart'; // Import for global routeObserver
import 'chat_screen.dart';
import '../widgets/no_animation_page_route.dart';
import '../theme/semantic_colors.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> with RouteAware {
  String _selectedDateForInstructionsLog = "";

  String get _username => Provider.of<AppState>(context, listen: false).username ?? "default";
  String? get _doctorName => Provider.of<AppState>(context, listen: false).doctor;
  String? get _treatment => Provider.of<AppState>(context, listen: false).treatment;
  String? get _subtype => Provider.of<AppState>(context, listen: false).treatmentSubtype;

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
    // Intentionally do nothing.
    // Re-initializing here causes janky back animation and an unexpected full refresh
    // when returning from Chat. The user can manually refresh if needed.
  }

  Future<void> _initializeProgress(String username) async {
    debugPrint('[Progress] init start for user=$username');
    try {
      await Provider.of<AppState>(context, listen: false).loadInstructionLogs(username: username);
      // Immediately pull server-side instruction status changes to populate past days too
      unawaited(Provider.of<AppState>(context, listen: false).pullInstructionStatusChanges());
      final logs = Provider.of<AppState>(context, listen: false).instructionLogs;
      debugPrint('[Progress] local+persisted instruction logs loaded count=${logs.length}');
    } catch (e) {
      debugPrint('[Progress][error] initialization failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Progress init failed: $e')));
      }
    }
    debugPrint('[Progress] init end');
  }

  List<dynamic> _filterInstructionLogs(
    List<dynamic> logs, {
    required String username,
    String? treatment,
    String? subtype,
  }) {
    String norm(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').replaceAll('–', '-').replaceAll('—', '-');

    // Compatibility: older app versions stored instruction logs without treatment/subtype.
    // To avoid mixing treatments, only treat empty treatment/subtype as wildcard when:
    // - the current episode has a procedureDate, and
    // - the log date is within the first 14 recovery days.
    final appState = Provider.of<AppState>(context, listen: false);
    final procedureDate = appState.procedureDate;
    final DateTime? windowStart =
        procedureDate != null ? DateTime(procedureDate.year, procedureDate.month, procedureDate.day) : null;
    final DateTime? windowEnd = windowStart?.add(const Duration(days: 13));

    bool _isWithinRecoveryWindow(String dateStr) {
      if (windowStart == null || windowEnd == null) return false;
      try {
        final d = DateTime.parse(dateStr);
        final day = DateTime(d.year, d.month, d.day);
        return !day.isBefore(windowStart) && !day.isAfter(windowEnd);
      } catch (_) {
        return false;
      }
    }

    final bool isPfdFixed = (treatment == 'Prosthesis Fitted' && subtype == 'Fixed Dentures');
    final Set<String> allowedPfdGeneral = {
      norm('Whenever local anesthesia is used, avoid chewing on your teeth until the numbness has worn off.'),
      norm('Proper brushing, flossing, and regular cleanings are necessary to maintain the restoration.'),
      norm('Pay special attention to your gumline.'),
      norm('Avoid very hot or hard foods.'),
      // Marathi variants
      norm('स्थानिक भूल दिल्यानंतर, सुन्नपणा जाईपर्यंत दातांवर चावणे टाळा.'),
      norm('पुनर्स्थापना टिकवण्यासाठी योग्य ब्रशिंग, फ्लॉसिंग आणि नियमित स्वच्छता आवश्यक आहे.'),
      norm('तुमच्या हिरड्यांच्या सीमेकडे विशेष लक्ष द्या.'),
      norm('अतिशय गरम किंवा कडक अन्न टाळा.'),
    };
    final Set<String> allowedPfdSpecific = {
      norm('If your bite feels high or uncomfortable, contact your dentist for an adjustment.'),
      norm(
        'If the restoration feels loose or comes off, keep it safe and contact your dentist. Do not try to glue it yourself.',
      ),
      norm(
        'Clean carefully around the restoration and gumline; use floss/interdental aids as advised by your dentist.',
      ),
      norm('If you notice persistent pain, swelling, or bleeding, contact your dentist.'),
      // Marathi variants
      norm('चावताना दात उंच वाटत असतील किंवा अस्वस्थ वाटत असेल, समायोजनासाठी दंतवैद्याशी संपर्क साधा.'),
      norm(
        'पुनर्स्थापना सैल वाटली किंवा निघाली तर ती सुरक्षित ठेवा आणि दंतवैद्याशी संपर्क साधा. स्वतः चिकटवण्याचा प्रयत्न करू नका.',
      ),
      norm(
        'पुनर्स्थापना व हिरड्यांच्या सीमेजवळ नीट स्वच्छता ठेवा; दंतवैद्याने सांगितल्याप्रमाणे फ्लॉस/इंटरडेंटल साधने वापरा.',
      ),
      norm('दुखणे, सूज किंवा रक्तस्राव सतत राहिल्यास दंतवैद्याशी संपर्क साधा.'),
    };

    return logs.where((log) {
      if ((log['username'] ?? log['user'] ?? "default") != username) return false;
      final logDate = (log['date'] ?? '').toString();
      final inWindow = _isWithinRecoveryWindow(logDate);
      final logTreatment = (log['treatment'] ?? '').toString();
      if (treatment != null && treatment.isNotEmpty) {
        // If the log has an explicit treatment, require an exact match.
        // If it's missing (legacy data), accept it only for this episode's recovery window.
        if (logTreatment.isNotEmpty) {
          if (logTreatment != treatment) return false;
        } else {
          if (!inWindow) return false;
        }
      }
      final logSubtype = (log['subtype'] ?? '').toString();
      if (subtype != null && subtype.isNotEmpty) {
        if (logSubtype.isNotEmpty) {
          // Accuracy: require exact subtype match when present.
          if (logSubtype != subtype) return false;
        } else {
          // Legacy subtype missing: only accept inside recovery window.
          if (!inWindow) return false;
        }
      }

      if (isPfdFixed) {
        final t = (log['type'] ?? '').toString().trim().toLowerCase();
        final instruction = (log['instruction'] ?? log['note'] ?? '').toString();
        final n = norm(instruction);
        if (t == 'general') {
          if (!allowedPfdGeneral.contains(n)) return false;
        } else if (t == 'specific') {
          if (!allowedPfdSpecific.contains(n)) return false;
        }
      }

      return true;
    }).toList();
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

    final nowLocal = appState.effectiveLocalNow();
    // Instructions log date dropdown must be limited to the first 14 days from procedure date.
    // Range: procedureDate .. min(today, procedureDate + 13 days)
    final int days =
        (nowLocal.difference(DateTime(procedureDate.year, procedureDate.month, procedureDate.day)).inDays + 1).clamp(
      1,
      14,
    );
    final List<String> allDates = List.generate(days, (i) {
      final d = procedureDate.add(Duration(days: i));
      return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    });

    if (_selectedDateForInstructionsLog.isEmpty && allDates.isNotEmpty) {
      final todayStr =
          "${nowLocal.year.toString().padLeft(4, '0')}-${nowLocal.month.toString().padLeft(2, '0')}-${nowLocal.day.toString().padLeft(2, '0')}";
      _selectedDateForInstructionsLog = allDates.contains(todayStr) ? todayStr : allDates.last;
    }

    // Always materialize the selected day against the expected instruction catalog.
    // This prevents duplicates and ensures "Not Followed" never exceeds the real checklist size.
    List<Map<String, dynamic>> materializedForSelectedDate() {
      String canonText(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll('–', '-').replaceAll('—', '-');

      String normText(String s) =>
          s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').replaceAll('–', '-').replaceAll('—', '-');

      int? asInt(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        return int.tryParse(v.toString());
      }

      DateTime? parseUpdatedAt(Map<String, dynamic> raw) {
        final candidates = [
          raw['updated_at'],
          raw['updatedAt'],
          raw['timestamp'],
          raw['created_at'],
          raw['createdAt'],
        ];
        for (final c in candidates) {
          if (c == null) continue;
          final dt = DateTime.tryParse(c.toString());
          if (dt != null) return dt;
        }
        return null;
      }

      // IMPORTANT: Only include items that are actually *logged* by the instruction screens.
      // Most screens show "don'ts" as text without checkboxes and they are not saved to logs.
      final generalCatalog = appState.currentDos.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      final specificCatalog =
          appState.currentSpecificSteps.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();

      // Build ordered expected list (deduped by stable identity).
      final List<Map<String, dynamic>> expectedOrdered = [];
      final Map<String, Map<String, dynamic>> expectedByKey = {};

      void addExpectedFromCatalog(String type, List<String> items) {
        for (final instruction in items) {
          final canonical = canonText(instruction);
          if (canonical.isEmpty) continue;
          final idx = appState.stableInstructionIndex(type, canonical);
          final key = '$type|#${idx.toString()}';
          if (expectedByKey.containsKey(key)) continue;
          final row = {
            'type': type,
            'instruction_index': idx,
            'instruction': canonical,
          };
          expectedByKey[key] = row;
          expectedOrdered.add(row);
        }
      }

      addExpectedFromCatalog('general', generalCatalog);
      addExpectedFromCatalog('specific', specificCatalog);

      // Fallback: infer expected instructions from what we've observed in this recovery window.
      if (expectedOrdered.isEmpty) {
        for (final rawAny in filteredLogs) {
          final raw = Map<String, dynamic>.from(rawAny);
          final type = (raw['type']?.toString() ?? '').trim().toLowerCase();
          if (type.isEmpty) continue;
          final instruction = (raw['instruction'] ?? raw['note'] ?? '').toString();
          final canonical = canonText(instruction);
          final idx = asInt(raw['instruction_index']) ??
              (canonical.isEmpty ? null : appState.stableInstructionIndex(type, canonical));
          final key = idx != null ? '$type|#${idx.toString()}' : '$type|${canonical.toLowerCase()}';
          if (expectedByKey.containsKey(key)) continue;
          final row = {
            'type': type,
            'instruction_index': idx,
            'instruction': canonical,
          };
          expectedByKey[key] = row;
          expectedOrdered.add(row);
        }
      }

      // Build latest per-day logs, de-duped by stable identity.
      final List<Map<String, dynamic>> rawForDate = filteredLogs
          .where((l) => (l['date']?.toString() ?? '') == _selectedDateForInstructionsLog)
          .map((l) => Map<String, dynamic>.from(l))
          .toList();

      final Map<String, Map<String, dynamic>> latestByKey = {};
      final Map<String, Map<String, dynamic>> latestByText = {};
      for (final raw in rawForDate) {
        final type = (raw['type']?.toString() ?? '').trim().toLowerCase();
        if (type.isEmpty) continue;
        final instruction = (raw['instruction'] ?? raw['note'] ?? '').toString();
        final canonical = canonText(instruction);
        final stableIdx =
            canonical.isNotEmpty ? appState.stableInstructionIndex(type, canonical) : asInt(raw['instruction_index']);
        final key = stableIdx != null ? '$type|#${stableIdx.toString()}' : '$type|${canonical.toLowerCase()}';

        // Normalize the stored index to the stable one so old inconsistent indices don't create duplicates.
        raw['instruction_index'] = stableIdx;
        raw['instruction'] = canonical.isNotEmpty ? canonical : instruction;

        final existing = latestByKey[key];
        if (existing == null) {
          latestByKey[key] = raw;
        } else {
          final a = parseUpdatedAt(existing);
          final b = parseUpdatedAt(raw);
          if (a == null || b == null) {
            // Fall back to last-write-wins if we can't compare timestamps.
            latestByKey[key] = raw;
          } else if (b.isAfter(a)) {
            latestByKey[key] = raw;
          }
        }

        // Also keep a text-keyed view so we can match expected items even if indices drift.
        final tKey = '$type|${normText(raw['instruction']?.toString() ?? '')}';
        final existingT = latestByText[tKey];
        if (existingT == null) {
          latestByText[tKey] = raw;
        } else {
          final a2 = parseUpdatedAt(existingT);
          final b2 = parseUpdatedAt(raw);
          if (a2 == null || b2 == null) {
            latestByText[tKey] = raw;
          } else if (b2.isAfter(a2)) {
            latestByText[tKey] = raw;
          }
        }
      }

      if (expectedOrdered.isEmpty) {
        // Nothing to materialize; just show de-duped day logs.
        return latestByKey.values.toList();
      }

      // Merge: for each expected item, show real log if present; otherwise synthetic Not Followed.
      return expectedOrdered.map((e) {
        final type = (e['type'] ?? '').toString().trim().toLowerCase();
        final idx = e['instruction_index'];
        final key = idx != null ? '$type|#${idx.toString()}' : null;
        final tKey = '$type|${normText((e['instruction'] ?? '').toString())}';
        final log = (key != null ? latestByKey[key] : null) ?? latestByText[tKey];
        if (log != null) return log;
        return {
          ...e,
          'date': _selectedDateForInstructionsLog,
          'followed': false,
          'synthetic': true,
        };
      }).toList();
    }

    final shownLogsForSelectedDate = materializedForSelectedDate();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? cs.outlineVariant.withValues(alpha: 0.55) : Colors.blueGrey[100]!,
        ),
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? cs.onSurface : Colors.blueGrey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh history',
                    icon: Icon(
                      Icons.refresh,
                      size: 20,
                      color: isDark ? cs.onSurfaceVariant : Colors.blueGrey,
                    ),
                    onPressed: () async {
                      final appState = Provider.of<AppState>(context, listen: false);
                      try {
                        await appState.pullInstructionStatusChanges();
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(const SnackBar(content: Text('Instruction history refreshed')));
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
                        }
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                  if (allDates.length > 1) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.5, minWidth: 10),
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
                        onChanged: (val) {
                          setState(() {
                            _selectedDateForInstructionsLog = val ?? "";
                          });
                        },
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? cs.onSurface : Colors.black87,
                        ),
                        underline: Container(
                          height: 1,
                          color: isDark ? cs.outlineVariant.withValues(alpha: 0.55) : Colors.blueGrey[100],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (shownLogsForSelectedDate.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? cs.surfaceContainerHighest : Colors.yellow[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "No instructions recorded for this day.",
                style: TextStyle(
                  color: isDark ? cs.onSurfaceVariant : Colors.black54,
                  fontSize: 15,
                ),
              ),
            )
          else
            ...shownLogsForSelectedDate.map((log) {
              final instruction = log['instruction']?.toString() ?? log['note']?.toString() ?? '';
              final type = log['type']?.toString().toLowerCase();
              final followed = log['followed'] == true || log['followed']?.toString() == 'true';
              final label = followed ? 'Followed' : 'Not Followed';
              final Color? baseColor = type == 'general'
                  ? (isDark ? cs.secondaryContainer : Colors.green[100])
                  : type == 'specific'
                      ? (isDark ? cs.errorContainer : Colors.red[100])
                      : (isDark ? cs.primaryContainer : Colors.blue[100]);
              final bg = followed ? baseColor : (isDark ? cs.surfaceContainerHighest : Colors.grey[200]);

              final Color labelTextColor;
              if (!isDark) {
                labelTextColor = Colors.black54;
              } else if (followed) {
                labelTextColor = type == 'general'
                    ? cs.onSecondaryContainer
                    : type == 'specific'
                        ? cs.onErrorContainer
                        : cs.onPrimaryContainer;
              } else {
                labelTextColor = cs.onSurfaceVariant;
              }

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
                        followed ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 18,
                        color: followed
                            ? Colors.green
                            : (isDark ? cs.onSurfaceVariant.withValues(alpha: 0.65) : Colors.black38),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: labelTextColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
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

  // Removed legacy _getTodayDate(); server-time-aware nowLocal is used directly.

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
    final cs = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final appState = Provider.of<AppState>(context, listen: false);
    final filteredLogs = _filterInstructionLogs(
      instructionLogs,
      username: _username,
      treatment: _treatment,
      subtype: _subtype,
    );

    // Materialize missing-as-not-followed across the recovery window so counts
    // remain accurate even with weak/offline usage.
    final procedureDate = appState.procedureDate;
    final nowLocal = appState.effectiveLocalNow();
    final DateTime start = procedureDate != null
        ? DateTime(procedureDate.year, procedureDate.month, procedureDate.day)
        : DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final int days = (nowLocal.difference(start).inDays + 1).clamp(1, 14);
    final List<String> allDates = List.generate(days, (i) {
      final d = start.add(Duration(days: i));
      return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    });

    String normText(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').replaceAll('–', '-').replaceAll('—', '-');

    String canonText(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll('–', '-').replaceAll('—', '-');

    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    // IMPORTANT: Only include items that are actually logged by instruction screens (checkboxed).
    // "Don'ts" are generally shown as text without checkboxes and are not stored, so they must
    // NOT be counted as expected items.
    final generalCatalog = appState.currentDos.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    final specificCatalog =
        appState.currentSpecificSteps.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();

    final Map<String, Map<String, dynamic>> expectedByKey = {};
    void addExpected(String type, List<String> items) {
      for (final instruction in items) {
        final canonical = canonText(instruction);
        if (canonical.isEmpty) continue;
        final idx = appState.stableInstructionIndex(type, canonical);
        expectedByKey.putIfAbsent('$type|#${idx.toString()}', () {
          return {
            'type': type,
            'instruction_index': idx,
            'instruction': canonical,
          };
        });
      }
    }

    addExpected('general', generalCatalog);
    addExpected('specific', specificCatalog);

    final List<Map<String, dynamic>> expected = expectedByKey.values.toList();

    if (expected.isEmpty) {
      // Fallback to observed union.
      final Map<String, Map<String, dynamic>> byKey = {};
      for (final raw in filteredLogs) {
        final type = (raw['type']?.toString() ?? '').trim().toLowerCase();
        final instruction = (raw['instruction'] ?? raw['note'] ?? '').toString();
        final canonical = canonText(instruction);
        final idx = asInt(raw['instruction_index']) ??
            (canonical.isEmpty ? null : appState.stableInstructionIndex(type, canonical));
        final idxStr = (idx == null) ? '' : idx.toString();
        final key = idxStr.isNotEmpty ? '$type|#${idxStr}' : '$type|${normText(canonical)}';
        byKey.putIfAbsent(key, () {
          return {
            'type': type,
            'instruction_index': idx,
            'instruction': canonical,
          };
        });
      }
      expected.addAll(byKey.values);
    }

    final Map<String, Map<String, dynamic>> latestByIdx = {};
    final Map<String, Map<String, dynamic>> latestByText = {};
    for (final raw in filteredLogs) {
      final date = (raw['date'] ?? '').toString();
      final type = (raw['type']?.toString() ?? '').trim().toLowerCase();
      final instruction = (raw['instruction'] ?? raw['note'] ?? '').toString();
      final idx = raw['instruction_index'];
      if (date.isEmpty || type.isEmpty) continue;
      if (idx != null && idx.toString().isNotEmpty) {
        latestByIdx['$date|$type|#${idx.toString()}'] = Map<String, dynamic>.from(raw);
      }
      if (instruction.trim().isNotEmpty) {
        latestByText['$date|$type|${normText(instruction)}'] = Map<String, dynamic>.from(raw);
      }
    }

    int generalFollowed = 0;
    int specificFollowed = 0;
    int notFollowedGeneral = 0;
    int notFollowedSpecific = 0;

    for (final date in allDates) {
      for (final e in expected) {
        final type = (e['type'] ?? '').toString().trim().toLowerCase();
        if (type.isEmpty) continue;
        final idx = e['instruction_index'];
        final idxKey = (idx == null) ? null : '$date|$type|#${idx.toString()}';
        final textKey = '$date|$type|${normText((e['instruction'] ?? '').toString())}';
        final log = (idxKey != null ? latestByIdx[idxKey] : null) ?? latestByText[textKey];
        final followed = log != null && (log['followed'] == true || log['followed']?.toString() == 'true');
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
    }

    final stats = {
      'GeneralFollowed': generalFollowed,
      'SpecificFollowed': specificFollowed,
      'GeneralNotFollowed': notFollowedGeneral,
      'SpecificNotFollowed': notFollowedSpecific,
    };

    final generalCount = stats['GeneralFollowed'] ?? 0;
    final specificCount = stats['SpecificFollowed'] ?? 0;
    final notFollowedGeneralCount = stats['GeneralNotFollowed'] ?? 0;
    final notFollowedSpecificCount = stats['SpecificNotFollowed'] ?? 0;

    final total = generalCount + specificCount + notFollowedGeneralCount + notFollowedSpecificCount;
    if (total == 0) {
      return Padding(
        padding: EdgeInsets.only(bottom: 16.0),
        child: Text(
          "No instruction logs available for selected treatment/subtype.",
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    final notFollowedTotal = notFollowedGeneralCount + notFollowedSpecificCount;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        children: [
          Text(
            "Instructions Followed",
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
              _buildPieLegend(context, semantic.success, "General Followed"),
              _buildPieLegend(context, semantic.info, "Specific Followed"),
              _buildPieLegend(context, cs.error, "Not Followed"),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  "$generalCount General, $specificCount Specific, $notFollowedTotal Not followed",
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

  Widget _buildPieLegend(BuildContext context, Color color, String label) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.70)),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = Provider.of<AppState>(context);
    final procedureDate = appState.procedureDate ?? appState.effectiveLocalNow();
    final nowLocal = appState.effectiveLocalNow();
    final int daysSinceProcedure =
        (nowLocal.difference(DateTime(procedureDate.year, procedureDate.month, procedureDate.day)).inDays + 1).clamp(
      1,
      10000,
    );

    final int totalRecoveryDays = 14;
    final int dayOfRecovery = daysSinceProcedure.clamp(1, totalRecoveryDays);
    final int progressPercent = ((dayOfRecovery / totalRecoveryDays) * 100).clamp(0, 100).toInt();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 18),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? colorScheme.surfaceContainerLow : colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                        border: isDark
                            ? Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.70))
                            : null,
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
                                    color: isDark ? colorScheme.onSurface : Colors.white,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.favorite_border,
                                color: isDark ? colorScheme.primary : Colors.white,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Day $dayOfRecovery of recovery',
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? colorScheme.onSurfaceVariant : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: (dayOfRecovery / totalRecoveryDays).clamp(0, 1),
                            backgroundColor: isDark ? colorScheme.surfaceContainerHighest : Colors.white24,
                            color: isDark ? colorScheme.primary : Colors.white,
                            minHeight: 5,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Recovery Progress: $progressPercent%',
                            style: TextStyle(
                              color: isDark ? colorScheme.onSurfaceVariant : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(22),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? colorScheme.surfaceContainerLow : colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                        border: isDark
                            ? Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.70))
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recovery Progress',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isDark ? colorScheme.onSurface : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Monitor your recovery day by day",
                            style: TextStyle(
                              fontSize: 15,
                              color: isDark ? colorScheme.onSurfaceVariant : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Card(
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
                            _buildSummaryRow(
                              context,
                              'Days since procedure',
                              '$daysSinceProcedure',
                              'days',
                              const Color(0xFFE8F0FE),
                              const Color(0xFF2196F3),
                            ),
                            const SizedBox(height: 10),
                            _buildSummaryRow(
                              context,
                              'Expected healing',
                              '7-14',
                              'days',
                              const Color(0xFFF2FBF3),
                              const Color(0xFF22B573),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildPieChart(appState.instructionLogs),
                    _buildInstructionsFollowedBox(appState.instructionLogs),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text(
                          "Chat with Doctor",
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            NoAnimationPageRoute(
                              builder: (_) => ChatScreen(
                                patientUsername: _username,
                                asDoctor: false,
                                doctorName: _doctorName,
                                readOnly: appState.procedureCompleted == true,
                                bannerText: appState.procedureCompleted == true ? 'Treatment completed' : null,
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
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, String label, String value, String unit, Color bgColor, Color textColor) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainer : bgColor,
        borderRadius: BorderRadius.circular(10),
        border: isDark
            ? Border(
                left: BorderSide(color: textColor.withValues(alpha: 0.90), width: 3),
              )
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isDark ? cs.onSurfaceVariant : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 26),
                ),
              ],
            ),
          ),
          Text(
            unit,
            style: TextStyle(color: isDark ? cs.onSurfaceVariant : Colors.black54),
          ),
        ],
      ),
    );
  }
}
