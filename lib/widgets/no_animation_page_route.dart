import 'package:flutter/material.dart';

/// A route with no push/pop animation.
///
/// Used to avoid platform/page transition effects (like zoom-out)
/// that can feel jarring or get stuck on some devices.
class NoAnimationPageRoute<T> extends PageRouteBuilder<T> {
  NoAnimationPageRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) : super(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
        );
}
