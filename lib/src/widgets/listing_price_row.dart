import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../utils/price_formatter.dart';

class ListingPriceRow extends StatelessWidget {
  final Listing listing;
  final TextStyle? style;

  const ListingPriceRow({
    super.key,
    required this.listing,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style;
    final previousPrice =
        listing.hasActivePriceReduction ? listing.previousPrice : null;
    final oldPriceStyle =
        (baseStyle ?? DefaultTextStyle.of(context).style).copyWith(
      color: Theme.of(context).colorScheme.outline,
      decoration: TextDecoration.lineThrough,
      decorationColor: Theme.of(context).colorScheme.outline,
      fontSize:
          ((baseStyle ?? DefaultTextStyle.of(context).style).fontSize ?? 14) *
              0.48,
      fontWeight: FontWeight.w600,
      height: 0.9,
    );
    final baseFontSize =
        (baseStyle ?? DefaultTextStyle.of(context).style).fontSize ?? 14;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          key: const ValueKey('listing_current_price'),
          '${formatPrice(listing.price)} ₽',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: baseStyle,
        ),
        if (previousPrice != null) ...[
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: baseFontSize * 5.4),
            child: Text(
              key: const ValueKey('listing_previous_price'),
              formatPrice(previousPrice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: oldPriceStyle,
            ),
          ),
          const SizedBox(width: 1),
          const Icon(
            key: ValueKey('listing_price_down_arrow'),
            Icons.arrow_downward,
            size: 9,
            weight: 800,
            opticalSize: 10,
            color: Colors.blue,
          ),
        ],
      ],
    );
  }
}
