import 'package:atta/src/theme/soft_shadows.dart';
import 'package:flutter/material.dart';

/// The approved white, cool-shadow surface used by profile-related screens.
///
/// It deliberately keeps dark mode on the existing theme surface and neutral
/// shadow treatment provided by [attaCoolSoftCardShadows].
class AttaCoolSurface extends StatelessWidget {
  const AttaCoolSurface({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final double borderRadius;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(borderRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: attaCoolSoftCardShadows(context),
      ),
      child: Material(
        color: theme.brightness == Brightness.light
            ? Colors.white
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: child,
      ),
    );
  }
}

/// A compact confirmation dialog matching the profile surface treatment.
class AttaCoolConfirmationDialog extends StatelessWidget {
  const AttaCoolConfirmationDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = 20.0;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.light
              ? Colors.white
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: attaCoolSoftCardShadows(context),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle(
                style: theme.textTheme.headlineSmall ?? const TextStyle(),
                child: title,
              ),
              const SizedBox(height: 16),
              DefaultTextStyle(
                style: theme.textTheme.bodyMedium ?? const TextStyle(),
                child: content,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: OverflowBar(
                  spacing: 8,
                  children: actions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the current layout while giving switches the clean native iOS look.
class AttaIosSwitchTheme extends StatelessWidget {
  const AttaIosSwitchTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SwitchTheme(
      data: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF34C759);
          }
          return isDark ? const Color(0xFF39393D) : const Color(0xFFE5E5EA);
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        splashRadius: 18,
      ),
      child: child,
    );
  }
}
