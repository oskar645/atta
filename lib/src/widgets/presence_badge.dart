import 'package:flutter/material.dart';

class PresenceBadge extends StatelessWidget {
  const PresenceBadge({
    super.key,
    required this.child,
    required this.isOnline,
    this.dotSize = 12,
    this.borderWidth = 2,
  });

  final Widget child;
  final bool isOnline;
  final double dotSize;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline
                  ? Colors.green
                  : Theme.of(context).colorScheme.outlineVariant,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: borderWidth,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
