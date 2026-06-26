import 'package:atta/src/services/api/api_client.dart';

class ReviewsApi {
  const ReviewsApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> listSellerReviews(String sellerId) async {
    final response = await _client.get('/users/$sellerId/reviews');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> addReview({
    required String sellerId,
    required String listingId,
    required int rating,
    required String text,
    String? reviewerName,
  }) async {
    final response = await _client.post(
      '/users/$sellerId/reviews',
      authorized: true,
      body: {
        'listing_id': listingId,
        'rating': rating,
        'text': text,
        if (reviewerName != null && reviewerName.trim().isNotEmpty)
          'reviewer_name': reviewerName.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> updateReview(
    String reviewId, {
    int? rating,
    String? text,
    String? replyText,
  }) async {
    final response = await _client.patch(
      '/reviews/$reviewId',
      authorized: true,
      body: {
        if (rating != null) 'rating': rating,
        if (text != null) 'text': text,
        if (replyText != null) 'reply_text': replyText,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> deleteReview(String reviewId) async {
    final response =
        await _client.delete('/reviews/$reviewId', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }
}
