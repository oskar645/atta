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
  final Map<String, bool> _confirmedStateByKey = <String, bool>{};
  final Map<String, bool> _desiredStateByKey = <String, bool>{};
  final Map<String, Future<void>> _toggleSyncInFlight =
      <String, Future<void>>{};

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
    final normalizedUid = uid.trim();
    final normalizedListingId = listingId.trim();
    if (normalizedUid.isEmpty || normalizedListingId.isEmpty) return;
    final previous = Set<String>.from(_cache[uid] ?? const <String>{});
    final next = Set<String>.from(previous);
    if (makeFavorite) {
      next.add(normalizedListingId);
    } else {
      next.remove(normalizedListingId);
    }
    _publish(uid, next);
    final key = _favoriteKey(normalizedUid, normalizedListingId);
    _confirmedStateByKey.putIfAbsent(
      key,
      () => previous.contains(normalizedListingId),
    );
    _desiredStateByKey[key] = makeFavorite;

    final existing = _toggleSyncInFlight[key];
    if (existing != null) {
      return existing;
    }

    final future = _syncFavoriteState(
      uid: normalizedUid,
      listingId: normalizedListingId,
    );
    _toggleSyncInFlight[key] = future;
    try {
      await future;
    } finally {
      if (identical(_toggleSyncInFlight[key], future)) {
        _toggleSyncInFlight.remove(key);
      }
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
    final previous = Set<String>.from(_cache[normalizedUid] ?? const <String>{});
    for (final listingId in {...previous, ...fresh}) {
      _confirmedStateByKey[_favoriteKey(normalizedUid, listingId)] =
          fresh.contains(listingId);
    }
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

  String _favoriteKey(String uid, String listingId) => '$uid::$listingId';

  Future<void> _syncFavoriteState({
    required String uid,
    required String listingId,
  }) async {
    final key = _favoriteKey(uid, listingId);
    Object? lastError;

    while (true) {
      final desired = _desiredStateByKey[key];
      final confirmed = _confirmedStateByKey[key] ?? false;
      if (desired == null || desired == confirmed) {
        break;
      }

      try {
        if (desired) {
          await _api.add(listingId);
        } else {
          await _api.remove(listingId);
        }
        _confirmedStateByKey[key] = desired;
        lastError = null;
      } on ApiException catch (error) {
        final alreadyApplied =
            (desired && error.statusCode == 409) || (!desired && error.statusCode == 404);
        if (alreadyApplied) {
          _confirmedStateByKey[key] = desired;
          continue;
        }
        if (_desiredStateByKey[key] == desired) {
          final reverted = Set<String>.from(_cache[uid] ?? const <String>{});
          if (confirmed) {
            reverted.add(listingId);
          } else {
            reverted.remove(listingId);
          }
          _publish(uid, reverted);
          _desiredStateByKey[key] = confirmed;
          lastError = error;
          break;
        }
      } catch (error) {
        if (_desiredStateByKey[key] == desired) {
          final reverted = Set<String>.from(_cache[uid] ?? const <String>{});
          if (confirmed) {
            reverted.add(listingId);
          } else {
            reverted.remove(listingId);
          }
          _publish(uid, reverted);
          _desiredStateByKey[key] = confirmed;
          lastError = error;
          break;
        }
      }
    }

    if (lastError != null) {
      throw lastError;
    }
  }

  void resetSession() {
    _cache.clear();
    _refreshInFlight.clear();
    _confirmedStateByKey.clear();
    _desiredStateByKey.clear();
    _toggleSyncInFlight.clear();
    for (final entry in _controllers.entries) {
      entry.value.add(const <String>{});
    }
  }
}
