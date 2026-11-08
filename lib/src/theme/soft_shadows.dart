import 'package:flutter/material.dart';

Color attaSoftShadowColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Colors.black.withValues(alpha: isDark ? 0.16 : 0.07);
}

List<BoxShadow> attaSoftShadows(BuildContext context) => <BoxShadow>[
      BoxShadow(
        color: attaSoftShadowColor(context),
        blurRadius: 8,
        spreadRadius: -1,
        offset: const Offset(0, 2),
      ),
    ];
