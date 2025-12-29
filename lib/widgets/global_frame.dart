import 'package:flutter/material.dart';

/// GlobalFrame applies a universal SafeArea + horizontal centering +
/// max width constraint. It intentionally does NOT add scrolling so
/// that existing scrollable bodies (ListView, SingleChildScrollView,
/// CustomScrollView) are not broken or given unbounded height.
///
/// This provides a "universal" baseline to reduce horizontal overflow
/// and notch overlap across all routes with a single application in
/// MaterialApp.builder.
class GlobalFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  const GlobalFrame({
    super.key,
    required this.child,
    this.maxWidth = 900,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cap = constraints.maxWidth > maxWidth ? maxWidth : constraints.maxWidth;
          return Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cap),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}
