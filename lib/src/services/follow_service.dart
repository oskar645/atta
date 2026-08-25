import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/user_follows_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';

class FollowedSeller {
  final String sellerId;
  final DateTime followedAt;

  const FollowedSeller({
    required this.sellerId,
    required this.followedAt,
  });
}

class FollowService {
  FollowService({
    UserFollowsApi? api,
  }) : _api = api ?? UserFollowsApi(_apiClient);

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);
  final UserFollowsApi _api;
  final Map<String, List<FollowedSeller>> _cache = {};
  final Map<String, StreamController<List<FollowedSeller>>>
      _followedControllers = <String, StreamController<List<FollowedSeller>>>{};
  final Map<String, StreamController<bool>> _isFollowingControllers =
      <String, StreamController<bool>>{};
  final Map<String, StreamController<int>> _followerCountControllers =
      <String, StreamController<int>>{};
  final Map<String, Future<List<FollowedSeller>>> _followedInFlight = {};
  final Map<String, Future<int>> _countInFlight = {};
  final Map<String, DateTime> _cacheAt = {};
  final Map<String, int> _followersCountCache = {};
  final Map<String, DateTime> _followersCountCachedAt = {};
  bool _timewebFollowsUnavailable = false;
  static const Duration _cacheTtl = Duration(minutes: 2);

  void _debugSource(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  void _markTimewebUnavailable(String message) {
    if (_timewebFollowsUnavailable) return;
    _timewebFollowsUnavailable = true;
    _debugSource(message);
  }

  Future<List<FollowedSeller>> _fetchFollowedSellers() async {
    try {
      final items = <FollowedSeller>[];
      final seen = <String>{};
      String? cursor;
      var hasMore = true;
      while (hasMore) {
        final response = await _api.list(limit: 100, cursor: cursor);
        final raw = response['items'];
        if (raw is List) {
          for (final row in raw.whereType<Map>()) {
            final map = Map<String, dynamic>.from(row);
            final sellerId = (map['seller_id'] ?? '').toString().trim();
            if (sellerId.isEmpty || !seen.add(sellerId)) continue;
            items.add(
              FollowedSeller(
                sellerId: sellerId,
                followedAt: _parseFollowedAt(map['created_at']),
              ),
            );
          }
        }
        cursor = (response['nextCursor'] ?? response['next_cursor'])
            ?.toString()
            .trim();
        if ((cursor ?? '').isEmpty) cursor = null;
        hasMore = response['hasMore'] == true && cursor != null;
      }
      return items;
    } on ApiException catch (error) {
      if (error.isNotFound) {
        _markTimewebUnavailable(
          'Follows source: Timeweb unavailable (404). Falling back to empty state until backend is updated.',
        );
        return const <FollowedSeller>[];
      }
      rethrow;
    }
  }

  Future<FollowedSellersPage> getFollowedSellersPage({
    required String followerId,
    int limit = 50,
    String? cursor,
    bool resetCache = false,
  }) async {
    if (runtimeType != FollowService) {
      if ((cursor ?? '').trim().isNotEmpty) {
        return const FollowedSellersPage(
          items: <FollowedSeller>[],
          hasMore: false,
        );
      }
      final items = await getFollowedSellers(followerId);
      return FollowedSellersPage(items: items, hasMore: false);
    }
    final follower = followerId.trim();
    if (follower.isEmpty || _timewebFollowsUnavailable) {
      return const FollowedSellersPage(
        items: <FollowedSeller>[],
        hasMore: false,
      );
    }
    try {
      final response = await _api.list(limit: limit, cursor: cursor);
      final items = _extractFollowedSellers(response);
      final merged = resetCache
          ? <FollowedSeller>[]
          : List<FollowedSeller>.from(
              _cache[follower] ?? const <FollowedSeller>[],
            );
      final seen = merged.map((item) => item.sellerId).toSet();
      for (final item in items) {
        if (seen.add(item.sellerId)) merged.add(item);
      }
      _cache[follower] = merged;
      _cacheAt[follower] = DateTime.now();
      _followedControllerFor(follower).add(List<FollowedSeller>.from(merged));
      _emitFollowingStates(follower);
      final nextCursor = _extractNextCursor(response);
      return FollowedSellersPage(
        items: items,
        hasMore: response['hasMore'] == true && nextCursor != null,
        nextCursor: nextCursor,
      );
    } on ApiException catch (error) {
      if (error.isNotFound) {
        _markTimewebUnavailable(
          'Follows source: Timeweb unavailable (404). Falling back to empty state until backend is updated.',
        );
        return const FollowedSellersPage(
          items: <FollowedSeller>[],
          hasMore: false,
        );
      }
      rethrow;
    }
  }

  Future<List<FollowedSeller>> getFollowedSellers(String followerId) async {
    final follower = followerId.trim();
    if (follower.isEmpty) return const <FollowedSeller>[];

    _debugSource('Follows source: Timeweb');
    if (_timewebFollowsUnavailable) {
      return const <FollowedSeller>[];
    }
    final cached = _cache[follower];
    final cachedAt = _cacheAt[follower];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return List<FollowedSeller>.from(cached);
    }
    return refreshFollowedSellers(follower);
  }

  List<FollowedSeller> peekFollowedSellers(String followerId) {
    final follower = followerId.trim();
    if (follower.isEmpty) return const <FollowedSeller>[];
    return List<FollowedSeller>.from(
      _cache[follower] ?? const <FollowedSeller>[],
    );
  }

  Future<int> _fetchFollowersCount(String sellerId) async {
    try {
      final response = await _api.countFollowers(sellerId);
      final raw = response['followers_count'];
      if (raw is num) return raw.toInt();
      return int.tryParse((raw ?? '').toString()) ?? 0;
    } on ApiException catch (error) {
      if (error.isNotFound) {
        _markTimewebUnavailable(
          'Follows source: Timeweb unavailable (404). Falling back to zero followers until backend is updated.',
        );
        return 0;
      }
      rethrow;
    }
  }

  DateTime _parseFollowedAt(dynamic value) {
    if (value is DateTime) return value.toUtc();
    final parsed = DateTime.tryParse((value ?? '').toString());
    return (parsed ?? DateTime.now()).toUtc();
  }

  List<FollowedSeller> _extractFollowedSellers(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <FollowedSeller>[];
    final items = <FollowedSeller>[];
    final seen = <String>{};
    for (final row in raw.whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      final sellerId = (map['seller_id'] ?? '').toString().trim();
      if (sellerId.isEmpty || !seen.add(sellerId)) continue;
      items.add(
        FollowedSeller(
          sellerId: sellerId,
          followedAt: _parseFollowedAt(map['created_at']),
        ),
      );
    }
    return items;
  }

  String? _extractNextCursor(Map<String, dynamic> response) {
    final cursor =
        (response['nextCursor'] ?? response['next_cursor'])?.toString().trim();
    return (cursor ?? '').isEmpty ? null : cursor;
  }

  Stream<int> streamFollowersCount(String sellerId) {
    final id = sellerId.trim();
    if (id.isEmpty) return const Stream<int>.empty();

    _debugSource('Follows source: Timeweb');
    if (_timewebFollowsUnavailable) {
      return Stream<int>.value(0);
    }
    final controller = _followerCountControllerFor(id);
    final cached = _followersCountCache[id];
    final cachedAt = _followersCountCachedAt[id];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return controller.stream.startWith(cached);
    }
    unawaited(refreshFollowersCount(id));
    return controller.stream.startWith(cached ?? 0);
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

    _debugSource('Follows source: Timeweb');
    if (_timewebFollowsUnavailable) {
      return Stream<bool>.value(false);
    }
    final key = '$follower::$seller';
    final controller = _isFollowingControllers.putIfAbsent(
      key,
      () => StreamController<bool>.broadcast(),
    );
    final cached = _cache[follower];
    final initial = cached?.any((item) => item.sellerId == seller) == true;
    unawaited(refreshFollowedSellers(follower));
    return controller.stream.startWith(initial);
  }

  Stream<List<FollowedSeller>> streamFollowedSellers(String followerId) {
    final follower = followerId.trim();
    if (follower.isEmpty) return Stream<List<FollowedSeller>>.value(const []);

    _debugSource('Follows source: Timeweb');
    if (_timewebFollowsUnavailable) {
      return Stream<List<FollowedSeller>>.value(const <FollowedSeller>[]);
    }
    final controller = _followedControllerFor(follower);
    unawaited(refreshFollowedSellers(follower));
    return controller.stream.startWith(
      List<FollowedSeller>.from(_cache[follower] ?? const <FollowedSeller>[]),
    );
  }

  Future<void> follow({
    required String followerId,
    required String sellerId,
  }) async {
    final follower = followerId.trim();
    final seller = sellerId.trim();
    if (follower.isEmpty || seller.isEmpty || follower == seller) return;

    _debugSource('Follows source: Timeweb');
    if (_timewebFollowsUnavailable) return;
    _applyOptimisticFollow(
      follower: follower,
      seller: seller,
      makeFollowing: true,
    );
    await _api.follow(seller);
  }

  Future<void> unfollow({
    required String followerId,
    required String sellerId,
  }) async {
    final follower = followerId.trim();
    final seller = sellerId.trim();
    if (follower.isEmpty || seller.isEmpty || follower == seller) return;

    _debugSource('Follows source: Timeweb');
    if (_timewebFollowsUnavailable) return;
    _applyOptimisticFollow(
      follower: follower,
      seller: seller,
      makeFollowing: false,
    );
    await _api.unfollow(seller);
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

  Future<List<FollowedSeller>> refreshFollowedSellers(String followerId) async {
    final follower = followerId.trim();
    if (follower.isEmpty) return const <FollowedSeller>[];
    final existing = _followedInFlight[follower];
    if (existing != null) return existing;
    final future = _fetchFollowedSellers().then((items) {
      _cache[follower] = items;
      _cacheAt[follower] = DateTime.now();
      _followedControllerFor(follower).add(List<FollowedSeller>.from(items));
      _emitFollowingStates(follower);
      return items;
    });
    _followedInFlight[follower] = future;
    try {
      return await future;
    } finally {
      if (identical(_followedInFlight[follower], future)) {
        _followedInFlight.remove(follower);
      }
    }
  }

  Future<int> refreshFollowersCount(String sellerId) async {
    final seller = sellerId.trim();
    if (seller.isEmpty) return 0;
    final existing = _countInFlight[seller];
    if (existing != null) return existing;
    final future = _fetchFollowersCount(seller).then((count) {
      _followersCountCache[seller] = count;
      _followersCountCachedAt[seller] = DateTime.now();
      _followerCountControllerFor(seller).add(count);
      return count;
    });
    _countInFlight[seller] = future;
    try {
      return await future;
    } finally {
      if (identical(_countInFlight[seller], future)) {
        _countInFlight.remove(seller);
      }
    }
  }

  void _applyOptimisticFollow({
    required String follower,
    required String seller,
    required bool makeFollowing,
  }) {
    final current = List<FollowedSeller>.from(_cache[follower] ?? const []);
    final next = current.where((item) => item.sellerId != seller).toList();
    if (makeFollowing) {
      next.insert(
        0,
        FollowedSeller(
          sellerId: seller,
          followedAt: DateTime.now().toUtc(),
        ),
      );
    }

    _cache[follower] = next;
    _cacheAt[follower] = DateTime.now();
    _followedControllerFor(follower).add(List<FollowedSeller>.from(next));
    _emitFollowingStates(follower);

    final oldCount = _followersCountCache[seller] ?? 0;
    final newCount =
        makeFollowing ? oldCount + 1 : (oldCount > 0 ? oldCount - 1 : 0);
    _followersCountCache[seller] = newCount;
    _followersCountCachedAt[seller] = DateTime.now();
    _followerCountControllerFor(seller).add(newCount);
  }

  void _emitFollowingStates(String follower) {
    final followed = _cache[follower] ?? const <FollowedSeller>[];
    final followedIds = followed.map((item) => item.sellerId).toSet();
    for (final entry in _isFollowingControllers.entries) {
      final parts = entry.key.split('::');
      if (parts.length != 2 || parts.first != follower) continue;
      entry.value.add(followedIds.contains(parts.last));
    }
  }

  StreamController<List<FollowedSeller>> _followedControllerFor(
      String follower) {
    return _followedControllers.putIfAbsent(
      follower,
      () => StreamController<List<FollowedSeller>>.broadcast(),
    );
  }

  StreamController<int> _followerCountControllerFor(String seller) {
    return _followerCountControllers.putIfAbsent(
      seller,
      () => StreamController<int>.broadcast(),
    );
  }

  void resetSession() {
    _cache.clear();
    _cacheAt.clear();
    _followersCountCache.clear();
    _followersCountCachedAt.clear();
    _followedInFlight.clear();
    _countInFlight.clear();
    _timewebFollowsUnavailable = false;
  }
}

class FollowedSellersPage {
  const FollowedSellersPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<FollowedSeller> items;
  final bool hasMore;
  final String? nextCursor;
}

extension<T> on Stream<T> {
  Stream<T> startWith(T initial) {
    return Stream<T>.multi(
      (controller) {
        controller.add(initial);
        final subscription = listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
      },
      isBroadcast: isBroadcast,
    );
  }
}
