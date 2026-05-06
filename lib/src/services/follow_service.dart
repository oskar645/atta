import 'package:supabase_flutter/supabase_flutter.dart';

class FollowedSeller {
  final String sellerId;
  final DateTime followedAt;

  const FollowedSeller({
    required this.sellerId,
    required this.followedAt,
  });
}

class FollowService {
  final SupabaseClient _db = Supabase.instance.client;

  DateTime _parseFollowedAt(dynamic value) {
    if (value is DateTime) return value.toUtc();
    final parsed = DateTime.tryParse((value ?? '').toString());
    return (parsed ?? DateTime.now()).toUtc();
  }

  Stream<int> streamFollowersCount(String sellerId) {
    final id = sellerId.trim();
    if (id.isEmpty) return const Stream<int>.empty();

    return _db
        .from('user_follows')
        .stream(primaryKey: ['follower_id', 'seller_id']).map(
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
        .stream(primaryKey: ['follower_id', 'seller_id']).map(
      (rows) => rows.any(
        (row) =>
            row['follower_id']?.toString() == follower &&
            row['seller_id']?.toString() == seller,
      ),
    );
  }

  Stream<List<FollowedSeller>> streamFollowedSellers(String followerId) {
    final follower = followerId.trim();
    if (follower.isEmpty) return Stream<List<FollowedSeller>>.value(const []);

    return _db
        .from('user_follows')
        .stream(primaryKey: ['follower_id', 'seller_id'])
        .eq('follower_id', follower)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => FollowedSeller(
                    sellerId: (row['seller_id'] ?? '').toString(),
                    followedAt: _parseFollowedAt(row['created_at']),
                  ))
              .where((x) => x.sellerId.trim().isNotEmpty)
              .toList(),
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
