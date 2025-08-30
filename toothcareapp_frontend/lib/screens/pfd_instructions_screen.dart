import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'home_screen.dart';
import 'treatment_screen.dart';

class PFDInstructionsScreen extends StatefulWidget {
  final DateTime date;
  const PFDInstructionsScreen({Key? key, required this.date}) : super(key: key);

  @override
  State<PFDInstructionsScreen> createState() => _PFDInstructionsScreenState();
}

class _PFDInstructionsScreenState extends State<PFDInstructionsScreen> {
  void _saveAllLogsForDay() {
    // Always use the selected date (widget.date) for log saving
    final procedureDate = DateTime(widget.date.year, widget.date.month, widget.date.day);
    final logDate = procedureDate;
    final logDateStr = logDate.toIso8601String().split('T')[0];
    final appState = Provider.of<AppState>(context, listen: false);
    for (int i = 0; i < fixedDos.length; i++) {
      appState.addInstructionLog(
        fixedDos[i][selectedLang] ?? '',
        date: logDateStr,
        type: 'general',
        followed: _dosChecked.length > i ? _dosChecked[i] : false,
        username: appState.username,
        treatment: appState.treatment,
        subtype: appState.treatmentSubtype,
      );
    }
    for (int i = 0; i < specificInstructions.length; i++) {
      appState.addInstructionLog(
        specificInstructions[i][selectedLang] ?? '',
        date: logDateStr,
        type: 'specific',
        followed: _specificChecked.length > i ? _specificChecked[i] : false,
        username: appState.username,
        treatment: appState.treatment,
        subtype: appState.treatmentSubtype,
      );
    }
  }
  String selectedLang = 'en'; // 'en' for English, 'mr' for Marathi
  bool showSpecific = false;

  static const List<Map<String, String>> fixedDos = [
    {
      "en": "Whenever local anesthesia is used, avoid chewing on your teeth until the numbness has worn off.",
      "mr": "स्थानिक भूल दिल्यानंतर, सुन्नपणा जाईपर्यंत दातांवर चावणे टाळा.",
    },
    {
      "en": "Proper brushing, flossing, and regular cleanings are necessary to maintain the restoration.",
      "mr": "पुनर्स्थापना टिकवण्यासाठी योग्य ब्रशिंग, फ्लॉसिंग आणि नियमित स्वच्छता आवश्यक आहे.",
    },
    {
      "en": "Pay special attention to your gumline.",
      "mr": "तुमच्या हिरड्यांच्या सीमेकडे विशेष लक्ष द्या.",
    },
    {
      "en": "Avoid very hot or hard foods.",
      "mr": "अतिशय गरम किंवा कडक अन्न टाळा.",
    },
  ];

  static const List<Map<String, String>> fixedDonts = [
    {
      "en": "Do not chew hard foods on the restorations for 24 hours from the time they were cemented.",
      "mr": "पुनर्स्थापना सिमेंट केल्यापासून २४ तास त्या भागावर कडक पदार्थ चघळू नका.",
    },
    {
      "en": "Do not chew ice or other hard objects.",
      "mr": "बर्फ किंवा इतर कडक वस्तू चघळू नका.",
    },
    {
      "en": "Avoid chewing very sticky food/candy because they can remove restorations.",
      "mr": "अतिशय चिकट पदार्थ/कँडी चघळू नका कारण ते पुनर्स्थापना काढू शकतात.",
    },
  ];

  static const List<Map<String, String>> specificInstructions = [
    {
      "en": "Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack.",
      "mr": "तोंडात ठेवलेल्या गॉजवर किमान ४५-६० मिनिटे घट्ट चावा आणि नंतर हलक्या हाताने काढा.",
    },
    {
      "en": "After going home apply ice pack on the area in 15-20 minute intervals till nighttime.",
      "mr": "घरी गेल्यावर, त्या भागावर १५-२० मिनिटांच्या अंतराने रात्रीपर्यंत बर्फाचा पॅक लावा.",
    },
    {
      "en": "After removing the pack take one doseage of medicines prescribed.",
      "mr": "पॅक काढल्यानंतर, सांगितलेली औषधे एक वेळ घ्या.",
    },
    {
      "en": "After 24 hours, gargle in that area with luke warm water and salt atleast 3-4 times a day.",
      "mr": "२४ तासांनंतर, त्या भागात कोमट पाण्यात मीठ घालून दिवसातून किमान ३-४ वेळा गुळण्या करा.",
    },
  ];

  static const int totalDays = 15;
  late int currentDay;
  late List<bool> _dosChecked;
  late List<bool> _specificChecked;

  String _generalChecklistKey(DateTime date) => "pfd_fixed_dos_${date.year}_${date.month}_${date.day}";
  String _specificChecklistKey(DateTime date) => "pfd_specific_${date.year}_${date.month}_${date.day}";

  @override
  void initState() {
    super.initState();

  final selectedDate = DateTime(widget.date.year, widget.date.month, widget.date.day);
  final appState = Provider.of<AppState>(context, listen: false);
  final proc = appState.procedureDate;
  final DateTime procedureDate = proc != null
    ? DateTime(proc.year, proc.month, proc.day)
    : selectedDate;
  int day = selectedDate.difference(procedureDate).inDays + 1;
    if (day < 1) day = 1;
    if (day > totalDays) day = totalDays;
    currentDay = day;
  _dosChecked = List<bool>.from(appState.getChecklistForKey(_generalChecklistKey(selectedDate)));
    if (_dosChecked.length != fixedDos.length) {
      _dosChecked = List.filled(fixedDos.length, false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
    appState.setChecklistForKey(_generalChecklistKey(selectedDate), _dosChecked);
      });
    }

  _specificChecked = List<bool>.from(appState.getChecklistForKey(_specificChecklistKey(selectedDate)));
    if (_specificChecked.length != specificInstructions.length) {
      _specificChecked = List.filled(specificInstructions.length, false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
    appState.setChecklistForKey(_specificChecklistKey(selectedDate), _specificChecked);
      });
    }
  // Save logs for all instructions for the selected day on load
  _saveAllLogsForDay();
  }

  void _updateChecklist(int idx, bool value) {
    setState(() {
      _dosChecked[idx] = value;
    });
  final selectedDate = DateTime(widget.date.year, widget.date.month, widget.date.day);
  Provider.of<AppState>(context, listen: false)
    .setChecklistForKey(_generalChecklistKey(selectedDate), _dosChecked);
    _saveAllLogsForDay();
  }

  void _updateSpecificChecklist(int idx, bool value) {
    setState(() {
      _specificChecked[idx] = value;
    });
  final selectedDate = DateTime(widget.date.year, widget.date.month, widget.date.day);
  Provider.of<AppState>(context, listen: false)
    .setChecklistForKey(_specificChecklistKey(selectedDate), _specificChecked);
    _saveAllLogsForDay();
  }

  void _logInstructionStatusIfNeeded() {
    final appState = Provider.of<AppState>(context, listen: false);
    final String dateStr = widget.date.toLocal().toString().split(' ').first;

    final List<String> notFollowedGeneral = [];
    for (int i = 0; i < fixedDos.length; i++) {
      if (!_dosChecked[i]) notFollowedGeneral.add(fixedDos[i][selectedLang]!);
    }

    final List<String> notFollowedSpecific = [];
    for (int i = 0; i < specificInstructions.length; i++) {
      if (!_specificChecked[i]) notFollowedSpecific.add(specificInstructions[i][selectedLang]!);
    }

    String buildSection(String title, List<String> list) {
      if (list.isEmpty) {
        return "$title: All followed ✅";
      }
      final buffer = StringBuffer("$title: Not followed ❌\n");
      for (final item in list) {
        buffer.writeln("• $item");
      }
      return buffer.toString().trimRight();
    }

    final String log = """
[Fixed Partial Denture] $dateStr (Day $currentDay)
${buildSection("General Instructions", notFollowedGeneral)}

${buildSection("Specific Instructions", notFollowedSpecific)}
""".trim();

    appState.addProgressFeedback("Instruction Log", log, date: dateStr);
  }

  void _goToDashboard() {
    _logInstructionStatusIfNeeded();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentDay >= totalDays) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(22),
                    child: const Icon(Icons.emoji_events_rounded, color: Color(0xFF2ECC71), size: 64),
                  ),
                ),
                const SizedBox(height: 28),
                Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
                    child: Column(
                      children: const [
                        Text(
                          "Recovery Complete!",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF222B45),
                            letterSpacing: 1.1,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          "Congratulations! Your procedure recovery is complete. You can now select a new treatment.",
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF6B7280),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.assignment_turned_in_rounded, size: 22),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0052CC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 3,
                      textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.2,
                      ),
                    ),
                    label: const Text("Select Different Treatment"),
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => TreatmentScreenMain(userName: "User")),
                            (route) => false,
                      );
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
      final subtype = appState.treatmentSubtype;

      String title = selectedLang == 'en'
          ? "General Instructions"
          : "सामान्य सूचना";
      if (treatment != null) {
        title = selectedLang == 'en'
            ? "Instructions (${treatment}${subtype != null && subtype.isNotEmpty ? " - $subtype" : ""})"
            : "सूचना (${treatment}${subtype != null && subtype.isNotEmpty ? " - $subtype" : ""})";
      }

      return Scaffold(
        backgroundColor: Colors.white,
        appBar: showSpecific
            ? AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.blue),
            onPressed: () {
              setState(() => showSpecific = false);
            },
          ),
          title: Text(
            selectedLang == 'en'
                ? "Specific Instructions - Day $currentDay"
                : "विशिष्ट सूचना - दिवस $currentDay",
            style: const TextStyle(
                color: Colors.blue, fontWeight: FontWeight.bold),
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[100],
                          foregroundColor: Colors.blue[900],
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
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[600]),
                          const SizedBox(width: 8),
                          Text(
                            selectedLang == 'en'
                                ? "Do's (Day $currentDay)"
                                : "करावयाच्या गोष्टी (दिवस $currentDay)",
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(
                        fixedDos.length,
                            (i) => Padding(
                          padding: const EdgeInsets.only(left: 8, top: 0, bottom: 0),
                          child: CheckboxListTile(
                            contentPadding: const EdgeInsets.only(left: 20, right: 0),
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                            title: Text(
                              fixedDos[i][selectedLang]!,
                              style: const TextStyle(fontSize: 15),
                            ),
                            value: _dosChecked[i],
                            onChanged: (bool? value) {
                              _updateChecklist(i, value ?? false);
                            },
                            activeColor: Colors.green,
                            checkboxShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE6E6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12.0, horizontal: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.cancel, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Text(
                                    selectedLang == 'en'
                                        ? "Don'ts"
                                        : "टाळा",
                                    style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...fixedDonts.map(
                                    (item) => Padding(
                                  padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.close, color: Colors.red, size: 18),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(item[selectedLang]!,
                                            style: const TextStyle(fontSize: 15)),
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.menu_book, color: Colors.white),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber[700],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          label: Text(
                            selectedLang == 'en'
                                ? "View Specific Instructions"
                                : "विशिष्ट सूचना पहा",
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
                            backgroundColor: Colors.blue[700],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: Text(
                            selectedLang == 'en'
                                ? "Continue to Dashboard"
                                : "डॅशबोर्डवर जा",
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _goToDashboard,
                        ),
                      ),
                    ] else ...[
                      Text(
                        selectedLang == 'en'
                            ? "Specific Instructions (Day $currentDay)"
                            : "विशिष्ट सूचना (दिवस $currentDay)",
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(specificInstructions.length, (i) =>
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: CheckboxListTile(
                              contentPadding: const EdgeInsets.only(
                                  left: 10, right: 0),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                              title: Text(
                                specificInstructions[i][selectedLang]!,
                                style: const TextStyle(fontSize: 15),
                              ),
                              value: _specificChecked[i],
                              onChanged: (bool? value) {
                                _updateSpecificChecklist(i, value ?? false);
                              },
                              activeColor: Colors.green,
                              checkboxShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          )),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: Text(
                            selectedLang == 'en'
                                ? "Go to Dashboard"
                                : "डॅशबोर्डवर जा",
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _goToDashboard,
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