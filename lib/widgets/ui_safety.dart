import 'package:flutter/material.dart';

/// SafeText: single-line text with ellipsis by default, for labels/titles.
class SafeText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int maxLines;
  final TextOverflow overflow;

  const SafeText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// KeyValueRow: label | value with safe ellipsis and alignment.
class KeyValueRow extends StatelessWidget {
  final Widget? leadingIcon;
  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final CrossAxisAlignment crossAxisAlignment;

  const KeyValueRow({
    super.key,
    this.leadingIcon,
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        if (leadingIcon != null) ...[
          leadingIcon!,
          const SizedBox(width: 12),
        ],
        Expanded(
          child: SafeText(label, style: labelStyle ?? const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500, fontSize: 15)),
        ),
        Expanded(
          flex: 2,
          child: SafeText(
            value,
            style: valueStyle ?? const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 15),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// ChipStrip: horizontally scrollable row of chips/buttons.
class ChipStrip extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double gap;

  const ChipStrip({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.gap = 8,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            children[i],
          ]
        ],
      ),
    );
  }
}
