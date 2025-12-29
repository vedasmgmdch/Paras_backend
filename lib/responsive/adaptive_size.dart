import 'package:flutter/material.dart';

/// AdaptiveSize provides lightweight scaling helpers so UI feels consistent
/// across small phones, large phones, tablets and desktop form factors
/// without enforcing a rigid pixel-perfect layout.
///
/// Design philosophy:
/// - Start from a reference (design) logical width.
/// - Scale up/down within a safe clamped range so typography does not
///   become unreadably small or cartoonishly large.
/// - Offer separate curves for spacing and font sizing (fonts scale a bit less).
class AdaptiveSize {
  /// Logical design width your UI mocks roughly targeted (e.g. iPhone 12 ~390).
  static const double _designWidth = 390.0;

  /// Min / max scale factors applied to generic sizing (padding, gaps, radii).
  static const double _minScale = 0.80;
  static const double _maxScale = 1.35;

  /// Font scaling uses a tighter clamp so text remains accessible.
  static const double _minFontScale = 0.90;
  static const double _maxFontScale = 1.22;

  /// Returns the raw unclamped scale (currentWidth / designWidth).
  static double rawScale(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w <= 0) return 1.0;
    return w / _designWidth;
  }

  /// Scale for general sizes (spacing, container widths) with clamp.
  static double scale(BuildContext context) {
    final s = rawScale(context);
    if (s < _minScale) return _minScale;
    if (s > _maxScale) return _maxScale;
    return s;
  }

  /// Scale specifically for fonts (narrower clamp).
  static double fontScale(BuildContext context) {
    final s = rawScale(context);
    if (s < _minFontScale) return _minFontScale;
    if (s > _maxFontScale) return _maxFontScale;
    return s;
  }

  /// Scales an arbitrary size (double) with general scale.
  static double size(BuildContext context, double base) => base * scale(context);

  /// Scales a font size with font scale.
  static double font(BuildContext context, double base) => base * fontScale(context);

  /// Convenience for vertical/horizontal gap sizing.
  static SizedBox vGap(BuildContext context, double base) => SizedBox(height: size(context, base));
  static SizedBox hGap(BuildContext context, double base) => SizedBox(width: size(context, base));

  /// Adaptive horizontal page padding (symmetric) based on width with smooth curve.
  static EdgeInsets pagePadding(BuildContext context, {double base = 24.0}) {
    final p = size(context, base);
    return EdgeInsets.symmetric(horizontal: p, vertical: p * 0.75);
  }
}

/// Extension for ergonomic usage: 16.adapt(context), 18.adaptFont(context)
extension AdaptiveNum on num {
  double adapt(BuildContext context) => AdaptiveSize.size(context, toDouble());
  double adaptFont(BuildContext context) => AdaptiveSize.font(context, toDouble());
}
