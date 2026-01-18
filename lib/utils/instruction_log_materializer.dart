// Shared materialization logic for instruction logs.
//
// Goals:
// - Canonicalize instruction strings consistently (whitespace + dash normalization)
// - Use stable identity derived from (type/group + canonical instruction text)
// - Dedupe day logs by newest timestamp ("latest row wins")
// - Materialize missing expected instructions as synthetic "Not Followed" rows
// - Compute consistent stats across the recovery window

class InstructionLogMaterializer {
  static String canonicalGroup(String? value) => (value ?? '').trim().toLowerCase();

  static String canonicalInstructionText(String? value) {
    return (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll('–', '-').replaceAll('—', '-');
  }

  static String normalizedInstructionKeyText(String? value) => canonicalInstructionText(value).toLowerCase();

  static int stableInstructionIndex(String group, String instruction) {
    final g = canonicalGroup(group);
    final i = canonicalInstructionText(instruction).toLowerCase();
    final s = '$g|$i';
    int hash = 0x811C9DC5; // FNV offset basis 32-bit
    const int prime = 0x01000193; // FNV prime
    for (final codeUnit in s.codeUnits) {
      hash ^= codeUnit & 0xFF;
      hash = (hash * prime) & 0xFFFFFFFF; // keep 32-bit
    }
    return hash & 0x7FFFFFFF; // positive int
  }

  static DateTime? parseUpdatedAt(Map<String, dynamic> raw) {
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

  static int? asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static List<Map<String, dynamic>> dedupeLatestByDateTypeInstruction(
    List<Map<String, dynamic>> logs, {
    int Function(String group, String instruction)? stableIndex,
  }) {
    final idxFn = stableIndex ?? stableInstructionIndex;

    String stableKey(Map<String, dynamic> log) {
      final date = (log['date'] ?? '').toString();
      final type = canonicalGroup((log['type'] ?? '').toString());
      final instruction = (log['instruction'] ?? log['note'] ?? '').toString();
      final canonical = canonicalInstructionText(instruction);
      final stableIdx = idxFn(type, canonical);
      return '$date|$type|#${stableIdx.toString()}';
    }

    final latest = <String, Map<String, dynamic>>{};
    for (final raw in logs) {
      final log = Map<String, dynamic>.from(raw);
      final key = stableKey(log);
      final prev = latest[key];
      if (prev == null) {
        latest[key] = log;
        continue;
      }
      final a = parseUpdatedAt(prev);
      final b = parseUpdatedAt(log);
      if (a == null || b == null) {
        latest[key] = log; // last-write-wins
      } else if (b.isAfter(a)) {
        latest[key] = log;
      }
    }
    return latest.values.toList();
  }

  static List<Map<String, dynamic>> materializeForSelectedDate({
    required List<Map<String, dynamic>> filteredLogs,
    required String selectedDate,
    required List<String> generalCatalog,
    required List<String> specificCatalog,
    int Function(String group, String instruction)? stableIndex,
  }) {
    final idxFn = stableIndex ?? stableInstructionIndex;

    // Build ordered expected list (deduped by stable identity).
    final List<Map<String, dynamic>> expectedOrdered = [];
    final Map<String, Map<String, dynamic>> expectedByKey = {};

    void addExpectedFromCatalog(String type, List<String> items) {
      for (final instruction in items) {
        final canonical = canonicalInstructionText(instruction);
        if (canonical.isEmpty) continue;
        final idx = idxFn(type, canonical);
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

    // Fallback: infer expected instructions from observed logs (if catalog is missing).
    if (expectedOrdered.isEmpty) {
      for (final rawAny in filteredLogs) {
        final raw = Map<String, dynamic>.from(rawAny);
        final type = canonicalGroup(raw['type']?.toString() ?? '');
        if (type.isEmpty) continue;
        final instruction = (raw['instruction'] ?? raw['note'] ?? '').toString();
        final canonical = canonicalInstructionText(instruction);
        final idx = asInt(raw['instruction_index']) ?? (canonical.isEmpty ? null : idxFn(type, canonical));
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
        .where((l) => (l['date']?.toString() ?? '') == selectedDate)
        .map((l) => Map<String, dynamic>.from(l))
        .toList();

    final Map<String, Map<String, dynamic>> latestByKey = {};
    final Map<String, Map<String, dynamic>> latestByText = {};

    for (final raw in rawForDate) {
      final type = canonicalGroup(raw['type']?.toString() ?? '');
      if (type.isEmpty) continue;
      final instruction = (raw['instruction'] ?? raw['note'] ?? '').toString();
      final canonical = canonicalInstructionText(instruction);
      final stableIdx = canonical.isNotEmpty ? idxFn(type, canonical) : asInt(raw['instruction_index']);
      final key = stableIdx != null ? '$type|#${stableIdx.toString()}' : '$type|${canonical.toLowerCase()}';

      raw['instruction_index'] = stableIdx;
      raw['instruction'] = canonical.isNotEmpty ? canonical : instruction;

      final existing = latestByKey[key];
      if (existing == null) {
        latestByKey[key] = raw;
      } else {
        final a = parseUpdatedAt(existing);
        final b = parseUpdatedAt(raw);
        if (a == null || b == null) {
          latestByKey[key] = raw;
        } else if (b.isAfter(a)) {
          latestByKey[key] = raw;
        }
      }

      final tKey = '$type|${normalizedInstructionKeyText(raw['instruction']?.toString() ?? '')}';
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
      return latestByKey.values.toList();
    }

    return expectedOrdered.map((e) {
      final type = canonicalGroup((e['type'] ?? '').toString());
      final idx = e['instruction_index'];
      final key = idx != null ? '$type|#${idx.toString()}' : null;
      final tKey = '$type|${normalizedInstructionKeyText((e['instruction'] ?? '').toString())}';
      final log = (key != null ? latestByKey[key] : null) ?? latestByText[tKey];
      if (log != null) return log;
      return {
        ...e,
        'date': selectedDate,
        'followed': false,
        'synthetic': true,
      };
    }).toList();
  }

  static Map<String, int> computeStatsAcrossDates({
    required List<Map<String, dynamic>> filteredLogs,
    required List<String> allDates,
    required List<String> generalCatalog,
    required List<String> specificCatalog,
    int Function(String group, String instruction)? stableIndex,
  }) {
    final idxFn = stableIndex ?? stableInstructionIndex;

    // Build expected unique list by stable identity.
    final Map<String, Map<String, dynamic>> expectedByKey = {};

    void addExpected(String type, List<String> items) {
      for (final instruction in items) {
        final canonical = canonicalInstructionText(instruction);
        if (canonical.isEmpty) continue;
        final idx = idxFn(type, canonical);
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

    // Fallback to observed union if catalog missing.
    if (expected.isEmpty) {
      final Map<String, Map<String, dynamic>> byKey = {};
      for (final rawAny in filteredLogs) {
        final raw = Map<String, dynamic>.from(rawAny);
        final type = canonicalGroup(raw['type']?.toString() ?? '');
        if (type.isEmpty) continue;
        final instruction = (raw['instruction'] ?? raw['note'] ?? '').toString();
        final canonical = canonicalInstructionText(instruction);
        final idx = asInt(raw['instruction_index']) ?? (canonical.isEmpty ? null : idxFn(type, canonical));
        final idxStr = (idx == null) ? '' : idx.toString();
        final key = idxStr.isNotEmpty ? '$type|#${idxStr}' : '$type|${normalizedInstructionKeyText(canonical)}';
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

    // Build latest-per-(date,type,expectedItem) maps.
    final Map<String, Map<String, dynamic>> latestByIdx = {};
    final Map<String, Map<String, dynamic>> latestByText = {};

    for (final rawAny in filteredLogs) {
      final raw = Map<String, dynamic>.from(rawAny);
      final date = (raw['date'] ?? '').toString();
      final type = canonicalGroup(raw['type']?.toString() ?? '');
      final instruction = (raw['instruction'] ?? raw['note'] ?? '').toString();
      if (date.isEmpty || type.isEmpty) continue;

      final canonical = canonicalInstructionText(instruction);
      final stableIdx = canonical.isNotEmpty ? idxFn(type, canonical) : asInt(raw['instruction_index']);

      if (stableIdx != null) {
        final k = '$date|$type|#${stableIdx.toString()}';
        final existing = latestByIdx[k];
        if (existing == null) {
          latestByIdx[k] = raw;
        } else {
          final a = parseUpdatedAt(existing);
          final b = parseUpdatedAt(raw);
          if (a == null || b == null) {
            latestByIdx[k] = raw;
          } else if (b.isAfter(a)) {
            latestByIdx[k] = raw;
          }
        }
      }

      if (canonical.trim().isNotEmpty) {
        final tKey = '$date|$type|${normalizedInstructionKeyText(canonical)}';
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
    }

    int generalFollowed = 0;
    int specificFollowed = 0;
    int notFollowedGeneral = 0;
    int notFollowedSpecific = 0;

    for (final date in allDates) {
      for (final e in expected) {
        final type = canonicalGroup((e['type'] ?? '').toString());
        if (type.isEmpty) continue;
        final idx = e['instruction_index'];
        final idxKey = (idx == null) ? null : '$date|$type|#${idx.toString()}';
        final textKey = '$date|$type|${normalizedInstructionKeyText((e['instruction'] ?? '').toString())}';
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

    return {
      'GeneralFollowed': generalFollowed,
      'SpecificFollowed': specificFollowed,
      'GeneralNotFollowed': notFollowedGeneral,
      'SpecificNotFollowed': notFollowedSpecific,
    };
  }
}
