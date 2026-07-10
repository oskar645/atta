import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/reviews_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';

class ReviewsService {
  ReviewsService({
    ReviewsApi? api,
  }) : _api = api ?? ReviewsApi(_apiClient);

  final ReviewsApi _api;

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);

  final Map<String, List<Map<String, dynamic>>> _cache =
      <String, List<Map<String, dynamic>>>{};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _controllers =
      <String, StreamController<List<Map<String, dynamic>>>>{};
  final Map<String, Future<List<Map<String, dynamic>>>> _inFlight =
      <String, Future<List<Map<String, dynamic>>>>{};
  final Map<String, DateTime> _cachedAt = <String, DateTime>{};

  static const Duration _cacheTtl = Duration(minutes: 2);

  StreamController<List<Map<String, dynamic>>> _controllerFor(String sellerId) {
    return _controllers.putIfAbsent(
      sellerId,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(),
    );
  }

  void _debugSource(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _sortNewestFirst(List<Map<String, dynamic>> rows) {
    final copy = rows.map((item) => Map<String, dynamic>.from(item)).toList();
    copy.sort((a, b) {
      final left = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final right = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    return copy;
  }

  void _publish(String sellerId, List<Map<String, dynamic>> rows) {
    final next = _sortNewestFirst(rows);
    _cache[sellerId] = next;
    _cachedAt[sellerId] = DateTime.now();
    _controllerFor(sellerId).add(
      next
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
    );
  }

  List<Map<String, dynamic>> peekSellerReviews(String sellerId) {
    return List<Map<String, dynamic>>.from(
      _cache[sellerId] ?? const <Map<String, dynamic>>[],
    );
  }

  Future<List<Map<String, dynamic>>> refreshSellerReviews(
    String sellerId,
  ) async {
    final id = sellerId.trim();
    if (id.isEmpty) return const <Map<String, dynamic>>[];
    final existing = _inFlight[id];
    if (existing != null) return existing;
    final future = () async {
      _debugSource('Reviews source: Timeweb');
      final response = await _api.listSellerReviews(id);
      final items = _extractItems(response);
      _publish(id, items);
      return List<Map<String, dynamic>>.from(_cache[id] ?? items);
    }();
    _inFlight[id] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[id], future)) {
        _inFlight.remove(id);
      }
    }
  }

  Stream<List<Map<String, dynamic>>> streamSellerReviews(String sellerId) {
    final id = sellerId.trim();
    if (id.isEmpty) {
      return Stream<List<Map<String, dynamic>>>.value(
        const <Map<String, dynamic>>[],
      ).asBroadcastStream();
    }
    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      final cached = _cache[id];
      final cachedAt = _cachedAt[id];
      final initial = cached
              ?.map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false) ??
          const <Map<String, dynamic>>[];
      controller.add(initial);

      final sub = _controllerFor(id).stream.listen(
        (items) {
          controller.add(
            items
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false),
          );
        },
        onError: controller.addError,
      );

      final isFresh = cached != null &&
          cachedAt != null &&
          DateTime.now().difference(cachedAt) < _cacheTtl;
      if (!isFresh) {
        unawaited(
          refreshSellerReviews(id).catchError((Object error, StackTrace stack) {
            _debugSource('Reviews source: refresh failed for $id: $error');
            return initial;
          }),
        );
      }

      controller.onCancel = () => sub.cancel();
    }).asBroadcastStream();
  }

  Stream<Map<String, dynamic>> streamSellerRating(String sellerId) {
    return streamSellerReviews(sellerId).map((items) {
      if (items.isEmpty) return {'avg': 0.0, 'count': 0};

      double sum = 0;
      int cnt = 0;

      for (final r in items) {
        final v = r['rating'];
        if (v is num) {
          sum += v.toDouble();
          cnt++;
        } else {
          final parsed = double.tryParse(v?.toString() ?? '');
          if (parsed != null) {
            sum += parsed;
            cnt++;
          }
        }
      }

      final avg = cnt == 0 ? 0.0 : (sum / cnt);
      return {'avg': avg, 'count': cnt};
    });
  }

  Future<void> addReview({
    required String sellerId,
    required String reviewerId,
    required String reviewerName,
    required String listingId,
    required int rating,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _debugSource('Reviews source: Timeweb');
    final response = await _api.addReview(
      sellerId: sellerId,
      listingId: listingId,
      rating: rating,
      text: trimmed,
      reviewerName: reviewerName,
    );
    final item = response['item'];
    if (item is Map) {
      final current =
          List<Map<String, dynamic>>.from(_cache[sellerId] ?? const []);
      current.insert(0, Map<String, dynamic>.from(item));
      _publish(sellerId, current);
      return;
    }
    await refreshSellerReviews(sellerId);
  }

  Future<void> replyToReview({
    required String sellerId,
    required String reviewId,
    required String replyText,
  }) async {
    final trimmed = replyText.trim();
    if (trimmed.isEmpty) return;

    _debugSource('Reviews source: Timeweb');
    final response = await _api.updateReview(
      reviewId,
      replyText: trimmed,
    );
    final item = response['item'];
    if (item is Map) {
      final current =
          List<Map<String, dynamic>>.from(_cache[sellerId] ?? const []);
      final index = current.indexWhere(
        (entry) => (entry['id'] ?? '').toString() == reviewId,
      );
      if (index != -1) {
        current[index] = Map<String, dynamic>.from(item);
        _publish(sellerId, current);
        return;
      }
    }
    await refreshSellerReviews(sellerId);
  }

  Future<void> deleteReview({
    required String reviewId,
  }) async {
    final id = reviewId.trim();
    if (id.isEmpty) return;

    _debugSource('Reviews source: Timeweb');
    await _api.deleteReview(id);
    for (final entry in _cache.entries.toList()) {
      final filtered = entry.value
          .where((item) => (item['id'] ?? '').toString() != id)
          .toList(growable: false);
      if (filtered.length != entry.value.length) {
        _publish(entry.key, filtered);
      }
    }
  }

  Future<void> resetNewReviewsCount(String sellerId) async {
    _debugSource('Reviews source: Timeweb');
  }

  void resetSession() {
    _cache.clear();
    _cachedAt.clear();
    _inFlight.clear();
    for (final controller in _controllers.values) {
      unawaited(controller.close());
    }
    _controllers.clear();
  }
}
