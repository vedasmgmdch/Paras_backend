import 'package:flutter_test/flutter_test.dart';
import 'package:tooth_care_app/utils/instruction_log_materializer.dart';

void main() {
  test('materializeForSelectedDate fills missing expected as synthetic not-followed', () {
    const generalCatalog = ['Bite firmly for 45–60 minutes'];

    final logs = <Map<String, dynamic>>[
      {
        'date': '2026-01-01',
        'type': 'general',
        'instruction': 'Bite firmly for 45-60 minutes',
        'followed': true,
        'updated_at': '2026-01-01T10:00:00Z',
      },
    ];

    final day1 = InstructionLogMaterializer.materializeForSelectedDate(
      filteredLogs: logs,
      selectedDate: '2026-01-01',
      generalCatalog: generalCatalog,
      specificCatalog: const [],
    );

    expect(day1, hasLength(1));
    expect(day1.first['followed'], isTrue);
    expect(day1.first['synthetic'], isNot(true));

    final day2 = InstructionLogMaterializer.materializeForSelectedDate(
      filteredLogs: logs,
      selectedDate: '2026-01-02',
      generalCatalog: generalCatalog,
      specificCatalog: const [],
    );

    expect(day2, hasLength(1));
    expect(day2.first['followed'], isFalse);
    expect(day2.first['synthetic'], isTrue);
  });

  test('computeStatsAcrossDates counts missing as not-followed', () {
    const generalCatalog = ['Bite firmly for 45–60 minutes'];

    final logs = <Map<String, dynamic>>[
      {
        'date': '2026-01-01',
        'type': 'general',
        'instruction': 'Bite firmly for 45-60 minutes',
        'followed': true,
        'updated_at': '2026-01-01T10:00:00Z',
      },
    ];

    final stats = InstructionLogMaterializer.computeStatsAcrossDates(
      filteredLogs: logs,
      allDates: const ['2026-01-01', '2026-01-02'],
      generalCatalog: generalCatalog,
      specificCatalog: const [],
    );

    expect(stats['GeneralFollowed'], 1);
    expect(stats['GeneralNotFollowed'], 1);
    expect(stats['SpecificFollowed'], 0);
    expect(stats['SpecificNotFollowed'], 0);
  });

  test('computeStatsAcrossDates never exceeds expectedCount * days', () {
    const generalCatalog = ['A', 'B'];
    const specificCatalog = ['C'];
    const allDates = ['2026-01-01', '2026-01-02'];

    // Intentionally add multiple rows that could cause duplicates if identity drifts
    // (dash differences, timestamps, instruction_index mismatch).
    final logs = <Map<String, dynamic>>[
      {
        'date': '2026-01-01',
        'type': 'general',
        'instruction': 'A',
        'followed': true,
        'updated_at': '2026-01-01T10:00:00Z',
      },
      {
        'date': '2026-01-01',
        'type': 'general',
        'instruction': 'A',
        'followed': false,
        'updated_at': '2026-01-01T09:00:00Z', // older, should lose
      },
      {
        'date': '2026-01-01',
        'type': 'specific',
        'instruction': 'C',
        'followed': true,
        'updated_at': '2026-01-01T10:00:00Z',
        'instruction_index': 123, // mismatch should not inflate counts
      },
    ];

    final stats = InstructionLogMaterializer.computeStatsAcrossDates(
      filteredLogs: logs,
      allDates: allDates,
      generalCatalog: generalCatalog,
      specificCatalog: specificCatalog,
    );

    final generalTotal = (stats['GeneralFollowed'] ?? 0) + (stats['GeneralNotFollowed'] ?? 0);
    final specificTotal = (stats['SpecificFollowed'] ?? 0) + (stats['SpecificNotFollowed'] ?? 0);

    expect(generalTotal, lessThanOrEqualTo(generalCatalog.length * allDates.length));
    expect(specificTotal, lessThanOrEqualTo(specificCatalog.length * allDates.length));
  });
}
