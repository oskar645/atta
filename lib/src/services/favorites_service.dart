import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/favorites_api.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/models/listing.dart';

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
  final Map<String, StreamController<bool>> _listingControllers =
      <String, StreamController<bool>>{};
  final Map<String, Future<Set<String>>> _refreshInFlight =
      <String, Future<Set<String>>>{};
  final Map<String, Object> _lastRefreshErrorByUser = <String, Object>{};
  final Map<String, bool> _confirmedStateByKey = <String, bool>{};
  final Map<String, bool> _desiredStateByKey = <String, bool>{};
  final Map<String, Future<void>> _toggleSyncInFlight =
      <String, Future<void>>{};

  Set<String> peekFavoriteIds(String uid) {
    return Set<String>.from(_cache[uid] ?? const <String>{});
  }

  bool isFavorite(String uid, String listingId) {
    final normalizedUid = uid.trim();
    final normalizedListingId = listingId.trim();
    if (normalizedUid.isEmpty || normalizedListingId.isEmpty) return false;
    return (_cache[normalizedUid] ?? const <String>{}).contains(
      normalizedListingId,
    );
  }

  Object? lastRefreshErrorForUser(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return null;
    return _lastRefreshErrorByUser[normalizedUid];
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
      try {
        final fresh = await refreshFavoriteIds(uid);
        yield Set<String>.from(fresh);
      } catch (error) {
        _lastRefreshErrorByUser[uid.trim()] = error;
        yield Set<String>.from(_cache[uid.trim()] ?? const <String>{});
      }
    }
    yield* controller.stream;
  }

  Stream<Set<String>> streamCachedFavoriteIds(String uid) {
    final normalizedUid = uid.trim();
    return Stream<Set<String>>.multi(
      (controller) {
        controller
            .add(Set<String>.from(_cache[normalizedUid] ?? const <String>{}));
        final sub = _controllerFor(normalizedUid).stream.listen(
              controller.add,
              onError: controller.addError,
            );
        controller.onCancel = () async {
          await sub.cancel();
        };
      },
      isBroadcast: true,
    );
  }

  Stream<bool> streamIsFavorite(String uid, String listingId) async* {
    final normalizedUid = uid.trim();
    final normalizedListingId = listingId.trim();
    if (normalizedUid.isEmpty || normalizedListingId.isEmpty) {
      yield false;
      return;
    }
    final controller =
        _listingControllerFor(normalizedUid, normalizedListingId);
    if (_cache.containsKey(normalizedUid)) {
      yield isFavorite(normalizedUid, normalizedListingId);
    } else {
      await refreshFavoriteIds(normalizedUid);
      yield isFavorite(normalizedUid, normalizedListingId);
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
    if (makeFavorite) {
      final next = <String>{
        normalizedListingId,
        ...previous.where((id) => id != normalizedListingId),
      };
      _publish(uid, next);
    } else {
      final next = Set<String>.from(previous);
      next.remove(normalizedListingId);
      _publish(uid, next);
    }
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

  Future<Set<String>> refreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      _debug('Favorites load skipped reason=no_user');
      return const <String>{};
    }
    final existing = _refreshInFlight[normalizedUid];
    if (existing != null) {
      _debug('Favorites load skipped reason=in_flight user=$normalizedUid');
      return existing;
    }
    final completer = Completer<Set<String>>();
    final future = completer.future;
    _refreshInFlight[normalizedUid] = future;
    _debug('Favorites load start reason=$reason user=$normalizedUid');
    () async {
      try {
        completer.complete(await _refreshFavoriteIdsSafe(normalizedUid));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight[normalizedUid], future)) {
        _refreshInFlight.remove(normalizedUid);
        _debug('Favorites inFlight cleared user=$normalizedUid');
      }
    }
  }

  Future<Set<String>> forceRefreshFavoriteIds(
    String uid, {
    String reason = 'manual',
  }) {
    return refreshFavoriteIds(uid, reason: reason);
  }

  Future<FavoriteIdsPage> getFavoriteIdsPage({
    required String uid,
    int limit = 50,
    String? cursor,
    bool resetCache = false,
  }) async {
    if (runtimeType != FavoritesService) {
      if ((cursor ?? '').trim().isNotEmpty) {
        return const FavoriteIdsPage(ids: <String>[], hasMore: false);
      }
      final ids = await refreshFavoriteIds(uid);
      return FavoriteIdsPage(ids: ids.toList(growable: false), hasMore: false);
    }
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return const FavoriteIdsPage(
        ids: <String>[],
        hasMore: false,
      );
    }
    try {
      final response = await _api.list(limit: limit, cursor: cursor);
      final ids = _extractFavoriteIds(response);
      final embeddedListings = _extractEmbeddedListings(response);
      final current = resetCache
          ? <String>{}
          : Set<String>.from(_cache[normalizedUid] ?? const <String>{});
      current.addAll(ids);
      _publish(normalizedUid, current);
      final nextCursor = _extractNextCursor(response);
      return FavoriteIdsPage(
        ids: ids,
        embeddedListings: embeddedListings,
        nextCursor: nextCursor,
        hasMore: response['hasMore'] == true && nextCursor != null,
      );
    } catch (error) {
      _lastRefreshErrorByUser[normalizedUid] = error;
      _debug('Favorites page load error message=$error user=$normalizedUid');
      rethrow;
    }
  }

  Future<Set<String>> _refreshFavoriteIdsSafe(String normalizedUid) async {
    late final Set<String> fresh;
    try {
      fresh = await _fetchFavoriteIds(normalizedUid);
      _lastRefreshErrorByUser.remove(normalizedUid);
    } catch (error) {
      _lastRefreshErrorByUser[normalizedUid] = error;
      return Set<String>.from(_cache[normalizedUid] ?? const <String>{});
    }
    final previous =
        Set<String>.from(_cache[normalizedUid] ?? const <String>{});
    for (final listingId in {...previous, ...fresh}) {
      _confirmedStateByKey[_favoriteKey(normalizedUid, listingId)] =
          fresh.contains(listingId);
    }
    _publish(normalizedUid, fresh);
    _debug(
      fresh.isEmpty
          ? 'Favorites load empty'
          : 'Favorites load success count=${fresh.length}',
    );
    return Set<String>.from(fresh);
  }

  Future<Set<String>> _fetchFavoriteIds(String uid) async {
    try {
      // ApiClient starts the transport timeout only after the HTTP send.
      final ids = <String>{};
      String? cursor;
      var hasMore = true;
      while (hasMore) {
        final response = await _api.list(limit: 100, cursor: cursor);
        ids.addAll(_extractFavoriteIds(response));
        cursor = _extractNextCursor(response);
        hasMore = response['hasMore'] == true && cursor != null;
      }
      return ids;
    } catch (error) {
      _debug('Favorites load error message=$error user=$uid');
      rethrow;
    } finally {
      _debug('Favorites load finally loading=false user=$uid');
    }
  }

  List<String> _extractFavoriteIds(Map<String, dynamic> response) {
    final raw = response['favorite_ids'];
    if (raw is! List) return const <String>[];
    return raw
        .map((item) => item.toString().trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  String? _extractNextCursor(Map<String, dynamic> response) {
    final cursor =
        (response['nextCursor'] ?? response['next_cursor'])?.toString().trim();
    return (cursor ?? '').isEmpty ? null : cursor;
  }

  Map<String, Listing> _extractEmbeddedListings(Map<String, dynamic> response) {
    final rawItems = response['items'];
    if (rawItems is! List) return const <String, Listing>{};
    final listings = <String, Listing>{};
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final rawListing = rawItem['listing'];
      if (rawListing is! Map) continue;
      try {
        final listing = Listing.fromMap(
          rawListing.map((key, value) => MapEntry(key.toString(), value)),
        );
        listings[listing.id] = listing;
      } catch (_) {
        continue;
      }
    }
    return listings;
  }

  StreamController<Set<String>> _controllerFor(String uid) {
    return _controllers.putIfAbsent(
      uid,
      () => StreamController<Set<String>>.broadcast(),
    );
  }

  StreamController<bool> _listingControllerFor(String uid, String listingId) {
    return _listingControllers.putIfAbsent(
      _favoriteKey(uid, listingId),
      () => StreamController<bool>.broadcast(),
    );
  }

  void _publish(String uid, Set<String> value) {
    final previous = Set<String>.from(_cache[uid] ?? const <String>{});
    final next = Set<String>.from(value);
    _cache[uid] = next;
    _controllerFor(uid).add(Set<String>.from(next));
    for (final listingId in {...previous, ...next}) {
      final wasFavorite = previous.contains(listingId);
      final isFavoriteNow = next.contains(listingId);
      if (wasFavorite == isFavoriteNow) continue;
      _listingControllerFor(uid, listingId).add(isFavoriteNow);
    }
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
        final alreadyApplied = (desired && error.statusCode == 409) ||
            (!desired && error.statusCode == 404);
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
    _lastRefreshErrorByUser.clear();
    _confirmedStateByKey.clear();
    _desiredStateByKey.clear();
    _toggleSyncInFlight.clear();
    for (final entry in _controllers.entries) {
      entry.value.add(const <String>{});
    }
    for (final entry in _listingControllers.entries) {
      entry.value.add(false);
    }
  }

  void _debug(String message) {
    assert(() {
      // Debug-only diagnostics for stuck private tabs.
      // ignore: avoid_print
      print(message);
      return true;
    }());
  }
}

class FavoriteIdsPage {
  const FavoriteIdsPage({
    required this.ids,
    required this.hasMore,
    this.embeddedListings = const <String, Listing>{},
    this.nextCursor,
  });

  final List<String> ids;
  final Map<String, Listing> embeddedListings;
  final bool hasMore;
  final String? nextCursor;
}
