import 'package:flutter/widgets.dart';
import '../app_state.dart';

/// Mixin to provide a unified post-frame snapshot trigger for instruction screens.
/// Usage: in initState(), after local state prepared, call scheduleInitialSnapshot(() => _saveAllLogsForDay());
mixin InstructionSnapshotHelper<T extends StatefulWidget> on State<T> {
  void scheduleInitialSnapshot(VoidCallback snapshotFn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) snapshotFn();
    });
  }

  /// Standard date string (yyyy-MM-dd) using AppState helper.
  String formatYMD(DateTime dt) => AppState.formatYMD(dt);
}