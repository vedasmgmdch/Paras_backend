import 'package:flutter/material.dart';
import 'doctor_login_screen.dart';
import '../widgets/no_animation_page_route.dart';

class UserScreen extends StatelessWidget {
  const UserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select Portal',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              const _TopLogosRow(),
              const SizedBox(height: 28),
              const Text(
                'Welcome',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose how you want to continue',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 36),
              _PortalCard(
                icon: Icons.medical_services_outlined,
                title: 'Doctor Portal',
                description: 'View assigned patients and monitor recovery progress.',
                buttonLabel: 'Enter Doctor Login',
                color: Colors.blue,
                onTap: () => Navigator.of(context).push(
                  NoAnimationPageRoute(builder: (_) => const DoctorLoginScreen()),
                ),
              ),
              const SizedBox(height: 28),
              _PortalCard(
                icon: Icons.favorite_outline,
                title: 'Patient Portal',
                description: 'Track treatments, instructions, reminders, and more.',
                buttonLabel: 'Continue as Patient',
                color: Colors.teal,
                onTap: () => Navigator.of(context).pushReplacementNamed('/patient'),
              ),
              const SizedBox(height: 40),
              const Column(
                children: [
                  Text(
                    'ToothCareGuide',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Better smiles. Better care.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black38,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopLogosRow extends StatelessWidget {
  const _TopLogosRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: const [
        _TopLogo(assetPath: 'assets/LOGO2.jpg'),
        _TopLogo(assetPath: 'assets/LOGO1.jpg'),
      ],
    );
  }
}

class _TopLogo extends StatelessWidget {
  final String assetPath;
  const _TopLogo({required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        assetPath,
        width: 58,
        height: 58,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            width: 58,
            height: 58,
            color: Colors.black12,
            alignment: Alignment.center,
            child: const Icon(Icons.image_not_supported_outlined, color: Colors.black45),
          );
        },
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
                    color: color.withValues(alpha: 0.12),
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
