import 'package:flutter/material.dart';

Color vipAccentColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Color.alphaBlend(
    const Color(0xFFE2B24D).withValues(alpha: 0.88),
    scheme.surface,
  );
}

Color vipBorderColor(BuildContext context) {
  return vipAccentColor(context).withValues(alpha: 0.85);
}

class ListingPromotionBadges extends StatelessWidget {
  const ListingPromotionBadges({
    super.key,
    required this.showVip,
    required this.showBump,
  });

  final bool showVip;
  final bool showBump;

  @override
  Widget build(BuildContext context) {
    if (!showVip && !showBump) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 8,
      top: 8,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (showVip)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: vipAccentColor(context),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: vipAccentColor(context).withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                'VIP',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          if (showBump)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFF2E6FD8).withValues(alpha: 0.24),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A2E6FD8),
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_upward_rounded,
                size: 15,
                color: Color(0xFF2E6FD8),
              ),
            ),
        ],
      ),
    );
  }
}
