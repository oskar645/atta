import 'package:supabase_flutter/supabase_flutter.dart';

class FollowService {
  final SupabaseClient _db = Supabase.instance.client;

  Stream<int> streamFollowersCount(String sellerId) {
    final id = sellerId.trim();
    if (id.isEmpty) return const Stream<int>.empty();

    return _db
        .from('user_follows')
        .stream(primaryKey: ['follower_id', 'seller_id'])
        .map(
          (rows) => rows.where((row) => row['seller_id']?.toString() == id).length,
        );
  }

  Stream<bool> streamIsFollowing({
    required String followerId,
    required String sellerId,
  }) {
    final follower = followerId.trim();
    final seller = sellerId.trim();
    if (follower.isEmpty || seller.isEmpty || follower == seller) {
      return Stream<bool>.value(false);
    }

    return _db
        .from('user_follows')
        .stream(primaryKey: ['follower_id', 'seller_id'])
        .map(
          (rows) => rows.any(
            (row) =>
                row['follower_id']?.toString() == follower &&
                row['seller_id']?.toString() == seller,
          ),
        );
  }

  Future<void> follow({
    required String followerId,
    required String sellerId,
  }) async {
    final follower = followerId.trim();
    final seller = sellerId.trim();
    if (follower.isEmpty || seller.isEmpty || follower == seller) return;

    final exists = await _db
        .from('user_follows')
        .select('follower_id')
        .eq('follower_id', follower)
        .eq('seller_id', seller)
        .maybeSingle();

    if (exists != null) return;

    await _db.from('user_follows').insert({
      'follower_id': follower,
      'seller_id': seller,
    });
  }

  Future<void> unfollow({
    required String followerId,
    required String sellerId,
  }) async {
    final follower = followerId.trim();
    final seller = sellerId.trim();
    if (follower.isEmpty || seller.isEmpty || follower == seller) return;

    await _db
        .from('user_follows')
        .delete()
        .eq('follower_id', follower)
        .eq('seller_id', seller);
  }

  Future<void> toggleFollow({
    required String followerId,
    required String sellerId,
    required bool isFollowing,
  }) {
    if (isFollowing) {
      return unfollow(followerId: followerId, sellerId: sellerId);
    }
    return follow(followerId: followerId, sellerId: sellerId);
  }
}
