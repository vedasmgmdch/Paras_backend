  // If this screen has instruction checklists, add log saving logic as in other instruction screens.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final procedureDate = appState.procedureDate ?? appState.effectiveLocalNow();
    final nowLocal = appState.effectiveLocalNow();
    final int daysSinceProcedure = (nowLocal
          .difference(DateTime(procedureDate.year, procedureDate.month, procedureDate.day))
          .inDays + 1)
        .clamp(1, 10000);

  // Recovery Dashboard variables (computed inline where needed)
  // progressPercent reserved for future progress UI; currently unused

    return Scaffold(
      backgroundColor: Colors.white,
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
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Recovery Calendar',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          "Track your healing progress",
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white,
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
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20
                              ),
                            ),
                          ),
                          _buildCalendarGrid(procedureDate, appState),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildLegendDot(Color(0xFFFFE0E6)),
                              const SizedBox(width: 4),
                              const Text('Procedure', style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 16),
                              _buildLegendDot(Color(0xFFB5E0D3)),
                              const SizedBox(width: 4),
                              const Text('Completed', style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 16),
                              _buildLegendDot(Color(0xFF2196F3)),
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
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F0FE),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Days since procedure',
                                        style: TextStyle(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w500
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$daysSinceProcedure',
                                        style: const TextStyle(
                                          color: Color(0xFF2196F3),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 26,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Text(
                                  'days',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2FBF3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      Text(
                                        'Expected healing',
                                        style: TextStyle(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w500
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '7-14',
                                        style: TextStyle(
                                          color: Color(0xFF22B573),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 26,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Text(
                                  'days',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "No progress entries yet. Add your first entry from the Progress tab.",
                            style: TextStyle(color: Colors.black54, fontSize: 15),
                          ),
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

  static Widget _buildCalendarGrid(DateTime procedureDate, AppState appState) {
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
        dotColor = const Color(0xFF2196F3); // Today
      } else if (isProcedure) {
        dotColor = const Color(0xFFFFE0E6); // Procedure
      } else if (isCompletedWindow) {
        dotColor = const Color(0xFFB5E0D3); // Completed since procedure
      }

      week.add(
        Padding(
          padding: const EdgeInsets.all(2.0),
          child: Container(
            decoration: BoxDecoration(
              color: dotColor ?? const Color(0xFFF5F6FA),
              borderRadius: BorderRadius.circular(8),
              border: isToday ? Border.all(color: const Color(0xFF2196F3), width: 2) : null,
            ),
            width: 36,
            height: 36,
            child: Center(
              child: Text(
                '$d',
                style: TextStyle(
                  // Ensure visibility when today's cell has blue background
                  color: isToday ? Colors.white : (dotColor != null ? Colors.black : Colors.grey[700]),
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
              .map((e) => Expanded(child: Center(child: Text(e, style: const TextStyle(fontWeight: FontWeight.w600)))))
              .toList(),
        ),
        const SizedBox(height: 4),
        ...rows,
      ],
    );
  }

  static Widget _buildLegendDot(Color color) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
    );
  }
}