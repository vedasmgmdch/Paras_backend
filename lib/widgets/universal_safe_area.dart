import 'package:flutter/material.dart';

/// UniversalOverflowSafe wraps arbitrary content to prevent common
/// layout overflow issues on very small or very large devices.
///
/// Features:
/// - SafeArea to avoid notches.
/// - SingleChildScrollView for vertical overflow.
/// - Center + ConstrainedBox to limit max width so content isn't too wide on tablets.
/// - Optional min padding.
/// - Keeps intrinsic scrolling for inner ListView/GridView (caller should avoid nesting scroll views improperly).
class UniversalOverflowSafe extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final Alignment alignment;
  final bool enableScroll;

  const UniversalOverflowSafe({
    super.key,
    required this.child,
    this.maxWidth = 680,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    this.alignment = Alignment.topCenter,
    this.enableScroll = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget core = Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
        ),
        child: child,
      ),
    );

    if (enableScroll) {
      core = SingleChildScrollView(
        padding: padding,
        child: core,
      );
    } else {
      core = Padding(
        padding: padding,
        child: core,
      );
    }

    return SafeArea(child: core);
  }
}
