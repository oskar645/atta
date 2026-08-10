import 'dart:async';

import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/saved_searches_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class SavedSearch {
  final String id;
  final String userId;
  final String title;
  final String queryKey;
  final String category;
  final String search;
  final String subcategory;
  final int? priceFrom;
  final int? priceTo;
  final String location;
  final bool preferLocationFirst;
  final int? radiusKm;
  final String autoBrand;
  final String autoModel;
  final String autoCondition;
  final int? autoYearFrom;
  final int? autoYearTo;
  final int? autoMileageFrom;
  final int? autoMileageTo;
  final String autoTransmission;
  final String autoDrive;
  final String autoBodyType;
  final String autoFuel;
  final String autoColor;
  final double? autoEngineVolumeFrom;
  final double? autoEngineVolumeTo;
  final int? autoOwners;
  final bool? autoCleared;
  final bool onlyUncrashed;
  final bool onlyWithPhoto;
  final bool alertsEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SavedSearch({
    required this.id,
    required this.userId,
    required this.title,
    required this.queryKey,
    required this.category,
    required this.search,
    required this.subcategory,
    required this.priceFrom,
    required this.priceTo,
    required this.location,
    required this.preferLocationFirst,
    required this.radiusKm,
    required this.autoBrand,
    required this.autoModel,
    required this.autoCondition,
    required this.autoYearFrom,
    required this.autoYearTo,
    required this.autoMileageFrom,
    required this.autoMileageTo,
    required this.autoTransmission,
    required this.autoDrive,
    required this.autoBodyType,
    required this.autoFuel,
    required this.autoColor,
    required this.autoEngineVolumeFrom,
    required this.autoEngineVolumeTo,
    required this.autoOwners,
    required this.autoCleared,
    required this.onlyUncrashed,
    required this.onlyWithPhoto,
    required this.alertsEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SavedSearch.fromMap(Map<String, dynamic> row) {
    DateTime parseDate(dynamic raw) {
      if (raw is DateTime) return raw.toUtc();
      if (raw is String) {
        return DateTime.tryParse(raw)?.toUtc() ?? DateTime.now().toUtc();
      }
      return DateTime.now().toUtc();
    }

    int? parseNullableInt(dynamic raw) {
      if (raw is num) return raw.toInt();
      return int.tryParse((raw ?? '').toString());
    }

    final queryKey = (row['query_key'] ?? '').toString();
    final keyFilters = _filtersFromQueryKey(queryKey);

    return SavedSearch(
      id: (row['id'] ?? '').toString(),
      userId: (row['user_id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      queryKey: queryKey,
      category: (row['category'] ?? '').toString(),
      search: (row['search'] ?? '').toString(),
      subcategory: (row['subcategory'] ?? '').toString(),
      priceFrom: keyFilters?.priceFrom,
      priceTo: keyFilters?.priceTo,
      location: (row['location'] ?? '').toString(),
      preferLocationFirst: row['prefer_location_first'] == true,
      radiusKm: parseNullableInt(row['radius_km']),
      autoBrand: (row['auto_brand'] ?? '').toString(),
      autoModel: (row['auto_model'] ?? '').toString(),
      autoCondition: (row['auto_condition'] ?? '').toString(),
      autoYearFrom: keyFilters?.autoYearFrom,
      autoYearTo: keyFilters?.autoYearTo,
      autoMileageFrom: keyFilters?.autoMileageFrom,
      autoMileageTo: parseNullableInt(row['auto_mileage_to']),
      autoTransmission: keyFilters?.autoTransmission ?? '',
      autoDrive: keyFilters?.autoDrive ?? '',
      autoBodyType: keyFilters?.autoBodyType ?? '',
      autoFuel: keyFilters?.autoFuel ?? '',
      autoColor: keyFilters?.autoColor ?? '',
      autoEngineVolumeFrom: keyFilters?.autoEngineVolumeFrom,
      autoEngineVolumeTo: keyFilters?.autoEngineVolumeTo,
      autoOwners: keyFilters?.autoOwners,
      autoCleared: keyFilters?.autoCleared,
      onlyUncrashed: row['only_uncrashed'] == true,
      onlyWithPhoto: keyFilters?.onlyWithPhoto ?? false,
      alertsEnabled: row['alerts_enabled'] != false,
      createdAt: parseDate(row['created_at']),
      updatedAt: parseDate(row['updated_at']),
    );
  }

  ListingFeedFilters toFilters() {
    return ListingFeedFilters(
      category: category,
      search: search,
      subcategory: subcategory,
      priceFrom: priceFrom,
      priceTo: priceTo,
      location: location,
      preferLocationFirst: preferLocationFirst,
      radiusKm: radiusKm,
      autoBrand: autoBrand,
      autoModel: autoModel,
      autoCondition: autoCondition,
      autoYearFrom: autoYearFrom,
      autoYearTo: autoYearTo,
      autoMileageFrom: autoMileageFrom,
      autoMileageTo: autoMileageTo,
      autoTransmission: autoTransmission,
      autoDrive: autoDrive,
      autoBodyType: autoBodyType,
      autoFuel: autoFuel,
      autoColor: autoColor,
      autoEngineVolumeFrom: autoEngineVolumeFrom,
      autoEngineVolumeTo: autoEngineVolumeTo,
      autoOwners: autoOwners,
      autoCleared: autoCleared,
      onlyUncrashed: onlyUncrashed,
      onlyWithPhoto: onlyWithPhoto,
    );
  }

  static ListingFeedFilters? _filtersFromQueryKey(String queryKey) {
    final parts = queryKey.split('|');
    if (parts.length != 26) return null;
    return ListingFeedFilters(
      category: parts[1],
      search: parts[0],
      subcategory: parts[2],
      priceFrom: int.tryParse(parts[3]),
      priceTo: int.tryParse(parts[4]),
      location: parts[5],
      preferLocationFirst: parts[6] == '1',
      radiusKm: int.tryParse(parts[7]),
      autoBrand: parts[8],
      autoModel: parts[9],
      autoCondition: parts[10],
      autoYearFrom: int.tryParse(parts[11]),
      autoYearTo: int.tryParse(parts[12]),
      autoMileageFrom: int.tryParse(parts[13]),
      autoMileageTo: int.tryParse(parts[14]),
      autoTransmission: parts[15],
      autoDrive: parts[16],
      autoBodyType: parts[17],
      autoFuel: parts[18],
      autoColor: parts[19],
      autoEngineVolumeFrom: double.tryParse(parts[20]),
      autoEngineVolumeTo: double.tryParse(parts[21]),
      autoOwners: int.tryParse(parts[22]),
      autoCleared: parts[23].isEmpty ? null : parts[23] == 'true',
      onlyUncrashed: parts[24] == '1',
      onlyWithPhoto: parts[25] == '1',
    );
  }
}

class SavedSearchService {
  static const String missingTableMessage =
      'Сохранённые поиски временно недоступны. Попробуйте позже.';

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);
  final ListingsService _listings = ListingsService();
  final NotificationsService _notifications = NotificationsService();
  final Uuid _uuid = const Uuid();
  final SavedSearchesApi _api = SavedSearchesApi(_apiClient);
  final Map<String, List<SavedSearch>> _cache = <String, List<SavedSearch>>{};
  final Map<String, DateTime> _cacheAt = <String, DateTime>{};
  final Map<String, Future<List<SavedSearch>>> _inFlight =
      <String, Future<List<SavedSearch>>>{};

  static const Duration _cacheTtl = Duration(minutes: 2);

  void _debugSource(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  List<SavedSearch> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <SavedSearch>[];
    return raw
        .whereType<Map>()
        .map((item) => SavedSearch.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  bool isMissingTableError(Object error) => false;

  Stream<List<SavedSearch>> streamSavedSearches(String userId) {
    _debugSource('SavedSearches source: Timeweb');
    final cached = peekSavedSearches(userId);
    return Stream<List<SavedSearch>>.fromFuture(
      getSavedSearches(userId),
    ).startWith(cached);
  }

  Future<List<SavedSearch>> getSavedSearches(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return const <SavedSearch>[];
    _debugSource('SavedSearches source: Timeweb');
    final cached = _cache[id];
    final cachedAt = _cacheAt[id];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return List<SavedSearch>.from(cached);
    }
    return refreshSavedSearches(id);
  }

  List<SavedSearch> peekSavedSearches(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return const <SavedSearch>[];
    return List<SavedSearch>.from(_cache[id] ?? const <SavedSearch>[]);
  }

  Future<List<SavedSearch>> refreshSavedSearches(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return const <SavedSearch>[];
    final existing = _inFlight[id];
    if (existing != null) return existing;
    final future = () async {
      final response = await _api.list();
      final items = _extractItems(response)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _cache[id] = List<SavedSearch>.from(items);
      _cacheAt[id] = DateTime.now();
      return items;
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

  String buildQueryKey({
    required String search,
    required ListingFeedFilters filters,
  }) {
    String norm(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

    final hasExtendedFilters = filters.priceFrom != null ||
        filters.priceTo != null ||
        filters.autoYearFrom != null ||
        filters.autoYearTo != null ||
        filters.autoMileageFrom != null ||
        filters.autoTransmission.trim().isNotEmpty ||
        filters.autoDrive.trim().isNotEmpty ||
        filters.autoBodyType.trim().isNotEmpty ||
        filters.autoFuel.trim().isNotEmpty ||
        filters.autoColor.trim().isNotEmpty ||
        filters.autoEngineVolumeFrom != null ||
        filters.autoEngineVolumeTo != null ||
        filters.autoOwners != null ||
        filters.autoCleared != null ||
        filters.onlyWithPhoto;

    if (!hasExtendedFilters) {
      return [
        norm(search),
        norm(filters.category),
        norm(filters.subcategory),
        norm(filters.location),
        filters.preferLocationFirst ? '1' : '0',
        filters.radiusKm?.toString() ?? '',
        norm(filters.autoBrand),
        norm(filters.autoModel),
        norm(filters.autoCondition),
        filters.autoMileageTo?.toString() ?? '',
        filters.onlyUncrashed ? '1' : '0',
      ].join('|');
    }

    return [
      norm(search),
      norm(filters.category),
      norm(filters.subcategory),
      filters.priceFrom?.toString() ?? '',
      filters.priceTo?.toString() ?? '',
      norm(filters.location),
      filters.preferLocationFirst ? '1' : '0',
      filters.radiusKm?.toString() ?? '',
      norm(filters.autoBrand),
      norm(filters.autoModel),
      norm(filters.autoCondition),
      filters.autoYearFrom?.toString() ?? '',
      filters.autoYearTo?.toString() ?? '',
      filters.autoMileageFrom?.toString() ?? '',
      filters.autoMileageTo?.toString() ?? '',
      norm(filters.autoTransmission),
      norm(filters.autoDrive),
      norm(filters.autoBodyType),
      norm(filters.autoFuel),
      norm(filters.autoColor),
      filters.autoEngineVolumeFrom?.toString() ?? '',
      filters.autoEngineVolumeTo?.toString() ?? '',
      filters.autoOwners?.toString() ?? '',
      filters.autoCleared?.toString() ?? '',
      filters.onlyUncrashed ? '1' : '0',
      filters.onlyWithPhoto ? '1' : '0',
    ].join('|');
  }

  bool canSaveSearch({
    required String search,
    required ListingFeedFilters filters,
  }) {
    return search.trim().isNotEmpty ||
        (filters.category.trim().isNotEmpty && filters.category != 'Все') ||
        (filters.subcategory.trim().isNotEmpty &&
            filters.subcategory != 'Все') ||
        filters.priceFrom != null ||
        filters.priceTo != null ||
        filters.location.trim().isNotEmpty ||
        filters.autoBrand.trim().isNotEmpty ||
        filters.autoModel.trim().isNotEmpty ||
        filters.autoCondition.trim().isNotEmpty ||
        filters.autoYearFrom != null ||
        filters.autoYearTo != null ||
        filters.autoMileageFrom != null ||
        filters.autoMileageTo != null ||
        filters.autoTransmission.trim().isNotEmpty ||
        filters.autoDrive.trim().isNotEmpty ||
        filters.autoBodyType.trim().isNotEmpty ||
        filters.autoFuel.trim().isNotEmpty ||
        filters.autoColor.trim().isNotEmpty ||
        filters.autoEngineVolumeFrom != null ||
        filters.autoEngineVolumeTo != null ||
        filters.autoOwners != null ||
        filters.autoCleared != null ||
        filters.onlyUncrashed ||
        filters.onlyWithPhoto;
  }

  String buildTitle({
    required String search,
    required ListingFeedFilters filters,
  }) {
    final parts = <String>[];

    if (filters.autoBrand.trim().isNotEmpty) {
      parts.add(filters.autoBrand.trim());
    }
    if (filters.autoModel.trim().isNotEmpty) {
      parts.add(filters.autoModel.trim());
    }
    if (parts.isEmpty &&
        filters.category.trim().isNotEmpty &&
        filters.category != 'Все') {
      parts.add(filters.category.trim());
    }
    if (parts.isEmpty && search.trim().isNotEmpty) {
      parts.add(search.trim());
    }
    if (parts.isEmpty) {
      parts.add('Сохранённый поиск');
    }

    return parts.join(' ');
  }

  String buildSummary({
    required String search,
    required ListingFeedFilters filters,
  }) {
    final parts = <String>[];

    if (filters.category.trim().isNotEmpty && filters.category != 'Все') {
      parts.add(filters.category);
    }
    if (filters.subcategory.trim().isNotEmpty && filters.subcategory != 'Все') {
      parts.add(filters.subcategory);
    }
    if (filters.autoBrand.trim().isNotEmpty) {
      parts.add(filters.autoBrand);
    }
    if (filters.autoModel.trim().isNotEmpty) {
      parts.add(filters.autoModel);
    }
    if (filters.autoCondition.trim().isNotEmpty) {
      parts.add(filters.autoCondition);
    }
    if (filters.priceFrom != null || filters.priceTo != null) {
      parts.add(
        '${filters.priceFrom == null ? '' : 'от ${filters.priceFrom} ₽'}'
                ' ${filters.priceTo == null ? '' : 'до ${filters.priceTo} ₽'}'
            .trim(),
      );
    }
    if (filters.autoYearFrom != null || filters.autoYearTo != null) {
      parts.add(
        '${filters.autoYearFrom == null ? '' : 'от ${filters.autoYearFrom} г.'}'
                ' ${filters.autoYearTo == null ? '' : 'до ${filters.autoYearTo} г.'}'
            .trim(),
      );
    }
    if (filters.autoMileageFrom != null) {
      parts.add('от ${filters.autoMileageFrom} км');
    }
    if (filters.autoMileageTo != null) {
      parts.add('до ${filters.autoMileageTo} км');
    }
    if (filters.autoTransmission.trim().isNotEmpty) {
      parts.add(filters.autoTransmission);
    }
    if (filters.autoDrive.trim().isNotEmpty) {
      parts.add(filters.autoDrive);
    }
    if (filters.onlyWithPhoto) {
      parts.add('с фото');
    }
    if (filters.onlyUncrashed) {
      parts.add('не битые');
    }
    if (filters.location.trim().isNotEmpty) {
      parts.add(filters.location);
    }
    if (search.trim().isNotEmpty) {
      parts.add('поиск: ${search.trim()}');
    }

    return parts.isEmpty ? 'Все объявления' : parts.join(' • ');
  }

  Future<void> saveSearch({
    required String userId,
    required String search,
    required ListingFeedFilters filters,
  }) async {
    _debugSource('SavedSearches source: Timeweb');
    await _api.save({
      'id': _uuid.v4(),
      'title': buildTitle(search: search, filters: filters),
      'query_key': buildQueryKey(search: search, filters: filters),
      'category': filters.category,
      'search': search.trim(),
      'subcategory': filters.subcategory,
      'location': filters.location.trim(),
      'prefer_location_first': filters.preferLocationFirst,
      'radius_km': filters.radiusKm,
      'auto_brand': filters.autoBrand.trim(),
      'auto_model': filters.autoModel.trim(),
      'auto_condition': filters.autoCondition.trim(),
      'auto_mileage_to': filters.autoMileageTo,
      'only_uncrashed': filters.onlyUncrashed,
      'alerts_enabled': true,
    });
  }

  Future<void> deleteSavedSearch({
    required String userId,
    required String queryKey,
  }) async {
    _debugSource('SavedSearches source: Timeweb');
    final response = await _api.list();
    final items = _extractItems(response);
    final item = items.cast<SavedSearch?>().firstWhere(
          (entry) => entry?.queryKey == queryKey,
          orElse: () => null,
        );
    if (item != null) {
      await _api.remove(item.id);
    }
  }

  Future<void> setAlertsEnabled({
    required String savedSearchId,
    required bool enabled,
  }) async {
    _debugSource('SavedSearches source: Timeweb');
    await _api.update(savedSearchId, {
      'alerts_enabled': enabled,
    });
  }

  Future<void> notifyMatchesForApprovedListing(
    Map<String, dynamic> rawListing,
  ) async {
    _debugSource('SavedSearches source: Timeweb');
    final listingRow = Map<String, dynamic>.from(rawListing);
    listingRow['status'] = 'approved';
    final listing = Listing.fromMap(listingRow);
    final response = await _api.list();
    final searches = _extractItems(response)
        .where((search) => search.alertsEnabled)
        .where((search) => search.userId != listing.ownerId)
        .toList();

    final notifiedUsers = <String>{};
    for (final savedSearch in searches) {
      if (notifiedUsers.contains(savedSearch.userId)) continue;
      if (!_listings.matchesFeedFilters(listing, savedSearch.toFilters())) {
        continue;
      }

      await _notifications.sendPersonal(
        userId: savedSearch.userId,
        title: NotificationsService.savedSearchNotificationTitle,
        body:
            '${savedSearch.title}: ${listing.title}. ${listing.price} ₽, ${listing.cityShort}.',
      );
      notifiedUsers.add(savedSearch.userId);
    }
  }
}

extension<T> on Stream<T> {
  Stream<T> startWith(T initial) async* {
    yield initial;
    yield* this;
  }
}
