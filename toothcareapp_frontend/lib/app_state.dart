import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AppState extends ChangeNotifier {
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

    // Only remove exact duplicate for same date, instruction, and type
    _instructionLogs.removeWhere((log) =>
      log['date'] == formattedDate &&
      log['instruction'] == instruction &&
      log['type'] == type &&
      log['username'] == user &&
      log['treatment'] == treat &&
      log['subtype'] == sub
    );

    _instructionLogs.add({
      'date': formattedDate,
      'note': note,
      'type': type,
      'followed': followed,
      'instruction': instruction,
      'username': user,
      'treatment': treat,
      'subtype': sub,
    });
    debugPrint('Added instruction log for $user on $formattedDate. Total logs: \\${_instructionLogs.length}');
    await _saveInstructionLogs(username: user);
    notifyListeners();
  }

  Future<void> clearInstructionLogs({String? username}) async {
    _instructionLogs.clear();
    await _saveInstructionLogs(username: username);
    notifyListeners();
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
}