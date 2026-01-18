import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'home_screen.dart';
import 'instruction_snapshot_helper.dart';
import '../widgets/treatment_actions_sheet.dart';

class BracesInstructionsScreen extends StatefulWidget {
  final DateTime? date;

  const BracesInstructionsScreen({super.key, this.date});
  @override
  State<BracesInstructionsScreen> createState() => _BracesInstructionsScreenState();
}

class _BracesInstructionsScreenState extends State<BracesInstructionsScreen>
    with InstructionSnapshotHelper<BracesInstructionsScreen> {
  DateTime _selectedLogDate() {
    return widget.date != null
        ? DateTime(widget.date!.year, widget.date!.month, widget.date!.day)
        : DateTime.now();
  }

  void _logInstructionChange({
    required DateTime logDate,
    required String group,
    required String instructionEn,
    required bool followed,
  }) {
    final appState = Provider.of<AppState>(context, listen: false);
    final logDateStr = AppState.formatYMD(logDate);
    final idx = appState.stableInstructionIndex(group, instructionEn);
    appState.addInstructionLog(
      instructionEn,
      date: logDateStr,
      type: group,
      followed: followed,
      username: appState.username,
      treatment: appState.treatment,
      subtype: appState.treatmentSubtype,
      instructionIndex: idx,
    );
  }

  String selectedLang = 'en'; // 'en' for English, 'mr' for Marathi

  static const List<Map<String, String>> bracesDos = [
    {
      "en": "Brush your teeth and rinse your mouth carefully after every meal.",
      "mr": "प्रत्येक जेवणानंतर दात ब्रश करा आणि तोंड नीट धुवा.",
    },
    {"en": "Floss daily (if possible).", "mr": "दररोज फ्लॉस करा (शक्य असल्यास)."},
    {"en": "Attend all your orthodontic appointments.", "mr": "तुमच्या सर्व ऑर्थोडॉन्टिक भेटींना उपस्थित राहा."},
  ];

  static const List<Map<String, String>> bracesDonts = [
    {
      "en":
          "Don’t eat foods that can damage or loosen your braces, particularly chewy, hard, or sticky foods (e.g., ice, popcorn, candies, toffee, etc.).",
      "mr":
          "ब्रेसेसला हानी पोहोचवू शकणारे किंवा ब्रेसेस सैल करू शकणारे पदार्थ खाऊ नका, विशेषतः चिवट, कडक किंवा चिकट पदार्थ (उदा. बर्फ, पॉपकॉर्न, कँडी, टॉफी इ.).",
    },
    {"en": "Don’t bite your nails or chew on pencils.", "mr": "नखं चघळू नका किंवा पेन्सिलवर चावू नका."},
  ];

  // --- Specific Instructions for Braces ---
  static const List<Map<String, String>> bracesSpecificInstructions = [
    {
      "en": "If a bracket or wire becomes loose, contact your orthodontist as soon as possible.",
      "mr": "ब्रॅकेट किंवा वायर सैल झाल्यास, शक्य तितक्या लवकर आपल्या ऑर्थोडॉन्टिस्टशी संपर्क साधा.",
    },
    {
      "en": "Use orthodontic wax to cover sharp or irritating wires.",
      "mr": "तीक्ष्ण किंवा त्रासदायक वायर झाकण्यासाठी ऑर्थोडॉन्टिक वॅक्स वापरा.",
    },
    {
      "en": "In case of mouth sores, rinse with warm salt water.",
      "mr": "तोंडात जखमा झाल्यास, कोमट मिठाच्या पाण्याने गुळण्या करा.",
    },
    {"en": "Avoid chewing gum during orthodontic treatment.", "mr": "ऑर्थोडॉन्टिक उपचारादरम्यान च्युइंगम टाळा."},
  ];

  static const int totalDays = 15;
  late int currentDay;
  late List<bool> _dosChecked;
  late List<bool> _specificChecked;
  bool _hasUserInteracted = false;
  bool showSpecific = false;

  String _generalChecklistKey(DateTime date) => "braces_dos_${date.year}_${date.month}_${date.day}";
  String _specificChecklistKey(DateTime date) => "braces_specific_${date.year}_${date.month}_${date.day}";

  @override
  void initState() {
    super.initState();

    final selectedDate = widget.date != null
        ? DateTime(widget.date!.year, widget.date!.month, widget.date!.day)
        : DateTime.now();
    final appState = Provider.of<AppState>(context, listen: false);
    int day = appState.daysSinceProcedure(selectedDate);
    if (day < 1) day = 1;
    if (day > totalDays) day = totalDays;
    currentDay = day;

    _dosChecked = List<bool>.from(appState.getChecklistForKey(_generalChecklistKey(selectedDate)));
    if (_dosChecked.length != bracesDos.length) {
      _dosChecked = List.filled(bracesDos.length, false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appState.setChecklistForKey(_generalChecklistKey(selectedDate), _dosChecked);
      });
    }

    _specificChecked = List<bool>.from(appState.getChecklistForKey(_specificChecklistKey(selectedDate)));
    if (_specificChecked.length != bracesSpecificInstructions.length) {
      _specificChecked = List.filled(bracesSpecificInstructions.length, false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appState.setChecklistForKey(_specificChecklistKey(selectedDate), _specificChecked);
      });
    }

    // After first frame: hydrate immediately from local logs, then refresh from server.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await appState.loadInstructionLogs(username: appState.username);
      if (!mounted) return;

      void hydrateFromAppState() {
        final hydratedGeneral = appState.buildFollowedChecklistForDay(
          day: selectedDate,
          type: 'general',
          length: bracesDos.length,
          instructionTextForIndex: (i) => bracesDos[i]['en'] ?? '',
          username: appState.username,
          treatment: appState.treatment,
          subtype: appState.treatmentSubtype,
        );
        final hydratedSpecific = appState.buildFollowedChecklistForDay(
          day: selectedDate,
          type: 'specific',
          length: bracesSpecificInstructions.length,
          instructionTextForIndex: (i) => bracesSpecificInstructions[i]['en'] ?? '',
          username: appState.username,
          treatment: appState.treatment,
          subtype: appState.treatmentSubtype,
        );

        setState(() {
          _dosChecked = hydratedGeneral;
          _specificChecked = hydratedSpecific;
        });
        appState.setChecklistForKey(_generalChecklistKey(selectedDate), _dosChecked);
        appState.setChecklistForKey(_specificChecklistKey(selectedDate), _specificChecked);
      }

      hydrateFromAppState();

      unawaited(() async {
        await appState.pullInstructionStatusChanges();
        if (!mounted) return;
        if (_hasUserInteracted) return;
        hydrateFromAppState();
      }());
    });
  }

  void _updateDos(int idx, bool? value) {
    _hasUserInteracted = true;
    setState(() {
      _dosChecked[idx] = value ?? false;
    });
    final selectedDate = _selectedLogDate();
    final followed = value ?? false;
    Provider.of<AppState>(context, listen: false)
        .setChecklistForKey(_generalChecklistKey(selectedDate), _dosChecked);
    _logInstructionChange(
      logDate: selectedDate,
      group: 'general',
      instructionEn: bracesDos[idx]['en'] ?? '',
      followed: followed,
    );
  }

  void _updateSpecificChecklist(int idx, bool value) {
    _hasUserInteracted = true;
    setState(() {
      _specificChecked[idx] = value;
    });
    final selectedDate = _selectedLogDate();
    Provider.of<AppState>(
      context,
      listen: false,
    ).setChecklistForKey(_specificChecklistKey(selectedDate), _specificChecked);
    _logInstructionChange(
      logDate: selectedDate,
      group: 'specific',
      instructionEn: bracesSpecificInstructions[idx]['en'] ?? '',
      followed: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (currentDay >= totalDays) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated check/celebration
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) => Transform.scale(scale: value, child: child),
                  child: Container(
                    decoration: BoxDecoration(color: colorScheme.secondaryContainer, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(22),
                    child: const Icon(Icons.emoji_events_rounded, color: Color(0xFF2ECC71), size: 64),
                  ),
                ),
                const SizedBox(height: 28),
                // Elevated card for message
                Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  color: colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
                    child: Column(
                      children: [
                        Text(
                          selectedLang == 'en' ? "Recovery Complete!" : "पुनरुत्थान पूर्ण!",
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          selectedLang == 'en'
                              ? "Congratulations! Your procedure recovery is complete. You can now select a new treatment."
                              : "अभिनंदन! तुमची उपचार प्रक्रिया पूर्ण झाली आहे. तुम्ही आता नवीन उपचार निवडू शकता.",
                          style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 34),
                // Modern rounded button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.assignment_turned_in_rounded, size: 22),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 3,
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                    ),
                    label: Text(selectedLang == 'en' ? "Select Different Treatment" : "नवीन उपचार निवडा"),
                    onPressed: () async {
                      await completeThenSelectNewTreatment(context, replaceStack: true);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      final appState = Provider.of<AppState>(context);
      final treatment = appState.treatment;

      String title = selectedLang == 'en' ? "General Instructions" : "सामान्य सूचना";
      if (treatment != null) {
        title = selectedLang == 'en' ? "Instructions (${treatment})" : "सूचना (${treatment})";
      }

      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: showSpecific
            ? AppBar(
                backgroundColor: colorScheme.surface,
                elevation: 1,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back, color: colorScheme.primary),
                  onPressed: () {
                    setState(() => showSpecific = false);
                  },
                ),
                title: Text(
                  selectedLang == 'en' ? "Specific Instructions - Day $currentDay" : "विशिष्ट सूचना - दिवस $currentDay",
                  style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
                ),
                centerTitle: true,
              )
            : null,
        body: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Language Switcher
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                        ),
                        icon: const Icon(Icons.language, size: 20),
                        label: Text(selectedLang == 'en' ? 'मराठी' : 'English'),
                        onPressed: () {
                          setState(() {
                            selectedLang = selectedLang == 'en' ? 'mr' : 'en';
                          });
                        },
                      ),
                    ),
                    if (!showSpecific) ...[
                      Text(
                        "$title (Day $currentDay)",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 20),
                      // Do's Section with Checklist
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          border: Border.all(color: Colors.green.shade200, width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green[700],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  selectedLang == 'en'
                                      ? "Do's (Day $currentDay)"
                                      : "करावयाच्या गोष्टी (दिवस $currentDay)",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...List.generate(
                                bracesDos.length,
                                (i) => Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: CheckboxListTile(
                                    value: _dosChecked[i],
                                    onChanged: (val) => _updateDos(i, val),
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    dense: true,
                                    title: Text(
                                      bracesDos[i][selectedLang]!,
                                      style: TextStyle(fontSize: 15, color: Colors.green.shade400, fontWeight: FontWeight.w600),
                                    ),
                                    activeColor: Colors.green.shade400,
                                    checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Don'ts Section (no checklist)
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          border: Border.all(color: Colors.red.shade200, width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red[700],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  selectedLang == 'en' ? "Don'ts" : "टाळा",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...List.generate(
                                bracesDonts.length,
                                (i) => Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.close, color: colorScheme.error, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          bracesDonts[i][selectedLang]!,
                                          style: TextStyle(fontSize: 15, color: colorScheme.error, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.menu_book, color: Colors.white),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          label: Text(
                            selectedLang == 'en' ? "View Specific Instructions" : "विशिष्ट सूचना पहा",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            setState(() {
                              showSpecific = true;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: Text(
                            selectedLang == 'en' ? "Continue to Dashboard" : "डॅशबोर्डवर जा",
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const HomeScreen()),
                              (route) => false,
                            );
                          },
                        ),
                      ),
                    ] else ...[
                      Text(
                        selectedLang == 'en'
                            ? "Specific Instructions (Day $currentDay)"
                            : "विशिष्ट सूचना (दिवस $currentDay)",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(
                        bracesSpecificInstructions.length,
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: CheckboxListTile(
                            contentPadding: const EdgeInsets.only(left: 10, right: 0),
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                            title: Text(
                              bracesSpecificInstructions[i][selectedLang]!,
                              style: const TextStyle(fontSize: 15),
                            ),
                            value: _specificChecked[i],
                            onChanged: (bool? value) {
                              _updateSpecificChecklist(i, value ?? false);
                            },
                            activeColor: Colors.green,
                            checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: Text(
                            selectedLang == 'en' ? "Go to Dashboard" : "डॅशबोर्डवर जा",
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const HomeScreen()),
                              (route) => false,
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }
}
