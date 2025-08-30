import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'home_screen.dart';
import 'treatment_screen.dart';

class RootCanalInstructionsScreen extends StatefulWidget {
  final DateTime date;
  const RootCanalInstructionsScreen({Key? key, required this.date}) : super(key: key);

  @override
  State<RootCanalInstructionsScreen> createState() => _RootCanalInstructionsScreenState();
}

class _RootCanalInstructionsScreenState extends State<RootCanalInstructionsScreen> {
  void _saveAllLogsForDay() {
    // Always use the selected date (widget.date) for log saving
    final procedureDate = DateTime(widget.date.year, widget.date.month, widget.date.day);
    final logDate = procedureDate;
    final logDateStr = logDate.toIso8601String().split('T')[0];
    final appState = Provider.of<AppState>(context, listen: false);
    for (int i = 0; i < generalInstructions.length; i++) {
      appState.addInstructionLog(
        generalInstructions[i][selectedLang] ?? '',
        date: logDateStr,
        type: 'general',
        followed: _generalChecked.length > i ? _generalChecked[i] : false,
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

  static const List<Map<String, String>> generalInstructions = [
    {
      "en": "If your lips or tongue feel numb avoid chewing on that side till numbness wears off.",
      "mr": "तोंड किंवा ओठ सुन्न असतील तर सुन्नपणा जाईपर्यंत त्या बाजूने चघळू नका.",
    },
    {
      "en": "If multiple appointments are required, do not bite hard/sticky food from the operated site till the completion of treatment.",
      "mr": "अनेक भेटींची आवश्यकता असल्यास, उपचार पूर्ण होईपर्यंत ऑपरेट केलेल्या भागावरून कडक/चिकट पदार्थ चघळू नका.",
    },
    {
      "en": "A putty-like material is placed in your tooth after completion of your treatment which is temporary; To protect and help keep your temporary in place.",
      "mr": "उपचार पूर्ण झाल्यावर दातात ठेवलेली पुट्टीसारखी सामग्री ही तात्पुरती असते; तात्पुरती भर सुरक्षित ठेवण्यासाठी आहे.",
    },
    {
      "en": "Avoid chewing sticky foods, especially on side of filling.",
      "mr": "चिकट पदार्थ टाळा, विशेषतः भर घातलेल्या बाजूस.",
    },
    {
      "en": "Avoid biting hard foods and hard substances, such as ice, fingernails and pencils.",
      "mr": "कडक अन्न आणि वस्तूंवर चावणे टाळा, जसे की बर्फ, नखं, पेन्सिल.",
    },
    {
      "en": "If possible, chew only on the opposite side of your mouth.",
      "mr": "शक्य असल्यास, तोंडाच्या विरुद्ध बाजूनेच चघळा.",
    },
    {
      "en": "It's important to continue to brush and floss regularly and normally.",
      "mr": "नियमितपणे आणि योग्य पद्धतीने ब्रश व फ्लॉस करत राहा.",
    },
  ];

  static const List<Map<String, String>> specificInstructions = [
    {
      "en": "DO NOT EAT anything for 1 hr post-treatment completion.",
      "mr": "उपचार पूर्ण झाल्यानंतर १ तास काहीही खाऊ नका.",
    },
    {
      "en": "If you are experiencing discomfort, apply an ice pack on the area in 10 minutes ON 5 minutes OFF intervals for up to an hour.",
      "mr": "असुविधा जाणवत असल्यास, त्या भागावर १० मिनिटे बर्फ लावा आणि ५ मिनिटे काढा, असे एक तासापर्यंत करा.",
    },
    {
      "en": "DO NOT SMOKE for the 1st day after treatment.",
      "mr": "उपचारानंतर पहिल्या दिवशी धूम्रपान करू नका.",
    },
  ];

  static const int totalDays = 15;
  late int currentDay;
  late List<bool> _generalChecked;
  late List<bool> _specificChecked;

  String _generalChecklistKey(DateTime date) => "root_canal_general_${date.year}_${date.month}_${date.day}";
  String _specificChecklistKey(DateTime date) => "root_canal_specific_${date.year}_${date.month}_${date.day}";

  @override
  void initState() {
    super.initState();
  final appState = Provider.of<AppState>(context, listen: false);
  final selectedDate = DateTime(widget.date.year, widget.date.month, widget.date.day);
  final proc = appState.procedureDate;
  final DateTime procedureDate = proc != null
    ? DateTime(proc.year, proc.month, proc.day)
    : selectedDate;
  int day = selectedDate.difference(procedureDate).inDays + 1;
  if (day < 1) day = 1;
  if (day > totalDays) day = totalDays;
  currentDay = day;

  _generalChecked = List<bool>.from(appState.getChecklistForKey(_generalChecklistKey(selectedDate)));
    if (_generalChecked.length != generalInstructions.length) {
      _generalChecked = List.filled(generalInstructions.length, false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
    appState.setChecklistForKey(_generalChecklistKey(selectedDate), _generalChecked);
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

  void _updateGeneral(int idx, bool? value) {
    setState(() {
      _generalChecked[idx] = value ?? false;
    });
  final selectedDate = DateTime(widget.date.year, widget.date.month, widget.date.day);
  Provider.of<AppState>(context, listen: false)
    .setChecklistForKey(_generalChecklistKey(selectedDate), _generalChecked);
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
    for (int i = 0; i < generalInstructions.length; i++) {
      if (!_generalChecked[i]) notFollowedGeneral.add(generalInstructions[i][selectedLang]!);
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
[Root Canal] $dateStr (Day $currentDay)
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
    final appState = Provider.of<AppState>(context);
    final treatment = appState.treatment;
    final subtype = appState.treatmentSubtype;

    // Use treatment name in the title if available, else fallback
    String title = selectedLang == 'en'
        ? "General Instructions"
        : "सामान्य सूचना";
    if (treatment != null && treatment.isNotEmpty) {
      title = selectedLang == 'en'
          ? "Instructions ($treatment${(subtype != null && subtype.isNotEmpty) ? " - $subtype" : ""})"
          : "सूचना ($treatment${(subtype != null && subtype.isNotEmpty) ? " - $subtype" : ""})";
    } else {
      title = selectedLang == 'en'
          ? "Instructions (Root Canal/Filling)"
          : "सूचना (मूळदात उपचार/फिलिंग)";
    }

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
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.green.shade200, width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.only(bottom: 20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8.0, horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green[700],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  selectedLang == 'en'
                                      ? "General Instructions (Day $currentDay)"
                                      : "सामान्य सूचना (दिवस $currentDay)",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...List.generate(
                                generalInstructions.length,
                                    (i) => Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: CheckboxListTile(
                                    value: _generalChecked[i],
                                    onChanged: (val) => _updateGeneral(i, val),
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    dense: true,
                                    title: Text(
                                      generalInstructions[i][selectedLang]!,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    activeColor: Colors.green,
                                    checkboxShape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(5),
                                    ),
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
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
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
                      ...List.generate(
                        specificInstructions.length,
                            (i) => Padding(
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