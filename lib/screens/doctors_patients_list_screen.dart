import 'package:flutter/material.dart';
import '../services/api_service.dart';
// import 'doctor_patient_progress_screen.dart'; // legacy summary screen (temporarily kept commented)
import 'doctor_patient_full_progress_screen.dart';
import 'department_doctors_data.dart';
import '../widgets/ui_safety.dart';
import '../widgets/no_animation_page_route.dart';

class DoctorsPatientsListScreen extends StatefulWidget {
  final String? initialDepartment;
  final String? initialDoctor;
  final bool lockSelection;

  const DoctorsPatientsListScreen({super.key, this.initialDepartment, this.initialDoctor, this.lockSelection = false});

  @override
  State<DoctorsPatientsListScreen> createState() => _DoctorsPatientsListScreenState();
}

class _DoctorsPatientsListScreenState extends State<DoctorsPatientsListScreen> {
  String? _selectedDepartment;
  String? _selectedDoctor;
  List<Map<String, dynamic>> _patients = [];
  bool _loading = false;
  String? _error;

  final TextEditingController _dateFromCtrl = TextEditingController();
  final TextEditingController _dateToCtrl = TextEditingController();
  String? _dateFilterError;

  @override
  void initState() {
    super.initState();
    _selectedDepartment = widget.initialDepartment;
    _selectedDoctor = widget.initialDoctor;

    // If preselected, fetch immediately.
    if (_selectedDoctor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchPatients();
      });
    }
  }

  @override
  void dispose() {
    _dateFromCtrl.dispose();
    _dateToCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseDateOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    // Accept both "YYYY-MM-DD" and timestamps like "YYYY-MM-DDTHH:mm:ss"
    final normalized = s.contains('T') ? s.split('T').first : s;
    final dt = DateTime.tryParse(normalized);
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day);
  }

  String _formatYMD(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _applyDateFilters(List<Map<String, dynamic>> src) {
    final from = _parseDateOnly(_dateFromCtrl.text);
    final to = _parseDateOnly(_dateToCtrl.text);

    // If user typed something but parsing failed, show a lightweight error and don't filter.
    if ((_dateFromCtrl.text.trim().isNotEmpty && from == null) || (_dateToCtrl.text.trim().isNotEmpty && to == null)) {
      _dateFilterError = 'Use YYYY-MM-DD (e.g. 2026-01-04)';
      return src;
    }

    if (from != null && to != null && to.isBefore(from)) {
      _dateFilterError = 'To date must be after From date';
      return src;
    }

    _dateFilterError = null;
    if (from == null && to == null) return src;

    return src.where((p) {
      final raw = (p['procedure_date'] ?? '').toString();
      final pd = _parseDateOnly(raw);
      if (pd == null) return false;
      if (from != null && pd.isBefore(from)) return false;
      if (to != null && pd.isAfter(to)) return false;
      return true;
    }).toList();
  }

  List<String> get _doctorList {
    if (_selectedDepartment == null) return [];
    return kDepartmentDoctors[_selectedDepartment!] ?? [];
  }

  Future<void> _fetchPatients() async {
    final doctor = _selectedDoctor;
    if (doctor == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // Watchdog: if still loading after 15s, surface timeout (unless finished)
    Future.delayed(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (_loading) {
        setState(() {
          _loading = false;
          _error = 'Request timed out. Please refresh.';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Timeout loading patients (15s)')));
      }
    });
    List<Map<String, dynamic>> list = const [];
    try {
      list = await ApiService.getPatientsByDoctor(doctor);
      if (!mounted) return;
      setState(() {
        _patients = list;
        if (_patients.isEmpty) {
          _error = 'No patients assigned to this doctor yet';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load patients';
      });
      // Show transient feedback so user knows it failed
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading patients: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredPatients = _applyDateFilters(_patients);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Doctor Dashboard'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search patients',
              onPressed: (_selectedDoctor == null || filteredPatients.isEmpty)
                  ? null
                  : () async {
                      final picked = await showSearch<_PatientPick?>(
                        context: context,
                        delegate: _PatientSearchDelegate(filteredPatients),
                      );
                      if (!mounted) return;
                      final username = picked?.username ?? '';
                      if (username.isEmpty) return;
                      Navigator.of(
                        context,
                      ).push(NoAnimationPageRoute(builder: (_) => DoctorPatientFullProgressScreen(username: username)));
                    },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading
                  ? null
                  : () {
                      if (_selectedDoctor != null) {
                        _fetchPatients();
                      } else {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('Select a doctor first')));
                      }
                    },
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.lockSelection)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool narrow = constraints.maxWidth < 520; // threshold for stacking
                    // Build dropdown widgets once
                    final departmentWidget = _DepartmentDropdown(
                      departments: kDepartments,
                      value: _selectedDepartment,
                      onChanged: (val) {
                        setState(() {
                          _selectedDepartment = val;
                          _selectedDoctor = null; // reset doctor when dept changes
                          _patients = [];
                          _error = null;
                        });
                        debugPrint('[DoctorDash] Department selected: $val');
                      },
                    );
                    final doctorWidget = _DoctorDropdown(
                      doctors: _doctorList,
                      value: _selectedDoctor,
                      enabled: _selectedDepartment != null,
                      onChanged: (val) {
                        setState(() {
                          _selectedDoctor = val;
                          _patients = [];
                          _error = null;
                        });
                        debugPrint('[DoctorDash] Doctor selected: $val (dept=$_selectedDepartment)');
                        if (val != null) {
                          _fetchPatients();
                        }
                      },
                    );

                    if (narrow) {
                      // For vertical stacking we MUST NOT use Expanded inside another Column (causes unbounded height flex error)
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [departmentWidget, const SizedBox(height: 12), doctorWidget],
                      );
                    }
                    // Wide layout: place dropdowns in a Row with Expanded to share space
                    return Row(
                      children: [
                        Expanded(child: departmentWidget),
                        const SizedBox(width: 12),
                        Expanded(child: doctorWidget),
                      ],
                    );
                  },
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: SafeText(
                  '$_selectedDepartment • $_selectedDoctor',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                _selectedDepartment == null
                    ? 'Select a department to view doctors'
                    : (_selectedDoctor == null
                        ? 'Select a doctor to view patients'
                        : (_loading
                            ? 'Loading patients for ${_selectedDoctor!}...'
                            : 'Showing patients for ${_selectedDoctor!}')),
                style: const TextStyle(fontSize: 13, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dateFromCtrl,
                          enabled: !_loading,
                          decoration: const InputDecoration(
                            labelText: 'Treatment start from (YYYY-MM-DD)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _dateToCtrl,
                          enabled: !_loading,
                          decoration: const InputDecoration(
                            labelText: 'Treatment start to (YYYY-MM-DD)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Clear date filter',
                        onPressed: _loading
                            ? null
                            : () {
                                _dateFromCtrl.clear();
                                _dateToCtrl.clear();
                                setState(() {
                                  _dateFilterError = null;
                                });
                              },
                        icon: const Icon(Icons.filter_alt_off),
                      ),
                    ],
                  ),
                  if (_dateFilterError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _dateFilterError!,
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  if (_dateFilterError == null &&
                      (_dateFromCtrl.text.trim().isNotEmpty || _dateToCtrl.text.trim().isNotEmpty))
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Tip: for exact date search, set both fields to the same date.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  if (_dateFilterError == null &&
                      (_dateFromCtrl.text.trim().isNotEmpty || _dateToCtrl.text.trim().isNotEmpty) &&
                      filteredPatients.isEmpty &&
                      !_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'No patients match the selected treatment start date filter.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_selectedDoctor == null
                      ? const Center(child: Text('Select a doctor'))
                      : (filteredPatients.isEmpty
                          ? Center(child: Text(_error ?? 'No patients'))
                          : ListView.separated(
                              itemCount: filteredPatients.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, idx) {
                                final p = filteredPatients[idx];
                                final name = p['name'] ?? 'Unknown';
                                final username = p['username'] ?? '';
                                final treatment = p['treatment'] ?? 'No treatment set';
                                final subtype = (p['treatment_subtype'] ?? '').toString().trim();
                                final rawDate = (p['procedure_date'] ?? '').toString();
                                final pd = _parseDateOnly(rawDate);
                                final dateLabel = pd == null ? '-' : _formatYMD(pd);
                                final tLabel = subtype.isNotEmpty ? '$treatment ($subtype)' : '$treatment';
                                return ListTile(
                                  title: SafeText(name),
                                  subtitle: SafeText('$username • $tLabel • Start: $dateLabel'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    if (username.isEmpty) return;
                                    Navigator.of(context).push(
                                      NoAnimationPageRoute(
                                        builder: (_) => DoctorPatientFullProgressScreen(username: username),
                                      ),
                                    );
                                  },
                                );
                              },
                            ))),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentDropdown extends StatelessWidget {
  final List<String> departments;
  final String? value;
  final ValueChanged<String?> onChanged;
  const _DepartmentDropdown({required this.departments, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Department', border: OutlineInputBorder(), isDense: true),
      isExpanded: true,
      selectedItemBuilder: (ctx) => departments
          .map(
            (d) => Align(
              alignment: Alignment.centerLeft,
              child: Text(d, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      items: departments
          .map(
            (d) => DropdownMenuItem(
              value: d,
              child: Text(d, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _DoctorDropdown extends StatelessWidget {
  final List<String> doctors;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;
  const _DoctorDropdown({required this.doctors, required this.value, required this.enabled, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: enabled ? value : null,
      decoration: const InputDecoration(labelText: 'Doctor', border: OutlineInputBorder(), isDense: true),
      isExpanded: true,
      selectedItemBuilder: (ctx) => doctors
          .map(
            (d) => Align(
              alignment: Alignment.centerLeft,
              child: Text(d, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      items: doctors
          .map(
            (d) => DropdownMenuItem(
              value: d,
              child: Text(d, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _PatientPick {
  final String username;
  const _PatientPick(this.username);
}

class _PatientSearchDelegate extends SearchDelegate<_PatientPick?> {
  final List<Map<String, dynamic>> patients;
  _PatientSearchDelegate(this.patients);

  Duration get transitionDuration => Duration.zero;

  @override
  String get searchFieldLabel => 'Search patient name/username';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty) IconButton(tooltip: 'Clear', onPressed: () => query = '', icon: const Icon(Icons.clear)),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(tooltip: 'Back', onPressed: () => close(context, null), icon: const Icon(Icons.arrow_back));
  }

  List<Map<String, dynamic>> _filtered() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return patients;
    return patients.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final username = (p['username'] ?? '').toString().toLowerCase();
      return name.contains(q) || username.contains(q);
    }).toList();
  }

  @override
  Widget buildResults(BuildContext context) {
    final list = _filtered();
    return _ResultsList(list: list, onPick: (u) => close(context, _PatientPick(u)));
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final list = _filtered();
    return _ResultsList(list: list, onPick: (u) => close(context, _PatientPick(u)));
  }
}

class _ResultsList extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final ValueChanged<String> onPick;
  const _ResultsList({required this.list, required this.onPick});

  DateTime? _parseDateOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final normalized = s.contains('T') ? s.split('T').first : s;
    final dt = DateTime.tryParse(normalized);
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day);
  }

  String _formatYMD(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return const Center(child: Text('No matches'));
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, idx) {
        final p = list[idx];
        final name = (p['name'] ?? 'Unknown').toString();
        final username = (p['username'] ?? '').toString();
        final treatment = (p['treatment'] ?? '').toString();
        final subtype = (p['treatment_subtype'] ?? '').toString().trim();
        final rawDate = (p['procedure_date'] ?? '').toString();
        final pd = _parseDateOnly(rawDate);
        final dateLabel = pd == null ? '' : _formatYMD(pd);
        final tLabel = subtype.isNotEmpty ? '$treatment ($subtype)' : treatment;
        final base = tLabel.isEmpty ? username : '$username • $tLabel';
        final subtitle = dateLabel.isEmpty ? base : '$base • Start: $dateLabel';
        return ListTile(
          title: SafeText(name),
          subtitle: SafeText(subtitle, maxLines: 2),
          onTap: () => onPick(username),
        );
      },
    );
  }
}
