import 'dart:async';

import 'package:atta/src/models/feed_ad.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/feed_ads_api.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';

class FeedAdsService {
  FeedAdsService({
    FeedAdsApi? api,
    MediaApi? mediaApi,
  })  : _api = api ?? FeedAdsApi(_apiClient),
        _mediaApi = mediaApi ?? MediaApi(_apiClient);

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);
  final FeedAdsApi _api;
  final MediaApi _mediaApi;
  bool _timewebFeedAdsUnavailable = false;
  FeedAd? _cachedActiveAd;
  DateTime? _cachedActiveAdAt;
  Future<FeedAd?>? _activeAdInFlight;
  final StreamController<FeedAd?> _activeAdController =
      StreamController<FeedAd?>.broadcast();
  final Map<String, DateTime> _lastDebugLogAt = <String, DateTime>{};

  static const Duration _activeAdTtl = Duration(minutes: 2);
  static const Duration _debugLogCooldown = Duration(seconds: 30);

  void _debugSource(String message) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    final lastLoggedAt = _lastDebugLogAt[message];
    if (lastLoggedAt != null &&
        now.difference(lastLoggedAt) < _debugLogCooldown) {
      return;
    }
    _lastDebugLogAt[message] = now;
    debugPrint(message);
  }

  void _markTimewebUnavailable(String message) {
    if (_timewebFeedAdsUnavailable) return;
    _timewebFeedAdsUnavailable = true;
    _debugSource(message);
  }

  List<FeedAd> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <FeedAd>[];
    return raw
        .whereType<Map>()
        .map((row) => FeedAd.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<FeedAd>> loadAllAds({String placement = 'home'}) async {
    _debugSource('FeedAds source: Timeweb');
    if (_timewebFeedAdsUnavailable) {
      return const <FeedAd>[];
    }

    try {
      final response = await _api.adminList(placement: placement);
      final items = _extractItems(response);
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } on ApiException catch (error) {
      if (error.isNotFound) {
        _markTimewebUnavailable(
          'FeedAds source: Timeweb unavailable (404). Falling back to empty state until backend is updated.',
        );
        return const <FeedAd>[];
      }
      rethrow;
    }
  }

  Stream<List<FeedAd>> streamAllAds({
    String placement = 'home',
    Duration pollingInterval = const Duration(seconds: 8),
  }) {
    return Stream<List<FeedAd>>.fromFuture(loadAllAds(placement: placement));
  }

  Stream<FeedAd?> streamActiveAd({String placement = 'home'}) {
    _debugSource('FeedAds source: Timeweb');
    if (_timewebFeedAdsUnavailable) {
      return Stream<FeedAd?>.value(null);
    }
    final cached = _cachedActiveAd;
    final cachedAt = _cachedActiveAdAt;
    if (cachedAt != null &&
        DateTime.now().difference(cachedAt) < _activeAdTtl) {
      return _activeAdController.stream.startWith(cached);
    }
    return Stream<FeedAd?>.fromFuture(refreshActiveAd(placement: placement))
        .asyncExpand((ad) => _activeAdController.stream.startWith(ad));
  }

  Future<FeedAd?> refreshActiveAd({
    String placement = 'home',
    bool rotate = false,
  }) async {
    final existing = _activeAdInFlight;
    if (existing != null && !rotate) return existing;
    final afterId = rotate ? _cachedActiveAd?.id : null;
    final future = () async {
      try {
        final response = await _api.active(
          placement: placement,
          afterId: afterId,
        );
        final raw = response['ad'];
        final ad =
            raw is! Map ? null : FeedAd.fromMap(Map<String, dynamic>.from(raw));
        _cachedActiveAd = ad;
        _cachedActiveAdAt = DateTime.now();
        _activeAdController.add(ad);
        return ad;
      } on ApiException catch (error) {
        if (error.isNotFound) {
          _markTimewebUnavailable(
            'FeedAds source: Timeweb unavailable (404). Falling back to no active ad until backend is updated.',
          );
          _cachedActiveAd = null;
          _cachedActiveAdAt = DateTime.now();
          _activeAdController.add(null);
          return null;
        }
        rethrow;
      }
    }();
    _activeAdInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_activeAdInFlight, future)) {
        _activeAdInFlight = null;
      }
    }
  }

  FeedAd _extractAd(Map<String, dynamic> response, {FeedAd? fallback}) {
    final raw = response['ad'];
    if (raw is Map) {
      return FeedAd.fromMap(Map<String, dynamic>.from(raw));
    }
    if (fallback != null) return fallback;
    throw StateError('Feed ad response does not contain ad.');
  }

  Future<FeedAd> createAd(FeedAd ad) async {
    _debugSource('FeedAds source: Timeweb');
    final response = await _api.create(ad.toMap());
    return _extractAd(response, fallback: ad);
  }

  Future<FeedAd> createAdWithImage({
    required FeedAd ad,
    Uint8List? imageBytes,
    String imageContentType = 'image/jpeg',
  }) async {
    final created = await createAd(ad);
    if (imageBytes == null) return created;

    try {
      final imageUrl = await uploadAdImage(
        feedAdId: created.id,
        bytes: imageBytes,
        contentType: imageContentType,
      );
      final uploadedUrl = imageUrl.trim();
      if (uploadedUrl.isEmpty) {
        throw StateError('Feed ad image upload did not return image URL.');
      }
      return created.copyWith(imageUrl: uploadedUrl);
    } catch (error) {
      try {
        await deleteAd(created.id);
      } catch (_) {}
      rethrow;
    }
  }

  Future<FeedAd> updateAd({
    required String adId,
    required String title,
    required String imageUrl,
    String? targetUrl,
    required int durationDays,
  }) async {
    _debugSource('FeedAds source: Timeweb');
    final body = <String, dynamic>{
      'title': title.trim(),
      'image_url': imageUrl.trim(),
      'duration_days': durationDays,
    };
    if (targetUrl != null) {
      body['target_url'] = targetUrl.trim();
    }
    final response = await _api.update(adId, body);
    final ad = _extractAd(response);
    if (_cachedActiveAd?.id == ad.id) {
      _cachedActiveAd = ad.isVisibleNow ? ad : null;
      _cachedActiveAdAt = DateTime.now();
      _activeAdController.add(_cachedActiveAd);
    }
    return ad;
  }

  Future<FeedAd> updateAdWithImage({
    required String adId,
    required String title,
    required String imageUrl,
    String? targetUrl,
    required int durationDays,
    Uint8List? imageBytes,
    String imageContentType = 'image/jpeg',
  }) async {
    final updated = await updateAd(
      adId: adId,
      title: title,
      imageUrl: imageUrl,
      targetUrl: targetUrl,
      durationDays: durationDays,
    );
    if (imageBytes == null) return updated;

    final uploadedUrl = await uploadAdImage(
      feedAdId: adId,
      bytes: imageBytes,
      contentType: imageContentType,
    );
    final normalizedUrl = uploadedUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw StateError('Feed ad image upload did not return image URL.');
    }
    final ad = updated.copyWith(imageUrl: normalizedUrl);
    if (_cachedActiveAd?.id == ad.id) {
      _cachedActiveAd = ad.isVisibleNow ? ad : null;
      _cachedActiveAdAt = DateTime.now();
      _activeAdController.add(_cachedActiveAd);
    }
    return ad;
  }

  Future<FeedAd> activateAd(String adId, {String placement = 'home'}) async {
    _debugSource('FeedAds source: Timeweb');
    final response = await _api.activate(adId);
    final ad = _extractAd(response);
    if (ad.placement == placement) {
      _cachedActiveAd ??= ad;
      _cachedActiveAdAt = DateTime.now();
      _activeAdController.add(_cachedActiveAd);
    }
    return ad;
  }

  Future<void> deactivateAd(String adId, {String placement = 'home'}) async {
    _debugSource('FeedAds source: Timeweb');
    final response = await _api.deactivate(adId);
    final ad = _extractAd(response);
    if (ad.placement == placement && _cachedActiveAd?.id == ad.id) {
      _cachedActiveAd = null;
      _cachedActiveAdAt = DateTime.now();
      _activeAdController.add(null);
    }
  }

  Future<void> deleteAd(String adId) async {
    _debugSource('FeedAds source: Timeweb');
    await _api.remove(adId);
    if (_cachedActiveAd?.id == adId) {
      _cachedActiveAd = null;
      _cachedActiveAdAt = DateTime.now();
      _activeAdController.add(null);
    }
  }

  Future<void> recordImpression(String adId) async {
    await _trackEvent(adId: adId, event: 'impression');
  }

  Future<void> recordClick(String adId) async {
    await _trackEvent(adId: adId, event: 'click');
  }

  Future<void> _trackEvent({
    required String adId,
    required String event,
  }) async {
    _debugSource('FeedAds source: Timeweb');
    if (event == 'click') {
      await _api.recordClick(adId);
    } else {
      await _api.recordImpression(adId);
    }
  }

  Future<String> uploadAdImage({
    String? feedAdId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final id = (feedAdId ?? '').trim();
    if (id.isEmpty) {
      throw UnsupportedError(
        'Сначала создайте баннер, затем загрузите изображение для Timeweb media.',
      );
    }
    final ext = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      _ => 'jpg',
    };
    final response = await _mediaApi.uploadFeedAdImage(
      feedAdId: id,
      bytes: bytes,
      fileName: 'feed-ad.$ext',
      contentType: contentType,
    );
    final ad = response['ad'];
    if (ad is Map) {
      return (ad['image_url'] ?? '').toString();
    }
    return '';
  }
}

extension<T> on Stream<T> {
  Stream<T> startWith(T initial) async* {
    yield initial;
    yield* this;
  }
}
