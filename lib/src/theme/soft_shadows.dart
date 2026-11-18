import 'dart:math' as math;

import 'package:flutter/material.dart';

Color attaSoftShadowColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark
      ? Colors.black.withValues(alpha: 0.20)
      : const Color(0x1F547CA5);
}

/// Light separation for regular cards and self-contained content blocks.
List<BoxShadow> attaSoftCardShadows(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return <BoxShadow>[
    BoxShadow(
      color: isDark
          ? Colors.black.withValues(alpha: 0.22)
          : const Color(0x1F547CA5),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: isDark
          ? Colors.black.withValues(alpha: 0.12)
          : const Color(0x10547CA5),
      blurRadius: 24,
      spreadRadius: -2,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Main-screen separation kept as a dedicated variant so later home-only
/// adjustments cannot affect the rest of the app. Its current cool-blue tone
/// matches the approved profile surfaces.
List<BoxShadow> attaHomeSoftCardShadows(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return const <BoxShadow>[
      BoxShadow(
        color: Color(0x3D7CA1C7),
        blurRadius: 3,
        offset: Offset.zero,
      ),
      BoxShadow(
        color: Color(0x247CA1C7),
        blurRadius: 10,
        offset: Offset(0, 1),
      ),
      BoxShadow(
        color: Color(0x127CA1C7),
        blurRadius: 22,
        offset: Offset(0, 4),
      ),
    ];
  }
  return const <BoxShadow>[
    BoxShadow(
      color: Color(0x38547CA5),
      blurRadius: 3,
      offset: Offset.zero,
    ),
    BoxShadow(
      color: Color(0x20547CA5),
      blurRadius: 10,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x10547CA5),
      blurRadius: 22,
      offset: Offset(0, 4),
    ),
  ];
}

/// The previously approved cool-blue treatment used outside the main screen.
/// Keeping it separate prevents later home-only color adjustments from
/// changing profile and filter surfaces.
List<BoxShadow> attaCoolSoftCardShadows(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return attaSoftCardShadows(context);
  }
  return const <BoxShadow>[
    BoxShadow(
      color: Color(0x38547CA5),
      blurRadius: 3,
      offset: Offset.zero,
    ),
    BoxShadow(
      color: Color(0x20547CA5),
      blurRadius: 10,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x10547CA5),
      blurRadius: 22,
      offset: Offset(0, 4),
    ),
  ];
}

/// Adds a subtle continuation of existing shadows only around rounded arcs.
///
/// The painter sits behind the opaque surface, so its inner half is hidden and
/// the already approved straight-edge shadows remain visually unchanged.
class AttaRoundedCornerShadowSupport extends StatelessWidget {
  const AttaRoundedCornerShadowSupport({
    super.key,
    required this.radius,
    required this.shadows,
    required this.child,
  });

  final double radius;
  final List<BoxShadow> shadows;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (shadows.isEmpty) {
      return child;
    }
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RoundedCornerShadowPainter(
                radius: radius,
                shadows: shadows,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _RoundedCornerShadowPainter extends CustomPainter {
  const _RoundedCornerShadowPainter({
    required this.radius,
    required this.shadows,
  });

  final double radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final cornerRadius =
        math.min(radius, math.min(size.width, size.height) / 2);
    if (cornerRadius <= 0) return;

    for (final shadow in shadows) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = shadow.color.withValues(alpha: shadow.color.a * 0.42)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          _convertRadiusToSigma(shadow.blurRadius),
        );
      final offset = shadow.offset;
      final diameter = cornerRadius * 2;
      final topLeft = Rect.fromLTWH(
        offset.dx,
        offset.dy,
        diameter,
        diameter,
      );
      final topRight = Rect.fromLTWH(
        size.width - diameter + offset.dx,
        offset.dy,
        diameter,
        diameter,
      );
      final bottomRight = Rect.fromLTWH(
        size.width - diameter + offset.dx,
        size.height - diameter + offset.dy,
        diameter,
        diameter,
      );
      final bottomLeft = Rect.fromLTWH(
        offset.dx,
        size.height - diameter + offset.dy,
        diameter,
        diameter,
      );

      canvas
        ..drawArc(topLeft, math.pi, math.pi / 2, false, arcPaint)
        ..drawArc(topRight, math.pi * 1.5, math.pi / 2, false, arcPaint)
        ..drawArc(bottomRight, 0, math.pi / 2, false, arcPaint)
        ..drawArc(bottomLeft, math.pi / 2, math.pi / 2, false, arcPaint);
    }
  }

  static double _convertRadiusToSigma(double radius) =>
      radius > 0 ? radius * 0.57735 + 0.5 : 0;

  @override
  bool shouldRepaint(covariant _RoundedCornerShadowPainter oldDelegate) =>
      radius != oldDelegate.radius || shadows != oldDelegate.shadows;
}

/// Moderate depth for controls that float above maps and other content.
List<BoxShadow> attaFloatingControlShadows(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.11),
      blurRadius: 12,
      spreadRadius: -1,
      offset: const Offset(0, 4),
    ),
  ];
}

/// Stronger depth reserved for overlays, floating previews and modal surfaces.
List<BoxShadow> attaModalOverlayShadows(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.12),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.10),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Backwards-compatible name used by existing card surfaces.
List<BoxShadow> attaSoftShadows(BuildContext context) =>
    attaSoftCardShadows(context);
