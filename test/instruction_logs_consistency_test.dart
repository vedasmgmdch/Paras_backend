import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tooth_care_app/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('stableInstructionIndex normalizes dash and group casing', () {
    final appState = AppState();

    final a = appState.stableInstructionIndex('Specific', 'Bite for 45–60 minutes');
    final b = appState.stableInstructionIndex('specific', 'Bite for 45-60 minutes');

    expect(a, b);
  });

  test('buildFollowedChecklistForDay matches by canonical text even if index differs', () async {
    final appState = AppState();

    const username = 'u1';
    const treatment = 'Implant';
    const subtype = 'Second Stage';
    const dateStr = '2026-01-18';

    // Simulate a legacy/server row where instruction_index may not match the current stable hash.
    // The hydration must still succeed via canonical text matching.
    await appState.addInstructionLog(
      'After 24 hours, gargle 3-4 times a day.',
      date: dateStr,
      type: 'specific',
      followed: true,
      username: username,
      treatment: treatment,
      subtype: subtype,
      instructionIndex: 2,
    );

    final day = DateTime(2026, 1, 18);
    final list = appState.buildFollowedChecklistForDay(
      day: day,
      type: 'specific',
      length: 1,
      instructionTextForIndex: (_) => 'After 24 hours, gargle 3–4 times a day.',
      username: username,
      treatment: treatment,
      subtype: subtype,
    );

    expect(list, [true]);
  });
}
