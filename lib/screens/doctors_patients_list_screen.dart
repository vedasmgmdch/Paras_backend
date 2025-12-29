import 'package:flutter/material.dart';
import '../services/api_service.dart';
// import 'doctor_patient_progress_screen.dart'; // legacy summary screen (temporarily kept commented)
import 'doctor_patient_full_progress_screen.dart';
import 'department_doctors_data.dart';
import '../widgets/ui_safety.dart';

class DoctorsPatientsListScreen extends StatefulWidget {
  const DoctorsPatientsListScreen({super.key});

  @override
  State<DoctorsPatientsListScreen> createState() => _DoctorsPatientsListScreenState();
}

class _DoctorsPatientsListScreenState extends State<DoctorsPatientsListScreen> {
  String? _selectedDepartment;
  String? _selectedDoctor;
  List<Map<String, dynamic>> _patients = [];
  bool _loading = false;
  String? _error;

  List<String> get _doctorList {
    if (_selectedDepartment == null) return [];
    return kDepartmentDoctors[_selectedDepartment!] ?? [];
  }

  Future<void> _fetchPatients() async {
    final doctor = _selectedDoctor;
    if (doctor == null) return;
    setState(() { _loading = true; _error = null; });
    // Watchdog: if still loading after 15s, surface timeout (unless finished)
    Future.delayed(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (_loading) {
        setState(() {
          _loading = false;
          _error = 'Request timed out. Please refresh.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timeout loading patients (15s)')),
        );
      }
    });
    List<Map<String,dynamic>> list = const [];
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
      setState(() { _error = 'Failed to load patients'; });
      // Show transient feedback so user knows it failed
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading patients: $e')),
      );
    } finally {
      if (mounted) {
        setState(() { _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () {
              if (_selectedDoctor != null) {
                _fetchPatients();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Select a doctor first')),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    children: [
                      departmentWidget,
                      const SizedBox(height: 12),
                      doctorWidget,
                    ],
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              _selectedDepartment == null
                  ? 'Select a department to view doctors'
                  : (_selectedDoctor == null
                      ? 'Select a doctor to view patients'
                      : (_loading ? 'Loading patients for ${_selectedDoctor!}...' : 'Showing patients for ${_selectedDoctor!}')),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_selectedDoctor == null
                    ? const Center(child: Text('Select a doctor'))
                    : (_patients.isEmpty
                        ? Center(child: Text(_error ?? 'No patients'))
                        : ListView.separated(
                            itemCount: _patients.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final p = _patients[idx];
                              final name = p['name'] ?? 'Unknown';
                              final username = p['username'] ?? '';
                              final treatment = p['treatment'] ?? 'No treatment set';
                              return ListTile(
                                title: SafeText(name),
                                subtitle: SafeText('$username • $treatment'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  if (username.isEmpty) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
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
    );
  }
}

class _DepartmentDropdown extends StatelessWidget {
  final List<String> departments;
  final String? value;
  final ValueChanged<String?> onChanged;
  const _DepartmentDropdown({
    required this.departments,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Department',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      isExpanded: true,
      selectedItemBuilder: (ctx) => departments
          .map((d) => Align(
                alignment: Alignment.centerLeft,
                child: Text(d, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      items: departments.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }
}

class _DoctorDropdown extends StatelessWidget {
  final List<String> doctors;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;
  const _DoctorDropdown({
    required this.doctors,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: enabled ? value : null,
      decoration: const InputDecoration(
        labelText: 'Doctor',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      isExpanded: true,
      selectedItemBuilder: (ctx) => doctors
          .map((d) => Align(
                alignment: Alignment.centerLeft,
                child: Text(d, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      items: doctors.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: enabled ? onChanged : null,
    );
  }
}
