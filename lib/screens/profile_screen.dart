import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/auth_flow.dart';
import 'calendar_screen.dart';
import '../widgets/ui_safety.dart';

class ProfileScreen extends StatelessWidget {
  final VoidCallback? onCheckRecoveryCalendar; // For Calendar tab switch
  final VoidCallback? onViewCareInstructions; // For Instructions tab switch

  const ProfileScreen({
    super.key,
    this.onCheckRecoveryCalendar,
    this.onViewCareInstructions,
  });

  // --- Fixed sign out method ---
  Future<void> _signOut(BuildContext context) async {
    await AuthFlow.signOut(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = Provider.of<AppState>(context);
    final patientId = appState.patientId != null ? "#${appState.patientId}" : "Not specified";
    final fullName = appState.fullName ?? "Not specified";
    final dob =
        appState.dob != null ? "${appState.dob!.day}/${appState.dob!.month}/${appState.dob!.year}" : "Not specified";
    final gender = appState.gender ?? "Not specified";
    final username = appState.username ?? "Not specified";
    final phone = appState.phone ?? "Not specified";
    final email = appState.email ?? "Not specified";
    final procedureDate = appState.procedureDate;
    final today = DateTime.now();
    final recoveryDay = procedureDate != null
        ? (today.difference(DateTime(procedureDate.year, procedureDate.month, procedureDate.day)).inDays + 1)
        : 0;

    final dosList = [
      ...appState.currentDos,
      "Eat soft cold foods for at least 2 days.",
      "Use warm salt water rinse as instructed.",
      "Eat your medicine as prescribed by your dentist.",
      "Drink plenty of fluids (without using a straw).",
      "Take medicines as prescribed by your doctor."
    ];
    final checks = appState.getChecklistForDate(today);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? colorScheme.surfaceContainerLow : Colors.red,
                                foregroundColor: isDark ? colorScheme.error : Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                side: isDark
                                    ? BorderSide(color: colorScheme.error.withValues(alpha: 0.60))
                                    : BorderSide.none,
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: const Size(0, 0),
                                elevation: isDark ? 0 : null,
                              ),
                              icon: const Icon(Icons.logout, size: 18),
                              label: const Text(
                                'Sign Out',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              onPressed: () => _signOut(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Header
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(22),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? colorScheme.surfaceContainerLow : colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                        border: isDark ? Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.70)) : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Patient Profile',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isDark ? colorScheme.onSurface : colorScheme.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Your recovery information",
                            style: TextStyle(
                              fontSize: 15,
                              color: (isDark ? colorScheme.onSurfaceVariant : colorScheme.onPrimary)
                                  .withValues(alpha: 0.92),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Card(
                      margin: const EdgeInsets.only(bottom: 20),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Dark mode',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              secondary: Icon(Icons.dark_mode_outlined, color: colorScheme.primary),
                              value: appState.themeMode == ThemeMode.dark,
                              onChanged: (isDark) {
                                appState.setThemeMode(
                                  isDark ? ThemeMode.dark : ThemeMode.light,
                                  syncToServer: true,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Personal Information Card
                    Card(
                      margin: const EdgeInsets.only(bottom: 20),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(18.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.person_outline, color: colorScheme.primary),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Personal Information',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: Icon(Icons.edit, color: colorScheme.primary),
                                  onPressed: () {
                                    _showEditBottomSheet(context, appState);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Icon(Icons.account_circle, size: 54, color: colorScheme.primary.withValues(alpha: 0.55)),
                            const SizedBox(height: 8),
                            Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                            Text(
                              'Patient ID: $patientId',
                              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
                            ),
                            const SizedBox(height: 16),
                            _infoTile(context, Icons.badge, 'Full Name', fullName,
                                colorScheme.primaryContainer.withValues(alpha: 0.55)),
                            _infoTile(context, Icons.cake, 'Date of Birth', dob,
                                colorScheme.primaryContainer.withValues(alpha: 0.55)),
                            _infoTile(context, Icons.person, 'Gender', gender,
                                colorScheme.primaryContainer.withValues(alpha: 0.55)),
                            _infoTile(context, Icons.account_circle, 'Username', username,
                                colorScheme.primaryContainer.withValues(alpha: 0.55)),
                            _infoTile(context, Icons.phone, 'Phone', phone,
                                colorScheme.primaryContainer.withValues(alpha: 0.55)),
                            _infoTile(
                              context,
                              Icons.email,
                              'Email',
                              email,
                              colorScheme.secondaryContainer.withValues(alpha: 0.55),
                              isEmail: true,
                            ),
                            const SizedBox(height: 16),
                            _infoTile(
                              context,
                              Icons.calendar_today,
                              'Procedure Date',
                              procedureDate != null
                                  ? "${procedureDate.day}/${procedureDate.month}/${procedureDate.year}"
                                  : "-",
                              colorScheme.secondaryContainer.withValues(alpha: 0.55),
                            ),
                            _infoTile(
                              context,
                              Icons.bar_chart,
                              'Recovery Day',
                              "Day $recoveryDay",
                              colorScheme.tertiaryContainer.withValues(alpha: 0.55),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Emergency Contact
                    _buildEmergencyContact(context),
                    // Today's Checklist
                    _buildChecklist(context, dosList, checks),
                    // Quick Actions
                    _buildQuickActions(context),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _showEditBottomSheet(BuildContext context, AppState appState) {
    final nameController = TextEditingController(text: appState.fullName ?? "");
    final emailController = TextEditingController(text: appState.email ?? "");
    final phoneController = TextEditingController(text: appState.phone ?? "");
    String gender = appState.gender ?? "Not specified";
    DateTime? selectedDob = appState.dob;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Edit Personal Information",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: "Full Name"),
                      ),
                      TextField(
                        controller: emailController,
                        decoration: const InputDecoration(labelText: "Email"),
                      ),
                      TextField(
                        controller: phoneController,
                        decoration: const InputDecoration(labelText: "Phone"),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: (gender != "Not specified") ? gender : null,
                        items: const ["Male", "Female", "Other"]
                            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        decoration: const InputDecoration(labelText: "Gender"),
                        onChanged: (val) {
                          setState(() {
                            gender = val ?? "Not specified";
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            selectedDob != null
                                ? "DOB: ${selectedDob!.day}/${selectedDob!.month}/${selectedDob!.year}"
                                : "Select DOB",
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedDob ?? DateTime(2000),
                                firstDate: DateTime(1900),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setState(() {
                                  selectedDob = date;
                                });
                              }
                            },
                            child: const Text("Pick Date"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            appState.updatePersonalInfo(
                              fullName: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
                              email: emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                              phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                              gender: gender == "Not specified" ? null : gender,
                              dob: selectedDob,
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                          child: const Text("Save Changes"),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  static Widget _infoTile(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color backgroundColor, {
    bool isEmail = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(10)),
      child: KeyValueRow(
        leadingIcon: Icon(icon, color: colorScheme.onSurfaceVariant, size: 22),
        label: label,
        value: value,
        crossAxisAlignment: isEmail ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      ),
    );
  }

  static Widget _buildEmergencyContact(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_phone, color: colorScheme.error),
                const SizedBox(width: 8),
                const Text(
                  "Emergency Contact",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? colorScheme.surfaceContainer : colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
                border: isDark
                    ? Border(
                        left: BorderSide(color: colorScheme.error.withValues(alpha: 0.95), width: 3),
                      )
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Dental Office",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? colorScheme.onSurface : colorScheme.onErrorContainer,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.phone, size: 18, color: isDark ? colorScheme.error : colorScheme.onErrorContainer),
                      const SizedBox(width: 6),
                      // Not const because of TextStyle
                      Text(
                        "022-27433404 , 022-27437992",
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? colorScheme.onSurface : colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.email, size: 18, color: isDark ? colorScheme.error : colorScheme.onErrorContainer),
                      const SizedBox(width: 6),
                      // Not const because of TextStyle
                      Text(
                        "mgmmcnb@gmail.com",
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? colorScheme.onSurface : colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Call immediately if you experience:",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              "• Severe pain not relieved by medication\n"
              "• Excessive bleeding after 24 hours\n"
              "• Signs of infection (fever, pus, severe swelling)\n"
              "• Numbness lasting more than 24 hours",
              style: TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklist(BuildContext context, List<String> dosList, List<bool> checks) {
    final colorScheme = Theme.of(context).colorScheme;
    // Compute completion status inside the function
    final allCompleted = checks.isNotEmpty && checks.every((c) => c);

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Today's Checklist", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 14),
            ...List.generate(dosList.length, (i) {
              final checked = i < checks.length ? checks[i] : false;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Icon(
                      checked ? Icons.check_box : Icons.check_box_outline_blank,
                      color: checked ? colorScheme.primary : colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dosList[i],
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              );
            }),
            // --- New warning message after last checklist item ---
            const SizedBox(height: 12),
            if (!allCompleted)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    // Red exclamation icon
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: colorScheme.error,
                      child: Icon(Icons.error_outline, color: colorScheme.onError, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Please Complete Your Today's Checklist By Clicking On View Care Instructions, If Not Completed.",
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Quick Actions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.tertiary,
                  foregroundColor: colorScheme.onTertiary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  if (onViewCareInstructions != null) {
                    onViewCareInstructions!();
                  } else {
                    // fallback navigation if desired
                    // (replace with your instructions screen navigation if needed)
                  }
                },
                child:
                    const Text("View Care Instructions", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.secondary,
                  foregroundColor: colorScheme.onSecondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  if (onCheckRecoveryCalendar != null) {
                    onCheckRecoveryCalendar!();
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CalendarScreen()),
                    );
                  }
                },
                child:
                    const Text("Check Recovery Calendar", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
