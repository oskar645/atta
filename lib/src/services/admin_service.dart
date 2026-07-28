import 'dart:convert';
import 'dart:async';

import 'package:atta/src/services/api/auth_api.dart';
import 'package:atta/src/services/api/admin_api.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminSectionSnapshot {
  const AdminSectionSnapshot({
    required this.count,
    required this.marker,
  });

  final int count;
  final String marker;
}

class AdminService {
  AdminService({
    AdminApi? api,
    AuthApi? authApi,
  })  : _api = api ?? AdminApi(_apiClient),
        _authApi = authApi ?? AuthApi(_apiClient);

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);
  static const String moderationSection = 'moderation';
  static const String supportSection = 'support';
  static const String reportsSection = 'reports';
  static const String _seenPrefsKeyPrefix = 'atta.admin.section_seen';

  final AdminApi _api;
  final AuthApi _authApi;
  final Map<String, _AdminCacheEntry> _cache = <String, _AdminCacheEntry>{};
  final StreamController<int> _moderationBadgeController =
      StreamController<int>.broadcast();
  final StreamController<int> _reportsBadgeController =
      StreamController<int>.broadcast();
  final StreamController<int> _supportBadgeController =
      StreamController<int>.broadcast();
  final StreamController<bool> _needsAttentionController =
      StreamController<bool>.broadcast();
  AuthUser? _lastAdminResolvedUser;
  DateTime? _lastAdminResolvedAt;
  DateTime? _lastAttentionRefreshAt;
  String? _activeAdminUid;
  Map<String, String> _seenMarkers = <String, String>{};
  final Map<String, AdminSectionSnapshot> _sectionSnapshots =
      <String, AdminSectionSnapshot>{};
  Future<void>? _seenMarkersLoadInFlight;

  static const Duration _defaultCacheTtl = Duration(seconds: 15);
  bool _sessionActive = true;

  void activateSession() {
    _sessionActive = true;
  }

  void bindAdminUser(String uid) {
    final normalized = uid.trim();
    if (normalized.isEmpty) {
      return;
    }
    if (_activeAdminUid == normalized && _seenMarkersLoadInFlight == null) {
      return;
    }
    _activeAdminUid = normalized;
    unawaited(_ensureSeenMarkersLoaded());
  }

  void resetSession() {
    _sessionActive = false;
    _cache.clear();
    _lastAdminResolvedUser = null;
    _lastAdminResolvedAt = null;
    _lastAttentionRefreshAt = null;
    _activeAdminUid = null;
    _seenMarkers = <String, String>{};
    _sectionSnapshots.clear();
    _emitSectionBadgeCounts();
  }

  Stream<bool> streamIsAdmin(String uid) {
    if (!_sessionActive) return Stream<bool>.value(false);
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return Stream<bool>.value(false);
    return Stream<bool>.fromFuture(isAdminOnce(normalizedUid));
  }

  Future<bool> isAdminOnce(String uid) async {
    final currentUser = await _refreshAdminIdentity();
    if (currentUser == null) return false;
    return currentUser.uid == uid && currentUser.isAdmin;
  }

  Stream<int> streamPendingModerationCount() {
    if (!_sessionActive) {
      return Stream<int>.value(0);
    }
    return _streamSectionBadgeCount(
      moderationSection,
      _moderationBadgeController,
      refreshOnListen: true,
    );
  }

  Stream<int> streamOpenReportsCount() {
    if (!_sessionActive) {
      return Stream<int>.value(0);
    }
    return _streamSectionBadgeCount(
      reportsSection,
      _reportsBadgeController,
      refreshOnListen: true,
    );
  }

  Stream<int> streamUnreadSupportForAdminCount() {
    if (!_sessionActive) {
      return Stream<int>.value(0);
    }
    return _streamSectionBadgeCount(
      supportSection,
      _supportBadgeController,
      refreshOnListen: true,
    );
  }

  Stream<bool> streamNeedsAttention({bool refreshOnListen = true}) {
    if (!_sessionActive) {
      return Stream<bool>.value(false);
    }
    return Stream<bool>.multi((controller) {
      controller.add(_hasAttention);
      final sub = _needsAttentionController.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      if (refreshOnListen) {
        unawaited(refreshAdminAttention(force: false));
      }
      controller.onCancel = () async {
        await sub.cancel();
      };
    }).distinct().asBroadcastStream();
  }

  Future<void> refreshAdminAttention({bool force = false}) async {
    if (!_sessionActive) {
      return;
    }
    final currentUser = await _tokenStorage.readCurrentUser();
    if (currentUser?.isAdmin != true) {
      _cache.clear();
      _lastAttentionRefreshAt = null;
      _sectionSnapshots.clear();
      _emitSectionBadgeCounts();
      return;
    }
    await _ensureSeenMarkersLoaded();
    if (!force &&
        _lastAttentionRefreshAt != null &&
        DateTime.now().difference(_lastAttentionRefreshAt!) <
            _defaultCacheTtl) {
      _emitSectionBadgeCounts();
      return;
    }
    try {
      final results = await Future.wait([
        listings(status: 'pending', forceRefresh: force),
        reports(forceRefresh: force),
        support(forceRefresh: force),
      ]);
      _updateSnapshotFromResponse(moderationSection, results[0]);
      _updateSnapshotFromResponse(reportsSection, results[1]);
      _updateSnapshotFromResponse(supportSection, results[2]);
      _lastAttentionRefreshAt = DateTime.now();
      _emitSectionBadgeCounts();
    } catch (error) {
      _debugSource('Admin attention refresh skipped: $error');
      _emitSectionBadgeCounts();
    }
  }

  Future<void> markSectionSeen(String section) async {
    await _ensureSeenMarkersLoaded();
    final snapshot = _sectionSnapshots[section];
    if (snapshot == null) {
      return;
    }
    _seenMarkers[section] = snapshot.marker;
    await _saveSeenMarkers();
    _emitSectionBadgeCounts();
  }

  Future<Map<String, dynamic>> dashboardStats({bool forceRefresh = false}) =>
      _cached('dashboardStats', _api.dashboardStats,
          forceRefresh: forceRefresh);
  Future<int> pendingModerationCount({bool forceRefresh = false}) async {
    final stats = await dashboardStats(forceRefresh: forceRefresh);
    final nestedStats = stats['stats'];
    final raw = stats['pendingModeration'] ??
        stats['pending_moderation'] ??
        (nestedStats is Map
            ? nestedStats['pendingModeration'] ??
                nestedStats['pending_moderation']
            : null) ??
        0;
    return (raw as num?)?.toInt() ?? int.tryParse('$raw') ?? 0;
  }

  Future<Map<String, dynamic>> users({bool forceRefresh = false}) =>
      _cached('users', _api.users, forceRefresh: forceRefresh);
  Future<Map<String, dynamic>> onlineUsers({bool forceRefresh = false}) =>
      _cached('onlineUsers', _api.onlineUsers, forceRefresh: forceRefresh);
  Future<Map<String, dynamic>> todayVisits({bool forceRefresh = false}) =>
      _cached('todayVisits', _api.todayVisits, forceRefresh: forceRefresh);
  Future<Map<String, dynamic>> userById(
    String userId, {
    bool forceRefresh = false,
  }) =>
      _cached(
        'user:$userId',
        () => _api.userById(userId),
        forceRefresh: forceRefresh,
      );
  Future<Map<String, dynamic>> deleteUser(String userId) async {
    final response = await _api.deleteUser(userId);
    if (response['deleted'] == true) {
      _removeItemFromCache('users', userId);
      _cache.remove('dashboardStats');
    }
    return response;
  }

  Future<Map<String, dynamic>> listings({
    String? status,
    bool forceRefresh = false,
  }) =>
      _cached(
        'listings:${status ?? 'all'}',
        () => _api.listings(status: status),
        forceRefresh: forceRefresh,
      );
  Future<Map<String, dynamic>> reports({bool forceRefresh = false}) =>
      _cached('reports', _api.reports, forceRefresh: forceRefresh);
  Future<Map<String, dynamic>> support({bool forceRefresh = false}) =>
      _cached('support', _api.support, forceRefresh: forceRefresh);
  Future<Map<String, dynamic>> promotions({
    String? status,
    String? type,
    String? userId,
    String? listingId,
    bool forceRefresh = false,
  }) =>
      _api.promotions(
        status: status,
        type: type,
        userId: userId,
        listingId: listingId,
      );
  Future<Map<String, dynamic>> promotionsSummary({bool forceRefresh = false}) =>
      _cached(
        'promotionsSummary',
        _api.promotionsSummary,
        forceRefresh: forceRefresh,
      );
  Future<Map<String, dynamic>> cancelPromotion(String promotionId) =>
      _api.cancelPromotion(promotionId);
  Future<Map<String, dynamic>> wallets({bool forceRefresh = false}) =>
      _cached('wallets', _api.wallets, forceRefresh: forceRefresh);
  Future<Map<String, dynamic>> walletTransactions({
    String? type,
    String? reason,
    String? userId,
    bool forceRefresh = false,
  }) =>
      _cached(
        'walletTransactions:${type ?? 'all'}:${reason ?? 'all'}:${userId ?? 'all'}',
        () => _api.walletTransactions(
          type: type,
          reason: reason,
          userId: userId,
        ),
        forceRefresh: forceRefresh,
      );
  Future<Map<String, dynamic>> bonusAnalytics({
    String? period,
    bool forceRefresh = false,
  }) =>
      _cached(
        'bonusAnalytics:${period ?? 'default'}',
        () => _api.bonusAnalytics(period: period),
        forceRefresh: forceRefresh,
      );
  Future<Map<String, dynamic>> approveListing(String listingId) =>
      _mutateListing(
        () => _api.approveListing(listingId),
        listingId: listingId,
        fallbackStatus: 'approved',
      );
  Future<Map<String, dynamic>> rejectListing(
    String listingId, {
    String? reason,
    String? moderationNote,
  }) =>
      _mutateListing(
        () => _api.rejectListing(
          listingId,
          reason: reason,
          moderationNote: moderationNote,
        ),
        listingId: listingId,
        fallbackStatus: 'rejected',
      );
  Future<Map<String, dynamic>> archiveListing(
    String listingId, {
    String? status,
    String? note,
  }) =>
      _mutateListing(
        () => _api.archiveListing(
          listingId,
          status: status,
          note: note,
        ),
        listingId: listingId,
        fallbackStatus:
            status?.trim().isNotEmpty == true ? status!.trim() : 'archived',
      );
  Future<Map<String, dynamic>> deleteListing(
    String listingId, {
    String? reason,
    String? moderationNote,
  }) =>
      _mutateListing(
        () => _api.deleteListing(
          listingId,
          reason: reason,
          moderationNote: moderationNote,
        ),
        listingId: listingId,
        fallbackStatus: 'deleted',
      );

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  List<Map<String, dynamic>>? _pendingItemsFromCache() {
    final entry = _cache['listings:pending'];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.updatedAt) >= _defaultCacheTtl) {
      return null;
    }
    final value = entry.value;
    if (value == null) return null;
    return _extractItems(value);
  }

  Future<Map<String, dynamic>> _mutateListing(
    Future<Map<String, dynamic>> Function() action, {
    required String listingId,
    required String fallbackStatus,
  }) async {
    final response = await action();
    final listing = _extractListing(response);
    _applyListingMutation(
      listingId: listingId,
      fallbackStatus: fallbackStatus,
      listing: listing,
    );
    return response;
  }

  Map<String, dynamic>? _extractListing(Map<String, dynamic> response) {
    final raw = response['listing'];
    if (raw is! Map) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  void _applyListingMutation({
    required String listingId,
    required String fallbackStatus,
    Map<String, dynamic>? listing,
  }) {
    final normalized = <String, dynamic>{
      'id': listingId,
      'status': fallbackStatus,
      ...?listing,
    };
    _replaceItemInCache('listings:all', normalized);
    _removeItemFromCache('listings:pending', listingId);
    if (fallbackStatus == 'deleted') {
      _removeItemFromCache('listings:approved', listingId);
      _removeItemFromCache('listings:rejected', listingId);
      _removeItemFromCache('listings:archived', listingId);
    } else {
      _replaceItemInCache('listings:$fallbackStatus', normalized);
    }
    _updatePendingSnapshotFromCache();
    _cache.remove('dashboardStats');
  }

  void _replaceItemInCache(String key, Map<String, dynamic> item) {
    final entry = _cache[key];
    final currentValue = entry?.value;
    if (currentValue == null) return;
    final nextItems = _extractItems(currentValue)
        .where((existing) => (existing['id'] ?? '').toString() != item['id'])
        .toList();
    nextItems.add(Map<String, dynamic>.from(item));
    _cache[key] = _AdminCacheEntry(
      updatedAt: DateTime.now(),
      value: <String, dynamic>{
        ...currentValue,
        'items': nextItems,
      },
    );
  }

  void _removeItemFromCache(String key, String listingId) {
    final entry = _cache[key];
    final currentValue = entry?.value;
    if (currentValue == null) return;
    _cache[key] = _AdminCacheEntry(
      updatedAt: DateTime.now(),
      value: <String, dynamic>{
        ...currentValue,
        'items': _extractItems(currentValue)
            .where(
              (item) => (item['id'] ?? '').toString() != listingId,
            )
            .toList(),
      },
    );
  }

  void _debugSource(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  Stream<int> _streamSectionBadgeCount(
      String section, StreamController<int> source,
      {bool refreshOnListen = false}) {
    return Stream<int>.multi((controller) {
      controller.add(_unreadCountFor(section));
      final sub = source.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      if (refreshOnListen) {
        unawaited(refreshAdminAttention(force: false));
      }
      controller.onCancel = () async {
        await sub.cancel();
      };
    }).distinct().asBroadcastStream();
  }

  Future<void> _ensureSeenMarkersLoaded() async {
    final existing = _seenMarkersLoadInFlight;
    if (existing != null) {
      return existing;
    }
    final future = _loadSeenMarkers();
    _seenMarkersLoadInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_seenMarkersLoadInFlight, future)) {
        _seenMarkersLoadInFlight = null;
      }
    }
  }

  Future<void> _loadSeenMarkers() async {
    final uid = _activeAdminUid?.trim() ?? '';
    if (uid.isEmpty) {
      _seenMarkers = <String, String>{};
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_seenPrefsKeyPrefix:$uid')?.trim() ?? '';
    if (raw.isEmpty) {
      _seenMarkers = <String, String>{};
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _seenMarkers = decoded.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );
      } else {
        _seenMarkers = <String, String>{};
      }
    } catch (_) {
      _seenMarkers = <String, String>{};
    }
  }

  Future<void> _saveSeenMarkers() async {
    final uid = _activeAdminUid?.trim() ?? '';
    if (uid.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_seenPrefsKeyPrefix:$uid',
      jsonEncode(_seenMarkers),
    );
  }

  void _updatePendingSnapshotFromCache() {
    final pending = _pendingItemsFromCache();
    if (pending == null) {
      return;
    }
    _sectionSnapshots[moderationSection] =
        _buildSectionSnapshot(pending, (item) => true);
    _emitSectionBadgeCounts();
  }

  void _updateSnapshotFromResponse(String section, Map<String, dynamic> value) {
    final items = _extractItems(value);
    switch (section) {
      case moderationSection:
        _sectionSnapshots[section] =
            _buildSectionSnapshot(items, (item) => true);
        break;
      case reportsSection:
        _sectionSnapshots[section] = _buildSectionSnapshot(
          items,
          (item) =>
              (item['status'] ?? '').toString().trim().toLowerCase() == 'open',
        );
        break;
      case supportSection:
        _sectionSnapshots[section] = _buildSectionSnapshot(
          items,
          (item) => item['unread_for_admin'] == true,
        );
        break;
    }
  }

  AdminSectionSnapshot _buildSectionSnapshot(
    List<Map<String, dynamic>> items,
    bool Function(Map<String, dynamic> item) include,
  ) {
    final filtered = items.where(include).toList(growable: false);
    if (filtered.isEmpty) {
      return const AdminSectionSnapshot(count: 0, marker: '');
    }
    var latestMarker = '';
    for (final item in filtered) {
      final itemMarker = [
        (item['updated_at'] ?? item['created_at'] ?? '').toString().trim(),
        (item['id'] ?? '').toString().trim(),
      ].join('|');
      if (itemMarker.compareTo(latestMarker) > 0) {
        latestMarker = itemMarker;
      }
    }
    return AdminSectionSnapshot(
      count: filtered.length,
      marker: '${filtered.length}|$latestMarker',
    );
  }

  int _unreadCountFor(String section) {
    final snapshot = _sectionSnapshots[section];
    if (snapshot == null || snapshot.count <= 0) {
      return 0;
    }
    final seenMarker = _seenMarkers[section]?.trim() ?? '';
    if (seenMarker.isNotEmpty && seenMarker == snapshot.marker) {
      return 0;
    }
    return snapshot.count;
  }

  bool get _hasAttention =>
      _unreadCountFor(moderationSection) > 0 ||
      _unreadCountFor(reportsSection) > 0 ||
      _unreadCountFor(supportSection) > 0;

  void _emitSectionBadgeCounts() {
    final moderationCount = _unreadCountFor(moderationSection);
    final reportsCount = _unreadCountFor(reportsSection);
    final supportCount = _unreadCountFor(supportSection);
    if (!_moderationBadgeController.isClosed) {
      _moderationBadgeController.add(moderationCount);
    }
    if (!_reportsBadgeController.isClosed) {
      _reportsBadgeController.add(reportsCount);
    }
    if (!_supportBadgeController.isClosed) {
      _supportBadgeController.add(supportCount);
    }
    if (!_needsAttentionController.isClosed) {
      _needsAttentionController.add(
        moderationCount > 0 || reportsCount > 0 || supportCount > 0,
      );
    }
  }

  Future<Map<String, dynamic>> _cached(
    String key,
    Future<Map<String, dynamic>> Function() loader, {
    bool forceRefresh = false,
  }) async {
    if (!_sessionActive) {
      throw const ApiException(
        'Требуется авторизация',
        statusCode: 401,
        code: 'local_unauthorized',
      );
    }
    final now = DateTime.now();
    final entry = _cache[key];
    if (!forceRefresh && entry != null) {
      if (entry.value != null &&
          now.difference(entry.updatedAt) < _defaultCacheTtl) {
        return entry.value!;
      }
      if (entry.inFlight != null) {
        return entry.inFlight!;
      }
    }

    final future = loader();
    _cache[key] = _AdminCacheEntry(
      updatedAt: entry?.updatedAt ?? now,
      value: entry?.value,
      inFlight: future,
    );
    try {
      final value = await future;
      _cache[key] = _AdminCacheEntry(
        updatedAt: DateTime.now(),
        value: value,
      );
      if (key == 'listings:pending') {
        _updateSnapshotFromResponse(moderationSection, value);
        _emitSectionBadgeCounts();
      } else if (key == 'reports') {
        _updateSnapshotFromResponse(reportsSection, value);
        _emitSectionBadgeCounts();
      } else if (key == 'support') {
        _updateSnapshotFromResponse(supportSection, value);
        _emitSectionBadgeCounts();
      }
      return value;
    } on ApiException catch (error) {
      if (error.statusCode == 403) {
        await _handleAdminForbidden(endpoint: key, error: error);
        throw const ApiException(
          'Доступ к админ-разделу запрещён. Войдите заново под администратором.',
          statusCode: 403,
          code: 'admin_forbidden',
        );
      }
      if (entry != null) {
        _cache[key] = entry;
      } else {
        _cache.remove(key);
      }
      rethrow;
    } catch (_) {
      if (entry != null) {
        _cache[key] = entry;
      } else {
        _cache.remove(key);
      }
      rethrow;
    }
  }

  Future<void> _handleAdminForbidden({
    required String endpoint,
    required ApiException error,
  }) async {
    final user = await _refreshAdminIdentity(forceRefresh: true);
    _debugSource(
      'Admin 403 endpoint=$endpoint status=${error.statusCode} '
      'phone=${_normalizePhoneForLog(user?.phone)} isAdmin=${user?.isAdmin == true}',
    );
    _cache.clear();
    _lastAttentionRefreshAt = null;
  }

  Future<AuthUser?> _refreshAdminIdentity({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _lastAdminResolvedAt != null &&
        now.difference(_lastAdminResolvedAt!) < _defaultCacheTtl) {
      return _lastAdminResolvedUser;
    }

    final cachedUser = await _tokenStorage.readCurrentUser();
    if (!forceRefresh) {
      _lastAdminResolvedUser = cachedUser;
      _lastAdminResolvedAt = now;
      return cachedUser;
    }

    final accessToken = await _tokenStorage.readAccessToken();
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (accessToken == null ||
        accessToken.trim().isEmpty ||
        refreshToken == null ||
        refreshToken.trim().isEmpty) {
      _lastAdminResolvedUser = cachedUser;
      _lastAdminResolvedAt = now;
      return cachedUser;
    }

    try {
      final response = await _authApi.me();
      final rawUser = response['user'];
      final normalizedMap = rawUser is Map
          ? rawUser.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      final hydratedUser = AuthUser.fromJson(<String, dynamic>{
        ...normalizedMap,
        'isAdmin': response['isAdmin'] ?? response['is_admin'],
        'is_admin': response['is_admin'] ?? response['isAdmin'],
        'role': normalizedMap['role'] ?? response['role'],
      });
      final nextUser = _mergeUsers(cachedUser, hydratedUser);
      await _tokenStorage.saveSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        currentUser: nextUser,
      );
      _lastAdminResolvedUser = nextUser;
      _lastAdminResolvedAt = now;
      return nextUser;
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        _lastAdminResolvedUser = cachedUser;
        _lastAdminResolvedAt = now;
        throw const ApiException(
          'Войдите снова',
          statusCode: 401,
          code: 'session_expired',
        );
      }
      _lastAdminResolvedUser = cachedUser;
      _lastAdminResolvedAt = now;
      return cachedUser;
    }
  }

  AuthUser _mergeUsers(AuthUser? previous, AuthUser next) {
    if (previous == null) {
      return next;
    }
    return AuthUser(
      uid: next.uid.isNotEmpty ? next.uid : previous.uid,
      email: _pickText(next.email, previous.email),
      displayName: _pickText(next.displayName, previous.displayName),
      phone: _pickText(next.phone, previous.phone),
      phoneVerified: next.phoneVerified || previous.phoneVerified,
      photoUrl: _pickText(next.photoUrl, previous.photoUrl),
      referralCode: _pickText(next.referralCode, previous.referralCode),
      isAdmin: next.isAdmin,
    );
  }

  String? _pickText(String? primary, String? fallback) {
    final normalizedPrimary = primary?.trim();
    if (normalizedPrimary != null && normalizedPrimary.isNotEmpty) {
      return normalizedPrimary;
    }
    final normalizedFallback = fallback?.trim();
    if (normalizedFallback != null && normalizedFallback.isNotEmpty) {
      return normalizedFallback;
    }
    return null;
  }

  String _normalizePhoneForLog(String? phone) {
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return 'unknown';
    }
    if (digits.length == 11 && digits.startsWith('8')) {
      return '7${digits.substring(1)}';
    }
    if (digits.length == 10) {
      return '7$digits';
    }
    return digits;
  }
}

class _AdminCacheEntry {
  const _AdminCacheEntry({
    required this.updatedAt,
    this.value,
    this.inFlight,
  });

  final DateTime updatedAt;
  final Map<String, dynamic>? value;
  final Future<Map<String, dynamic>>? inFlight;
}
