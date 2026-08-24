import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/viewed_listings_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';

class ListingHistoryService extends ChangeNotifier {
  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);
  static final ViewedListingsApi _api = ViewedListingsApi(_apiClient);
  static const String _legacyPrefsKey = 'listing_history_v1';
  static const String _prefsKeyPrefix = 'listing_history_v2';
  static const Duration _remoteSyncCooldown = Duration(seconds: 45);

  final Set<String> _viewedIds = <String>{};
  bool _loaded = false;
  final TokenStorage _storage;
  final ViewedListingsApi _viewedListingsApi;
  Future<void>? _activateSessionInFlight;
  String? _lastSyncedUserId;
  DateTime? _lastRemoteSyncAt;

  ListingHistoryService({
    TokenStorage? tokenStorage,
    ViewedListingsApi? api,
  })  : _storage = tokenStorage ?? _tokenStorage,
        _viewedListingsApi = api ?? _api {
    unawaited(_load());
  }

  bool get isLoaded => _loaded;

  List<String> get viewedIdsNewestFirst =>
      _viewedIds.toList(growable: false).reversed.toList(growable: false);

  bool hasViewed(String listingId) {
    return _viewedIds.contains(listingId.trim());
  }

  Future<void> markViewed(String listingId) async {
    final id = listingId.trim();
    if (id.isEmpty) return;

    final before = _viewedIds.toList(growable: false);
    _viewedIds.remove(id);
    _viewedIds.add(id);

    if (!_listEquals(before, _viewedIds.toList(growable: false)) || !_loaded) {
      notifyListeners();
    }

    await _save();
    if (ApiConfig.useTimewebBackend) {
      try {
        await _viewedListingsApi.mark(id);
      } catch (_) {}
    }
  }

  Future<void> activateSession() async {
    final user = await _storage.readCurrentUser();
    final uid = user?.uid.trim() ?? '';
    final now = DateTime.now();
    final existing = _activateSessionInFlight;
    if (existing != null) {
      return existing;
    }
    if (_loaded &&
        _lastSyncedUserId == uid &&
        _lastRemoteSyncAt != null &&
        now.difference(_lastRemoteSyncAt!) < _remoteSyncCooldown) {
      return;
    }
    final future = _load();
    _activateSessionInFlight = future;
    try {
      await future;
      _lastSyncedUserId = uid;
      _lastRemoteSyncAt = DateTime.now();
    } finally {
      if (identical(_activateSessionInFlight, future)) {
        _activateSessionInFlight = null;
      }
    }
  }

  Future<ViewedListingsPage> getViewedListingsPage({
    int limit = 50,
    String? cursor,
  }) async {
    final response = await _viewedListingsApi.list(
      limit: limit,
      cursor: cursor,
    );
    final ids = _extractBackendViewedIds(response);
    final nextCursor = _extractNextCursor(response);
    return ViewedListingsPage(
      ids: ids,
      hasMore: response['hasMore'] == true && nextCursor != null,
      nextCursor: nextCursor,
    );
  }

  Future<void> _load() async {
    final user = await _storage.readCurrentUser();
    final uid = user?.uid.trim() ?? '';
    await _loadLocal(uid: uid);
    await _syncRemote(uid);
  }

  Future<void> _loadLocal({String? uid}) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedUid =
        uid ?? (await _storage.readCurrentUser())?.uid.trim() ?? '';
    final stored = prefs.getStringList(await _prefsKeyForUid(resolvedUid)) ??
        const <String>[];
    final localIds = stored
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    _viewedIds
      ..clear()
      ..addAll(localIds);
    _loaded = true;
    notifyListeners();
  }

  Future<void> _syncRemote(String uid) async {
    if (!ApiConfig.useTimewebBackend || uid.isEmpty) {
      _lastSyncedUserId = uid;
      _lastRemoteSyncAt = DateTime.now();
      return;
    }
    try {
      final backendIds = <String>[];
      final seen = <String>{};
      String? cursor;
      var hasMore = true;
      while (hasMore) {
        final response = await _viewedListingsApi.list(
          limit: 100,
          cursor: cursor,
        );
        for (final id in _extractBackendViewedIds(response)) {
          if (seen.add(id)) backendIds.add(id);
        }
        cursor = _extractNextCursor(response);
        hasMore = response['hasMore'] == true && cursor != null;
      }
      final mergedIds = <String>[..._viewedIds];
      for (final id in backendIds) {
        mergedIds.remove(id);
        mergedIds.insert(0, id);
      }
      final normalized = mergedIds.toList(growable: false);
      _viewedIds
        ..clear()
        ..addAll(normalized);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(await _prefsKeyForUid(uid), normalized);
      notifyListeners();
    } on ApiException catch (error) {
      if (!error.isUnauthorized &&
          !error.isNetworkError &&
          !error.isTimeout &&
          !error.isServerUnavailable) {
        rethrow;
      }
    } catch (_) {}
    _lastSyncedUserId = uid;
    _lastRemoteSyncAt = DateTime.now();
  }

  String? _extractNextCursor(Map<String, dynamic> response) {
    final cursor =
        (response['nextCursor'] ?? response['next_cursor'])?.toString().trim();
    return (cursor ?? '').isEmpty ? null : cursor;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      await _prefsKey(),
      _viewedIds.toList(growable: false),
    );
  }

  Future<void> resetSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _prefsKey());
    await prefs.remove(_legacyPrefsKey);
    _viewedIds.clear();
    _loaded = true;
    _lastSyncedUserId = null;
    _lastRemoteSyncAt = null;
    _activateSessionInFlight = null;
    notifyListeners();
  }

  Future<String> _prefsKey() async {
    final user = await _storage.readCurrentUser();
    final uid = user?.uid.trim() ?? '';
    return _prefsKeyForUid(uid);
  }

  Future<String> _prefsKeyForUid(String uid) async {
    if (uid.isEmpty) {
      return '$_prefsKeyPrefix:anonymous';
    }
    return '$_prefsKeyPrefix:$uid';
  }

  List<String> _extractBackendViewedIds(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <String>[];
    return raw
        .whereType<Map>()
        .map((item) => (item['listing_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class ViewedListingsPage {
  const ViewedListingsPage({
    required this.ids,
    required this.hasMore,
    this.nextCursor,
  });

  final List<String> ids;
  final bool hasMore;
  final String? nextCursor;
}
