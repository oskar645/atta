// lib/src/models/review.dart

class Review {
  final String id;
  final String sellerId;
  final String reviewerId;
  final String reviewerName;
  final String listingId;
  final int rating;
  final String text;
  final DateTime createdAt;

  final String? replyText;
  final DateTime? replyAt;

  Review({
    required this.id,
    required this.sellerId,
    required this.reviewerId,
    required this.reviewerName,
    required this.listingId,
    required this.rating,
    required this.text,
    required this.createdAt,
    this.replyText,
    this.replyAt,
  });

  static DateTime _parseDt(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  factory Review.fromMap(Map<String, dynamic> row) {
    return Review(
      id: row['id']?.toString() ?? '',
      sellerId: (row['seller_id'] ?? '').toString(),
      reviewerId: (row['reviewer_id'] ?? '').toString(),
      reviewerName: (row['reviewer_name'] ?? '').toString(),
      listingId: (row['listing_id'] ?? '').toString(),
      rating: (row['rating'] is num)
          ? (row['rating'] as num).toInt()
          : (int.tryParse('${row['rating']}') ?? 0),
      text: (row['text'] ?? '').toString(),
      createdAt: _parseDt(row['created_at']),
      replyText: row['reply_text']?.toString(),
      replyAt: row['reply_at'] == null ? null : _parseDt(row['reply_at']),
    );
  }
}
