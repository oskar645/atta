import 'dart:async';

import 'package:atta/src/services/api/auth_api.dart';
import 'package:atta/src/services/api/admin_api.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';

class AdminService {
  AdminService({
    AdminApi? api,
    AuthApi? authApi,
  })  : _api = api ?? AdminApi(_apiClient),
        _authApi = authApi ?? AuthApi(_apiClient);

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);

  final AdminApi _api;
  final AuthApi _authApi;
  final Map<String, _AdminCacheEntry> _cache = <String, _AdminCacheEntry>{};
  final StreamController<int> _pendingCountController =
      StreamController<int>.broadcast();
  Stream<int>? _openReportsCountStream;
  Stream<int>? _unreadSupportCountStream;
  DateTime? _lastReportsCountRefreshAt;
  DateTime? _lastSupportCountRefreshAt;
  AuthUser? _lastAdminResolvedUser;
  DateTime? _lastAdminResolvedAt;

  static const Duration _defaultCacheTtl = Duration(seconds: 15);
  bool _sessionActive = true;

  void activateSession() {
    _sessionActive = true;
  }

  void resetSession() {
    _sessionActive = false;
    _cache.clear();
    _openReportsCountStream = null;
    _unreadSupportCountStream = null;
    _lastReportsCountRefreshAt = null;
    _lastSupportCountRefreshAt = null;
    _lastAdminResolvedUser = null;
    _lastAdminResolvedAt = null;
    if (!_pendingCountController.isClosed) {
      _pendingCountController.add(0);
    }
  }

  Stream<bool> streamIsAdmin(String uid) {
    if (!_sessionActive) return Stream<bool>.value(false);
    return Stream<bool>.fromFuture(isAdminOnce(uid)).asBroadcastStream();
  }

  Future<bool> isAdminOnce(String uid) async {
    final currentUser = await _refreshAdminIdentity();
    if (currentUser == null) return false;
    return currentUser.uid == uid && currentUser.isAdmin;
  }

  Stream<int> streamPendingModerationCount() async* {
    if (!_sessionActive) {
      yield 0;
      return;
    }
    final cachedPending = _pendingItemsFromCache();
    if (cachedPending != null) {
      yield cachedPending.length;
    } else {
      try {
        final response = await listings(status: 'pending');
        yield _extractItems(response).length;
      } catch (error) {
        _debugSource('Admin source: Timeweb unavailable: $error');
        yield 0;
      }
    }
    yield* _pendingCountController.stream.distinct();
  }

  Stream<int> streamOpenReportsCount() {
    if (!_sessionActive) {
      return Stream<int>.value(0);
    }
    return _openReportsCountStream ??= Stream<int>.multi((controller) {
      Future<void> emit() async {
        try {
          final response = await reports(
            forceRefresh: _isCountRefreshStale(_lastReportsCountRefreshAt),
          );
          _lastReportsCountRefreshAt = DateTime.now();
          controller.add(
            _extractItems(response)
                .where((item) => (item['status'] ?? '').toString() == 'open')
                .length,
          );
        } catch (_) {
          controller.add(0);
        }
      }

      emit();
    }).distinct().asBroadcastStream();
  }

  Stream<int> streamUnreadSupportForAdminCount() {
    if (!_sessionActive) {
      return Stream<int>.value(0);
    }
    return _unreadSupportCountStream ??= Stream<int>.multi((controller) {
      Future<void> emit() async {
        try {
          final response = await support(
            forceRefresh: _isCountRefreshStale(_lastSupportCountRefreshAt),
          );
          _lastSupportCountRefreshAt = DateTime.now();
          controller.add(
            _extractItems(response)
                .where((item) => item['unread_for_admin'] == true)
                .length,
          );
        } catch (_) {
          controller.add(0);
        }
      }

      emit();
    }).distinct().asBroadcastStream();
  }

  Stream<bool> streamNeedsAttention() {
    final controller = StreamController<bool>.broadcast();

    int pending = 0;
    int reports = 0;
    int support = 0;

    StreamSubscription<int>? s1;
    StreamSubscription<int>? s2;
    StreamSubscription<int>? s3;

    void emit() {
      if (!controller.isClosed) {
        controller.add(pending > 0 || reports > 0 || support > 0);
      }
    }

    controller.onListen = () {
      s1 = streamPendingModerationCount().listen(
        (v) {
          pending = v;
          emit();
        },
        onError: controller.addError,
      );
      s2 = streamOpenReportsCount().listen(
        (v) {
          reports = v;
          emit();
        },
        onError: controller.addError,
      );
      s3 = streamUnreadSupportForAdminCount().listen(
        (v) {
          support = v;
          emit();
        },
        onError: controller.addError,
      );
    };

    controller.onCancel = () async {
      await s1?.cancel();
      await s2?.cancel();
      await s3?.cancel();
    };

    return controller.stream.distinct();
  }

  Future<Map<String, dynamic>> dashboardStats({bool forceRefresh = false}) =>
      _cached('dashboardStats', _api.dashboardStats,
          forceRefresh: forceRefresh);
  Future<Map<String, dynamic>> users({bool forceRefresh = false}) =>
      _cached('users', _api.users, forceRefresh: forceRefresh);
  Future<Map<String, dynamic>> userById(
    String userId, {
    bool forceRefresh = false,
  }) =>
      _cached(
        'user:$userId',
        () => _api.userById(userId),
        forceRefresh: forceRefresh,
      );
  Future<Map<String, dynamic>> deleteUser(String userId) =>
      _api.deleteUser(userId);
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
    _cache.remove('dashboardStats');
    final pendingCount = _pendingItemsFromCache()?.length ?? 0;
    if (!_pendingCountController.isClosed) {
      _pendingCountController.add(pendingCount);
    }
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

  bool _isCountRefreshStale(DateTime? lastRefreshAt) {
    if (lastRefreshAt == null) return true;
    return DateTime.now().difference(lastRefreshAt) >= _defaultCacheTtl;
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
    _openReportsCountStream = null;
    _unreadSupportCountStream = null;
    _lastReportsCountRefreshAt = null;
    _lastSupportCountRefreshAt = null;
  }

  Future<AuthUser?> _refreshAdminIdentity({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _lastAdminResolvedUser != null &&
        _lastAdminResolvedAt != null &&
        now.difference(_lastAdminResolvedAt!) < _defaultCacheTtl) {
      return _lastAdminResolvedUser;
    }

    final accessToken = await _tokenStorage.readAccessToken();
    final refreshToken = await _tokenStorage.readRefreshToken();
    final cachedUser = await _tokenStorage.readCurrentUser();
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
        _lastAdminResolvedUser = null;
        _lastAdminResolvedAt = now;
        return null;
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
