import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/api_service.dart';
import 'category_screen.dart';
import 'tto_instructions_screen.dart';
import 'pfd_instructions_screen.dart';
import 'prd_instructions_screen.dart';
import 'root_canal_instructions_screen.dart';
import 'ifs_instructions_screen.dart';
import 'iss_instructions_screen.dart';
import 'braces_instructions_screen.dart';
import 'filling_instructions_screen.dart';
import 'tc_instructions_screen.dart';
import 'tw_instructions_screen.dart';
import 'gs_instructions_screen.dart';
import 'v_l_instructions_screen.dart';

// --- Tooth Fracture Options Widget ---
class _ToothFractureOptions extends StatelessWidget {
  final List<Map<String, dynamic>> options;
  final int? selectedIndex;
  final ValueChanged<int> onOptionTap;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  const _ToothFractureOptions({
    required this.options,
    required this.selectedIndex,
    required this.onOptionTap,
    required this.onBack,
    required this.onContinue,
    Key? key,
  }) : super(key: key);

  double _iconSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 350) return 22;
    if (width < 400) return 26;
    return 32;
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = _iconSize(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.blue),
            onPressed: onBack,
          ),
          const SizedBox(height: 12),
          const Text(
            "What care do you need for the fractured tooth?",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black87),
          ),
          const SizedBox(height: 18),
          ...List.generate(options.length, (i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: selectedIndex == i ? const Color(0xFF2196F3) : const Color(0xFF0CA9E7),
                  width: selectedIndex == i ? 2.5 : 1.5,
                ),
              ),
              elevation: 0,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: selectedIndex == i ? const Color(0xFF2196F3) : const Color(0xFF0CA9E7),
                  child: Icon(options[i]['icon'], color: Colors.white, size: iconSize),
                ),
                title: Text(options[i]['label'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                onTap: () => onOptionTap(i),
              ),
            ),
          )),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onContinue,
              child: const Text("Continue"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ProsthesisTypeSelector widget
class ProsthesisTypeSelector extends StatefulWidget {
  final Function(String) onTypeSelected;
  final VoidCallback onBackToTreatment;

  const ProsthesisTypeSelector({
    Key? key,
    required this.onTypeSelected,
    required this.onBackToTreatment,
  }) : super(key: key);

  @override
  State<ProsthesisTypeSelector> createState() => _ProsthesisTypeSelectorState();
}

class _ProsthesisTypeSelectorState extends State<ProsthesisTypeSelector> {
  int? _selectedType;

  double _iconSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 350) return 32;
    if (width < 400) return 40;
    return 56;
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = _iconSize(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.blue),
            onPressed: widget.onBackToTreatment,
            tooltip: "Back to Treatment Selection",
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF00B4F6),
              borderRadius: BorderRadius.circular(23),
            ),
            child: const Center(
              child: Text(
                "Prosthesis Fitted",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Choose your type:",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 8),
          const Text(
            "Please select between the following options of dentures:",
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 26),
          Column(
            children: [
              GestureDetector(
                onTap: () async {
                  setState(() {
                    _selectedType = 0;
                  });
                  final selectedDateTime = await showDateTimePicker(context);
                  if (selectedDateTime != null) {
                    final appState = Provider.of<AppState>(context, listen: false);
                    appState.setTreatment('Prosthesis Fitted', subtype: "Fixed Dentures");
                    appState.setProcedureDateTime(selectedDateTime, TimeOfDay.fromDateTime(selectedDateTime));

                    await ApiService.saveTreatmentInfo(
                      username: appState.username!,
                      treatment: "Prosthesis Fitted",
                      subtype: "Fixed Dentures",
                      procedureDate: selectedDateTime,
                      procedureTime: TimeOfDay.fromDateTime(selectedDateTime),
                    );

                    widget.onTypeSelected("Fixed Dentures\nDate: ${selectedDateTime.toString()}");
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _selectedType == 0 ? Colors.cyan : Colors.cyan.shade100,
                      width: _selectedType == 0 ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Fixed Dentures',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: Colors.black),
                      ),
                      const SizedBox(height: 16),
                      Icon(Icons.view_module, color: Colors.cyan, size: iconSize),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  setState(() {
                    _selectedType = 1;
                  });
                  final selectedDateTime = await showDateTimePicker(context);
                  if (selectedDateTime != null) {
                    final appState = Provider.of<AppState>(context, listen: false);
                    appState.setTreatment('Prosthesis Fitted', subtype: "Removable Dentures");
                    appState.setProcedureDateTime(selectedDateTime, TimeOfDay.fromDateTime(selectedDateTime));

                    await ApiService.saveTreatmentInfo(
                      username: appState.username!,
                      treatment: "Prosthesis Fitted",
                      subtype: "Removable Dentures",
                      procedureDate: selectedDateTime,
                      procedureTime: TimeOfDay.fromDateTime(selectedDateTime),
                    );

                    widget.onTypeSelected("Removable Dentures\nDate: ${selectedDateTime.toString()}");
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _selectedType == 1 ? Colors.cyan : Colors.cyan.shade100,
                      width: _selectedType == 1 ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Removable Dentures',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: Colors.black),
                      ),
                      const SizedBox(height: 16),
                      Icon(Icons.circle, color: Colors.cyan, size: iconSize),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<DateTime?> showDateTimePicker(BuildContext context) async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null) return null;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

// ImplantTypeSelector widget (unchanged)
class ImplantTypeSelector extends StatelessWidget {
  final String? selectedStage;
  final Function(String) onStageSelected;
  final VoidCallback? onContinue;
  final VoidCallback onBackToTreatment;
  final DateTime selectedDate;
  final TimeOfDay selectedTime;

  const ImplantTypeSelector({
    Key? key,
    required this.onStageSelected,
    required this.selectedDate,
    required this.selectedTime,
    this.selectedStage,
    this.onContinue,
    required this.onBackToTreatment,
  }) : super(key: key);

  double _iconSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 350) return 32;
    if (width < 400) return 40;
    return 56;
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = _iconSize(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.blue),
            onPressed: onBackToTreatment,
            tooltip: "Back to Treatment Selection",
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.deepPurple[400],
              borderRadius: BorderRadius.circular(23),
            ),
            child: const Center(
              child: Text(
                "Implant",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Choose the type:",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 8),
          const Text(
            "Please select between the following stages of your implant:",
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    onStageSelected("First Stage");
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selectedStage == "First Stage"
                            ? Colors.deepPurple
                            : Colors.deepPurple.shade100,
                        width: selectedStage == "First Stage" ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'First Stage',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: Colors.black),
                        ),
                        const SizedBox(height: 16),
                        Icon(Icons.looks_one, color: Colors.deepPurple, size: iconSize),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    onStageSelected("Second Stage");
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selectedStage == "Second Stage"
                            ? Colors.deepPurple
                            : Colors.deepPurple.shade100,
                        width: selectedStage == "Second Stage" ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Second Stage',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: Colors.black),
                        ),
                        const SizedBox(height: 16),
                        Icon(Icons.looks_two, color: Colors.deepPurple, size: iconSize),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onContinue,
              child: const Text("Continue"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 22),
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// PART 2/2

class TreatmentScreenMain extends StatefulWidget {
  final String userName;

  const TreatmentScreenMain({Key? key, required this.userName}) : super(key: key);

  @override
  State<TreatmentScreenMain> createState() => _TreatmentScreenMainState();
}

class _TreatmentScreenMainState extends State<TreatmentScreenMain> {
  int? _selectedIndex;
  bool showFractureOptions = false;
  int? _selectedFractureOptionIndex;
  String? _selectedImplantStage;

  final treatments = [
    {'label': 'Tooth Taken Out', 'icon': Icons.medical_services},
    {'label': 'Prosthesis Fitted', 'icon': Icons.view_module},
    {'label': 'Root Canal/Filling', 'icon': Icons.healing},
    {'label': 'Implant', 'icon': Icons.favorite_border},
    {'label': 'Tooth Fracture', 'icon': Icons.broken_image},
    {'label': 'Braces', 'icon': Icons.emoji_people},
  ];

  final List<Map<String, dynamic>> fractureOptions = [
    {'icon': Icons.auto_fix_high, 'label': 'Filling'},
    {'icon': Icons.cleaning_services, 'label': 'Teeth Cleaning'},
    {'icon': Icons.stars, 'label': 'Teeth Whitening'},
    {'icon': Icons.medical_services_outlined, 'label': 'Gum Surgery'},
    {'icon': Icons.view_array, 'label': 'Veneers/Laminates'},
  ];

  double _treatmentIconSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 350) return 28;
    if (width < 400) return 36;
    return 48;
  }

  void _navigateToCategoryScreen(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => CategoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isProsthesisFitted = _selectedIndex != null &&
        treatments[_selectedIndex!]['label'] == 'Prosthesis Fitted';
    final bool isImplant = _selectedIndex != null &&
        treatments[_selectedIndex!]['label'] == 'Implant';

    final treatmentIconSize = _treatmentIconSize(context);

    if (showFractureOptions) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.blue),
            onPressed: () => _navigateToCategoryScreen(context),
          ),
          title: Text("Hi ${widget.userName},"),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 18.0),
          child: _ToothFractureOptions(
            options: fractureOptions,
            selectedIndex: _selectedFractureOptionIndex,
            onOptionTap: (idx) {
              setState(() {
                _selectedFractureOptionIndex = idx;
              });
            },
            onBack: () {
              setState(() {
                showFractureOptions = false;
                _selectedIndex = null;
                _selectedFractureOptionIndex = null;
              });
            },
            onContinue: _selectedFractureOptionIndex == null
                ? null
                : () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (pickedDate == null) return;
              final pickedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (pickedTime == null) return;

              final selectedDateTime = DateTime(
                pickedDate.year,
                pickedDate.month,
                pickedDate.day,
                pickedTime.hour,
                pickedTime.minute,
              );

              final appState =
              Provider.of<AppState>(context, listen: false);
              final subtype =
              fractureOptions[_selectedFractureOptionIndex!]['label'] as String;

              appState.setTreatment("Tooth Fracture", subtype: subtype);
              appState.setProcedureDateTime(
                  selectedDateTime, TimeOfDay.fromDateTime(selectedDateTime));

              await ApiService.saveTreatmentInfo(
                username: appState.username ?? widget.userName,
                treatment: "Tooth Fracture",
                subtype: subtype,
                procedureDate: selectedDateTime,
                procedureTime: TimeOfDay.fromDateTime(selectedDateTime),
              );

        Widget navScreen;
              switch (subtype) {
                case "Filling":
          navScreen = FillingInstructionsScreen(date: DateTime.now());
                  break;
                case "Teeth Cleaning":
          navScreen = TCInstructionsScreen(date: DateTime.now());
                  break;
                case "Teeth Whitening":
          navScreen = TWInstructionsScreen(date: DateTime.now());
                  break;
                case "Gum Surgery":
          navScreen = GSInstructionsScreen(date: DateTime.now());
                  break;
                case "Veneers/Laminates":
          navScreen = VLInstructionsScreen(date: DateTime.now());
                  break;
                default:
          navScreen = FillingInstructionsScreen(date: DateTime.now());
              }
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => navScreen),
                    (route) => false,
              );
            },
          ),
        ),
      );
    }

    if (isProsthesisFitted) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.blue),
            onPressed: () => _navigateToCategoryScreen(context),
          ),
          title: Text("Hi ${widget.userName},"),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 18.0),
          child: ProsthesisTypeSelector(
            onTypeSelected: (String typeWithDate) {
              final parts = typeWithDate.split('\nDate: ');
              final type = parts[0];
              final dateTime = DateTime.tryParse(parts[1]);
              if (dateTime != null) {
        if (type == "Fixed Dentures") {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
            builder: (_) =>
              PFDInstructionsScreen(date: DateTime.now())),
                  );
                } else if (type == "Removable Dentures") {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
            builder: (_) =>
              PRDInstructionsScreen(date: DateTime.now())),
                  );
                }
              }
            },
            onBackToTreatment: () {
              setState(() {
                _selectedIndex = null;
                showFractureOptions = false;
                _selectedImplantStage = null;
              });
            },
          ),
        ),
      );
    }

    if (isImplant) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.blue),
            onPressed: () => _navigateToCategoryScreen(context),
          ),
          title: Text("Hi ${widget.userName},"),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 18.0),
          child: ImplantTypeSelector(
            selectedStage: _selectedImplantStage,
            selectedDate: DateTime.now(),
            selectedTime: TimeOfDay.now(),
            onStageSelected: (String stage) {
              setState(() {
                _selectedImplantStage = stage;
              });
            },
            onContinue: _selectedImplantStage == null
                ? null
                : () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (pickedDate == null) return;
              final pickedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (pickedTime == null) return;

              final selectedDateTime = DateTime(
                pickedDate.year,
                pickedDate.month,
                pickedDate.day,
                pickedTime.hour,
                pickedTime.minute,
              );

              final appState = Provider.of<AppState>(context, listen: false);
              appState.setTreatment('Implant', subtype: _selectedImplantStage);
              appState.setProcedureDateTime(selectedDateTime, TimeOfDay.fromDateTime(selectedDateTime));

              await ApiService.saveTreatmentInfo(
                username: appState.username ?? widget.userName,
                treatment: "Implant",
                subtype: _selectedImplantStage,
                procedureDate: selectedDateTime,
                procedureTime: TimeOfDay.fromDateTime(selectedDateTime),
              );

        if (_selectedImplantStage == "First Stage") {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
            builder: (_) =>
              IFSInstructionsScreen(date: DateTime.now())),
                      (route) => false,
                );
              } else if (_selectedImplantStage == "Second Stage") {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
            builder: (_) =>
              ISSInstructionsScreen(date: DateTime.now())),
                      (route) => false,
                );
              }
            },
            onBackToTreatment: () {
              setState(() {
                _selectedIndex = null;
                showFractureOptions = false;
                _selectedImplantStage = null;
              });
            },
          ),
        ),
      );
    }

    // --- Main selection grid, overflow-free ---
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.blue),
          onPressed: () => _navigateToCategoryScreen(context),
        ),
        title: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: "Hi ${widget.userName}",
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 22,
                    fontWeight: FontWeight.w400),
              ),
              const TextSpan(
                text: ", ",
                style: TextStyle(color: Colors.black, fontSize: 22),
              ),
              const WidgetSpan(
                child: Icon(Icons.waving_hand, color: Colors.amber, size: 22),
              ),
            ],
          ),
        ),
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          int gridCrossAxisCount = 2;
          double gridChildAspectRatio = 1.3;
          if (constraints.maxWidth < 400) gridChildAspectRatio = 1.1;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Please select your area of need",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Color(0xFF2B2B2B),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    "I have/had ...",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Color(0xFF2B2B2B),
                    ),
                  ),
                  const SizedBox(height: 26),
                  GridView.count(
                    crossAxisCount: gridCrossAxisCount,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    childAspectRatio: gridChildAspectRatio,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: List.generate(treatments.length, (index) {
                      final item = treatments[index];
                      final isSelected = _selectedIndex == index;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedIndex = index;
                            showFractureOptions = false;
                            _selectedImplantStage = null;
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.blue.withOpacity(0.08)
                                : Colors.blue.withOpacity(0.04),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.blue
                                  : Colors.blue.shade100,
                              width: isSelected ? 2.0 : 1.0,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item['icon'] as IconData,
                                  color: Colors.blue,
                                  size: treatmentIconSize,
                                ),
                                const SizedBox(height: 10),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    item['label'] as String,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF2B2B2B),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.search, color: Colors.blue),
                      label: const Text(
                        "Search for other operative care",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        side: const BorderSide(color: Color(0xFFB9E5FF)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: Colors.white,
                      ),
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selectedIndex == null
                          ? null
                          : () async {
                        final selectedTreatment =
                        treatments[_selectedIndex!]['label'] as String;

                        final appState =
                        Provider.of<AppState>(context, listen: false);
                        final username = appState.username ?? widget.userName;

                        DateTime? procedureDate;
                        TimeOfDay? procedureTime;

                        if (selectedTreatment == 'Tooth Taken Out') {
                          procedureDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2101),
                          );
                          if (procedureDate == null) return;
                          procedureTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (procedureTime == null) return;
                          final procedureDateTime = DateTime(
                            procedureDate.year,
                            procedureDate.month,
                            procedureDate.day,
                            procedureTime.hour,
                            procedureTime.minute,
                          );
                          appState.setTreatment(
                            selectedTreatment,
                            subtype: null,
                          );
                          appState.setProcedureDateTime(
                            procedureDateTime,
                            procedureTime,
                          );
                          await ApiService.saveTreatmentInfo(
                            username: username,
                            treatment: selectedTreatment,
                            subtype: null,
                            procedureDate: procedureDateTime,
                            procedureTime: procedureTime,
                          );
        Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) =>
          TTOInstructionsScreen(date: DateTime.now()),
                            ),
                                (route) => false,
                          );
                        } else if (selectedTreatment == 'Root Canal/Filling') {
                          procedureDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (procedureDate != null) {
                            procedureTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (procedureTime != null) {
                              final selectedDateTime = DateTime(
                                procedureDate.year,
                                procedureDate.month,
                                procedureDate.day,
                                procedureTime.hour,
                                procedureTime.minute,
                              );
                              appState.setTreatment(
                                selectedTreatment,
                                procedureDate: selectedDateTime,
                              );
                              appState.setProcedureDateTime(
                                selectedDateTime,
                                procedureTime,
                              );
                              await ApiService.saveTreatmentInfo(
                                username: username,
                                treatment: selectedTreatment,
                                subtype: null,
                                procedureDate: selectedDateTime,
                                procedureTime: procedureTime,
                              );
                Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) =>
                    RootCanalInstructionsScreen(
                      date: DateTime.now()),
                                ),
                                    (route) => false,
                              );
                            }
                          }
                        } else if (selectedTreatment == 'Implant') {
                          // Handled above by ImplantTypeSelector
                        } else if (selectedTreatment == 'Tooth Fracture') {
                          setState(() {
                            showFractureOptions = true;
                          });
                        } else if (selectedTreatment == 'Braces') {
                          await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          ).then((date) async {
                            if (date != null) {
                              procedureDate = date;
                              await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              ).then((time) async {
                                if (time != null) {
                                  procedureTime = time;
                                  appState.setProcedureDateTime(
                                      procedureDate!, procedureTime!);
                                  appState.setTreatment(selectedTreatment);
                                  await ApiService.saveTreatmentInfo(
                                    username: username,
                                    treatment: selectedTreatment,
                                    subtype: null,
                                    procedureDate: procedureDate!,
                                    procedureTime: procedureTime!,
                                  );
                  Navigator.of(context).pushAndRemoveUntil(
                                    MaterialPageRoute(
                    builder: (_) =>
                    BracesInstructionsScreen(date: DateTime.now()),
                                    ),
                                        (route) => false,
                                  );
                                }
                              });
                            }
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      child: const Text("Continue"),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}