import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

// A small, dismissible card that helps users enable exact alarms,
// allow notifications, and disable battery optimizations on aggressive ROMs.
class ReliabilityTipsCard extends StatefulWidget {
  const ReliabilityTipsCard({super.key});

  @override
  State<ReliabilityTipsCard> createState() => _ReliabilityTipsCardState();
}

class _ReliabilityTipsCardState extends State<ReliabilityTipsCard> {
  static const _prefsKeyHidden = 'reliability_tips_hidden_v1';
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _loadHidden();
  }

  Future<void> _loadHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final h = prefs.getBool(_prefsKeyHidden) ?? false;
      if (mounted) setState(() => _hidden = h);
    } catch (_) {}
  }

  Future<void> _setHidden(bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeyHidden, v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB2DFDB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alarm, color: Color(0xFF00796B)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Make reminders more reliable',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Hide',
                icon: const Icon(Icons.close),
                onPressed: () async {
                  setState(() => _hidden = true);
                  await _setHidden(true);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'For best on-time delivery, please:',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TipButton(
                icon: Icons.notifications_active,
                label: 'Allow notifications',
                onTap: () async {
                  await NotificationService.ensurePermissions();
                  await NotificationService.openAppNotificationSettings();
                },
              ),
              if (Platform.isAndroid)
                _TipButton(
                  icon: Icons.access_alarm,
                  label: 'Enable exact alarms',
                  onTap: () async {
                    final ok = await NotificationService.requestExactAlarmsPermission();
                    if (!ok) {
                      // Some ROMs require visiting settings manually
                      await NotificationService.openExactAlarmsSettings();
                    }
                  },
                ),
              if (Platform.isAndroid)
                _TipButton(
                  icon: Icons.battery_saver,
                  label: 'Disable battery optimization',
                  onTap: () async {
                    await NotificationService.openBatteryOptimizationSettings();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Tip: Some devices delay alarms when battery saver is on. These steps help the phone deliver reminders exactly at the scheduled time.',
            style: TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _TipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _TipButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
