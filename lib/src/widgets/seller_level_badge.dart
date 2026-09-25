import 'package:flutter/material.dart';

enum SellerLevelBadgeSize {
  large,
  compact,
}

class SellerLevelBadge extends StatelessWidget {
  const SellerLevelBadge({
    super.key,
    required this.level,
    this.size = SellerLevelBadgeSize.compact,
  });

  final String? level;
  final SellerLevelBadgeSize size;

  static String? levelFromRow(Map<String, dynamic> row) {
    final value = (row['sellerLevel'] ?? row['seller_level'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return switch (value) {
      'bronze' || 'silver' || 'gold' => value,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final normalized = _normalize(level);
    if (normalized == null) return const SizedBox.shrink();

    final config = _config(normalized);

    return Semantics(
      label: config.label,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = _metrics(constraints.maxWidth);
          final labelParts = config.label.split(' ');

          return SizedBox(
            width: metrics.badgeWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  config.asset,
                  width: metrics.imageSize,
                  height: metrics.imageSize,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 2),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SellerLevelLabelLine(
                      text: labelParts.first,
                      color: config.color,
                      fontSize: metrics.fontSize,
                    ),
                    _SellerLevelLabelLine(
                      text: labelParts.last,
                      color: config.color,
                      fontSize: metrics.fontSize,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  _SellerLevelBadgeMetrics _metrics(double maxWidth) {
    final isLarge = size == SellerLevelBadgeSize.large;
    final fallbackWidth = isLarge ? 58.0 : 48.0;
    final minWidth = isLarge ? 52.0 : 42.0;
    final maxBadgeWidth = isLarge ? 64.0 : 52.0;
    final width = maxWidth.isFinite
        ? maxWidth.clamp(minWidth, maxBadgeWidth).toDouble()
        : fallbackWidth;

    final fontMin = isLarge ? 10.0 : 8.0;
    final fontMax = isLarge ? 12.0 : 11.0;
    final fontDivisor = isLarge ? 5.15 : 5.15;
    final fontSize = (width / fontDivisor).clamp(fontMin, fontMax).toDouble();

    final imageMin = isLarge ? 28.0 : 20.0;
    final imageMax = isLarge ? 32.0 : 24.0;
    final imageDivisor = isLarge ? 2.0 : 2.15;
    final imageSize =
        (width / imageDivisor).clamp(imageMin, imageMax).toDouble();

    return _SellerLevelBadgeMetrics(
      badgeWidth: width,
      imageSize: imageSize,
      fontSize: fontSize,
    );
  }

  String? _normalize(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    return switch (normalized) {
      'bronze' || 'silver' || 'gold' => normalized,
      _ => null,
    };
  }

  _SellerLevelConfig _config(String level) {
    return switch (level) {
      'bronze' => const _SellerLevelConfig(
          asset: 'assets/seller_levels/bronze.png',
          label: 'Бронзовый продавец',
          color: Color(0xFFB86A32),
        ),
      'silver' => const _SellerLevelConfig(
          asset: 'assets/seller_levels/silver.png',
          label: 'Серебряный продавец',
          color: Color(0xFF7A7F87),
        ),
      _ => const _SellerLevelConfig(
          asset: 'assets/seller_levels/gold.png',
          label: 'Золотой продавец',
          color: Color(0xFFC49116),
        ),
    };
  }
}

class _SellerLevelConfig {
  const _SellerLevelConfig({
    required this.asset,
    required this.label,
    required this.color,
  });

  final String asset;
  final String label;
  final Color color;
}

class _SellerLevelBadgeMetrics {
  const _SellerLevelBadgeMetrics({
    required this.badgeWidth,
    required this.imageSize,
    required this.fontSize,
  });

  final double badgeWidth;
  final double imageSize;
  final double fontSize;
}

class _SellerLevelLabelLine extends StatelessWidget {
  const _SellerLevelLabelLine({
    required this.text,
    required this.color,
    required this.fontSize,
  });

  final String text;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
          height: 1.05,
        ),
      ),
    );
  }
}
