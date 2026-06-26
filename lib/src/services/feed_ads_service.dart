import 'dart:async';
import 'dart:typed_data';

import 'package:atta/src/models/feed_ad.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/feed_ads_api.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';

class FeedAdsService {
  FeedAdsService()
      : _api = FeedAdsApi(_apiClient),
        _mediaApi = MediaApi(_apiClient);

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

  static const Duration _activeAdTtl = Duration(minutes: 2);

  void _debugSource(String message) {
    if (!kDebugMode) return;
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

  Stream<List<FeedAd>> streamAllAds({String placement = 'home'}) {
    _debugSource('FeedAds source: Timeweb');
    if (_timewebFeedAdsUnavailable) {
      return Stream<List<FeedAd>>.value(const <FeedAd>[]);
    }
    return Stream<int>.periodic(
      const Duration(seconds: 8),
      (tick) => tick,
    ).asyncMap((_) async {
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
    }).startWith(const <FeedAd>[]);
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

  Future<FeedAd?> refreshActiveAd({String placement = 'home'}) async {
    final existing = _activeAdInFlight;
    if (existing != null) return existing;
    final future = () async {
      try {
        final response = await _api.active(placement: placement);
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

  Future<void> createAd(FeedAd ad) async {
    _debugSource('FeedAds source: Timeweb');
    await _api.create(ad.toMap());
  }

  Future<void> updateAd({
    required String adId,
    required String title,
    required String imageUrl,
    required String targetUrl,
    required int durationDays,
  }) async {
    _debugSource('FeedAds source: Timeweb');
    await _api.update(adId, {
      'title': title.trim(),
      'image_url': imageUrl.trim(),
      'target_url': targetUrl.trim(),
      'duration_days': durationDays,
    });
  }

  Future<void> activateAd(String adId, {String placement = 'home'}) async {
    _debugSource('FeedAds source: Timeweb');
    await _api.activate(adId);
  }

  Future<void> deactivateAd(String adId) async {
    _debugSource('FeedAds source: Timeweb');
    await _api.deactivate(adId);
  }

  Future<void> deleteAd(String adId) async {
    _debugSource('FeedAds source: Timeweb');
    await _api.remove(adId);
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
