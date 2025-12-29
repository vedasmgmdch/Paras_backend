import 'package:flutter/material.dart';

/// Basic breakpoint definitions for adaptive layout.
class Breakpoints {
  static const double xs = 360;   // very small phones
  static const double sm = 600;   // phones / phablets
  static const double md = 960;   // tablets portrait
  static const double lg = 1280;  // tablets landscape / small desktop
  static const double xl = 1600;  // large desktop
}

class Responsive {
  static double width(BuildContext context) => MediaQuery.of(context).size.width;
  static bool isXS(BuildContext context) => width(context) < Breakpoints.xs;
  static bool isSM(BuildContext context) => width(context) < Breakpoints.sm;
  static bool isMD(BuildContext context) => width(context) < Breakpoints.md;
  static bool isLG(BuildContext context) => width(context) < Breakpoints.lg;
  static bool isXL(BuildContext context) => width(context) >= Breakpoints.lg;

  /// Horizontal padding that scales down for tiny screens and scales up modestly for large screens.
  static EdgeInsets adaptivePagePadding(BuildContext context) {
    final w = width(context);
    if (w < Breakpoints.xs) return const EdgeInsets.symmetric(horizontal: 12, vertical: 16);
    if (w < Breakpoints.sm) return const EdgeInsets.symmetric(horizontal: 20, vertical: 20);
    if (w < Breakpoints.md) return const EdgeInsets.symmetric(horizontal: 32, vertical: 24);
    if (w < Breakpoints.lg) return const EdgeInsets.symmetric(horizontal: 48, vertical: 32);
    return const EdgeInsets.symmetric(horizontal: 72, vertical: 40);
  }

  /// Constrains a child to a max width and centers it.
  static Widget maxWidth({required double maxWidth, required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final constrained = width > maxWidth
            ? Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: maxWidth, child: child),
              )
            : child;
        return constrained;
      },
    );
  }

  /// Scales a base spacing value slightly depending on width.
  static double scaleSpacing(BuildContext context, double base) {
    final w = width(context);
    if (w < Breakpoints.xs) return base * 0.75;
    if (w < Breakpoints.sm) return base * 0.85;
    if (w < Breakpoints.md) return base;
    if (w < Breakpoints.lg) return base * 1.15;
    return base * 1.25;
  }
}
