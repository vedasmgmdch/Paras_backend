import 'package:flutter/material.dart';
import 'dart:async'; // for Timer used in batching
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'services/api_service.dart';
import 'package:intl/intl.dart';
import 'instruction_catalog.dart';

class AppState extends ChangeNotifier {
  // Reusable date formatter (yyyy-MM-dd) to standardize instruction log dates
  static final DateFormat _ymd = DateFormat('yyyy-MM-dd');

  static const String _prefsThemeModeKey = 'theme_mode_v1';
  static const String _prefsThemeModePendingKey = 'theme_mode_pending_v1';

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  String _prefsThemeModeKeyForUser(String username) =>
      'theme_mode_v1_${username.trim()}';

  String _encodeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  ThemeMode _decodeThemeMode(String? value) {
    switch ((value ?? '').toLowerCase().trim()) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  Future<void> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    // Prefer per-user theme mode if we have a last-known username.
    var lastUser = (prefs.getString('username') ?? '').trim();
    String? themeFromUserDetails;
    // Back-compat: older builds did not persist 'username' separately.
    // Fall back to the persisted user_details blob.
    if (lastUser.isEmpty) {
      try {
        final raw = prefs.getString('user_details');
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          final u = (decoded is Map ? (decoded['username'] ?? '') : '')
              .toString()
              .trim();
          themeFromUserDetails = (decoded is Map
                  ? (decoded['themeMode'] ?? decoded['theme_mode'] ?? '')
                  : '')
              .toString();
          if (u.isNotEmpty) {
            lastUser = u;
            // Cache for next startup.
            await prefs.setString('username', lastUser);
          }
        }
      } catch (_) {
        // ignore
      }
    }
    // Theme is account-scoped. If logged out (no username), default to light.
    // Avoid the legacy global key here; it causes cross-account leakage.
    final stored = lastUser.isNotEmpty
        ? prefs.getString(_prefsThemeModeKeyForUser(lastUser))
        : null;
    // If the per-user theme key is missing, fall back to what was persisted in user_details.
    // Also seed the per-user key so the next cold start is stable.
    final fallback =
        (stored == null || stored.trim().isEmpty) ? themeFromUserDetails : null;
    final next = _decodeThemeMode(stored ?? fallback);

    assert(() {
      debugPrint(
        '[theme] loadThemeMode: username=$lastUser stored=$stored fallback=$fallback next=${_encodeThemeMode(next)}',
      );
      return true;
    }());

    if (lastUser.isNotEmpty &&
        (stored == null || stored.trim().isEmpty) &&
        (fallback ?? '').trim().isNotEmpty) {
      try {
        await prefs.setString(
            _prefsThemeModeKeyForUser(lastUser), _encodeThemeMode(next));
      } catch (_) {}
    }
    if (next == _themeMode) return;
    _themeMode = next;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode, {bool syncToServer = false}) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final encoded = _encodeThemeMode(mode);
    final u = (username ?? prefs.getString('username') ?? '').trim();
    if (u.isNotEmpty) {
      await prefs.setString(_prefsThemeModeKeyForUser(u), encoded);
    }

    assert(() {
      debugPrint(
          '[theme] setThemeMode: username=$u encoded=$encoded syncToServer=$syncToServer');
      return true;
    }());

    if (!syncToServer) return;

    // Server sync (best-effort). If it fails (offline, token missing, etc.),
    // keep a pending value to retry later.
    final hasAuth = (token ?? '').trim().isNotEmpty;
    if (!hasAuth) {
      await prefs.setString(_prefsThemeModePendingKey, encoded);
      return;
    }
    final ok = await ApiService.updateMyThemeMode(encoded);
    if (ok) {
      await prefs.remove(_prefsThemeModePendingKey);
    } else {
      await prefs.setString(_prefsThemeModePendingKey, encoded);
    }
  }

  Future<void> flushPendingThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final pending =
        (prefs.getString(_prefsThemeModePendingKey) ?? '').trim().toLowerCase();
    if (pending.isEmpty) return;
    final hasAuth = (token ?? '').trim().isNotEmpty;
    if (!hasAuth) return;
    final ok = await ApiService.updateMyThemeMode(pending);
    if (ok) {
      await prefs.remove(_prefsThemeModePendingKey);
    }
  }

  Future<void> applyThemeModeFromServerIfNeeded(dynamic serverThemeMode) async {
    final prefs = await SharedPreferences.getInstance();

    final rawServer = (serverThemeMode?.toString() ?? '').trim();
    if (rawServer.isEmpty) return;

    // If there's a pending local choice to sync, don't override it with server data.
    final pending = (prefs.getString(_prefsThemeModePendingKey) ?? '').trim();
    if (pending.isNotEmpty) return;

    // If we already have a local preference for this device/user, keep it.
    final u = (username ?? prefs.getString('username') ?? '').trim();
    final hasLocalPreference =
        u.isNotEmpty ? prefs.containsKey(_prefsThemeModeKeyForUser(u)) : false;
    if (hasLocalPreference) return;

    final decoded = _decodeThemeMode(rawServer);
    // Set locally only (server is already the source of truth here).
    await setThemeMode(decoded, syncToServer: false);
  }

  /// Apply theme_mode coming from the backend as the account source-of-truth.
  ///
  /// Use this right after login / auto-login so switching accounts on the same
  /// device always picks the correct theme.
  ///
  /// If there is a pending local preference to sync (offline), we do NOT
  /// override it.
  Future<void> applyThemeModeFromServer(dynamic serverThemeMode) async {
    final prefs = await SharedPreferences.getInstance();

    final rawServer = (serverThemeMode?.toString() ?? '').trim();
    if (rawServer.isEmpty) return;

    // If there's a pending local choice to sync, don't override it with server data.
    final pending = (prefs.getString(_prefsThemeModePendingKey) ?? '').trim();
    if (pending.isNotEmpty) return;

    final decoded = _decodeThemeMode(rawServer);
    await setThemeMode(decoded, syncToServer: false);
  }

  String _canonicalTreatment(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final s = raw.toLowerCase();
    // Back-compat aliases
    if (s == 'prosthesis') return 'Prosthesis Fitted';
    return raw;
  }

  String _canonicalSubtype(String? treatment, String? value) {
    final t = _canonicalTreatment(treatment);
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final s = raw.toLowerCase();

    if (t == 'Prosthesis Fitted') {
      if (s == 'fixed' || s == 'fixed denture' || s == 'fixed dentures')
        return 'Fixed Dentures';
      if (s == 'removable' ||
          s == 'removable denture' ||
          s == 'removable dentures') return 'Removable Dentures';
    }
    return raw;
  }

  String _canonicalGroup(String? value) => (value ?? '').trim().toLowerCase();

  String _canonicalInstructionText(String? value) {
    return (value ?? '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('–', '-')
        .replaceAll('—', '-');
  }

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
    final selected =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final procLocal =
        proc != null ? DateTime(proc.year, proc.month, proc.day) : selected;
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
  int? patientId;
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
      department != null &&
      department!.isNotEmpty &&
      doctor != null &&
      doctor!.isNotEmpty &&
      treatment != null &&
      treatment!.isNotEmpty &&
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
        final stored =
            prefs.getString(_checklistStorageKey(k, username: username));
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
      try {
        targetKeys = List<String>.from(jsonDecode(targetRegJson));
      } catch (_) {
        targetKeys = [];
      }
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

  Future<void> _saveChecklistForKey(String key, List<bool> list,
      {String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    // Save value
    await prefs.setString(
        _checklistStorageKey(key, username: username), jsonEncode(list));
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
  Future<void>? _pullInstructionStatusInFlight;

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  bool isInstructionFollowedForDay({
    required DateTime day,
    required String type,
    required int instructionIndex,
    String? instructionText,
    String? username,
    String? treatment,
    String? subtype,
  }) {
    final dateStr = formatYMD(day);
    final user = (username ?? this.username ?? '').trim();
    final treat = _canonicalTreatment((treatment ?? _treatment ?? '').trim());
    final sub =
        _canonicalSubtype(treat, (subtype ?? _treatmentSubtype ?? '').trim());

    String norm(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final wantedText = instructionText == null ? null : norm(instructionText);

    bool anyFollowed = false;
    for (final log in _instructionLogs) {
      if ((log['date'] ?? '').toString() != dateStr) continue;
      if (_canonicalGroup((log['type'] ?? '').toString()) !=
          _canonicalGroup(type)) continue;
      if ((log['username'] ?? '').toString() != user) continue;

      final logTreat = _canonicalTreatment((log['treatment'] ?? '').toString());
      final logSub =
          _canonicalSubtype(logTreat, (log['subtype'] ?? '').toString());
      if (treat.isNotEmpty && logTreat != treat) continue;
      if (sub.isNotEmpty && logSub != sub) continue;

      final localIdx = _asInt(log['instruction_index']);
      final matchesIdx = (localIdx != null && localIdx == instructionIndex);
      bool matchesText = false;
      if (!matchesIdx && wantedText != null && wantedText.isNotEmpty) {
        final localText = (log['instruction'] ?? log['note'] ?? '').toString();
        matchesText = norm(localText) == wantedText;
      }
      if (!matchesIdx && !matchesText) continue;

      final followed =
          log['followed'] == true || log['followed']?.toString() == 'true';
      anyFollowed = anyFollowed || followed;
    }
    return anyFollowed;
  }

  List<bool> buildFollowedChecklistForDay({
    required DateTime day,
    required String type,
    required int length,
    required String Function(int index) instructionTextForIndex,
    String? username,
    String? treatment,
    String? subtype,
  }) {
    return List<bool>.generate(
      length,
      (i) => isInstructionFollowedForDay(
        day: day,
        type: type,
        instructionIndex: i,
        instructionText: instructionTextForIndex(i),
        username: username,
        treatment: treatment,
        subtype: subtype,
      ),
    );
  }

  // Serialize instruction-log mutations because many screens fire multiple
  // addInstructionLog() calls without awaiting them (race condition -> duplicates).
  Future<void> _instructionLogOp = Future<void>.value();

  Timer? _pendingUploadFlushTimer;
  bool _pendingUploadFlushInProgress = false;
  static const Duration _pendingUploadFlushInterval = Duration(seconds: 30);

  void _startPendingUploadFlushLoop() {
    _pendingUploadFlushTimer?.cancel();
    _pendingUploadFlushTimer = null;

    final user = (username ?? '').trim();
    if (user.isEmpty) return;
    if (token == null || token!.isEmpty) return;

    _pendingUploadFlushTimer =
        Timer.periodic(_pendingUploadFlushInterval, (_) async {
      if (_pendingUploadFlushInProgress) return;
      if (token == null || token!.isEmpty) return;
      final u = (username ?? '').trim();
      if (u.isEmpty) return;

      _pendingUploadFlushInProgress = true;
      try {
        await flushPendingInstructionUploads(username: u);
      } finally {
        _pendingUploadFlushInProgress = false;
      }
    });
  }

  void _stopPendingUploadFlushLoop() {
    _pendingUploadFlushTimer?.cancel();
    _pendingUploadFlushTimer = null;
    _pendingUploadFlushInProgress = false;
  }

  String? _instructionLogsLoadedForUser;
  bool _instructionLogsHydrated = false;

  List<Map<String, dynamic>> get instructionLogs =>
      List.unmodifiable(_instructionLogs);

  Future<void> resetLocalStateForTreatmentReplacement(
      {String? username}) async {
    final user = username ?? this.username;
    // Clear instruction log cache so old treatment rows can't pollute UI.
    _instructionLogs.clear();
    _instructionLogsHydrated = false;
    _instructionLogsLoadedForUser = null;
    _lastInstructionSyncUtc = null;
    _pendingInstructionBatches.clear();
    _pendingBatchTouched.clear();
    _batchTimer?.cancel();
    _batchTimer = null;
    if (user != null && user.isNotEmpty) {
      await _saveInstructionLogs(username: user);
    }
    notifyListeners();
  }

  Future<void> _saveInstructionLogs({String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    final key =
        username != null ? 'instruction_logs_${username}' : 'instruction_logs';
    await prefs.setString(key, jsonEncode(_instructionLogs));
  }

  Future<void> loadInstructionLogs(
      {String? username, bool force = false}) async {
    final userKey = (username ?? this.username)?.toString();
    if (!force &&
        _instructionLogsHydrated &&
        _instructionLogsLoadedForUser == userKey) {
      return;
    }

    final wasHydrated = _instructionLogsHydrated;

    final prefs = await SharedPreferences.getInstance();
    final key =
        username != null ? 'instruction_logs_${username}' : 'instruction_logs';
    final data = prefs.getString(key);
    final legacy = prefs.getString('instruction_logs'); // migrate if present

    // If we already have logs in-memory and there is no persisted data to read or migrate,
    // just mark hydrated and return.
    if (!force &&
        data == null &&
        legacy == null &&
        _instructionLogs.isNotEmpty) {
      _instructionLogsHydrated = true;
      _instructionLogsLoadedForUser = userKey;
      return;
    }

    final beforeCount = _instructionLogs.length;
    _instructionLogs.clear();
    if (data != null) {
      final List<dynamic> decoded = jsonDecode(data);
      for (var item in decoded) {
        final user = (item['username'] ?? username ?? '').toString();
        final type = _canonicalGroup(item['type'] ?? '');
        final treat = _canonicalTreatment(item['treatment']);
        final sub = _canonicalSubtype(treat, item['subtype']);
        final instruction = _canonicalInstructionText(
            item['instruction'] ?? item['note'] ?? '');
        _instructionLogs.add({
          'date': item['date'] ?? '',
          'note': item['note'] ?? '',
          'type': type,
          'followed': item['followed'] ?? false,
          'instruction': instruction,
          'username': user,
          'treatment': treat,
          'subtype': sub,
          'everFollowed': item['everFollowed'] ?? (item['followed'] ?? false),
          'updated_at': item['updated_at'] ?? item['updatedAt'],
          'instruction_index':
              item['instruction_index'] ?? item['instructionIndex'],
          'quarantined': item['quarantined'] ?? false,
        });
      }
    }
    // Merge legacy logs (without username scoping) once
    if (legacy != null) {
      try {
        final List<dynamic> decoded = jsonDecode(legacy);
        for (var item in decoded) {
          final user = (item['username'] ?? username ?? '').toString();
          final type = _canonicalGroup(item['type'] ?? '');
          final treat = _canonicalTreatment(item['treatment']);
          final sub = _canonicalSubtype(treat, item['subtype']);
          final instruction = _canonicalInstructionText(
              item['instruction'] ?? item['note'] ?? '');
          final m = {
            'date': item['date'] ?? '',
            'note': item['note'] ?? '',
            'type': type,
            'followed': item['followed'] ?? false,
            'instruction': instruction,
            'username': user,
            'treatment': treat,
            'subtype': sub,
            'updated_at': item['updated_at'] ?? item['updatedAt'],
            'instruction_index':
                item['instruction_index'] ?? item['instructionIndex'],
            'quarantined': item['quarantined'] ?? false,
          };
          // Avoid duplicates
          final exists = _instructionLogs.any(
            (e) =>
                e['date'] == m['date'] &&
                e['instruction'] == m['instruction'] &&
                e['type'] == m['type'] &&
                e['username'] == m['username'],
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

    // Normalize + de-dupe persisted logs (fixes "Prosthesis" vs "Prosthesis Fitted" stacking).
    final before = _instructionLogs.length;
    _normalizeAndDedupeInstructionLogs();
    final after = _instructionLogs.length;
    if (before != after) {
      debugPrint('[InstructionLogs] normalized+deduped: $before -> $after');
    }

    // Avoid unnecessary writes/notifications when nothing actually changed.
    final didChange = force ||
        !wasHydrated ||
        beforeCount != _instructionLogs.length ||
        legacy != null;

    _instructionLogsHydrated = true;
    _instructionLogsLoadedForUser = userKey;
    if (didChange) {
      await _saveInstructionLogs(username: username ?? this.username);
      debugPrint(
          'Loaded instruction logs for $username: count = \${_instructionLogs.length}');
      notifyListeners();
    }
  }

  // --- Quarantine / allowlist for known-bad legacy data ---
  static String _normAllowlistText(String s) {
    return s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('–', '-')
        .replaceAll('—', '-');
  }

  static final Set<String> _pfdFixedAllowedGeneral = {
    // English
    'Whenever local anesthesia is used, avoid chewing on your teeth until the numbness has worn off.',
    'Proper brushing, flossing, and regular cleanings are necessary to maintain the restoration.',
    'Pay special attention to your gumline.',
    'Avoid very hot or hard foods.',
    // Marathi
    'स्थानिक भूल दिल्यानंतर, सुन्नपणा जाईपर्यंत दातांवर चावणे टाळा.',
    'पुनर्स्थापना टिकवण्यासाठी योग्य ब्रशिंग, फ्लॉसिंग आणि नियमित स्वच्छता आवश्यक आहे.',
    'तुमच्या हिरड्यांच्या सीमेकडे विशेष लक्ष द्या.',
    'अतिशय गरम किंवा कडक अन्न टाळा.',
  }.map(_normAllowlistText).toSet();

  static final Set<String> _pfdFixedAllowedSpecific = {
    // English
    'If your bite feels high or uncomfortable, contact your dentist for an adjustment.',
    'If the restoration feels loose or comes off, keep it safe and contact your dentist. Do not try to glue it yourself.',
    'Clean carefully around the restoration and gumline; use floss/interdental aids as advised by your dentist.',
    'If you notice persistent pain, swelling, or bleeding, contact your dentist.',
    // Marathi
    'चावताना दात उंच वाटत असतील किंवा अस्वस्थ वाटत असेल, समायोजनासाठी दंतवैद्याशी संपर्क साधा.',
    'पुनर्स्थापना सैल वाटली किंवा निघाली तर ती सुरक्षित ठेवा आणि दंतवैद्याशी संपर्क साधा. स्वतः चिकटवण्याचा प्रयत्न करू नका.',
    'पुनर्स्थापना व हिरड्यांच्या सीमेजवळ नीट स्वच्छता ठेवा; दंतवैद्याने सांगितल्याप्रमाणे फ्लॉस/इंटरडेंटल साधने वापरा.',
    'दुखणे, सूज किंवा रक्तस्राव सतत राहिल्यास दंतवैद्याशी संपर्क साधा.',
  }.map(_normAllowlistText).toSet();

  bool _isAllowedForPfdFixed({
    required String treatment,
    required String subtype,
    required String group,
    required String instruction,
  }) {
    if (!(treatment == 'Prosthesis Fitted' && subtype == 'Fixed Dentures'))
      return true;
    final type = _canonicalGroup(group);
    final n = _normAllowlistText(instruction);
    if (type == 'general') return _pfdFixedAllowedGeneral.contains(n);
    if (type == 'specific') return _pfdFixedAllowedSpecific.contains(n);
    return true;
  }

  void _normalizeAndDedupeInstructionLogs() {
    final Map<String, Map<String, dynamic>> latest = {};

    DateTime? parseIsoUtcLocal(dynamic s) {
      if (s == null) return null;
      final str = s.toString();
      if (str.trim().isEmpty) return null;
      try {
        return DateTime.parse(str).toUtc();
      } catch (_) {
        return null;
      }
    }

    String normKeyText(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    // First pass: build a lookup from (date,user,treat,sub,type,text) -> preferred index.
    // This lets us merge legacy/server rows that have a different/missing instruction_index.
    final Map<String, int> preferredIndexByTextKey = {};
    for (final raw in _instructionLogs) {
      final date = (raw['date'] ?? '').toString();
      final user = (raw['username'] ?? '').toString();
      final type = _canonicalGroup(raw['type']?.toString());
      final treat = _canonicalTreatment(raw['treatment']?.toString());
      final sub = _canonicalSubtype(treat, raw['subtype']?.toString());
      final instruction = _canonicalInstructionText(
          (raw['instruction'] ?? raw['note'] ?? '').toString());
      final allowed = _isAllowedForPfdFixed(
          treatment: treat,
          subtype: sub,
          group: type,
          instruction: instruction);
      if (!allowed) continue;
      final idx = _asInt(raw['instruction_index'] ?? raw['instructionIndex']);
      if (idx == null) continue;
      final textKey =
          '$date|$user|$treat|$sub|$type|${normKeyText(instruction)}';
      preferredIndexByTextKey.putIfAbsent(textKey, () => idx);
    }

    for (final raw in _instructionLogs) {
      final date = (raw['date'] ?? '').toString();
      final user = (raw['username'] ?? '').toString();
      final type = _canonicalGroup(raw['type']?.toString());
      String treat = _canonicalTreatment(raw['treatment']?.toString());
      String sub = _canonicalSubtype(treat, raw['subtype']?.toString());
      final instruction = _canonicalInstructionText(
          (raw['instruction'] ?? raw['note'] ?? '').toString());
      int? idx = _asInt(raw['instruction_index'] ?? raw['instructionIndex']);

      final allowed = _isAllowedForPfdFixed(
          treatment: treat,
          subtype: sub,
          group: type,
          instruction: instruction);
      final quarantined = !allowed;
      if (quarantined) {
        // Keep the text/history but un-assign it from PFD Fixed so it never pollutes progress.
        treat = '';
        sub = '';
      }

      final followed =
          raw['followed'] == true || raw['followed']?.toString() == 'true';
      final prevEver = raw['everFollowed'] == true ||
          raw['everFollowed']?.toString() == 'true';
      final ever = followed || prevEver;

        final updatedAtStr = (raw['updated_at'] ?? raw['updatedAt'])?.toString();
        final updatedAt = parseIsoUtcLocal(updatedAtStr);

      // If index is missing (or differs across sources), try to adopt the preferred index for the same text.
      final textKey =
          '$date|$user|$treat|$sub|$type|${normKeyText(instruction)}';
      idx = idx ?? preferredIndexByTextKey[textKey];
      idx = idx ?? stableInstructionIndex(type, instruction);

      // Use the (possibly adopted) index for the dedupe key.
      final key = '$date|$user|$treat|$sub|$type|#${idx.toString()}';

      final entry = {
        'date': date,
        'note': instruction,
        'type': type,
        'followed': followed,
        'instruction': instruction,
        'username': user,
        'treatment': treat,
        'subtype': sub,
        'instruction_index': idx,
        'everFollowed': ever,
        'updated_at': updatedAtStr,
        'quarantined': quarantined,
      };

      final prev = latest[key];
      if (prev == null) {
        latest[key] = entry;
        continue;
      }

      // Prefer the newest row by updated_at; always merge everFollowed.
        final prevUpdatedAt =
          parseIsoUtcLocal(prev['updated_at'] ?? prev['updatedAt']);

      final mergedEver =
          (prev['everFollowed'] == true) || (entry['everFollowed'] == true);

      final keepPrev = prevUpdatedAt != null &&
          (updatedAt == null || prevUpdatedAt.isAfter(updatedAt));
      if (keepPrev) {
        prev['everFollowed'] = mergedEver;
        latest[key] = prev;
      } else {
        entry['everFollowed'] = mergedEver;
        latest[key] = entry;
      }
    }

    _instructionLogs
      ..clear()
      ..addAll(latest.values);
  }

  DateTime? get lastInstructionSyncUtc => _lastInstructionSyncUtc;

  Future<void> pullInstructionStatusChanges() {
    final existing = _pullInstructionStatusInFlight;
    if (existing != null) return existing;
    final fut = _pullInstructionStatusChangesInternal();
    _pullInstructionStatusInFlight = fut;
    return fut.whenComplete(() {
      _pullInstructionStatusInFlight = null;
    });
  }

  Future<void> _pullInstructionStatusChangesInternal() async {
    try {
      if (token == null) return; // not logged in

      final initialSince =
          DateTime.now().toUtc().subtract(const Duration(days: 60));
      final since = (_lastInstructionSyncUtc ?? initialSince).toIso8601String();

      Future<List<Map<String, dynamic>>?> retryChanges() async {
        for (int attempt = 0; attempt < 3; attempt++) {
          final res =
              await ApiService.fetchInstructionStatusChanges(sinceIso: since);
          if (res != null) return res;
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
        return null;
      }

      Future<List<Map<String, dynamic>>?> retryRange(
          String dateFrom, String dateTo) async {
        for (int attempt = 0; attempt < 2; attempt++) {
          final res = await ApiService.listInstructionStatus(
              dateFrom: dateFrom, dateTo: dateTo);
          if (res != null) return res;
          await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
        }
        return null;
      }

      List<Map<String, dynamic>>? changes = await retryChanges();

      if (changes == null) {
        final from = DateTime.now().subtract(const Duration(days: 60));
        final dateFrom = _ymd.format(from);
        final dateTo = _ymd.format(DateTime.now());
        final range = await retryRange(dateFrom, dateTo);
        if (range != null) {
          changes = range
              .map(
                (row) => {
                  'date': (row['date'] ?? '').toString(),
                  'group': (row['group'] ?? row['type'] ?? '').toString(),
                  'instruction_text': (row['instruction_text'] ??
                          row['instruction'] ??
                          row['note'] ??
                          '')
                      .toString(),
                  'followed': row['followed'] == true ||
                      row['followed']?.toString() == 'true',
                  'ever_followed': row['ever_followed'] == true ||
                      row['ever_followed']?.toString() == 'true',
                  'treatment': row['treatment'] ?? '',
                  'subtype': row['subtype'],
                  'instruction_index': row['instruction_index'] ??
                      stableInstructionIndex(
                        (row['group'] ?? '').toString(),
                        (row['instruction_text'] ?? '').toString(),
                      ),
                  'updated_at': row['updated_at']?.toString(),
                },
              )
              .toList();
        }
      }

      if (changes == null || changes.isEmpty) return;

      bool changed = false;
      DateTime maxTs = _lastInstructionSyncUtc ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

      String normType(String s) => s.trim().toLowerCase();

      String normText(String s) {
        return s
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll('–', '-')
            .replaceAll('—', '-');
      }

      DateTime? parseIsoUtc(dynamic s) {
        if (s == null) return null;
        final str = s.toString();
        if (str.trim().isEmpty) return null;
        try {
          return DateTime.parse(str).toUtc();
        } catch (_) {
          return null;
        }
      }

      int? asInt(dynamic v) {
        if (v is int) return v;
        return int.tryParse(v?.toString() ?? '');
      }

      for (final row in changes) {
        final date = (row['date'] ?? '').toString();
        final rawType = (row['group'] ?? row['type'] ?? '').toString();
        final type = normType(rawType);
        final instruction = _canonicalInstructionText(
          (row['instruction_text'] ?? row['instruction'] ?? row['note'] ?? '')
              .toString(),
        );
        final followed =
            row['followed'] == true || row['followed']?.toString() == 'true';
        final everFollowed = row['ever_followed'] == true ||
            row['ever_followed']?.toString() == 'true';
        final updatedAtStr = row['updated_at']?.toString();
        DateTime? updatedAt;
        try {
          if (updatedAtStr != null) {
            updatedAt = DateTime.parse(updatedAtStr).toUtc();
          }
        } catch (_) {
          updatedAt = null;
        }
        if (updatedAt != null && updatedAt.isAfter(maxTs)) maxTs = updatedAt;
        // Keep missing treatment/subtype as empty.
        // Filling them from current state can mis-attribute old rows to the wrong treatment.
        final normTreatment =
            _canonicalTreatment((row['treatment'] ?? '').toString());
        final normSubtype =
            _canonicalSubtype(normTreatment, (row['subtype'] ?? '').toString());
        final quarantined = !_isAllowedForPfdFixed(
          treatment: normTreatment,
          subtype: normSubtype,
          group: type,
          instruction: instruction,
        );

        // Use original treatment/subtype for matching/removal, but store quarantined rows as unassigned.
        final matchTreatment = normTreatment;
        final matchSubtype = normSubtype;
        final storeTreatment = quarantined ? '' : normTreatment;
        final storeSubtype = quarantined ? '' : normSubtype;
        final incomingIdx =
            asInt(row['instruction_index'] ?? row['instructionIndex']);
        final canonicalIdx =
            incomingIdx ?? stableInstructionIndex(type, instruction);

        bool matchesOrEmpty(dynamic a, dynamic b) {
          // Strict match (treat null as empty). Avoid wildcard matching that can mix treatments.
          final aa = (a ?? '').toString();
          final bb = (b ?? '').toString();
          return aa == bb;
        }

        // Replace local entry by composite key, but also remove *all* duplicates.
        // Normalize type/text to avoid "General" vs "general" or punctuation variants causing stacking.
        final matchIndices = <int>[];
        for (int i = 0; i < _instructionLogs.length; i++) {
          final e = _instructionLogs[i];
          if ((e['date'] ?? '').toString() != date) continue;
          if (normType((e['type'] ?? '').toString()) != type) continue;
          if ((e['username'] ?? '').toString() !=
              (username ?? this.username ?? '')) continue;
          if (!matchesOrEmpty(e['treatment'], matchTreatment)) continue;
          if (!matchesOrEmpty(e['subtype'], matchSubtype)) continue;

          final localIdx =
              asInt(e['instruction_index'] ?? e['instructionIndex']);
          if (localIdx != null && localIdx == canonicalIdx) {
            matchIndices.add(i);
            continue;
          }

          // Text match should dedupe even if instruction_index differs across sources.
          final localText = (e['instruction'] ?? e['note'] ?? '').toString();
          if (normText(localText) == normText(instruction)) {
            matchIndices.add(i);
          }
        }

        // Last-write-wins: do not let an older server row overwrite a newer local change.
        int? bestLocalIndex;
        DateTime? bestLocalUpdatedAt;
        for (final i in matchIndices) {
          final ts =
              parseIsoUtc(_instructionLogs[i]['updated_at'] ?? _instructionLogs[i]['updatedAt']);
          if (ts == null) continue;
          if (bestLocalUpdatedAt == null || ts.isAfter(bestLocalUpdatedAt)) {
            bestLocalUpdatedAt = ts;
            bestLocalIndex = i;
          }
        }

        final keepLocal = bestLocalUpdatedAt != null &&
            (updatedAt == null || bestLocalUpdatedAt.isAfter(updatedAt));
        if (keepLocal) {
          // Remove duplicates but keep the newest local row.
          for (final i in matchIndices.reversed) {
            if (i == bestLocalIndex) continue;
            _instructionLogs.removeAt(i);
            changed = true;
            if (bestLocalIndex != null && i < bestLocalIndex) {
              bestLocalIndex = bestLocalIndex - 1;
            }
          }

          // Still merge everFollowed from the server row.
          if (bestLocalIndex != null) {
            final existing = _instructionLogs[bestLocalIndex];
            final prevEver = existing['everFollowed'] == true ||
                existing['everFollowed']?.toString() == 'true';
            final mergedEver = prevEver || everFollowed || followed;
            if (mergedEver != prevEver) {
              existing['everFollowed'] = true;
              changed = true;
            }
          }
          continue;
        }

        for (final i in matchIndices.reversed) {
          _instructionLogs.removeAt(i);
        }
        final entry = {
          'date': date,
          'note': instruction,
          'type': type,
          'followed': followed,
          'instruction': instruction,
          'username': username ?? this.username ?? '',
          'treatment': storeTreatment,
          'subtype': storeSubtype,
          'everFollowed': everFollowed || followed,
          'updated_at': updatedAt?.toIso8601String(),
          'instruction_index': canonicalIdx,
          'quarantined': quarantined,
        };
        _instructionLogs.add(entry);
        changed = true;
      }
      if (changed) {
        _normalizeAndDedupeInstructionLogs();
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
    int? instructionIndex,
  }) async {
    // Ensure all callers (even those not awaiting) mutate logs serially.
    _instructionLogOp = _instructionLogOp.then((_) async {
      final now = DateTime.now();
      final formattedDate = date ??
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final user = username ?? this.username ?? '';
      String treat = _canonicalTreatment(treatment ?? _treatment ?? '');
      String sub = _canonicalSubtype(treat, subtype ?? _treatmentSubtype ?? '');
      final String typeCanon = _canonicalGroup(type);
      final instruction = _canonicalInstructionText(note);
      final idx =
          instructionIndex ?? stableInstructionIndex(typeCanon, instruction);
      final quarantined = !_isAllowedForPfdFixed(
          treatment: treat,
          subtype: sub,
          group: typeCanon,
          instruction: instruction);
      if (quarantined) {
        treat = '';
        sub = '';
      }

      String norm(String s) =>
          s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

      bool sameRow(Map<String, dynamic> log) {
        if ((log['date'] ?? '').toString() != formattedDate) return false;
        if (_canonicalGroup((log['type'] ?? '').toString()) != typeCanon)
          return false;
        if ((log['username'] ?? '').toString() != user) return false;

        final logTreat =
            _canonicalTreatment((log['treatment'] ?? '').toString());
        final logSub =
            _canonicalSubtype(logTreat, (log['subtype'] ?? '').toString());
        if (treat.isNotEmpty && logTreat != treat) return false;
        if (sub.isNotEmpty && logSub != sub) return false;

        final localIdx = log['instruction_index'];
        final localInt = localIdx is int
            ? localIdx
            : int.tryParse(localIdx?.toString() ?? '');
        if (localInt != null && localInt == idx) return true;

        final localText = (log['instruction'] ?? log['note'] ?? '').toString();
        return norm(localText) == norm(instruction);
      }

      final matchIndices = <int>[];
      bool anyPrevFollowed = false;
      bool anyPrevEver = false;
      String? adoptTreatment;
      String? adoptSubtype;

      for (int i = 0; i < _instructionLogs.length; i++) {
        final log = _instructionLogs[i];
        if (!sameRow(log)) continue;
        matchIndices.add(i);
        final prevFollowed =
            log['followed'] == true || log['followed']?.toString() == 'true';
        final prevEver = log['everFollowed'] == true ||
            log['everFollowed']?.toString() == 'true';
        anyPrevFollowed = anyPrevFollowed || prevFollowed;
        anyPrevEver = anyPrevEver || prevEver || prevFollowed;
        final lt = (log['treatment'] ?? '').toString();
        final ls = (log['subtype'] ?? '').toString();
        if (adoptTreatment == null && lt.isNotEmpty) adoptTreatment = lt;
        if (adoptSubtype == null && ls.isNotEmpty) adoptSubtype = ls;
      }

      // If caller didn't pass treatment/subtype (or state not hydrated yet), adopt from existing.
      if (treat.isEmpty && adoptTreatment != null) treat = adoptTreatment;
      if (sub.isEmpty && adoptSubtype != null) sub = adoptSubtype;

      // Remove ALL prior matches to prevent stacking.
      for (final i in matchIndices.reversed) {
        _instructionLogs.removeAt(i);
      }

      final entry = {
        'date': formattedDate,
        'note': instruction,
        'type': typeCanon,
        'followed': followed,
        'instruction': instruction,
        'username': user,
        'treatment': treat,
        'subtype': sub,
        'instruction_index': idx,
        'everFollowed': followed || anyPrevEver,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'quarantined': quarantined,
      };

      _instructionLogs.add(entry);
      _normalizeAndDedupeInstructionLogs();
      await _saveInstructionLogs(username: user);
      notifyListeners();
      // Queue for debounced batch sync instead of immediate single-row POST.
      _queueInstructionEntryForBatch(entry);
    });

    // Await the queued operation so callers that DO await remain correct.
    await _instructionLogOp;
  }

  // Explicit method if caller wants to ensure sync completion
  Future<bool> addInstructionLogAndSync(
    String note, {
    String? date,
    String type = '',
    bool followed = false,
    String? username,
    String? treatment,
    String? subtype,
  }) async {
    await addInstructionLog(
      note,
      date: date,
      type: type,
      followed: followed,
      username: username,
      treatment: treatment,
      subtype: subtype,
    );
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
  final Map<String, Map<int, Map<String, dynamic>>> _pendingInstructionBatches =
      {};
  final Map<String, DateTime> _pendingBatchTouched = {};
  Timer? _batchTimer;
  static const Duration _batchDebounce = Duration(milliseconds: 500);

  void _queueInstructionEntryForBatch(Map<String, dynamic> entry) {
    final date = (entry['date'] ?? '').toString();
    final group = (entry['type'] ?? entry['group'] ?? '').toString();
    final idx =
        _asInt(entry['instruction_index'] ?? entry['instructionIndex']) ?? 0;
    if (date.isEmpty || group.isEmpty) {
      // Fallback: send immediately if something is malformed
      _syncInstructionEntry(entry);
      return;
    }
    final key = '$date|$group';
    _pendingInstructionBatches.putIfAbsent(key, () => {});
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
        final ok = await _postInstructionItems(items);
        if (ok) {
          debugPrint(
              '[InstructionBatch] Uploaded ${items.length} items for $k');
        } else {
          throw Exception('saveInstructionStatus returned false');
        }
      } catch (e) {
        debugPrint('[InstructionBatch][error] $k -> $e');
        // Requeue on failure (optional with simple retry strategy)
        _pendingInstructionBatches[k] = {
          for (final it in items) it['instruction_index']: it
        };
        _pendingBatchTouched[k] = DateTime.now();
        _scheduleBatchFlush();
      }
    }
  }

  String _pendingInstructionUploadStorageKey(String user) =>
      'pending_instruction_uploads_${user}';

  String _pendingUploadItemKey(Map<String, dynamic> e) {
    final date = (e['date'] ?? '').toString();
    final group = (e['group'] ?? e['type'] ?? '').toString();
    final idx = _asInt(e['instruction_index'] ?? e['instructionIndex']) ?? 0;
    final treatment = (e['treatment'] ?? '').toString();
    final subtype = (e['subtype'] ?? '').toString();
    return '$date|$group|#${idx.toString()}|$treatment|$subtype';
  }

  Future<void> _enqueuePendingInstructionUploads(
      List<Map<String, dynamic>> payloadItems,
      {String? username}) async {
    final user = (username ?? this.username ?? '').trim();
    if (user.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _pendingInstructionUploadStorageKey(user);
      final existingStr = prefs.getString(key);
      final Map<String, Map<String, dynamic>> merged = {};
      if (existingStr != null && existingStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(existingStr);
          if (decoded is List) {
            for (final it in decoded) {
              if (it is Map) {
                final m = Map<String, dynamic>.from(it);
                merged[_pendingUploadItemKey(m)] = m;
              }
            }
          }
        } catch (_) {
          // ignore corrupt queue
        }
      }
      for (final it in payloadItems) {
        merged[_pendingUploadItemKey(it)] = it;
      }
      await prefs.setString(key, jsonEncode(merged.values.toList()));
    } catch (e) {
      debugPrint('[PendingUpload] enqueue failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadPendingInstructionUploads(
      {String? username}) async {
    final user = (username ?? this.username ?? '').trim();
    if (user.isEmpty) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _pendingInstructionUploadStorageKey(user);
      final s = prefs.getString(key);
      if (s == null || s.isEmpty) return const [];
      final decoded = jsonDecode(s);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _clearPendingInstructionUploads({String? username}) async {
    final user = (username ?? this.username ?? '').trim();
    if (user.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingInstructionUploadStorageKey(user));
    } catch (_) {}
  }

  Future<void> flushPendingInstructionUploads({String? username}) async {
    final user = (username ?? this.username ?? '').trim();
    if (user.isEmpty) return;
    if (token == null || token!.isEmpty) return;
    final pending = await _loadPendingInstructionUploads(username: user);
    if (pending.isEmpty) return;

    // Send in chunks to avoid huge payloads on slow networks.
    const int chunkSize = 200;
    int offset = 0;
    while (offset < pending.length) {
      final chunk = pending.sublist(
          offset, (offset + chunkSize).clamp(0, pending.length));
      final ok = await ApiService.saveInstructionStatus(chunk);
      if (!ok) {
        // Keep queue for later retries.
        return;
      }
      offset += chunk.length;
    }
    await _clearPendingInstructionUploads(username: user);
  }

  Future<bool> _postInstructionItems(List<Map<String, dynamic>> items) async {
    try {
      final filtered = items.where((e) {
        final q = e['quarantined'];
        return !(q == true || q?.toString() == 'true');
      }).toList();

      if (filtered.isEmpty) return true;
      // Map entry to backend expected shape. addInstructionLog already added instruction_index.
      final payloadItems = filtered
          .map(
            (e) => {
              'date': e['date'],
              'treatment': e['treatment'] ?? '',
              'subtype': e['subtype'],
              'group': e['type'] ?? e['group'] ?? '',
              'instruction_index': e['instruction_index'] ?? 0,
              'instruction_text': e['instruction'] ?? e['note'] ?? '',
              'followed': e['followed'] ?? false,
              'ever_followed': (e['everFollowed'] == true ||
                  e['everFollowed']?.toString() == 'true'),
            },
          )
          .toList();
      final ok = await ApiService.saveInstructionStatus(payloadItems);
      if (!ok) {
        await _enqueuePendingInstructionUploads(payloadItems,
            username: username);
      }
      return ok;
    } catch (e) {
      debugPrint('Post instruction items failed: $e');
      try {
        // Best-effort: persist what we can so it eventually syncs.
        final payloadItems = items
            .where((e) {
              final q = e['quarantined'];
              return !(q == true || q?.toString() == 'true');
            })
            .map(
              (e) => {
                'date': e['date'],
                'treatment': e['treatment'] ?? '',
                'subtype': e['subtype'],
                'group': e['type'] ?? e['group'] ?? '',
                'instruction_index': e['instruction_index'] ?? 0,
                'instruction_text': e['instruction'] ?? e['note'] ?? '',
                'followed': e['followed'] ?? false,
              },
            )
            .toList();
        if (payloadItems.isNotEmpty) {
          await _enqueuePendingInstructionUploads(payloadItems,
              username: username);
        }
      } catch (_) {}
      return false;
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

  void setTreatment(String? treatment,
      {String? subtype, DateTime? procedureDate}) {
    final canonicalTreatment = _canonicalTreatment(treatment);
    final canonicalSubtype = _canonicalSubtype(canonicalTreatment, subtype);
    if (_treatment != canonicalTreatment ||
        _treatmentSubtype != canonicalSubtype) {
      _treatment = canonicalTreatment;
      _treatmentSubtype = canonicalSubtype;
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

  // Treatment instructions (expected/loggable)
  // NOTE: The older _treatmentInstructions + fixed slicing (4 dos/2 donts/rest specific)
  // was incorrect for several treatments and was never populated in this codebase.
  // We now use a centralized catalog of the *logged/checkable* instructions.
  Map<String, List<String>> _currentExpectedByGroup() {
    final expected = InstructionCatalog.getExpected(
        treatment: _treatment, subtype: _treatmentSubtype);
    if (expected == null) return const {};
    return expected;
  }

  List<String> get currentDos =>
      List<String>.from((_currentExpectedByGroup()['general'] ?? const [])
          .map(_canonicalInstructionText)
          .where((e) => e.isNotEmpty));

  // "Don'ts" are informational in most screens and are not logged as checklist items.
  // Keep this empty so Progress screens don't count them as expected.
  List<String> get currentDonts => const [];

  List<String> get currentSpecificSteps =>
      List<String>.from((_currentExpectedByGroup()['specific'] ?? const [])
          .map(_canonicalInstructionText)
          .where((e) => e.isNotEmpty));

  void setUserDetails({
    int? patientId,
    required String fullName,
    required DateTime dob,
    required String gender,
    required String username,
    required String password,
    required String phone,
    required String email,
  }) {
    this.patientId = patientId;
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
    _startPendingUploadFlushLoop();
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

  /// Clears current treatment selection and related fields locally.
  ///
  /// Use this after the backend has started a new open episode (e.g. after
  /// marking the previous treatment as completed) so the UI does not keep
  /// showing stale treatment details.
  Future<void> startNewEpisodeLocally({String? username}) async {
    _treatment = null;
    _treatmentSubtype = null;
    _implantStage = null;
    procedureDate = null;
    procedureTime = null;
    _procedureCompleted = false;
    await resetLocalStateForTreatmentReplacement(username: username);
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

  List<bool> getChecklistForTreatmentDay(
      String treatmentKey, int day, int itemCount) {
    String key = "${treatmentKey}_day$day";
    return List<bool>.from(
        _persistedChecklists[key] ?? List.filled(itemCount, false));
  }

  void setChecklistForTreatmentDay(
      String treatmentKey, int day, List<bool> values) {
    String key = "${treatmentKey}_day$day";
    _persistedChecklists[key] = List<bool>.from(values);
    // Persist as well
    _saveChecklistForKey(key, _persistedChecklists[key]!, username: username);
    notifyListeners();
  }

  Future<void> reset() async {
    patientId = null;
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
    _stopPendingUploadFlushLoop();

    // On logout/reset, always revert UI to light until a user logs in.
    _themeMode = ThemeMode.light;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('username');
    await prefs.remove('user_details');
    await prefs.remove(_prefsThemeModePendingKey);
    await prefs.remove(_prefsThemeModeKey); // legacy global key (avoid leakage)
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
    _progressFeedback
        .add({'title': title, 'note': note, 'date': formattedDate});
    notifyListeners();
  }

  void clearProgressFeedback() {
    _progressFeedback.clear();
    notifyListeners();
  }

  Future<void> _saveUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    // Persist last username separately so account-scoped settings (theme, etc.) can load
    // before the full user_details blob is hydrated.
    final u = (username ?? '').trim();
    if (u.isNotEmpty) {
      await prefs.setString('username', u);
    }
    await prefs.setString(
      'user_details',
      jsonEncode({
        'patientId': patientId,
        'fullName': fullName,
        'dob': dob?.toIso8601String(),
        'gender': gender,
        'username': username,
        'password': password,
        'phone': phone,
        'email': email,
        'token': token,
        'themeMode': _encodeThemeMode(_themeMode),
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
      }),
    );
    // No need to store hasSelectedCategory in SharedPreferences
  }

  Future<void> loadUserDetails({bool runBulkSync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('user_details');
    String? loadedToken = prefs.getString('token');
    if (data != null) {
      final decoded = jsonDecode(data);
      patientId = decoded['patientId'] is int
          ? decoded['patientId']
          : int.tryParse((decoded['patientId'] ?? '').toString());
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
      _treatment = _canonicalTreatment(decoded['treatment']);
      _treatmentSubtype =
          _canonicalSubtype(_treatment, decoded['treatmentSubtype']);
      _implantStage = decoded['implantStage'];
      _procedureCompleted = decoded['procedureCompleted'];
      procedureDate = decoded['procedureDate'] != null
          ? DateTime.parse(decoded['procedureDate'])
          : null;
      procedureTime = decoded['procedureTime'] != null
          ? _parseTimeOfDay(decoded['procedureTime'])
          : null;

      // Restore theme for this account if present.
      // This is a fallback; the primary path is loadThemeMode() before runApp.
      try {
        final raw = (decoded['themeMode'] ?? decoded['theme_mode'])?.toString();
        if (raw != null && raw.trim().isNotEmpty) {
          final restored = _decodeThemeMode(raw);
          _themeMode = restored;

          assert(() {
            debugPrint('[theme] loadUserDetails: restoredFromUserDetails=$raw');
            return true;
          }());
        }
      } catch (_) {}
      notifyListeners();

      // Cache last username for account-scoped preferences.
      final u = (username ?? '').trim();
      if (u.isNotEmpty) {
        await prefs.setString('username', u);
      }
    } else {
      if (loadedToken != null) {
        token = loadedToken;
        notifyListeners();
      }
    }
    // After loading user details, attempt loading instruction logs and optionally run one-time bulk sync.
    await loadInstructionLogs(username: username);

    // Always pull server-side changes first so multi-device state is canonical.
    await pullInstructionStatusChanges();

    if (runBulkSync) {
      await maybeBulkSyncInstructionLogs();
    }

    // Best-effort: flush any instruction-status uploads that were queued while offline.
    await flushPendingInstructionUploads(username: username);
    _startPendingUploadFlushLoop();
  }

  Future<void> maybeBulkSyncInstructionLogs() async {
    final user = username;
    if (user == null || user.isEmpty) return;
    if (token == null || token!.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final syncFlagKey = 'instruction_bulk_synced_${user}';
    if (prefs.getBool(syncFlagKey) ?? false) return;
    final ok = await bulkSyncAllInstructionLogs();
    if (ok) {
      await prefs.setBool(syncFlagKey, true);
    }
  }

  // Properly use setters for private fields (fixes direct assignment error)
  Future<void> clearUserData() async {
    // Clear in-memory user/session state.
    username = null;
    patientId = null;
    fullName = null;
    dob = null;
    gender = null;
    phone = null;
    email = null;
    password = null;
    token = null;

    // On logout, always revert UI to light until a user logs in.
    _themeMode = ThemeMode.light;

    setDepartment(null);
    setDoctor(null);
    setTreatment(null, subtype: null);
    setTreatmentSubtype(null);
    procedureDate = null;
    procedureTime = null;
    procedureCompleted = false;
    _stopPendingUploadFlushLoop();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_details');
    await prefs.remove('token');
    await prefs.remove('username');
    await prefs.remove(_prefsThemeModePendingKey);
    await prefs.remove(_prefsThemeModeKey); // legacy global key (avoid leakage)
  }

  void updatePersonalInfo(
      {String? fullName,
      String? email,
      String? phone,
      String? gender,
      DateTime? dob}) {
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
    final s =
        (group.trim().toLowerCase() + '|' + instruction.trim().toLowerCase());
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
      final items = _instructionLogs.where((e) {
        final q = e['quarantined'];
        final followed = e['followed'] == true || e['followed']?.toString() == 'true';
        return !(q == true || q?.toString() == 'true') && followed;
      }).map((e) {
        final type = (e['type'] ?? '').toString();
        final instruction = (e['instruction'] ?? e['note'] ?? '').toString();
        final localIdx = e['instruction_index'];
        final idx = (localIdx is int)
            ? localIdx
            : (int.tryParse(localIdx?.toString() ?? '') ??
                stableInstructionIndex(type, instruction));
        return {
          'date': e['date'],
          'treatment': e['treatment'] ?? '',
          'subtype': e['subtype'],
          'group': type,
          'instruction_index': idx,
          'instruction_text': instruction,
          'followed': e['followed'] ?? false,
          'ever_followed': (e['everFollowed'] == true ||
              e['everFollowed']?.toString() == 'true'),
        };
      }).toList();

      if (items.isEmpty) return true;
      final ok = await ApiService.saveInstructionStatus(items);
      if (ok)
        debugPrint('Bulk sync succeeded: ${items.length} instruction rows');
      else
        debugPrint('Bulk sync failed');
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
