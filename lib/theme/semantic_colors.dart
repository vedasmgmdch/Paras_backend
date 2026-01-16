import 'package:flutter/material.dart';

/// App-specific semantic colors used across screens.
///
/// Why: The app historically used many hardcoded colors (greens/reds/pastels)
/// that didn’t adapt to dark mode. This extension centralizes those tokens so
/// screens can stay layout-identical while colors remain consistent.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  /// Calendar-specific emphasis (procedure day).
  final Color procedure;
  final Color onProcedure;
  final Color procedureContainer;
  final Color onProcedureContainer;

  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.procedure,
    required this.onProcedure,
    required this.procedureContainer,
    required this.onProcedureContainer,
  });

  static AppSemanticColors light(ColorScheme cs) {
    return AppSemanticColors(
      // Matches existing app green.
      success: const Color(0xFF22B573),
      onSuccess: Colors.white,
      successContainer: const Color(0xFFE8F5E9),
      onSuccessContainer: const Color(0xFF0B2E1A),

      // Modern amber that isn’t neon.
      warning: const Color(0xFFF59E0B),
      onWarning: const Color(0xFF1A1200),
      warningContainer: const Color(0xFFFFF4D6),
      onWarningContainer: const Color(0xFF2B1D00),

      // Use app blue as informational.
      info: cs.primary,
      onInfo: cs.onPrimary,
      infoContainer: cs.primaryContainer,
      onInfoContainer: cs.onPrimaryContainer,

      // Soft pink for procedure day (keeps original feel).
      procedure: const Color(0xFFFF5A7A),
      onProcedure: Colors.white,
      procedureContainer: const Color(0xFFFFE0E6),
      onProcedureContainer: const Color(0xFF4A0B18),
    );
  }

  static AppSemanticColors dark(ColorScheme cs) {
    // In dark mode, prefer scheme-based containers so contrast stays correct.
    return AppSemanticColors(
      // Muted green that reads as "success" on charcoal surfaces.
      success: const Color(0xFF34D399),
      onSuccess: const Color(0xFF052012),
      successContainer: const Color(0xFF0E2A1B),
      onSuccessContainer: const Color(0xFFBFF3D2),

      // Warm amber that isn't neon.
      warning: const Color(0xFFFBBF24),
      onWarning: const Color(0xFF241400),
      warningContainer: const Color(0xFF2A1F07),
      onWarningContainer: const Color(0xFFFFE2A8),

      info: cs.primary,
      onInfo: cs.onPrimary,
      infoContainer: cs.primaryContainer,
      onInfoContainer: cs.onPrimaryContainer,

      // Procedure day: keep a pink accent but make it container-first.
      procedure: const Color(0xFFFF6B88),
      onProcedure: const Color(0xFF1B0A0E),
      procedureContainer: const Color(0xFF3A1A23),
      onProcedureContainer: const Color(0xFFFFD7E0),
    );
  }

  static AppSemanticColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppSemanticColors>();
    assert(ext != null, 'AppSemanticColors is not registered on ThemeData.extensions');
    return ext!;
  }

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? procedure,
    Color? onProcedure,
    Color? procedureContainer,
    Color? onProcedureContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      procedure: procedure ?? this.procedure,
      onProcedure: onProcedure ?? this.onProcedure,
      procedureContainer: procedureContainer ?? this.procedureContainer,
      onProcedureContainer: onProcedureContainer ?? this.onProcedureContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      procedure: Color.lerp(procedure, other.procedure, t)!,
      onProcedure: Color.lerp(onProcedure, other.onProcedure, t)!,
      procedureContainer: Color.lerp(procedureContainer, other.procedureContainer, t)!,
      onProcedureContainer: Color.lerp(onProcedureContainer, other.onProcedureContainer, t)!,
    );
  }
}
