import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FavoritesService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Стрим избранных id объявлений пользователя
  Stream<Set<String>> streamFavoriteIds(String uid) {
    final stream = _client
        .from('favorites')
        .stream(primaryKey: ['user_id', 'listing_id'])
        .order('created_at', ascending: false);

    return stream.map((rows) {
      return rows
          .where((row) => row['user_id']?.toString() == uid)
          .map((row) => row['listing_id'].toString())
          .toSet();
    });
  }

  /// Добавить / убрать из избранного
  Future<void> toggleFavorite({
    required String uid,
    required String listingId,
    required bool makeFavorite,
  }) async {
    try {
      if (makeFavorite) {
        await _client.from('favorites').upsert(
          {
            'user_id': uid,
            'listing_id': listingId,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'user_id,listing_id',
        );
      } else {
        await _client
            .from('favorites')
            .delete()
            .eq('user_id', uid)
            .eq('listing_id', listingId);
      }
    } catch (e) {
      debugPrint('Ошибка при изменении избранного: $e');
      rethrow;
    }
  }
}
