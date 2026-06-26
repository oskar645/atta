import 'package:atta/src/models/active_promotion.dart';

class ListingStats {
  final int views;
  final int favorites;
  final int messages;
  final int calls;
  final int showcaseImpressions;
  final int showcaseClicks;
  final List<ActivePromotion> activePromotions;

  const ListingStats({
    required this.views,
    required this.favorites,
    required this.messages,
    required this.calls,
    required this.showcaseImpressions,
    required this.showcaseClicks,
    required this.activePromotions,
  });
}
