import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/favorites_api.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth/token_storage.dart';

class FavoritesService {
  FavoritesService({
    FavoritesApi? api,
  }) : _api = api ?? FavoritesApi(_apiClient);

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);

  final FavoritesApi _api;
  final Map<String, Set<String>> _cache = <String, Set<String>>{};
  final Map<String, StreamController<Set<String>>> _controllers =
      <String, StreamController<Set<String>>>{};
  final Map<String, Future<Set<String>>> _refreshInFlight =
      <String, Future<Set<String>>>{};

  Set<String> peekFavoriteIds(String uid) {
    return Set<String>.from(_cache[uid] ?? const <String>{});
  }

  Future<Set<String>> getFavoriteIds(String uid) async {
    final cached = _cache[uid];
    if (cached != null) {
      return Set<String>.from(cached);
    }
    return refreshFavoriteIds(uid);
  }

  Stream<Set<String>> streamFavoriteIds(String uid) async* {
    final controller = _controllerFor(uid);
    final cached = _cache[uid];
    if (cached != null) {
      yield Set<String>.from(cached);
    } else {
      final fresh = await refreshFavoriteIds(uid);
      yield Set<String>.from(fresh);
    }
    yield* controller.stream;
  }

  Future<void> toggleFavorite({
    required String uid,
    required String listingId,
    required bool makeFavorite,
  }) async {
    final previous = Set<String>.from(_cache[uid] ?? const <String>{});
    final next = Set<String>.from(previous);
    if (makeFavorite) {
      next.add(listingId);
    } else {
      next.remove(listingId);
    }
    _publish(uid, next);

    try {
      if (makeFavorite) {
        await _api.add(listingId);
      } else {
        await _api.remove(listingId);
      }
    } on ApiException catch (error) {
      final alreadyApplied = (makeFavorite && error.statusCode == 409) ||
          (!makeFavorite && error.statusCode == 404);
      if (alreadyApplied) {
        return;
      }
      _publish(uid, previous);
      rethrow;
    } catch (_) {
      _publish(uid, previous);
      rethrow;
    }
  }

  Future<Set<String>> refreshFavoriteIds(String uid) async {
    final normalizedUid = uid.trim();
    final existing = _refreshInFlight[normalizedUid];
    if (existing != null) {
      return existing;
    }
    final future = _fetchFavoriteIds();
    _refreshInFlight[normalizedUid] = future;
    final fresh = await future.whenComplete(() {
      if (identical(_refreshInFlight[normalizedUid], future)) {
        _refreshInFlight.remove(normalizedUid);
      }
    });
    _publish(uid, fresh);
    return Set<String>.from(fresh);
  }

  Future<Set<String>> _fetchFavoriteIds() async {
    final response = await _api.list();
    final raw = response['favorite_ids'];
    if (raw is List) {
      return raw.map((item) => item.toString()).toSet();
    }
    return <String>{};
  }

  StreamController<Set<String>> _controllerFor(String uid) {
    return _controllers.putIfAbsent(
      uid,
      () => StreamController<Set<String>>.broadcast(),
    );
  }

  void _publish(String uid, Set<String> value) {
    final next = Set<String>.from(value);
    _cache[uid] = next;
    _controllerFor(uid).add(Set<String>.from(next));
  }

  void resetSession() {
    _cache.clear();
    _refreshInFlight.clear();
    for (final entry in _controllers.entries) {
      entry.value.add(const <String>{});
    }
  }
}
