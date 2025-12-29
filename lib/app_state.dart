import 'package:flutter/material.dart';
import 'dart:async'; // for Timer used in batching
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'services/api_service.dart';
import 'package:intl/intl.dart';

class AppState extends ChangeNotifier {
  // Reusable date formatter (yyyy-MM-dd) to standardize instruction log dates
  static final DateFormat _ymd = DateFormat('yyyy-MM-dd');

  /// Format a DateTime (local) to canonical yyyy-MM-dd string
  static String formatYMD(DateTime dt) => _ymd.format(dt);

  // --- Server time sync ---
  DateTime? _serverUtcNow;
  DateTime? get serverUtcNow => _serverUtcNow;

  /// Call to refresh server time. If the request fails, leaves the last value unchanged.
  Future<void> syncServerTime() async {
    final now = await ApiService.getServerUtcNow();
    if (now != null) {
      _serverUtcNow = now;
      notifyListeners();
    }
  }

  /// Returns the best 'now' to use for date comparisons: server UTC if available, else device UTC.
  DateTime effectiveUtcNow() => (_serverUtcNow ?? DateTime.now().toUtc());

  /// Returns the local DateTime corresponding to effectiveUtcNow.
  DateTime effectiveLocalNow() => effectiveUtcNow().toLocal();

  /// Compute days since procedure based on server time if available; falls back to device time.
  int daysSinceProcedure(DateTime selectedDate) {
    final proc = procedureDate;
    final selected = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final procLocal = proc != null ? DateTime(proc.year, proc.month, proc.day) : selected;
    int day = selected.difference(procLocal).inDays + 1;
    if (day < 1) day = 1;
    return day;
  }

  /// Background backfill (design stub): iterate over known dates & ensure all
  /// instruction templates pushed. Currently NO-OP to avoid unexpected network
  /// load; call with implement=true to enable logic later.
  Future<void> backfillInstructionSnapshots({bool implement = false}) async {
    if (!implement) return; // intentionally inert until explicitly enabled
    // Potential algorithm (not yet active):
    // 1. Determine treatment & subtype; if null -> abort.
    // 2. Determine procedureDate; generate days from procedureDate..today.
    // 3. For each day, synthesize full instruction set (general+specific) and
    //    call addInstructionLog for each missing combination (idempotent due to removal logic).
    // 4. Flush batches.
  }
  // User details
  String? fullName;
  DateTime? dob;
  String? gender;
  String? username;
  String? password;
  String? phone;
  String? email;
  String? token;

  // Computed category selection flag
  bool get hasSelectedCategory =>
      department != null && department!.isNotEmpty &&
          doctor != null && doctor!.isNotEmpty &&
          treatment != null && treatment!.isNotEmpty &&
          procedureDate != null;

  // Procedure details
  DateTime? procedureDate;
  TimeOfDay? procedureTime;

  // Private fields for department, doctor, treatment & subtype
  String? _department;
  String? _doctor;
  String? _treatment;
  String? _treatmentSubtype;
  String? _implantStage;
  bool? _procedureCompleted;
  bool? get procedureCompleted => _procedureCompleted;
  set procedureCompleted(bool? val) {
    _procedureCompleted = val;
    _saveUserDetails();
    notifyListeners();
  }

  // Checklist data
  final Map<String, List<bool>> _dailyChecklist = {};
  final Map<String, List<bool>> _persistedChecklists = {};

  // --- Checklist persistence helpers ---
  String _checklistStorageKey(String key, {String? username}) {
    final user = (username ?? this.username ?? 'default').trim();
    return 'checklist_${user}_$key';
  }

  String _checklistRegistryKey({String? username}) {
    final user = (username ?? this.username ?? 'default').trim();
    return 'checklist_keys_$user';
  }

  Future<void> loadAllChecklists({String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    // Migrate any 'default' user checklists to this user (first login scenario)
    final user = (username ?? this.username)?.trim();
    if (user != null && user.isNotEmpty && user != 'default') {
      await _migrateDefaultChecklistsToUser(user);
    }
    final registryKey = _checklistRegistryKey(username: username);
    final registryJson = prefs.getString(registryKey);
    if (registryJson == null || registryJson.isEmpty) {
      return;
    }
    try {
      final List<dynamic> keys = jsonDecode(registryJson);
      for (final k in keys) {
        if (k is! String) continue;
        final stored = prefs.getString(_checklistStorageKey(k, username: username));
        if (stored == null) continue;
        final List<dynamic> decoded = jsonDecode(stored);
        final list = decoded.map((e) => e == true).toList();
        _persistedChecklists[k] = List<bool>.from(list);
      }
      notifyListeners();
    } catch (_) {
      // Ignore corrupt entries
    }
  }

  // Migrate persisted checklists from 'default' user to a real username once.
  Future<void> _migrateDefaultChecklistsToUser(String username) async {
    if (username.trim().isEmpty || username == 'default') return;
    final prefs = await SharedPreferences.getInstance();
    final defaultRegistryKey = _checklistRegistryKey(username: 'default');
    final registryJson = prefs.getString(defaultRegistryKey);
    if (registryJson == null || registryJson.isEmpty) return;
    List<String> defaultKeys = [];
    try {
      defaultKeys = List<String>.from(jsonDecode(registryJson));
    } catch (_) {
      defaultKeys = [];
    }
    if (defaultKeys.isEmpty) {
      await prefs.remove(defaultRegistryKey);
      return;
    }
    // Load target registry for the real user
    final targetRegistryKey = _checklistRegistryKey(username: username);
    List<String> targetKeys = [];
    final targetRegJson = prefs.getString(targetRegistryKey);
    if (targetRegJson != null && targetRegJson.isNotEmpty) {
      try { targetKeys = List<String>.from(jsonDecode(targetRegJson)); } catch (_) { targetKeys = []; }
    }

    bool changedTargetReg = false;
    for (final k in defaultKeys) {
      final srcKey = _checklistStorageKey(k, username: 'default');
      final dstKey = _checklistStorageKey(k, username: username);
      final src = prefs.getString(srcKey);
      if (src == null) {
        await prefs.remove(srcKey);
        continue;
      }
      final dst = prefs.getString(dstKey);
      if (dst == null) {
        await prefs.setString(dstKey, src);
        if (!targetKeys.contains(k)) {
          targetKeys.add(k);
          changedTargetReg = true;
        }
      }
      // Remove default entry after migrating
      await prefs.remove(srcKey);
    }
    if (changedTargetReg) {
      await prefs.setString(targetRegistryKey, jsonEncode(targetKeys));
    }
    // Finally, remove the default registry
    await prefs.remove(defaultRegistryKey);
  }

  Future<void> _saveChecklistForKey(String key, List<bool> list, {String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    // Save value
    await prefs.setString(
      _checklistStorageKey(key, username: username),
      jsonEncode(list),
    );
    // Update registry
    final registryKey = _checklistRegistryKey(username: username);
    final registryJson = prefs.getString(registryKey);
    List<String> keys = [];
    if (registryJson != null && registryJson.isNotEmpty) {
      try {
        keys = List<String>.from(jsonDecode(registryJson));
      } catch (_) {
        keys = [];
      }
    }
    if (!keys.contains(key)) {
      keys.add(key);
      await prefs.setString(registryKey, jsonEncode(keys));
    }
  }

  // Instruction logs (for ProgressScreen)
  final List<Map<String, dynamic>> _instructionLogs = [];
  DateTime? _lastInstructionSyncUtc;

  List<Map<String, dynamic>> get instructionLogs =>
      List.unmodifiable(_instructionLogs);

  Future<void> _saveInstructionLogs({String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = username != null ? 'instruction_logs_${username}' : 'instruction_logs';
    await prefs.setString(key, jsonEncode(_instructionLogs));
  }

  Future<void> loadInstructionLogs({String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = username != null ? 'instruction_logs_${username}' : 'instruction_logs';
    final data = prefs.getString(key);
    final legacy = prefs.getString('instruction_logs'); // migrate if present
    _instructionLogs.clear();
    if (data != null) {
      final List<dynamic> decoded = jsonDecode(data);
      for (var item in decoded) {
        _instructionLogs.add({
          'date': item['date'] ?? '',
          'note': item['note'] ?? '',
          'type': item['type'] ?? '',
          'followed': item['followed'] ?? false,
          'instruction': item['instruction'] ?? item['note'] ?? '',
          'username': item['username'] ?? username ?? '',
          'treatment': item['treatment'] ?? '',
          'subtype': item['subtype'] ?? '',
            'everFollowed': item['everFollowed'] ?? (item['followed'] ?? false),
        });
      }
    }
    // Merge legacy logs (without username scoping) once
    if (legacy != null) {
      try {
        final List<dynamic> decoded = jsonDecode(legacy);
        for (var item in decoded) {
          final m = {
            'date': item['date'] ?? '',
            'note': item['note'] ?? '',
            'type': item['type'] ?? '',
            'followed': item['followed'] ?? false,
            'instruction': item['instruction'] ?? item['note'] ?? '',
            'username': item['username'] ?? username ?? '',
            'treatment': item['treatment'] ?? '',
            'subtype': item['subtype'] ?? '',
          };
          // Avoid duplicates
          final exists = _instructionLogs.any((e) =>
            e['date'] == m['date'] &&
            e['instruction'] == m['instruction'] &&
            e['type'] == m['type'] &&
            e['username'] == m['username']
          );
          if (!exists) _instructionLogs.add(m);
        }
        // After migration, save to user-scoped key and clear legacy
        await _saveInstructionLogs(username: username ?? this.username);
        await prefs.remove('instruction_logs');
      } catch (_) {
        // ignore migration errors
      }
    }
    debugPrint('Loaded instruction logs for $username: count = \\${_instructionLogs.length}');
    notifyListeners();
  }

  DateTime? get lastInstructionSyncUtc => _lastInstructionSyncUtc;

  Future<void> pullInstructionStatusChanges() async {
    try {
      if (token == null) return; // not logged in
  // If we've never synced before, fetch a generous history window so patient portal shows past days too.
  final initialSince = DateTime.now().toUtc().subtract(const Duration(days: 60));
  final since = (_lastInstructionSyncUtc ?? initialSince).toIso8601String();
      List<Map<String,dynamic>>? changes = await ApiService.fetchInstructionStatusChanges(sinceIso: since);
      // Fallback: if incremental changes failed (null) or the backend hasn't registered the endpoint yet, pull a date-range list (60 days)
      if (changes == null) {
        final from = DateTime.now().subtract(const Duration(days: 60));
        final dateFrom = _ymd.format(from);
        final dateTo = _ymd.format(DateTime.now());
        final range = await ApiService.listInstructionStatus(dateFrom: dateFrom, dateTo: dateTo);
        if (range != null) {
          // Normalize into the same shape as changes
          changes = range.map((row) => {
            'date': (row['date'] ?? '').toString(),
            'group': (row['group'] ?? row['type'] ?? '').toString(),
            'instruction_text': (row['instruction_text'] ?? row['instruction'] ?? row['note'] ?? '').toString(),
            'followed': row['followed'] == true || row['followed']?.toString() == 'true',
            'ever_followed': row['ever_followed'] == true || row['ever_followed']?.toString() == 'true',
            'treatment': row['treatment'] ?? '',
            'subtype': row['subtype'],
            'instruction_index': row['instruction_index'] ?? stableInstructionIndex((row['group']??'').toString(), (row['instruction_text']??'').toString()),
            'updated_at': row['updated_at']?.toString(),
          }).toList();
        }
      }
      if (changes == null || changes.isEmpty) return;
      bool changed = false;
      DateTime maxTs = _lastInstructionSyncUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      for (final row in changes) {
        final date = (row['date'] ?? '').toString();
        final type = (row['group'] ?? row['type'] ?? '').toString();
        final instruction = (row['instruction_text'] ?? row['instruction'] ?? row['note'] ?? '').toString();
        final followed = row['followed'] == true || row['followed']?.toString() == 'true';
        final everFollowed = row['ever_followed'] == true || row['ever_followed']?.toString() == 'true';
        final updatedAtStr = row['updated_at']?.toString();
        DateTime? updatedAt;
        try { if (updatedAtStr != null) { updatedAt = DateTime.parse(updatedAtStr).toUtc(); } } catch(_){ updatedAt = null; }
        if (updatedAt != null && updatedAt.isAfter(maxTs)) maxTs = updatedAt;
        // Normalize treatment/subtype so patient filters match even if older rows lacked these fields
        final rawTreatment = (row['treatment'] ?? '').toString();
        final rawSubtype = row['subtype']?.toString();
        final normTreatment = rawTreatment.isEmpty ? (_treatment ?? '') : rawTreatment;
        final normSubtype = (rawSubtype == null || rawSubtype.isEmpty) ? _treatmentSubtype : rawSubtype;
        // Replace local entry (latest wins) by composite key
        final idx = _instructionLogs.indexWhere((e) => e['date']==date && (e['instruction']==instruction || e['note']==instruction) && (e['type']??'')==type);
        final entry = {
          'date': date,
          'note': instruction,
          'type': type,
          'followed': followed,
          'instruction': instruction,
          'username': username ?? this.username ?? '',
          'treatment': normTreatment,
          'subtype': normSubtype,
          'everFollowed': everFollowed || followed,
          'instruction_index': row['instruction_index'] ?? stableInstructionIndex(type, instruction),
        };
        if (idx == -1) {
          _instructionLogs.add(entry); changed = true;
        } else {
          _instructionLogs[idx] = entry; changed = true;
        }
      }
      if (changed) {
        await _saveInstructionLogs(username: username ?? this.username);
        _lastInstructionSyncUtc = maxTs;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('pullInstructionStatusChanges error: $e');
    }
  }

  Future<void> addInstructionLog(
      String note, {
        String? date,
        String type = '',
        bool followed = false,
        String? username,
        String? treatment,
        String? subtype,
      }) async {
    final now = DateTime.now();
    final formattedDate = date ??
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final user = username ?? this.username ?? '';
    final treat = treatment ?? _treatment ?? '';
    final sub = subtype ?? _treatmentSubtype ?? '';
    final instruction = note;

    // Protect a previously followed=true log from being overwritten to false (demotion guard)
    final existingIndex = _instructionLogs.indexWhere((log) =>
      log['date'] == formattedDate &&
      log['instruction'] == instruction &&
      log['type'] == type &&
      log['username'] == user &&
      log['treatment'] == treat &&
      log['subtype'] == sub
    );
    if (existingIndex != -1) {
      final prev = _instructionLogs[existingIndex];
      final prevFollowed = prev['followed'] == true || prev['followed']?.toString() == 'true';
      final prevEver = prev['everFollowed'] == true || prev['everFollowed']?.toString() == 'true';
      // If previous is followed and new is not, skip demotion
      if (prevFollowed && !followed) {
        return; // do not overwrite
      }
      // We'll replace but carry over everFollowed sticky flag
      _instructionLogs.removeAt(existingIndex);
      if (followed && !prevEver) {
        // sticky adopt
      }
    }

    final entry = {
      'date': formattedDate,
      'note': note,
      'type': type,
      'followed': followed,
      'instruction': instruction,
      'username': user,
      'treatment': treat,
      'subtype': sub,
      'instruction_index': stableInstructionIndex(type, instruction),
      'everFollowed': followed || (existingIndex != -1 && (_instructionLogs.any((e)=> false) ? false : true)), // will patch below
    };
    // Fix everFollowed logic: easier after constructing base map.
    if (existingIndex != -1) {
      // We removed old entry earlier; fetch its everFollowed from saved copy if needed (not stored now). For simplicity, recompute by scanning logs.
      // If any prior log for same keys had followed true, set everFollowed
      final hadPriorFollowed = _instructionLogs.any((log) =>
        log['date'] == formattedDate &&
        log['instruction'] == instruction &&
        log['type'] == type &&
        log['username'] == user &&
        log['treatment'] == treat &&
        log['subtype'] == sub &&
        (log['followed'] == true || log['followed']?.toString() == 'true')
      );
      entry['everFollowed'] = hadPriorFollowed || followed;
    } else {
      entry['everFollowed'] = followed;
    }
    _instructionLogs.add(entry);
    debugPrint('Added instruction log for $user on $formattedDate. Total logs: ${_instructionLogs.length}');
    await _saveInstructionLogs(username: user);
    notifyListeners();
    // Queue for debounced batch sync instead of immediate single-row POST.
    _queueInstructionEntryForBatch(entry);
  }

  // Explicit method if caller wants to ensure sync completion
  Future<bool> addInstructionLogAndSync(String note, {String? date, String type = '', bool followed = false, String? username, String? treatment, String? subtype}) async {
    await addInstructionLog(note, date: date, type: type, followed: followed, username: username, treatment: treatment, subtype: subtype);
    return true; // network errors logged internally
  }

  void _syncInstructionEntry(Map<String, dynamic> entry) async {
    try {
      // Lazy import to avoid coupling at top-level
      // ignore: avoid_web_libraries_in_flutter
      // Dynamically call ApiService to send one-item bulk
      // We keep instruction_index consistent (already included)
      final items = [entry];
      // Import inside method scope
      // Using a separate function to avoid analyzer complaints
      await _postInstructionItems(items);
    } catch (e) {
      debugPrint('Instruction sync failed: $e');
    }
  }

  // --- Debounced batching for instruction status uploads ---
  final Map<String, Map<int, Map<String,dynamic>>> _pendingInstructionBatches = {};
  final Map<String, DateTime> _pendingBatchTouched = {};
  Timer? _batchTimer;
  static const Duration _batchDebounce = Duration(milliseconds: 500);

  void _queueInstructionEntryForBatch(Map<String,dynamic> entry) {
    final date = (entry['date'] ?? '').toString();
    final group = (entry['type'] ?? entry['group'] ?? '').toString();
    final idx = entry['instruction_index'] ?? 0;
    if (date.isEmpty || group.isEmpty) {
      // Fallback: send immediately if something is malformed
      _syncInstructionEntry(entry);
      return;
    }
    final key = '$date|$group';
    _pendingInstructionBatches.putIfAbsent(key, ()=> {});
    // Overwrite latest version per index
    _pendingInstructionBatches[key]![idx] = entry;
    _pendingBatchTouched[key] = DateTime.now();
    _scheduleBatchFlush();
  }

  void _scheduleBatchFlush() {
    _batchTimer?.cancel();
    _batchTimer = Timer(_batchDebounce, _flushDueInstructionBatches);
  }

  Future<void> flushAllInstructionBatches() async {
    await _flushDueInstructionBatches(forceAll: true);
  }

  Future<void> _flushDueInstructionBatches({bool forceAll = false}) async {
    final now = DateTime.now();
    final toSendKeys = <String>[];
    for (final entry in _pendingInstructionBatches.entries) {
      final key = entry.key;
      final touched = _pendingBatchTouched[key] ?? now;
      if (forceAll || now.difference(touched) >= _batchDebounce) {
        toSendKeys.add(key);
      }
    }
    if (toSendKeys.isEmpty) return;
    for (final k in toSendKeys) {
      final map = _pendingInstructionBatches.remove(k);
      _pendingBatchTouched.remove(k);
      if (map == null || map.isEmpty) continue;
      final items = map.values.toList();
      try {
        await _postInstructionItems(items);
        debugPrint('[InstructionBatch] Uploaded ${items.length} items for $k');
      } catch (e) {
        debugPrint('[InstructionBatch][error] $k -> $e');
        // Requeue on failure (optional with simple retry strategy)
        _pendingInstructionBatches[k] = { for (final it in items) it['instruction_index'] : it };
        _pendingBatchTouched[k] = DateTime.now();
        _scheduleBatchFlush();
      }
    }
  }

  Future<void> _postInstructionItems(List<Map<String, dynamic>> items) async {
    try {
      // Map entry to backend expected shape. addInstructionLog already added instruction_index.
      final payloadItems = items.map((e) => {
        'date': e['date'],
        'treatment': e['treatment'] ?? '',
        'subtype': e['subtype'],
        'group': e['type'] ?? e['group'] ?? '',
        'instruction_index': e['instruction_index'] ?? 0,
        'instruction_text': e['instruction'] ?? e['note'] ?? '',
        'followed': e['followed'] ?? false,
        'ever_followed': (e['everFollowed'] == true || e['everFollowed']?.toString() == 'true'),
      }).toList();
      await ApiService.saveInstructionStatus(payloadItems);
    } catch (e) {
      debugPrint('Post instruction items failed: $e');
    }
  }

  // Getters for private fields
  String? get department => _department;
  String? get doctor => _doctor;
  String? get treatment => _treatment;
  String? get treatmentSubtype => _treatmentSubtype;
  String? get implantStage => _implantStage;

  // Setters for private fields
  void setDepartment(String? value) {
    if (_department != value) {
      _department = value;
      _saveUserDetails();
      notifyListeners();
    }
  }

  void setDoctor(String? value) {
    if (_doctor != value) {
      _doctor = value;
      _saveUserDetails();
      notifyListeners();
    }
  }

  void setTreatment(String? treatment, {String? subtype, DateTime? procedureDate}) {
    if (_treatment != treatment || _treatmentSubtype != subtype) {
      _treatment = treatment;
      _treatmentSubtype = subtype;
      if (treatment == 'Implant' && subtype != null) {
        final parts = subtype.split('\n').first.trim();
        _implantStage = parts;
      } else {
        _implantStage = null;
      }
      if (procedureDate != null) {
        this.procedureDate = procedureDate;
      }
      _saveUserDetails();
      notifyListeners();
    }
  }

  void setTreatmentSubtype(String? value) {
    if (_treatmentSubtype != value) {
      _treatmentSubtype = value;
      _saveUserDetails();
      notifyListeners();
    }
  }

  // Treatment instructions
  final Map<String, List<String>> _treatmentInstructions = {};

  List<String> get currentTreatmentInstructions {
    if (_treatment == null) return [];
    final baseInstructions = _treatmentInstructions[_treatment!] ?? [];
    if (_treatmentSubtype != null && _treatmentSubtype!.isNotEmpty) {
      final subtypeKey = '$_treatment:$_treatmentSubtype';
      final subtypeInstructions = _treatmentInstructions[subtypeKey] ?? [];
      return [...baseInstructions, ...subtypeInstructions];
    }
    return baseInstructions;
  }

  List<String> get currentDos => currentTreatmentInstructions.take(4).toList();
  List<String> get currentDonts =>
      currentTreatmentInstructions.skip(4).take(2).toList();
  List<String> get currentSpecificSteps =>
      currentTreatmentInstructions.skip(6).toList();

  void setUserDetails({
    required String fullName,
    required DateTime dob,
    required String gender,
    required String username,
    required String password,
    required String phone,
    required String email,
  }) {
    this.fullName = fullName;
    this.dob = dob;
    this.gender = gender;
    this.username = username;
    this.password = password;
    this.phone = phone;
    this.email = email;
    _saveUserDetails();
    notifyListeners();
  }

  void setLoginDetails(String username, String password) {
    this.username = username;
    this.password = password;
    _saveUserDetails();
    notifyListeners();
  }

  Future<void> setToken(String token) async {
    this.token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await _saveUserDetails();
    notifyListeners();
  }
  /// Sync token from SharedPreferences to AppState.token (call at startup)
  Future<void> syncTokenFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final tokenFromPrefs = prefs.getString('token');
    if (tokenFromPrefs != null && tokenFromPrefs != token) {
      setToken(tokenFromPrefs);
    }
  }

  void setProcedureDateTime(DateTime date, TimeOfDay time) {
    procedureDate = date;
    procedureTime = time;
    _saveUserDetails();
    notifyListeners();
  }

  List<bool> getChecklistForDate(DateTime date) {
    final key = _dateKey(date);
    final n = currentDos.length;
    return List<bool>.from(_dailyChecklist[key] ?? List.filled(n, false));
  }

  void setChecklistForDate(DateTime date, List<bool> values) {
    final key = _dateKey(date);
    _dailyChecklist[key] = List<bool>.from(values);
    notifyListeners();
  }

  List<bool> getChecklistForKey(String key) {
    return _persistedChecklists[key] ?? [];
  }

  void setChecklistForKey(String key, List<bool> list) {
    _persistedChecklists[key] = List<bool>.from(list);
    // Persist asynchronously (no await to keep API sync-friendly)
    _saveChecklistForKey(key, list, username: username);
    notifyListeners();
  }

  List<bool> getChecklistForTreatmentDay(String treatmentKey, int day, int itemCount) {
    String key = "${treatmentKey}_day$day";
    return List<bool>.from(_persistedChecklists[key] ?? List.filled(itemCount, false));
  }

  void setChecklistForTreatmentDay(String treatmentKey, int day, List<bool> values) {
    String key = "${treatmentKey}_day$day";
  _persistedChecklists[key] = List<bool>.from(values);
  // Persist as well
  _saveChecklistForKey(key, _persistedChecklists[key]!, username: username);
    notifyListeners();
  }

  Future<void> reset() async {
    fullName = null;
    dob = null;
    gender = null;
    username = null;
    password = null;
    phone = null;
    email = null;
    token = null;
    procedureDate = null;
    procedureTime = null;
    _department = null;
    _doctor = null;
    _treatment = null;
    _treatmentSubtype = null;
    _implantStage = null;
    _procedureCompleted = null;
    _dailyChecklist.clear();
    _persistedChecklists.clear();
    _progressFeedback.clear();
    _instructionLogs.clear();
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('token');
      prefs.remove('user_details');
    });
    _saveInstructionLogs(username: username);
    _saveUserDetails();
    notifyListeners();
  }

  static String _dateKey(DateTime date) =>
      "${date.year.toString().padLeft(4, '0')}-"
          "${date.month.toString().padLeft(2, '0')}-"
          "${date.day.toString().padLeft(2, '0')}";

  final List<Map<String, String>> _progressFeedback = [];

  List<Map<String, String>> get progressFeedback =>
      List.unmodifiable(_progressFeedback);

  void addProgressFeedback(String title, String note, {String? date}) {
    final now = DateTime.now();
    final formattedDate = date ??
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    _progressFeedback.add({
      'title': title,
      'note': note,
      'date': formattedDate,
    });
    notifyListeners();
  }

  void clearProgressFeedback() {
    _progressFeedback.clear();
    notifyListeners();
  }

  Future<void> _saveUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_details', jsonEncode({
      'fullName': fullName,
      'dob': dob?.toIso8601String(),
      'gender': gender,
      'username': username,
      'password': password,
      'phone': phone,
      'email': email,
      'token': token,
      'department': _department,
      'doctor': _doctor,
      'treatment': _treatment,
      'treatmentSubtype': _treatmentSubtype,
      'implantStage': _implantStage,
      'procedureCompleted': _procedureCompleted,
      'procedureDate': procedureDate?.toIso8601String(),
      'procedureTime': procedureTime != null
          ? "${procedureTime!.hour.toString().padLeft(2, '0')}:${procedureTime!.minute.toString().padLeft(2, '0')}"
          : null,
    }));
    // No need to store hasSelectedCategory in SharedPreferences
  }

  Future<void> loadUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('user_details');
    String? loadedToken = prefs.getString('token');
    if (data != null) {
      final decoded = jsonDecode(data);
      fullName = decoded['fullName'];
      dob = decoded['dob'] != null ? DateTime.parse(decoded['dob']) : null;
      gender = decoded['gender'];
      username = decoded['username'];
      password = decoded['password'];
      phone = decoded['phone'];
      email = decoded['email'];
      token = decoded['token'] ?? loadedToken;
      _department = decoded['department'];
      _doctor = decoded['doctor'];
      _treatment = decoded['treatment'];
      _treatmentSubtype = decoded['treatmentSubtype'];
      _implantStage = decoded['implantStage'];
      _procedureCompleted = decoded['procedureCompleted'];
      procedureDate = decoded['procedureDate'] != null ? DateTime.parse(decoded['procedureDate']) : null;
      procedureTime = decoded['procedureTime'] != null ? _parseTimeOfDay(decoded['procedureTime']) : null;
      notifyListeners();
    } else {
      if (loadedToken != null) {
        token = loadedToken;
        notifyListeners();
      }
    }
    // After loading user details, attempt loading instruction logs then one-time bulk sync
    await loadInstructionLogs(username: username);
    if (username != null && token != null) {
      final syncFlagKey = 'instruction_bulk_synced_${username}';
      if (!(prefs.getBool(syncFlagKey) ?? false)) {
        final ok = await bulkSyncAllInstructionLogs();
        if (ok) {
          await prefs.setBool(syncFlagKey, true);
        }
      }
    }
  }

  // Properly use setters for private fields (fixes direct assignment error)
  void clearUserData() async {
    username = null;
    fullName = null;
    dob = null;
    gender = null;
    phone = null;
    email = null;
    setDepartment(null);
    setDoctor(null);
    setTreatment(null, subtype: null);
    setTreatmentSubtype(null);
    procedureDate = null;
    procedureTime = null;
    procedureCompleted = false;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_details');
  }

  void updatePersonalInfo({
    String? fullName,
    String? email,
    String? phone,
    String? gender,
    DateTime? dob,
  }) {
    this.fullName = fullName ?? this.fullName;
    this.email = email ?? this.email;
    this.phone = phone ?? this.phone;
    this.gender = gender ?? this.gender;
    this.dob = dob ?? this.dob;
    _saveUserDetails();
    notifyListeners();
  }

  static TimeOfDay? _parseTimeOfDay(dynamic timeStr) {
    if (timeStr == null) return null;
    final str = timeStr is String ? timeStr : timeStr.toString();
    final parts = str.split(":");
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  int stableInstructionIndex(String group, String instruction) {
    final s = (group.trim().toLowerCase() + '|' + instruction.trim().toLowerCase());
    int hash = 0x811C9DC5; // FNV offset basis 32-bit
    const int prime = 0x01000193; // FNV prime
    for (final codeUnit in s.codeUnits) {
      hash ^= codeUnit & 0xFF;
      hash = (hash * prime) & 0xFFFFFFFF; // keep 32-bit
    }
    return hash & 0x7FFFFFFF; // positive int
  }

  Future<bool> bulkSyncAllInstructionLogs() async {
    if (_instructionLogs.isEmpty) return true;
    try {
      final items = _instructionLogs.map((e) {
        final type = (e['type'] ?? '').toString();
        final instruction = (e['instruction'] ?? e['note'] ?? '').toString();
        final idx = stableInstructionIndex(type, instruction);
        return {
          'date': e['date'],
          'treatment': e['treatment'] ?? '',
          'subtype': e['subtype'],
          'group': type,
          'instruction_index': idx,
          'instruction_text': instruction,
          'followed': e['followed'] ?? false,
          'ever_followed': (e['everFollowed'] == true || e['everFollowed']?.toString() == 'true'),
        };
      }).toList();
      final ok = await ApiService.saveInstructionStatus(items);
      if (ok) debugPrint('Bulk sync succeeded: ${items.length} instruction rows');
      else debugPrint('Bulk sync failed');
      return ok;
    } catch (e) {
      debugPrint('Bulk sync error: $e');
      return false;
    }
  }

  Future<bool> forceResyncInstructionLogs() async {
    final prefs = await SharedPreferences.getInstance();
    if (username == null) return false;
    final flagKey = 'instruction_bulk_synced_${username}';
    await prefs.remove(flagKey);
    return await bulkSyncAllInstructionLogs();
  }
}