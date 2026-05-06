import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReviewsService {
  final SupabaseClient _c = Supabase.instance.client;

  /// Все отзывы продавца (лента) — по seller_id
  Stream<List<Map<String, dynamic>>> streamSellerReviews(String sellerId) {
    final stream = _c
        .from('reviews')
        .stream(primaryKey: ['id'])
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);

    return stream.map((rows) => rows.cast<Map<String, dynamic>>());
  }

  /// Рейтинг продавца: avg + count (считаем на клиенте)
  Stream<Map<String, dynamic>> streamSellerRating(String sellerId) {
    return streamSellerReviews(sellerId).map((items) {
      if (items.isEmpty) return {'avg': 0.0, 'count': 0};

      double sum = 0;
      int cnt = 0;

      for (final r in items) {
        final v = r['rating'];
        if (v is num) {
          sum += v.toDouble();
          cnt++;
        }
      }

      final avg = cnt == 0 ? 0.0 : (sum / cnt);
      return {'avg': avg, 'count': cnt};
    });
  }

  /// Добавить отзыв — под твою схему:
  /// seller_id / reviewer_id / listing_id / rating / comment
  /// + сохраняем reviewer_name (чтобы в отзывах было имя, а не "Пользователь")
  Future<void> addReview({
    required String sellerId,
    required String reviewerId,
    required String reviewerName,
    required String listingId,
    required int rating,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;

    await _c.from('reviews').insert({
      'seller_id': sellerId,
      'reviewer_id': reviewerId,
      'reviewer_name': reviewerName.trim().isEmpty ? null : reviewerName.trim(),
      'listing_id': listingId,
      'rating': rating,
      'comment': t,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Ответ продавца на отзыв
  Future<void> replyToReview({
    required String sellerId,
    required String reviewId,
    required String replyText,
  }) async {
    final t = replyText.trim();
    if (t.isEmpty) return;

    await _c
        .from('reviews')
        .update({
          'reply_text': t,
          'reply_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', reviewId)
        .eq('seller_id', sellerId);
  }

  /// Удалить отзыв (используется из админского UI)
  Future<void> deleteReview({
    required String reviewId,
  }) async {
    final id = reviewId.trim();
    if (id.isEmpty) return;
    final deleted = await _c.from('reviews').delete().eq('id', id).select('id');
    if (deleted.isEmpty) {
      throw Exception(
        'Не удалось удалить отзыв. Проверьте права администратора для DELETE в Supabase.',
      );
    }
  }

  /// Пока no-op (если у тебя нет счетчика новых отзывов)
  Future<void> resetNewReviewsCount(String sellerId) async {
    return;
  }
}
