// If this screen has instruction checklists, add log saving logic as in other instruction screens.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/semantic_colors.dart';

class _AccountCondition {
  final String label;
  final String sublabel;
  final double score;
  final Color color;

  const _AccountCondition({
    required this.label,
    required this.sublabel,
    required this.score,
    required this.color,
  });
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with WidgetsBindingObserver {
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleMidnightRefresh();
      if (mounted) setState(() {});
    }
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    if (!mounted) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final now = appState.effectiveLocalNow();
    final nextMidnight = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    var delay = nextMidnight.difference(now);
    if (delay.isNegative) {
      delay = const Duration(seconds: 1);
    }

    // Add a tiny buffer so we reliably land on the next day.
    _midnightTimer = Timer(delay + const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {});
      _scheduleMidnightRefresh();
    });
  }

  _AccountCondition _computeAccountCondition(BuildContext context, AppState appState) {
    final semantic = AppSemanticColors.of(context);
    final user = appState.username ?? '';
    final treatment = appState.treatment ?? '';
    final subtype = appState.treatmentSubtype ?? '';

    String normText(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').replaceAll('–', '-').replaceAll('—', '-');

    String canonText(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll('–', '-').replaceAll('—', '-');

    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    // Filter logs to the active account/treatment/subtype. Also keep legacy logs
    // (missing treatment/subtype) only within the first 14 recovery days.
    final procedureDate = appState.procedureDate;
    final DateTime? windowStart =
        procedureDate != null ? DateTime(procedureDate.year, procedureDate.month, procedureDate.day) : null;
    final DateTime? windowEnd = windowStart?.add(const Duration(days: 13));

    bool isWithinRecoveryWindow(String dateStr) {
      if (windowStart == null || windowEnd == null) return false;
      try {
        final d = DateTime.parse(dateStr);
        final day = DateTime(d.year, d.month, d.day);
        return !day.isBefore(windowStart) && !day.isAfter(windowEnd);
      } catch (_) {
        return false;
      }
    }

    final filteredLogs = appState.instructionLogs.where((raw) {
      if ((raw['username'] ?? raw['user'] ?? '').toString() != user) return false;
      final dateStr = (raw['date'] ?? '').toString();
      if (dateStr.isEmpty) return false;

      final logTreatment = (raw['treatment'] ?? '').toString();
      if (treatment.isNotEmpty) {
        if (logTreatment.isNotEmpty) {
          if (logTreatment != treatment) return false;
        } else {
          if (!isWithinRecoveryWindow(dateStr)) return false;
        }
      }

      final logSubtype = (raw['subtype'] ?? '').toString();
      if (subtype.isNotEmpty) {
        if (logSubtype.isNotEmpty) {
          if (logSubtype != subtype) return false;
        } else {
          if (!isWithinRecoveryWindow(dateStr)) return false;
        }
      }

      return true;
    }).toList();

    // Compute expected checklist items (checkboxed items only) and materialize
    // missing items as not-followed, matching the pie chart logic.
    final now = appState.effectiveLocalNow();
    final DateTime start = procedureDate != null
        ? DateTime(procedureDate.year, procedureDate.month, procedureDate.day)
        : DateTime(now.year, now.month, now.day);
    final int days = (now.difference(start).inDays + 1).clamp(1, 14);
    final List<String> allDates = List.generate(days, (i) {
      final d = start.add(Duration(days: i));
      return "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    });

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
      // Fallback: infer expected set from observed logs.
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

    int followedTotal = 0;
    int expectedTotal = 0;
    for (final date in allDates) {
      for (final e in expected) {
        final type = (e['type'] ?? '').toString().trim().toLowerCase();
        if (type.isEmpty) continue;
        expectedTotal++;

        final idx = e['instruction_index'];
        final idxKey = (idx == null) ? null : '$date|$type|#${idx.toString()}';
        final textKey = '$date|$type|${normText((e['instruction'] ?? '').toString())}';
        final log = (idxKey != null ? latestByIdx[idxKey] : null) ?? latestByText[textKey];
        final isFollowed = log != null && (log['followed'] == true || log['followed']?.toString() == 'true');
        if (isFollowed) followedTotal++;
      }
    }

    if (expectedTotal == 0) {
      return _AccountCondition(
        label: 'No data yet',
        sublabel: 'Follow instructions to build your progress',
        score: 0,
        color: semantic.info,
      );
    }

    final ratio = (followedTotal / expectedTotal).clamp(0.0, 1.0);
    if (ratio >= 0.80) {
      return _AccountCondition(
        label: 'Good',
        sublabel: 'Since procedure • ${(ratio * 100).round()}% instructions followed',
        score: ratio,
        color: semantic.success,
      );
    }
    if (ratio >= 0.50) {
      return _AccountCondition(
        label: 'Alright',
        sublabel: 'Since procedure • ${(ratio * 100).round()}% instructions followed',
        score: ratio,
        color: semantic.info,
      );
    }
    return _AccountCondition(
      label: 'Needs attention',
      sublabel: 'Since procedure • ${(ratio * 100).round()}% instructions followed',
      score: ratio,
      color: semantic.warning,
    );
  }

  Widget _buildAccountProgressBar(BuildContext context, AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    final condition = _computeAccountCondition(context, appState);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Progress Status',
                  style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: condition.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  condition.label,
                  style: TextStyle(fontWeight: FontWeight.bold, color: condition.color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: condition.score.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: condition.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            condition.sublabel,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final procedureDate = appState.procedureDate ?? appState.effectiveLocalNow();
    final nowLocal = appState.effectiveLocalNow();
    final int daysSinceProcedure =
        (nowLocal.difference(DateTime(procedureDate.year, procedureDate.month, procedureDate.day)).inDays + 1)
            .clamp(1, 10000);

    // Recovery Dashboard variables (computed inline where needed)
    // progressPercent reserved for future progress UI; currently unused

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 8.0),
                child: Column(
                  children: [
                    // Blue header card
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(22),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? colorScheme.surfaceContainerLow : colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                        border: isDark ? Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.70)) : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recovery Calendar',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isDark ? colorScheme.onSurface : colorScheme.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Track your healing progress",
                            style: TextStyle(
                              fontSize: 15,
                              color: (isDark ? colorScheme.onSurfaceVariant : colorScheme.onPrimary)
                                  .withValues(alpha: 0.92),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Recovery Timeline Card
                    Card(
                      margin: const EdgeInsets.only(bottom: 18),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(bottom: 10.0),
                              child: Text(
                                'Recovery Timeline',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                              ),
                            ),
                            _buildCalendarGrid(context, procedureDate, appState),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildLegendDot(context, AppSemanticColors.of(context).procedureContainer),
                                const SizedBox(width: 4),
                                const Text('Procedure', style: TextStyle(fontSize: 14)),
                                const SizedBox(width: 16),
                                _buildLegendDot(context, AppSemanticColors.of(context).successContainer),
                                const SizedBox(width: 4),
                                const Text('Completed', style: TextStyle(fontSize: 14)),
                                const SizedBox(width: 16),
                                _buildLegendDot(context, Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 4),
                                const Text('Today', style: TextStyle(fontSize: 14)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Progress Summary Card
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
                              child: Text(
                                'Progress Summary',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? colorScheme.surfaceContainer
                                    : colorScheme.primaryContainer.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(10),
                                border: isDark
                                    ? Border(
                                        left: BorderSide(
                                          color: colorScheme.primary.withValues(alpha: 0.95),
                                          width: 3,
                                        ),
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
                                          'Days since procedure',
                                          style: TextStyle(
                                              color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$daysSinceProcedure',
                                          style: TextStyle(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 26,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'days',
                                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? colorScheme.surfaceContainer
                                    : colorScheme.secondaryContainer.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(10),
                                border: isDark
                                    ? Border(
                                        left: BorderSide(
                                          color: colorScheme.secondary.withValues(alpha: 0.95),
                                          width: 3,
                                        ),
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
                                          'Expected healing',
                                          style: TextStyle(
                                              color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '7-14',
                                          style: TextStyle(
                                            color: colorScheme.secondary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 26,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'days',
                                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            _buildAccountProgressBar(context, appState),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildCalendarGrid(BuildContext context, DateTime procedureDate, AppState appState) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = appState.effectiveLocalNow();
    final today = DateTime(now.year, now.month, now.day);
    final proc = DateTime(procedureDate.year, procedureDate.month, procedureDate.day);

    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    List<Widget> rows = [];
    List<Widget> week = [];
    final weekdayOfFirst = firstDayOfMonth.weekday;
    for (int i = 1; i < weekdayOfFirst; i++) {
      week.add(Container(width: 36, height: 36));
    }

    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(now.year, now.month, d);
      final dateOnly = DateTime(date.year, date.month, date.day);

      final bool isToday = dateOnly == today;
      final bool isProcedure = dateOnly == proc;
      final bool isCompletedWindow = dateOnly.isAfter(proc) && dateOnly.isBefore(today);

      Color? dotColor;
      if (isToday) {
        dotColor = colorScheme.primary; // Today
      } else if (isProcedure) {
        dotColor = semantic.procedureContainer; // Procedure
      } else if (isCompletedWindow) {
        // Preserve the existing light-mode look, but use theme containers in dark mode.
        dotColor = isDark ? semantic.successContainer : const Color(0xFFB5E0D3);
      }

      final Color cellBase = isDark ? colorScheme.surfaceContainerHighest : const Color(0xFFF5F6FA);

      week.add(
        Padding(
          padding: const EdgeInsets.all(2.0),
          child: Container(
            decoration: BoxDecoration(
              color: dotColor ?? cellBase,
              borderRadius: BorderRadius.circular(8),
              border: isToday ? Border.all(color: colorScheme.primary, width: 2) : null,
            ),
            width: 36,
            height: 36,
            child: Center(
              child: Text(
                '$d',
                style: TextStyle(
                  // Ensure visibility when cells are filled.
                  color: isToday
                      ? colorScheme.onPrimary
                      : (isProcedure
                          ? (isDark ? semantic.onProcedureContainer : Colors.black)
                          : (isCompletedWindow
                              ? (isDark ? semantic.onSuccessContainer : Colors.black)
                              : (isDark ? colorScheme.onSurfaceVariant : Colors.grey[700]))),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );

      if (week.length == 7) {
        rows.add(Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: week));
        week = [];
      }
    }

    if (week.isNotEmpty) {
      while (week.length < 7) week.add(Container(width: 36, height: 36));
      rows.add(Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: week));
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
              .map(
                (e) => Expanded(
                  child: Center(
                    child: Text(
                      e,
                      style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        ...rows,
      ],
    );
  }

  static Widget _buildLegendDot(BuildContext context, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.80)),
      ),
    );
  }
}
