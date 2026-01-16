import 'package:flutter/material.dart';

/// ResponsiveHeaderRow automatically reflows between a single-line Row and a
/// two-line layout (text above, action right) when space is tight or text scale is high.
///
/// Usage:
///   ResponsiveHeaderRow(
///     icon: Icons.schedule,
///     label: 'Next reminder: Today 08:30',
///     action: TextButton(onPressed: ..., child: Text('Manage')),
///   )
class ResponsiveHeaderRow extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Widget action;
  final double narrowWidth;
  final double maxTextScaleBeforeWrap;
  final TextStyle? labelStyle;

  const ResponsiveHeaderRow({
    super.key,
    this.icon,
    required this.label,
    required this.action,
    this.narrowWidth = 340,
    this.maxTextScaleBeforeWrap = 1.3,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        // Use new text scaling API (textScaleFactorOf is deprecated)
        final textScaler = MediaQuery.textScalerOf(context);
        final textScale = textScaler.scale(1.0);
        final narrow = c.maxWidth < narrowWidth || textScale > maxTextScaleBeforeWrap;

        final textWidget = Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle ?? TextStyle(fontSize: 15, color: cs.onSurface),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                  ],
                  Expanded(child: textWidget),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: action,
              ),
            ],
          );
        }

        return Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
            ],
            Expanded(child: textWidget),
            const SizedBox(width: 8),
            action,
          ],
        );
      },
    );
  }
}
