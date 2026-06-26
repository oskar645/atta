import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/listings_api.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/api/reviews_api.dart';
import 'package:atta/src/services/api/users_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/image_preparation_service.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

class AvatarUploadResult {
  const AvatarUploadResult({
    required this.avatarUrl,
    required this.previousAvatarUrl,
  });

  final String avatarUrl;
  final String previousAvatarUrl;
}

class ProfileService {
  ProfileService({
    TokenStorage? tokenStorage,
    UsersApi? usersApi,
    ListingsApi? listingsApi,
    MediaApi? mediaApi,
    ReviewsApi? reviewsApi,
    ImagePreparationService? imagePreparationService,
    Future<void> Function(String url)? avatarCacheEvictor,
  })  : _tokenStorage = tokenStorage ?? _sharedTokenStorage,
        _usersApi = usersApi ??
            UsersApi(_apiClientFor(tokenStorage ?? _sharedTokenStorage)),
        _listingsApi = listingsApi ??
            ListingsApi(_apiClientFor(tokenStorage ?? _sharedTokenStorage)),
        _mediaApi = mediaApi ??
            MediaApi(_apiClientFor(tokenStorage ?? _sharedTokenStorage)),
        _reviewsApi = reviewsApi ??
            ReviewsApi(_apiClientFor(tokenStorage ?? _sharedTokenStorage)),
        _imagePreparationService =
            imagePreparationService ?? ImagePreparationService(),
        _avatarCacheEvictor = avatarCacheEvictor;

  static final TokenStorage _sharedTokenStorage = TokenStorage();
  static ApiClient _apiClientFor(TokenStorage tokenStorage) =>
      ApiClient(tokenStorage: tokenStorage);

  final TokenStorage _tokenStorage;
  final UsersApi _usersApi;
  final ListingsApi _listingsApi;
  final MediaApi _mediaApi;
  final ReviewsApi _reviewsApi;
  final ImagePreparationService _imagePreparationService;
  final Future<void> Function(String url)? _avatarCacheEvictor;
  final Map<String, Map<String, dynamic>> _profileCache = {};
  final Map<String, DateTime> _profileCachedAt = {};
  final Map<String, Future<Map<String, dynamic>>> _profileInFlight = {};

  static const Duration _profileCacheTtl = Duration(minutes: 2);

  Map<String, dynamic> _normalizeRow(Map<String, dynamic>? row) {
    if (row == null || row.isEmpty) return <String, dynamic>{};
    return Map<String, dynamic>.from(row);
  }

  Map<String, dynamic> _mergeRows(
    Map<String, dynamic>? base,
    Map<String, dynamic>? override,
  ) {
    final merged = <String, dynamic>{};
    if (base != null && base.isNotEmpty) merged.addAll(base);
    if (override != null && override.isNotEmpty) merged.addAll(override);
    _preservePreferredAvatar(merged, base, override);
    return merged;
  }

  void _preservePreferredAvatar(
    Map<String, dynamic> target,
    Map<String, dynamic>? base,
    Map<String, dynamic>? override,
  ) {
    final baseAvatar = _extractAvatarUrl(base);
    final overrideAvatar = _extractAvatarUrl(override);
    final preferredAvatar = _preferAvatarUrl(
      primaryUrl: overrideAvatar,
      primaryRow: override,
      fallbackUrl: baseAvatar,
      fallbackRow: base,
    );
    if (preferredAvatar.isEmpty) {
      return;
    }
    target['avatar_url'] = preferredAvatar;
    target['avatarUrl'] = preferredAvatar;

    final basePhoto = _extractPhotoUrl(base);
    final overridePhoto = _extractPhotoUrl(override);
    final preferredPhoto = _preferAvatarUrl(
      primaryUrl: overridePhoto.isNotEmpty ? overridePhoto : overrideAvatar,
      primaryRow: override,
      fallbackUrl: basePhoto.isNotEmpty ? basePhoto : baseAvatar,
      fallbackRow: base,
    );
    final photo = preferredPhoto.isNotEmpty ? preferredPhoto : preferredAvatar;
    target['photo_url'] = photo;
    target['photoUrl'] = photo;
  }

  void _cacheProfile(String uid, Map<String, dynamic> row) {
    final id = uid.trim();
    if (id.isEmpty || row.isEmpty) return;
    _profileCache[id] = _normalizeRow(row);
    _profileCachedAt[id] = DateTime.now();
  }

  Map<String, dynamic> getCachedProfile(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return <String, dynamic>{};
    return _normalizeRow(_profileCache[id]);
  }

  void seedProfile(String uid, Map<String, dynamic> row) {
    _cacheProfile(uid, row);
  }

  void resetSession() {
    _profileCache.clear();
    _profileCachedAt.clear();
    _profileInFlight.clear();
  }

  Stream<Map<String, dynamic>> streamProfile(
    String uid, {
    Map<String, dynamic>? seed,
  }) async* {
    final id = uid.trim();
    if (id.isEmpty) {
      yield <String, dynamic>{};
      return;
    }

    final seeded = _mergeRows(getCachedProfile(id), _normalizeRow(seed));
    if (seeded.isNotEmpty) {
      _cacheProfile(id, seeded);
      yield seeded;
    }

    _debugSource('Profile source: Timeweb');
    try {
      final live = await getProfile(id);
      if (live.isNotEmpty) {
        _cacheProfile(id, live);
      }
      yield _mergeRows(seeded, live);
    } catch (_) {
      yield seeded;
    }
  }

  Future<Map<String, dynamic>> getProfile(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return <String, dynamic>{};
    final cached = getCachedProfile(id);
    final cachedAt = _profileCachedAt[id];
    if (cached.isNotEmpty &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _profileCacheTtl) {
      return cached;
    }
    final inFlight = _profileInFlight[id];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _getProfileInternal(id, cached);
    _profileInFlight[id] = future;
    try {
      return await future;
    } finally {
      if (identical(_profileInFlight[id], future)) {
        _profileInFlight.remove(id);
      }
    }
  }

  Future<Map<String, dynamic>> _getProfileInternal(
    String uid,
    Map<String, dynamic> cached,
  ) async {
    _debugSource('Profile source: Timeweb');
    final currentUser = await _tokenStorage.readCurrentUser();
    final response = currentUser?.uid == uid
        ? await _usersApi.me()
        : await _usersApi.publicProfile(uid);
    final normalized = _mergeRows(
      _currentUserFallback(uid, currentUser),
      _normalizeBackendProfile(response),
    );
    if (currentUser?.uid == uid) {
      await _syncCurrentUserFromProfile(normalized, currentUser);
    }
    if (normalized.isNotEmpty) _cacheProfile(uid, normalized);
    return _mergeRows(cached, normalized);
  }

  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {
    _debugSource('Profile source: Timeweb');
    final payload = <String, dynamic>{
      if (data['display_name'] != null) 'display_name': data['display_name'],
      if (data['name'] != null) 'name': data['name'],
      if (data['phone'] != null) 'phone': data['phone'],
      if (data['avatar_url'] != null) 'avatar_url': data['avatar_url'],
      if (data['photo_url'] != null) 'photo_url': data['photo_url'],
    };
    final response = await _usersApi.updateMe(payload);
    final updated = _mergeRows(
      _currentUserFallback(uid, await _tokenStorage.readCurrentUser()),
      _normalizeBackendProfile(response),
    );
    if (updated.isNotEmpty) {
      _cacheProfile(uid, _mergeRows(getCachedProfile(uid), updated));
      await _syncCurrentUserFromProfile(
          updated, await _tokenStorage.readCurrentUser());
    }
  }

  String pickNameFromRow(
    Map<String, dynamic> row, {
    String fallback = 'Пользователь',
  }) {
    final dn =
        (row['display_name'] ?? row['displayName'] ?? '').toString().trim();
    final name = (row['name'] ?? '').toString().trim();
    final email = (row['email'] ?? '').toString().trim();
    return dn.isNotEmpty
        ? dn
        : (name.isNotEmpty ? name : (email.isNotEmpty ? email : fallback));
  }

  String pickAvatarFromRow(Map<String, dynamic> row) {
    final a1 = _withAvatarVersion(
      (row['avatar_url'] ?? '').toString().trim(),
      _avatarVersionForRow(row),
    );
    if (a1.isNotEmpty) return a1;
    final a2 = _withAvatarVersion(
      (row['photo_url'] ?? '').toString().trim(),
      _avatarVersionForRow(row),
    );
    if (a2.isNotEmpty) return a2;
    return '';
  }

  String _extractAvatarUrl(Map<String, dynamic>? row) =>
      (row?['avatar_url'] ?? row?['avatarUrl'] ?? '').toString().trim();

  String _extractPhotoUrl(Map<String, dynamic>? row) =>
      (row?['photo_url'] ?? row?['photoUrl'] ?? '').toString().trim();

  String _preferAvatarUrl({
    required String primaryUrl,
    required Map<String, dynamic>? primaryRow,
    required String fallbackUrl,
    required Map<String, dynamic>? fallbackRow,
  }) {
    final primary = primaryUrl.trim();
    final fallback = fallbackUrl.trim();
    if (primary.isEmpty) return fallback;
    if (fallback.isEmpty) return primary;
    if (primary == fallback) return primary;

    final primaryVersion = _parseAvatarVersion(
      _avatarVersionForRow(primaryRow ?? const <String, dynamic>{})
              .trim()
              .isNotEmpty
          ? _avatarVersionForRow(primaryRow ?? const <String, dynamic>{})
          : _avatarVersionFromUrl(primary),
    );
    final fallbackVersion = _parseAvatarVersion(
      _avatarVersionForRow(fallbackRow ?? const <String, dynamic>{})
              .trim()
              .isNotEmpty
          ? _avatarVersionForRow(fallbackRow ?? const <String, dynamic>{})
          : _avatarVersionFromUrl(fallback),
    );

    if (primaryVersion != null && fallbackVersion != null) {
      return primaryVersion.isBefore(fallbackVersion) ? fallback : primary;
    }
    if (primaryVersion == null && fallbackVersion != null) {
      return fallback;
    }
    return primary;
  }

  Future<AvatarUploadResult> uploadAvatar({
    required String uid,
    required Uint8List bytes,
    String fileName = 'avatar.jpg',
    String contentType = 'image/jpeg',
  }) async {
    _debugSource('Profile source: Timeweb');
    final previousAvatar = pickAvatarFromRow(
      _mergeRows(
        getCachedProfile(uid),
        _currentUserFallback(uid, await _tokenStorage.readCurrentUser()),
      ),
    );
    final prepared = await _imagePreparationService.prepareAvatarBytes(
      bytes,
      fileName: fileName,
    );
    final response = await _mediaApi.uploadAvatar(
      bytes: prepared.bytes,
      fileName: prepared.fileName,
      contentType:
          prepared.contentType.isNotEmpty ? prepared.contentType : contentType,
    );
    if (kDebugMode) {
      final rawAvatarUrl = (response['avatar_url'] ?? '').toString().trim();
      final resolution = resolveMediaUrl(
        rawAvatarUrl,
        categoryHint: 'avatars',
      );
      debugPrint(
        'Avatar upload response imageUrl=$rawAvatarUrl resolved=${resolution.resolvedUrl} category=avatar provider=${resolution.provider} userAvatar=${(response['user'] is Map ? (response['user']['avatar_url'] ?? response['user']['avatarUrl'] ?? '') : '').toString().trim()}',
      );
    }
    final normalizedResponse = _normalizeBackendProfile(response);
    final merged = _mergeRows(
      getCachedProfile(uid),
      normalizedResponse.isNotEmpty
          ? normalizedResponse
          : <String, dynamic>{
              'avatar_url': (response['avatar_url'] ?? '').toString().trim(),
              'photo_url': (response['photo_url'] ?? '').toString().trim(),
            },
    );
    if (merged.isNotEmpty) {
      _cacheProfile(uid, merged);
      await _syncCurrentUserFromProfile(
          merged, await _tokenStorage.readCurrentUser());
    }
    final avatarUrl = pickAvatarFromRow(merged);
    await _evictAvatarCache(previousAvatar);
    await _evictAvatarCache(avatarUrl);
    return AvatarUploadResult(
      avatarUrl: avatarUrl,
      previousAvatarUrl: previousAvatar,
    );
  }

  Stream<int> streamMyListingsCount(String uid) async* {
    try {
      final response = await _listingsApi.list(
        queryParameters: {
          'ownerId': uid,
        },
      );
      final items = _extractItems(response);
      final count = items
          .where((item) => (item['status'] ?? '').toString() == 'approved')
          .length;
      yield count;
    } catch (_) {
      yield 0;
    }
  }

  Stream<double> streamMyRatingAvg(String uid) {
    return Stream<double>.fromFuture((() async {
      try {
        final response = await _reviewsApi.listSellerReviews(uid);
        final items = _extractItems(response);
        if (items.isEmpty) return 0.0;
        final sum = items.fold<num>(
          0,
          (total, item) => total + ((item['rating'] as num?) ?? 0),
        );
        return (sum / items.length).toDouble();
      } catch (_) {
        return 0.0;
      }
    })());
  }

  Stream<int> streamMyReviewsCount(String uid) {
    return Stream<int>.fromFuture((() async {
      try {
        final response = await _reviewsApi.listSellerReviews(uid);
        return _extractItems(response).length;
      } catch (_) {
        return 0;
      }
    })());
  }

  Stream<String> streamDisplayName(
    String uid, {
    String fallback = 'Пользователь',
  }) {
    return streamProfile(uid)
        .map((row) => pickNameFromRow(row, fallback: fallback));
  }

  Future<String> getDisplayName(
    String uid, {
    String fallback = 'Пользователь',
  }) async {
    final row = await getProfile(uid);
    return pickNameFromRow(row, fallback: fallback);
  }

  Map<String, dynamic> _normalizeBackendProfile(Map<String, dynamic> response) {
    final user = response['user'];
    if (user is Map<String, dynamic>) {
      return _normalizeAvatarFields(Map<String, dynamic>.from(user));
    }
    if (user is Map) {
      return _normalizeAvatarFields(
        user.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return _normalizeAvatarFields(_normalizeRow(response));
  }

  Map<String, dynamic> _currentUserFallback(
    String uid,
    dynamic currentUser,
  ) {
    if (currentUser == null || currentUser.uid != uid) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{
      'id': currentUser.uid,
      if ((currentUser.email ?? '').toString().trim().isNotEmpty)
        'email': currentUser.email,
      if ((currentUser.displayName ?? '').toString().trim().isNotEmpty) ...{
        'display_name': currentUser.displayName,
        'name': currentUser.displayName,
      },
      if ((currentUser.photoUrl ?? '').toString().trim().isNotEmpty) ...{
        'avatar_url': currentUser.photoUrl,
        'photo_url': currentUser.photoUrl,
      },
      if ((currentUser.phone ?? '').toString().trim().isNotEmpty)
        'phone': currentUser.phone,
      'phone_verified': currentUser.phoneVerified,
      'phoneVerified': currentUser.phoneVerified,
    };
  }

  Map<String, dynamic> _normalizeAvatarFields(Map<String, dynamic> row) {
    if (row.isEmpty) return row;
    final version = _avatarVersionForRow(row);
    final avatarUrl = _withAvatarVersion(
      resolvePublicMediaUrl(
        (row['avatar_url'] ?? row['avatarUrl'] ?? '').toString(),
        categoryHint: 'avatars',
      ).trim(),
      version,
    );
    final photoUrl = _withAvatarVersion(
      resolvePublicMediaUrl(
        (row['photo_url'] ?? row['photoUrl'] ?? '').toString(),
        categoryHint: 'avatars',
      ).trim(),
      version,
    );
    final normalized = <String, dynamic>{...row};
    if (avatarUrl.isNotEmpty) {
      normalized['avatar_url'] = avatarUrl;
      normalized['avatarUrl'] = avatarUrl;
    } else {
      normalized.remove('avatar_url');
      normalized.remove('avatarUrl');
    }
    if (photoUrl.isNotEmpty) {
      normalized['photo_url'] = photoUrl;
      normalized['photoUrl'] = photoUrl;
    } else {
      normalized.remove('photo_url');
      normalized.remove('photoUrl');
    }
    return normalized;
  }

  String _avatarVersionForRow(Map<String, dynamic> row) {
    for (final key in const ['avatar_updated_at', 'updated_at', 'updatedAt']) {
      final raw = row[key]?.toString().trim() ?? '';
      if (raw.isNotEmpty) return raw;
    }
    return '';
  }

  String _avatarVersionFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri?.queryParameters['v']?.trim() ?? '';
  }

  DateTime? _parseAvatarVersion(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(Uri.decodeQueryComponent(value));
  }

  String _withAvatarVersion(String url, String version) {
    final trimmedUrl = url.trim();
    final trimmedVersion = version.trim();
    if (trimmedUrl.isEmpty || trimmedVersion.isEmpty) return trimmedUrl;
    final separator = trimmedUrl.contains('?') ? '&' : '?';
    if (trimmedUrl.contains('v=')) return trimmedUrl;
    return '$trimmedUrl${separator}v=${Uri.encodeQueryComponent(trimmedVersion)}';
  }

  Future<void> _evictAvatarCache(String url) async {
    if (_avatarCacheEvictor != null) {
      await _avatarCacheEvictor!(url);
      return;
    }
    for (final candidate in _avatarCacheVariants(url)) {
      await CachedNetworkImage.evictFromCache(candidate);
      PaintingBinding.instance.imageCache.evict(
        NetworkImage(candidate),
      );
    }
  }

  List<String> _avatarCacheVariants(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return const <String>[];
    final variants = <String>{trimmed};
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasQuery) {
      final parameters = Map<String, String>.from(uri.queryParameters)
        ..remove('v');
      final stripped = uri.replace(
        queryParameters: parameters.isEmpty ? null : parameters,
      );
      variants.add(stripped.toString());
    }
    return variants.toList(growable: false);
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  void _debugSource(String message) {
    if (!kDebugMode || message == 'Profile source: Timeweb') return;
    debugPrint(message);
  }

  Future<void> _syncCurrentUserFromProfile(
    Map<String, dynamic> row,
    dynamic currentUser,
  ) async {
    if (currentUser == null || row.isEmpty || currentUser.uid != row['id']) {
      return;
    }

    final accessToken = await _tokenStorage.readAccessToken();
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (accessToken == null || refreshToken == null) {
      return;
    }

    String? pickText(List<String> keys) {
      for (final key in keys) {
        final value = row[key]?.toString().trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    }

    final nextUser = AuthUser(
      uid: currentUser.uid,
      email: pickText(const ['email']) ?? currentUser.email,
      displayName: pickText(const ['display_name', 'displayName', 'name']) ??
          currentUser.displayName,
      phone: pickText(const ['phone', 'normalized_phone', 'normalizedPhone']) ??
          currentUser.phone,
      phoneVerified: row['phoneVerified'] == true ||
          row['phone_verified'] == true ||
          row['isPhoneVerified'] == true ||
          currentUser.phoneVerified == true,
      photoUrl: pickText(const [
            'avatar_url',
            'avatarUrl',
            'photo_url',
            'photoUrl',
          ]) ??
          currentUser.photoUrl,
      isAdmin: row['isAdmin'] == true ||
          row['is_admin'] == true ||
          row['role'] == 'admin' ||
          currentUser.isAdmin == true,
    );

    await _tokenStorage.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      currentUser: nextUser,
    );
  }
}
