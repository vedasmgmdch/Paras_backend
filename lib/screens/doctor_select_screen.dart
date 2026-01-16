import 'package:flutter/material.dart';

import '../widgets/no_animation_page_route.dart';
import 'department_doctors_data.dart';
import 'doctors_patients_list_screen.dart';

class DoctorSelectScreen extends StatefulWidget {
  const DoctorSelectScreen({super.key});

  @override
  State<DoctorSelectScreen> createState() => _DoctorSelectScreenState();
}

class _DoctorSelectScreenState extends State<DoctorSelectScreen> {
  String? _selectedDepartment;
  String? _selectedDoctor;

  List<String> get _doctorList {
    if (_selectedDepartment == null) return const [];
    return kDepartmentDoctors[_selectedDepartment!] ?? const [];
  }

  void _continue() {
    final dept = _selectedDepartment;
    final doc = _selectedDoctor;
    if (dept == null || doc == null) return;

    Navigator.of(context).push(
      NoAnimationPageRoute(
        builder: (_) => DoctorsPatientsListScreen(initialDepartment: dept, initialDoctor: doc, lockSelection: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _selectedDepartment != null && _selectedDoctor != null;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Select Doctor')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: Column(
                    children: [
                      SizedBox(height: (constraints.maxHeight * 0.18).clamp(24, 140).toDouble()),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Please select the department and doctor',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedDepartment,
                                decoration: const InputDecoration(
                                  labelText: 'Department',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                isExpanded: true,
                                items: kDepartments
                                    .map(
                                      (d) => DropdownMenuItem(
                                        value: d,
                                        child: Text(d, overflow: TextOverflow.ellipsis),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedDepartment = val;
                                    _selectedDoctor = null;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedDoctor,
                                decoration: const InputDecoration(
                                  labelText: 'Doctor',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                isExpanded: true,
                                items: _doctorList
                                    .map(
                                      (d) => DropdownMenuItem(
                                        value: d,
                                        child: Text(d, overflow: TextOverflow.ellipsis),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _selectedDepartment == null
                                    ? null
                                    : (val) {
                                        setState(() {
                                          _selectedDoctor = val;
                                        });
                                      },
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: canContinue ? _continue : null,
                                  child: const Text('Continue'),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Tip: You can search patients on the next screen.',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
