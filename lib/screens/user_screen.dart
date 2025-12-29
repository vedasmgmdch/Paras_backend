import 'package:flutter/material.dart';
// Reverted simple user screen without adaptive/universal wrappers.

/// Entry selection screen: lets the user choose Doctor or Patient flows.
/// Doctor: navigates to DoctorLoginScreen (to be implemented).
/// Patient: navigates to existing Welcome/login/signup flow (AppEntryGate).
class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Select Portal'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how you want to continue',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 36),
            _PortalCard(
              icon: Icons.medical_services_outlined,
              title: 'Doctor Portal',
              description: 'View assigned patients and monitor recovery progress.',
              buttonLabel: "Enter Doctor Login",
              color: Colors.blue,
              onTap: () => Navigator.of(context).pushNamed('/doctor-login'),
            ),
            const SizedBox(height: 28),
            _PortalCard(
              icon: Icons.favorite_outline,
              title: 'Patient Portal',
              description: 'Track treatments, instructions, reminders, and more.',
              buttonLabel: "Continue as Patient",
              color: Colors.teal,
              onTap: () => Navigator.of(context).pushReplacementNamed('/patient'),
            ),
            const SizedBox(height: 40),
            Column(
              children: const [
                Text(
                  'ToothCareGuide',
                  style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Colors.black54),
                ),
                SizedBox(height: 6),
                Text(
                  'Better smiles. Better care.',
                  style: TextStyle(fontSize: 12, color: Colors.black38),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final Color color;
  final VoidCallback onTap;
  const _PortalCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.1),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Icon(icon, color: color, size: 30),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.3),
                      ),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                onPressed: onTap,
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
