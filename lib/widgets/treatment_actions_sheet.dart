import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../app_state.dart';
import '../screens/treatment_screen.dart';

/// Shows the same Treatment Actions bottom sheet used in history screen.
/// Options:
/// - Mark Treatment Completed (with confirmation)
/// - Select/Change Treatment (navigate to TreatmentScreenMain)
Future<void> showTreatmentActionsSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final appState = Provider.of<AppState>(context, listen: false);
      final userName = appState.username ?? 'User';
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                const ListTile(
                  title: Text('Choose an action',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(appState.procedureCompleted == true
                      ? 'Start New Procedure'
                      : 'Mark Treatment Completed'),
                  subtitle: Text(appState.procedureCompleted == true
                      ? 'Locks the completed treatment and starts a new episode'
                      : 'Locks current treatment and starts a new episode'),
                  onTap: () async {
                    Navigator.of(ctx).pop();

                    // If the treatment is already marked completed, we only need to start a new episode.
                    if (appState.procedureCompleted == true) {
                      final ok =
                          await ApiService.startNewProcedureAfterCompletion();
                      if (!context.mounted) return;
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Failed to start a new procedure.')),
                        );
                        return;
                      }
                      await appState.startNewEpisodeLocally(
                          username: appState.username);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'New procedure started. Please select the new treatment.')),
                      );
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              TreatmentScreenMain(userName: userName),
                        ),
                      );
                      return;
                    }

                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        title: const Text('Confirm completion'),
                        content: const Text(
                            'Are you sure you want to mark the current treatment as completed? This will lock it and start a new episode.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(dCtx).pop(false),
                              child: const Text('Cancel')),
                          ElevatedButton(
                              onPressed: () => Navigator.of(dCtx).pop(true),
                              child: const Text('Mark Complete')),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    final success = await ApiService.markEpisodeComplete();
                    if (!context.mounted) return;
                    if (!success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Failed to mark previous treatment as complete.')),
                      );
                      return;
                    }

                    // Backend has started a fresh open episode; clear local state so UI doesn't
                    // keep showing the previous treatment.
                    await appState.startNewEpisodeLocally(
                        username: appState.username);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Treatment marked complete. A new episode has been started.')),
                    );

                    // Take user to select the next treatment for the new episode.
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TreatmentScreenMain(userName: userName),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.medical_services, color: Colors.blue),
                  title: const Text('Select/Change Treatment'),
                  subtitle: const Text(
                      'Pick a treatment and date/time without marking complete'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TreatmentScreenMain(userName: userName),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Completes the current treatment (locks it and opens a new episode),
/// then navigates to Treatment selection. No confirmation dialog.
/// If [replaceStack] is true, it will clear the navigation stack similar to
/// pushAndRemoveUntil behavior used in some instruction screens.
Future<void> completeThenSelectNewTreatment(
  BuildContext context, {
  bool replaceStack = false,
}) async {
  final success = await ApiService.markEpisodeComplete();
  if (!context.mounted) return;
  if (!success) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('Failed to finalize previous treatment. Please try again.')),
    );
    return;
  }

  final appState = Provider.of<AppState>(context, listen: false);
  await appState.startNewEpisodeLocally(username: appState.username);
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
        content: Text('Previous treatment completed. Starting a new one...')),
  );
  final userName = appState.username ?? 'User';
  final route = MaterialPageRoute(
    builder: (_) => TreatmentScreenMain(userName: userName),
  );
  if (replaceStack) {
    Navigator.of(context).pushAndRemoveUntil(route, (r) => false);
  } else {
    await Navigator.of(context).push(route);
  }
}
