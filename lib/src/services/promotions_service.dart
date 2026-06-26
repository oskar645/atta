import 'package:atta/src/models/active_promotion.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/models/listing_stats.dart';
import 'package:atta/src/models/promotion_plan.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/promotions_api.dart';
import 'package:atta/src/services/api/listings_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';

class PromotionsService {
  PromotionsService()
      : _api = PromotionsApi(_apiClient),
        _listingsApi = ListingsApi(_apiClient);

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);

  final PromotionsApi _api;
  final ListingsApi _listingsApi;

  Future<List<PromotionPlan>> getPlans() async {
    if (!ApiConfig.useTimewebBackend) return const <PromotionPlan>[];
    final response = await _api.getPlans();
    final items = response['items'];
    if (items is! List) return const <PromotionPlan>[];
    return items
        .whereType<Map>()
        .map(
          (item) => PromotionPlan.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((plan) => plan.type != 'turbo')
        .toList();
  }

  Future<Map<String, dynamic>> promoteListing(
    String listingId,
    String type,
  ) async {
    if (!ApiConfig.useTimewebBackend) {
      throw Exception('Продвижение доступно только через Timeweb backend');
    }
    if (kDebugMode) {
      debugPrint(
        'Promotions activate request listingId=$listingId planId=$type endpoint=/listings/$listingId/promotions',
      );
    }
    return _api.promoteListing(listingId, type);
  }

  Future<List<ActivePromotion>> getListingPromotions(String listingId) async {
    return (await getListingPromotionState(listingId)).activePromotions;
  }

  Future<ListingPromotionState> getListingPromotionState(
      String listingId) async {
    if (!ApiConfig.useTimewebBackend) {
      return const ListingPromotionState(
        activePromotions: <ActivePromotion>[],
        canPromote: false,
        cannotPromoteReason:
            'Продвижение доступно только через Timeweb backend',
      );
    }
    final response = await _api.getListingPromotions(listingId);
    final promotions = response['promotions'];
    if (promotions is! Map) {
      return const ListingPromotionState(
        activePromotions: <ActivePromotion>[],
        canPromote: false,
      );
    }
    final normalized =
        promotions.map((key, value) => MapEntry(key.toString(), value));
    return ListingPromotionState(
      activePromotions: [
        normalized['activeShowcase'],
        normalized['activeBump'],
        normalized['activeVip'],
        normalized['activeTurbo'],
      ]
          .whereType<Map>()
          .map(
            (item) => ActivePromotion.fromMap(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(),
      canPromote:
          response['canPromote'] == true || response['can_promote'] == true,
      cannotPromoteReason:
          (response['cannotPromoteReason'] ?? response['cannot_promote_reason'])
              ?.toString(),
      cannotPromoteCode:
          (response['cannotPromoteCode'] ?? response['cannot_promote_code'])
              ?.toString(),
    );
  }

  Future<ListingStats> getListingStats(String listingId) async {
    if (!ApiConfig.useTimewebBackend) {
      return const ListingStats(
        views: 0,
        favorites: 0,
        messages: 0,
        calls: 0,
        showcaseImpressions: 0,
        showcaseClicks: 0,
        activePromotions: <ActivePromotion>[],
      );
    }

    final listingResponse = await _listingsApi.getById(listingId);
    final listingMap = listingResponse['listing'];
    final listing = listingMap is Map
        ? Listing.fromMap(
            listingMap.map((key, value) => MapEntry(key.toString(), value)),
          )
        : null;
    final activePromotions = await getListingPromotions(listingId);
    final showcase = activePromotions.where((item) => item.type == 'showcase');
    final showcaseImpressions =
        showcase.fold<int>(0, (sum, item) => sum + item.impressionsCount);
    final showcaseClicks =
        showcase.fold<int>(0, (sum, item) => sum + item.clicksCount);

    return ListingStats(
      views: listing?.viewCount ?? 0,
      favorites: 0,
      messages: 0,
      calls: 0,
      showcaseImpressions: showcaseImpressions,
      showcaseClicks: showcaseClicks,
      activePromotions: activePromotions,
    );
  }
}

class ListingPromotionState {
  const ListingPromotionState({
    required this.activePromotions,
    required this.canPromote,
    this.cannotPromoteReason,
    this.cannotPromoteCode,
  });

  final List<ActivePromotion> activePromotions;
  final bool canPromote;
  final String? cannotPromoteReason;
  final String? cannotPromoteCode;
}
