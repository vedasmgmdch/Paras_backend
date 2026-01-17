import 'package:flutter/material.dart';

class AuthDialogs {
  static Future<bool> confirmSessionTakeover(BuildContext context) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account in use'),
        content: const Text(
          'This account is currently active on another device. Do you want to login here and sign out the other device?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Login here')),
        ],
      ),
    );
    return res == true;
  }
}
