import 'package:flutter/material.dart';

import '../models/listing.dart';
import '../services/reviews_service.dart';
import '../utils/price_formatter.dart';
import 'listing_promotion_badges.dart';
import 'media_preview_box.dart';

class ListingCard extends StatelessWidget {
  final Listing listing;
  final bool isFav;
  final bool isSeen;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggleFav;
  final ReviewsService reviews;

  const ListingCard({
    super.key,
    required this.listing,
    required this.isFav,
    required this.isSeen,
    required this.onOpen,
    required this.onToggleFav,
    required this.reviews,
  });

  @override
  Widget build(BuildContext context) {
    final photo = listing.firstPhotoUrl;
    final cityShort = listing.cityShort.trim();
    final hasVipPromotion = listing.hasVipPromotion;
    final hasBumpPromotion = listing.hasBumpPromotion;
    final borderColor = hasVipPromotion
        ? vipBorderColor(context)
        : Theme.of(context).colorScheme.outlineVariant;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: borderColor,
            width: hasVipPromotion ? 1.25 : 1,
          ),
        ),
        shadowColor: hasVipPromotion
            ? vipAccentColor(context).withValues(alpha: 0.20)
            : null,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: photo == null || photo.isEmpty
                            ? const MediaPreviewBox(
                                imageUrl: '',
                                categoryHint: 'listings',
                                borderRadius: 0,
                              )
                            : MediaPreviewBox(
                                imageUrl: photo,
                                categoryHint: 'listings',
                                borderRadius: 0,
                              ),
                      ),
                      if (isSeen)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            color: Colors.transparent,
                            child: const Text(
                              'Просмотрено',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ListingPromotionBadges(
                        showVip: false,
                        showBump: hasBumpPromotion,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              listing.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                height: 1.05,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            height: 28,
                            width: 28,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 28,
                                height: 28,
                              ),
                              onPressed: () => onToggleFav(!isFav),
                              icon: Icon(
                                isFav ? Icons.favorite : Icons.favorite_border,
                                color: isFav
                                    ? Colors.red
                                    : Theme.of(context).colorScheme.outline,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: hasVipPromotion
                                ? Border.all(
                                    color: vipBorderColor(context),
                                    width: 1.1,
                                  )
                                : null,
                            color: hasVipPromotion
                                ? vipAccentColor(context).withValues(alpha: 0.08)
                                : Colors.transparent,
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: hasVipPromotion ? 8 : 0,
                              vertical: hasVipPromotion ? 4 : 0,
                            ),
                            child: Text(
                              '${formatPrice(listing.price)} ₽',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: hasVipPromotion
                                    ? vipBorderColor(context)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      StreamBuilder<Map<String, dynamic>>(
                        stream: reviews.streamSellerRating(listing.ownerId),
                        builder: (context, rSnap) {
                          final avg =
                              (rSnap.data?['avg'] as num?)?.toDouble() ?? 0.0;
                          final cnt =
                              (rSnap.data?['count'] as num?)?.toInt() ?? 0;

                          return Row(
                            children: [
                              const Icon(Icons.star,
                                  size: 14, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(
                                avg.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '($cnt)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cityShort.isEmpty ? 'Город не указан' : cityShort,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ),
                          if (hasVipPromotion) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: vipAccentColor(context),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.workspace_premium_rounded,
                                    size: 11,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'VIP',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
