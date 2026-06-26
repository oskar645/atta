class ShowcaseItem {
  final String promotionId;
  final String listingId;
  final String title;
  final int price;
  final String city;
  final String? firstPhotoUrl;
  final String sellerId;
  final String sellerName;
  final String? sellerAvatarUrl;
  final double? sellerRating;
  final String category;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int impressionsCount;
  final int clicksCount;

  const ShowcaseItem({
    required this.promotionId,
    required this.listingId,
    required this.title,
    required this.price,
    required this.city,
    required this.firstPhotoUrl,
    required this.sellerId,
    required this.sellerName,
    required this.sellerAvatarUrl,
    required this.sellerRating,
    required this.category,
    required this.startsAt,
    required this.endsAt,
    required this.impressionsCount,
    required this.clicksCount,
  });

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  factory ShowcaseItem.fromMap(Map<String, dynamic> map) {
    return ShowcaseItem(
      promotionId: (map['promotionId'] ?? map['promotion_id'] ?? '').toString(),
      listingId: (map['listingId'] ?? map['listing_id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      price: (map['price'] ?? 0) is num ? (map['price'] as num).toInt() : 0,
      city: (map['city'] ?? '').toString(),
      firstPhotoUrl: (map['firstPhotoUrl'] ?? map['first_photo_url'])
                  ?.toString()
                  .trim()
                  .isEmpty ??
              true
          ? null
          : (map['firstPhotoUrl'] ?? map['first_photo_url']).toString(),
      sellerId: (map['sellerId'] ?? map['seller_id'] ?? '').toString(),
      sellerName: (map['sellerName'] ?? map['seller_name'] ?? '').toString(),
      sellerAvatarUrl: (map['sellerAvatarUrl'] ?? map['seller_avatar_url'])
                  ?.toString()
                  .trim()
                  .isEmpty ??
              true
          ? null
          : (map['sellerAvatarUrl'] ?? map['seller_avatar_url']).toString(),
      sellerRating: (map['sellerRating'] ?? map['seller_rating']) is num
          ? ((map['sellerRating'] ?? map['seller_rating']) as num).toDouble()
          : null,
      category: (map['category'] ?? '').toString(),
      startsAt: _parseDate(map['startsAt'] ?? map['starts_at']),
      endsAt: _parseDate(map['endsAt'] ?? map['ends_at']),
      impressionsCount: (map['impressionsCount'] ??
              map['impressions_count'] ??
              0) is num
          ? ((map['impressionsCount'] ?? map['impressions_count'] ?? 0) as num)
              .toInt()
          : 0,
      clicksCount: (map['clicksCount'] ?? map['clicks_count'] ?? 0) is num
          ? ((map['clicksCount'] ?? map['clicks_count'] ?? 0) as num).toInt()
          : 0,
    );
  }
}
