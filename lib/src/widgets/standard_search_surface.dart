import 'package:flutter/material.dart';

import '../theme/soft_shadows.dart';
import '../theme/ui_metrics.dart';

class StandardSearchSurface extends StatelessWidget {
  const StandardSearchSurface({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.boxShadows,
    this.surfaceColor,
    this.supportRoundedShadowCorners = false,
  });

  final Widget child;
  final double borderRadius;
  final List<BoxShadow>? boxShadows;
  final Color? surfaceColor;
  final bool supportRoundedShadowCorners;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shadows = boxShadows ?? attaCoolSoftCardShadows(context);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows,
      ),
      child: Material(
        color: surfaceColor ??
            (theme.brightness == Brightness.light
                ? Colors.white
                : theme.colorScheme.surface),
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: kStandardSearchFieldHeight,
          child: child,
        ),
      ),
    );
    if (!supportRoundedShadowCorners) return surface;
    return AttaRoundedCornerShadowSupport(
      radius: borderRadius,
      shadows: shadows,
      child: surface,
    );
  }
}
