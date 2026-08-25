import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atta/src/models/car_specs.dart';
import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/listings_api.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/image_preparation_service.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

class ListingFeedFilters {
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
  const ListingFeedFilters({
    required this.category,
    required this.search,
    this.subcategory = 'Все',
    this.priceFrom,
    this.priceTo,
    this.location = '',
    this.preferLocationFirst = false,
    this.radiusKm,
    this.autoBrand = '',
    this.autoModel = '',
    this.autoCondition = '',
    this.autoYearFrom,
    this.autoYearTo,
    this.autoMileageFrom,
    this.autoMileageTo,
    this.autoTransmission = '',
    this.autoDrive = '',
    this.autoBodyType = '',
    this.autoFuel = '',
    this.autoColor = '',
    this.autoEngineVolumeFrom,
    this.autoEngineVolumeTo,
    this.autoOwners,
    this.autoCleared,
    this.onlyUncrashed = false,
    this.onlyWithPhoto = false,
  });
}

class CreateListingResult {
  final String listingId;
  final ListingPhotoUploadResult photoUploadResult;
  final Listing? listing;

  const CreateListingResult({
    required this.listingId,
    this.photoUploadResult = const ListingPhotoUploadResult(),
    this.listing,
  });

  bool get photoUploadFailed => photoUploadResult.hasFailures;
}

class ListingsFeedPage {
  const ListingsFeedPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<Listing> items;
  final bool hasMore;
  final String? nextCursor;
}

class MyListingsPage {
  const MyListingsPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<Listing> items;
  final bool hasMore;
  final String? nextCursor;
}

class ListingPhotoUploadFailure {
  const ListingPhotoUploadFailure({
    required this.file,
    required this.index,
    required this.message,
  });

  final File file;
  final int index;
  final String message;
}

typedef ListingPhotoUploadStatusCallback = void Function(
  ListingPhotoUploadStatus status,
);

class ListingPhotoUploadStatus {
  const ListingPhotoUploadStatus({
    required this.file,
    required this.index,
    required this.state,
    this.message = '',
    this.listingId = '',
  });

  final File file;
  final int index;
  final String state;
  final String message;
  final String listingId;
}

class ListingPhotoUploadResult {
  const ListingPhotoUploadResult({
    this.requestedCount = 0,
    this.uploadedCount = 0,
    this.failures = const <ListingPhotoUploadFailure>[],
    this.listing,
  });

  final int requestedCount;
  final int uploadedCount;
  final List<ListingPhotoUploadFailure> failures;
  final Listing? listing;

  int get failedCount => failures.length;
  bool get hasFailures => failures.isNotEmpty;
  bool get allFailed => requestedCount > 0 && uploadedCount == 0;
}

class ListingPhotoUploadResponse {
  const ListingPhotoUploadResponse({
    required this.listing,
    required this.photoId,
  });

  final Listing listing;
  final String photoId;
}

class ListingsService {
  ListingsService({
    ListingsApi? api,
    MediaApi? mediaApi,
  })  : _api = api ?? ListingsApi(_apiClient),
        _mediaApi = mediaApi ?? MediaApi(_apiClient),
        _imagePreparationService = ImagePreparationService();

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);

  final ListingsApi _api;
  final MediaApi _mediaApi;
  final ImagePreparationService _imagePreparationService;
  final StreamController<void> _refreshController =
      StreamController<void>.broadcast();
  final Map<String, Listing> _listingById = <String, Listing>{};
  final Map<String, List<Listing>> _timewebCache = <String, List<Listing>>{};
  final Map<String, DateTime> _timewebCachedAt = <String, DateTime>{};
  final Map<String, Future<List<Listing>>> _timewebInFlight =
      <String, Future<List<Listing>>>{};
  List<Listing>? _myListingsCache;
  DateTime? _myListingsCachedAt;
  Future<List<Listing>>? _myListingsInFlight;
  String? _myListingsCacheUserId;
  String? _myListingsInFlightUserId;
  Object? _lastMyListingsError;
  String? _lastMyListingsErrorUserId;
  final Map<String, List<Listing>> _ownerListingsCache =
      <String, List<Listing>>{};
  final Map<String, DateTime> _ownerListingsCachedAt = <String, DateTime>{};
  final Map<String, Future<List<Listing>>> _ownerListingsInFlight =
      <String, Future<List<Listing>>>{};
  final Map<String, Future<ListingsFeedPage>> _feedPageInFlight =
      <String, Future<ListingsFeedPage>>{};

  static const Duration _cacheTtl = Duration(seconds: 20);

  Stream<void> get refreshes => _refreshController.stream;

  Stream<List<Listing>> streamListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) async* {
    final effectiveFilters = filters ??
        ListingFeedFilters(
          category: category,
          search: search,
        );

    _debugSource('Listings source: Timeweb');
    yield await _fetchListings(effectiveFilters);
    await for (final _ in _refreshController.stream) {
      yield await _fetchListings(effectiveFilters);
    }
  }

  bool matchesFeedFilters(Listing listing, ListingFeedFilters filters) {
    return _matchesFilters(listing, filters);
  }

  Stream<List<Listing>> streamMyListings(String uid) async* {
    _debugSource('Listings source: Timeweb');
    yield await _fetchMyListings(uid);
    await for (final _ in _refreshController.stream) {
      yield await _fetchMyListings(uid);
    }
  }

  Stream<int> streamMyListingsCount(String uid) {
    return streamMyListings(uid).map((items) => items.length);
  }

  Stream<List<Listing>> streamListingsByOwner(String ownerId) {
    return streamListingsByOwnerAll(ownerId).map(
      (items) => items.where((x) => x.status == 'approved').toList(),
    );
  }

  List<Listing> peekListingsByOwner(String ownerId) {
    return List<Listing>.from(
      _ownerListingsCache[ownerId.trim()] ?? const <Listing>[],
    );
  }

  Future<List<Listing>> getListingsByOwnerAll(String ownerId) async {
    _debugSource('Listings source: Timeweb');
    return _fetchListingsByOwner(ownerId);
  }

  Future<List<Listing>> refreshListingsByOwner(String ownerId) async {
    final id = ownerId.trim();
    if (id.isEmpty) return const <Listing>[];
    _ownerListingsCache.remove(id);
    _ownerListingsCachedAt.remove(id);
    _debugSource('Listings source: Timeweb');
    return _fetchListingsByOwner(id, forceRefresh: true);
  }

  Future<ListingsFeedPage> getPublicOwnerListingsPage({
    required String ownerId,
    required String status,
    int limit = 20,
    String? cursor,
    bool forceRefresh = false,
  }) async {
    if (runtimeType != ListingsService) {
      if ((cursor ?? '').trim().isNotEmpty) {
        return const ListingsFeedPage(items: <Listing>[], hasMore: false);
      }
      final items = forceRefresh
          ? await refreshListingsByOwner(ownerId)
          : await getListingsByOwnerAll(ownerId);
      final allowed = status == 'archive'
          ? const <String>{'archived', 'sold'}
          : <String>{status};
      return ListingsFeedPage(
        items: items.where((item) => allowed.contains(item.status)).toList(),
        hasMore: false,
      );
    }

    final id = ownerId.trim();
    if (id.isEmpty) {
      return const ListingsFeedPage(items: <Listing>[], hasMore: false);
    }
    final normalizedStatus = status.trim().toLowerCase();
    final requestKey = [
      'owner',
      id,
      normalizedStatus,
      limit,
      (cursor ?? '').trim(),
      if (forceRefresh) 'refresh',
    ].join('|');
    final existing = _feedPageInFlight[requestKey];
    if (existing != null) {
      return existing;
    }

    final future = () async {
      _debugSource('Listings source: Timeweb');
      final response = await _api.list(
        queryParameters: {
          'ownerId': id,
          'limit': limit,
          if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
          if (normalizedStatus == 'archive')
            'publicMode': 'archive'
          else
            'status': normalizedStatus,
        },
      );
      final allowed = normalizedStatus == 'archive'
          ? const <String>{'archived', 'sold'}
          : <String>{normalizedStatus};
      final items = _dedupeAndSortListings(_extractItems(response))
          .where((item) => item.ownerId == id && allowed.contains(item.status))
          .toList(growable: false);
      _cacheListings(items);
      if ((cursor ?? '').trim().isEmpty && normalizedStatus == 'approved') {
        _ownerListingsCache[id] = List<Listing>.from(items);
        _ownerListingsCachedAt[id] = DateTime.now();
      }
      final nextCursor = _extractNextCursor(response);
      return ListingsFeedPage(
        items: items,
        hasMore:
            (response['hasMore'] == true || response['has_more'] == true) &&
                nextCursor != null,
        nextCursor: nextCursor,
      );
    }();
    _feedPageInFlight[requestKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_feedPageInFlight[requestKey], future)) {
        _feedPageInFlight.remove(requestKey);
      }
    }
  }

  Stream<List<Listing>> streamListingsByOwnerAll(String ownerId) async* {
    _debugSource('Listings source: Timeweb');
    yield await _fetchListingsByOwner(ownerId);
    await for (final _ in _refreshController.stream) {
      yield await _fetchListingsByOwner(ownerId);
    }
  }

  Stream<List<Listing>> streamSimilarListings(
    Listing base, {
    int limit = 10,
  }) async* {
    _debugSource('Listings source: Timeweb');
    yield await getSimilarListings(base, limit: limit);
    await for (final _ in _refreshController.stream) {
      yield await getSimilarListings(base, limit: limit);
    }
  }

  Future<List<Listing>> getSimilarListings(
    Listing base, {
    int limit = 10,
  }) async {
    _debugSource('Listings source: Timeweb');
    final items = await _fetchListings(
      ListingFeedFilters(
        category: base.category,
        search: '',
      ),
    );
    final filtered = items
        .where((x) => x.id != base.id)
        .where((x) => x.category == base.category)
        .toList();
    filtered.sort((a, b) => _compareSimilarListings(a, b, base));
    return filtered.take(limit).toList(growable: false);
  }

  Stream<List<Listing>> streamMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
  }) {
    return streamMyListings(uid).map(
      (items) => items.where((x) => statuses.contains(x.status)).toList(),
    );
  }

  Future<List<Listing>> getListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) async {
    final effectiveFilters = filters ??
        ListingFeedFilters(
          category: category,
          search: search,
        );

    _debugSource('Listings source: Timeweb');
    return _fetchListings(effectiveFilters);
  }

  Future<ListingsFeedPage> getListingsPage({
    required String category,
    required String search,
    ListingFeedFilters? filters,
    int limit = 20,
    String? cursor,
    bool useVipInterleave = false,
    int vipRotation = 0,
  }) async {
    final effectiveFilters = filters ??
        ListingFeedFilters(
          category: category,
          search: search,
        );
    final requestKey = [
      _filtersCacheKey(effectiveFilters),
      limit,
      (cursor ?? '').trim(),
      if (useVipInterleave) 'vip_interleave_v1:$vipRotation',
    ].join('|');
    final existing = _feedPageInFlight[requestKey];
    if (existing != null) {
      return existing;
    }

    final future = () async {
      _debugSource('Listings source: Timeweb');
      final response = await _api.list(
        queryParameters: {
          if (!_isAllCategory(effectiveFilters.category))
            'category': effectiveFilters.category,
          if (effectiveFilters.search.trim().isNotEmpty)
            'search': effectiveFilters.search.trim(),
          if (effectiveFilters.location.trim().isNotEmpty)
            'city': effectiveFilters.location.trim(),
          if (effectiveFilters.priceFrom != null)
            'minPrice': effectiveFilters.priceFrom,
          if (effectiveFilters.priceTo != null)
            'maxPrice': effectiveFilters.priceTo,
          'limit': limit,
          if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
          if (useVipInterleave) 'feedMode': 'vip_interleave_v1',
          if (useVipInterleave) 'vipRotation': vipRotation,
        },
      );
      final items = _extractItems(response);
      final filtered = items
          .where((item) => _matchesFilters(item, effectiveFilters))
          .toList();
      _cacheListings(items);
      return ListingsFeedPage(
        items: filtered,
        hasMore: response['hasMore'] == true || response['has_more'] == true,
        nextCursor: (response['nextCursor'] ?? response['next_cursor'])
            ?.toString()
            .trim(),
      );
    }();
    _feedPageInFlight[requestKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_feedPageInFlight[requestKey], future)) {
        _feedPageInFlight.remove(requestKey);
      }
    }
  }

  Future<ListingsFeedPage> getVipListingsPage({
    int limit = 20,
    String? cursor,
    String category = 'Все',
    String search = '',
  }) async {
    final effectiveCategory = category.trim().isEmpty ? 'Все' : category.trim();
    final effectiveSearch = search.trim();
    final requestKey = [
      'vip',
      effectiveCategory,
      effectiveSearch,
      limit,
      (cursor ?? '').trim(),
    ].join('|');
    final existing = _feedPageInFlight[requestKey];
    if (existing != null) {
      return existing;
    }

    final future = () async {
      final response = await _api.vipListings(
        limit: limit,
        cursor: cursor,
        category: _isAllCategory(effectiveCategory) ? null : effectiveCategory,
        search: effectiveSearch,
      );
      final items = _extractItems(response);
      _cacheListings(items);
      return ListingsFeedPage(
        items: items,
        hasMore: response['hasMore'] == true || response['has_more'] == true,
        nextCursor: _extractNextCursor(response),
      );
    }();
    _feedPageInFlight[requestKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_feedPageInFlight[requestKey], future)) {
        _feedPageInFlight.remove(requestKey);
      }
    }
  }

  List<Listing> peekListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) {
    final effectiveFilters = filters ??
        ListingFeedFilters(
          category: category,
          search: search,
        );
    final key = _filtersCacheKey(effectiveFilters);
    return List<Listing>.from(_timewebCache[key] ?? const <Listing>[]);
  }

  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
    bool forceRefresh = false,
  }) async {
    _debugSource('Listings source: Timeweb');
    final items = await _fetchMyListings(
      uid,
      statuses: statuses,
      forceRefresh: forceRefresh,
    );
    return items.where((item) => statuses.contains(item.status)).toList();
  }

  Future<MyListingsPage> getMyListingsPageByStatuses(
    String uid, {
    required Set<String> statuses,
    int limit = 20,
    String? cursor,
    bool forceRefresh = false,
  }) async {
    if (runtimeType != ListingsService) {
      if ((cursor ?? '').trim().isNotEmpty) {
        return const MyListingsPage(items: <Listing>[], hasMore: false);
      }
      final items = await getMyListingsByStatuses(
        uid,
        statuses: statuses,
        forceRefresh: forceRefresh,
      );
      return MyListingsPage(items: items, hasMore: false);
    }
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return const MyListingsPage(items: <Listing>[], hasMore: false);
    }
    _debugSource('Listings source: Timeweb');
    final statusList = statuses.toList(growable: false)..sort();
    if (statusList.isEmpty) {
      return const MyListingsPage(items: <Listing>[], hasMore: false);
    }

    var cursorState = _decodeMyListingsCursor(cursor);
    var statusIndex = cursorState.statusIndex.clamp(0, statusList.length - 1);
    String? statusCursor = cursorState.cursor;
    final collected = <Listing>[];
    final seen = <String>{};
    String? nextCursor;
    var hasMore = false;

    while (statusIndex < statusList.length && collected.isEmpty) {
      final response = await _api.myListings(
        status: statusList[statusIndex],
        limit: limit,
        cursor: statusCursor,
      );
      for (final item in _sanitizeMyListings(
        _extractItems(response),
        currentUserId: normalizedUid,
      )) {
        if (statuses.contains(item.status) && seen.add(item.id)) {
          collected.add(item);
        }
      }
      _cacheListings(collected);
      _syncMyListingsPageCache(
        normalizedUid,
        statuses: statuses,
        items: collected,
        reset: (cursor ?? '').trim().isEmpty,
      );
      final responseCursor = _extractNextCursor(response);
      if (response['hasMore'] == true && responseCursor != null) {
        hasMore = true;
        nextCursor = _encodeMyListingsCursor(statusIndex, responseCursor);
      } else {
        statusIndex += 1;
        statusCursor = null;
        hasMore = statusIndex < statusList.length;
        nextCursor =
            hasMore ? _encodeMyListingsCursor(statusIndex, null) : null;
      }
    }

    return MyListingsPage(
      items: collected,
      hasMore: hasMore,
      nextCursor: nextCursor,
    );
  }

  /// Reloads the shared source for every "My listings" tab in one request.
  Future<List<Listing>> refreshMyListings(String uid) {
    return _fetchMyListings(uid, forceRefresh: true);
  }

  List<Listing> peekMyListingsByStatuses({
    required Set<String> statuses,
  }) {
    final items = List<Listing>.from(_myListingsCache ?? const <Listing>[]);
    return items.where((item) => statuses.contains(item.status)).toList();
  }

  Object? lastMyListingsErrorForUser(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty || _lastMyListingsErrorUserId != normalizedUid) {
      return null;
    }
    return _lastMyListingsError;
  }

  Future<Listing?> getLatestApprovedListingByOwner(String ownerId) async {
    _debugSource('Listings source: Timeweb');
    final items = await _fetchListingsByOwner(ownerId);
    final approved = items.where((item) => item.status == 'approved').toList();
    if (approved.isEmpty) return null;
    approved.sort(_compareFeedListings);
    return approved.first;
  }

  Future<CreateListingResult> createListing({
    required String ownerId,
    required String ownerEmail,
    required String ownerName,
    required String title,
    required String description,
    required String category,
    required String subcategory,
    required int price,
    required String phone,
    required bool phoneHidden,
    required String city,
    required Map<String, bool> delivery,
    required List<File> photos,
    CarSpecs? car,
    String? dealType,
    String? clothesType,
    String? clothesSize,
    String? oemPartNumber,
    ListingPhotoUploadStatusCallback? onPhotoStatusChanged,
  }) async {
    _debugSource('Listings source: Timeweb');
    _debugCreateListingStart(
      ownerId: ownerId,
      title: title,
      photoCount: photos.length,
    );
    final created = await _api.create({
      'owner_email': ownerEmail,
      'owner_name': ownerName,
      'title': title,
      'description': description,
      'category': category,
      'subcategory': subcategory,
      'price': price,
      'phone': phone,
      'phone_hidden': phoneHidden,
      'city': city,
      'address': city,
      'delivery': delivery,
      'photo_urls': const <String>[],
      if (car != null) 'car': car.toMap(),
      if (dealType != null && dealType.trim().isNotEmpty)
        'deal_type': dealType.trim(),
      if (clothesType != null && clothesType.trim().isNotEmpty)
        'clothes_type': clothesType.trim(),
      if (category == 'Одежда' &&
          clothesSize != null &&
          clothesSize.trim().isNotEmpty)
        'clothes_size': clothesSize.trim(),
      if (category == 'Запчасти' && oemPartNumber != null)
        'oem_part_number': oemPartNumber.trim(),
    });
    final createdListing = _extractListingFromResponse(created);
    final listingId = createdListing?.id ?? '';
    Listing? latestListing = createdListing;
    var photoUploadResult = const ListingPhotoUploadResult();
    if (listingId.isNotEmpty) {
      if (latestListing != null) {
        _upsertListingInCaches(latestListing);
        _emitRefresh(clearCaches: false);
      }
      photoUploadResult = await uploadListingPhotos(
        listingId: listingId,
        photos: photos,
        onStatusChanged: onPhotoStatusChanged,
      );
      latestListing = photoUploadResult.listing ?? latestListing;
    }
    latestListing ??=
        listingId.isEmpty ? null : await getListingById(listingId);
    if (latestListing != null) {
      _upsertListingInCaches(latestListing);
      _emitRefresh(clearCaches: false);
      unawaited(_refreshListingFromBackend(listingId));
    } else {
      _emitRefresh();
    }
    return CreateListingResult(
      listingId: listingId,
      photoUploadResult: photoUploadResult,
      listing: latestListing,
    );
  }

  Future<CreateListingResult> createDraftListing({
    required String ownerEmail,
    required String ownerName,
    required String category,
    required String subcategory,
    required String city,
    required String phone,
    required bool phoneHidden,
    required Map<String, bool> delivery,
  }) async {
    _debugSource('Listings source: Timeweb');
    final created = await _api.create({
      'owner_email': ownerEmail,
      'owner_name': ownerName,
      'title': 'Черновик объявления',
      'description': 'Черновик объявления',
      'category': category,
      'subcategory': subcategory,
      'price': 0,
      'phone': phone,
      'phone_hidden': phoneHidden,
      'city': city,
      'address': city,
      'delivery': delivery,
      'photo_urls': const <String>[],
      'status': 'pending',
    });
    final listing = _extractListingFromResponse(created);
    final listingId = listing?.id ?? '';
    if (listing != null) {
      _upsertListingInCaches(listing);
      _emitRefresh(clearCaches: false);
    }
    return CreateListingResult(listingId: listingId, listing: listing);
  }

  Future<Listing?> deleteListing({required Listing listing}) async {
    _debugSource('Listings source: Timeweb');
    final response = await _api.deleteListing(listing.id);
    final updated = _extractListingFromResponse(response) ??
        _listingById[listing.id] ??
        listing;
    _upsertListingInCaches(updated);
    _emitRefresh(clearCaches: false);
    unawaited(_refreshListingFromBackend(listing.id));
    return updated;
  }

  void applyExternalListingUpdate(Listing listing) {
    _upsertListingInCaches(listing);
    _emitRefresh(clearCaches: false);
  }

  Future<Listing?> archiveListing({
    required String listingId,
    required String status,
    String? note,
  }) async {
    _debugSource('Listings source: Timeweb');
    final response = await _api.archive(
      listingId,
      status: status.trim().isEmpty ? 'archived' : status.trim(),
      note: note,
    );
    final updated = _extractListingFromResponse(response);
    if (updated != null) {
      _upsertListingInCaches(updated);
      _emitRefresh(clearCaches: false);
    } else {
      _emitRefresh();
    }
    unawaited(_refreshListingFromBackend(listingId));
    return updated;
  }

  Future<void> incrementView(String listingId) async {
    _debugSource('Listings source: Timeweb');
    final currentUser = await _tokenStorage.readCurrentUser();
    await _api.incrementView(
      listingId,
      viewerUserId: currentUser?.uid,
    );
    _emitRefresh();
  }

  Future<Listing?> getListingById(String id) async {
    _debugSource('Listings source: Timeweb');
    final cached = _listingById[id];
    if (cached != null) {
      return cached;
    }
    final response = await _api.getById(id);
    final listing = _extractListingFromResponse(response);
    if (listing != null) {
      _upsertListingInCaches(listing);
    }
    return listing;
  }

  Listing? peekListingById(String id) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return null;
    return _listingById[normalizedId];
  }

  void cacheListings(Iterable<Listing> items) {
    _cacheListings(items.toList(growable: false));
  }

  Future<Listing?> refreshListingById(String listingId) async {
    final id = listingId.trim();
    if (id.isEmpty) return null;
    try {
      final response = await _api.getById(id);
      final listing = _extractListingFromResponse(response);
      if (listing == null) return null;
      _upsertListingInCaches(listing);
      _emitRefresh(clearCaches: false);
      return listing;
    } catch (_) {
      return null;
    }
  }

  Future<Listing?> updateListing({
    required String listingId,
    required String title,
    required String description,
    required int price,
    required String phone,
    required bool phoneHidden,
    required String city,
    required Map<String, bool> delivery,
    String? category,
    String? subcategory,
    CarSpecs? car,
    String? dealType,
    String? clothesType,
    String? clothesSize,
    String? oemPartNumber,
  }) async {
    _debugSource('Listings source: Timeweb');
    final response = await _api.update(
      listingId,
      {
        'title': title,
        'description': description,
        if (category != null && category.trim().isNotEmpty)
          'category': category.trim(),
        if (subcategory != null && subcategory.trim().isNotEmpty)
          'subcategory': subcategory.trim(),
        'price': price,
        'phone': phone,
        'phone_hidden': phoneHidden,
        'city': city,
        'address': city,
        'delivery': delivery,
        if (car != null) 'car': car.toMap(),
        if (dealType != null && dealType.trim().isNotEmpty)
          'deal_type': dealType.trim(),
        if (clothesType != null && clothesType.trim().isNotEmpty)
          'clothes_type': clothesType.trim(),
        if (category == 'Одежда' &&
            clothesSize != null &&
            clothesSize.trim().isNotEmpty)
          'clothes_size': clothesSize.trim(),
        if (category == 'Запчасти' && oemPartNumber != null)
          'oem_part_number': oemPartNumber.trim(),
      },
    );
    final updated = _extractListingFromResponse(response);
    if (updated != null) {
      _upsertListingInCaches(updated);
      _emitRefresh(clearCaches: false);
      unawaited(_refreshListingFromBackend(listingId));
    } else {
      _emitRefresh();
    }
    return updated;
  }

  Future<Listing> uploadListingPhoto({
    required String listingId,
    required File file,
    int? sortOrder,
    PreparedImage? preparedImage,
  }) async {
    return (await uploadListingPhotoItem(
      listingId: listingId,
      file: file,
      sortOrder: sortOrder,
      preparedImage: preparedImage,
    ))
        .listing;
  }

  Future<ListingPhotoUploadResponse> uploadListingPhotoItem({
    required String listingId,
    required File file,
    int? sortOrder,
    PreparedImage? preparedImage,
  }) async {
    if (ApiConfig.useTimewebBackend) {
      final prepared = preparedImage ??
          await _imagePreparationService.prepareListingImage(file);
      final response = await _mediaApi.uploadListingPhoto(
        listingId: listingId,
        bytes: prepared.bytes,
        fileName: prepared.fileName,
        contentType: prepared.contentType,
        sortOrder: sortOrder,
      );
      if (kDebugMode) {
        final photo = response['photo'];
        final rawImageUrl =
            (photo is Map ? (photo['url'] ?? photo['public_url'] ?? '') : '')
                .toString()
                .trim();
        final resolution = resolveMediaUrl(
          rawImageUrl,
          categoryHint: 'listings',
        );
        debugPrint(
          'Listing upload response imageUrl=$rawImageUrl resolved=${resolution.resolvedUrl} category=listing provider=${resolution.provider}',
        );
      }
      final raw = response['listing'];
      if (raw is! Map) {
        throw Exception('Не удалось обновить фото объявления');
      }
      final photoRaw = response['photo'];
      final photoId =
          (photoRaw is Map ? (photoRaw['id'] ?? '') : '').toString().trim();
      final listing = Listing.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      _upsertListingInCaches(listing);
      _emitRefresh(clearCaches: false);
      return ListingPhotoUploadResponse(listing: listing, photoId: photoId);
    }

    throw UnimplementedError('Legacy listing photo upload is not handled here');
  }

  Future<ListingPhotoUploadResult> uploadListingPhotos({
    required String listingId,
    required List<File> photos,
    int startIndex = 0,
    List<int>? sortOrders,
    ListingPhotoUploadStatusCallback? onStatusChanged,
  }) async {
    Listing? latestListing;
    var uploadedCount = 0;
    final failures = <ListingPhotoUploadFailure>[];

    for (var i = 0; i < photos.length; i++) {
      final file = photos[i];
      final targetSortOrder = sortOrders != null && i < sortOrders.length
          ? sortOrders[i]
          : startIndex + i;
      onStatusChanged?.call(
        ListingPhotoUploadStatus(
          file: file,
          index: targetSortOrder,
          state: 'preparing',
          message: 'Сжимаем фото...',
          listingId: listingId,
        ),
      );
      try {
        final prepared =
            await _imagePreparationService.prepareListingImage(file);
        onStatusChanged?.call(
          ListingPhotoUploadStatus(
            file: file,
            index: targetSortOrder,
            state: 'uploading',
            message: 'Загружаем...',
            listingId: listingId,
          ),
        );
        latestListing = await uploadListingPhoto(
          listingId: listingId,
          file: file,
          sortOrder: targetSortOrder,
          preparedImage: prepared,
        );
        uploadedCount += 1;
        onStatusChanged?.call(
          ListingPhotoUploadStatus(
            file: file,
            index: targetSortOrder,
            state: 'uploaded',
            message: 'Загружено',
            listingId: listingId,
          ),
        );
      } catch (error) {
        final message = _friendlyPhotoUploadError(error);
        failures.add(
          ListingPhotoUploadFailure(
            file: file,
            index: targetSortOrder,
            message: message,
          ),
        );
        onStatusChanged?.call(
          ListingPhotoUploadStatus(
            file: file,
            index: targetSortOrder,
            state: 'failed',
            message: message,
            listingId: listingId,
          ),
        );
        _logPhotoUploadError(
          listingId: listingId,
          index: targetSortOrder,
          error: error,
        );
      }
    }

    latestListing ??=
        listingId.isEmpty ? null : await getListingById(listingId);
    return ListingPhotoUploadResult(
      requestedCount: photos.length,
      uploadedCount: uploadedCount,
      failures: failures,
      listing: latestListing,
    );
  }

  String _friendlyPhotoUploadError(Object error) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
    final text = error.toString().toLowerCase();
    if (text.contains('413') || text.contains('too large')) {
      return 'Фото слишком большое. Попробуйте другое фото.';
    }
    return 'Не удалось загрузить фото. Попробуйте ещё раз.';
  }

  Future<Listing> deleteListingPhoto({
    required String listingId,
    required String photoId,
  }) async {
    if (ApiConfig.useTimewebBackend) {
      final response = await _mediaApi.deleteListingPhoto(
        listingId: listingId,
        photoId: photoId,
      );
      final raw = response['listing'];
      if (raw is! Map) {
        throw Exception('Не удалось удалить фото объявления');
      }
      final listing = Listing.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      _upsertListingInCaches(listing);
      _emitRefresh(clearCaches: false);
      return listing;
    }

    throw UnimplementedError('Legacy listing photo delete is not handled here');
  }

  bool _matchesFilters(Listing listing, ListingFeedFilters filters) {
    if (listing.status != 'approved') return false;

    if (!_isAllCategory(filters.category) &&
        listing.category != filters.category) {
      return false;
    }

    final subcategory = filters.subcategory.trim();
    if (subcategory.isNotEmpty &&
        subcategory != 'Все' &&
        listing.subcategory != subcategory) {
      return false;
    }

    if (!_matchesSearch(listing, filters.search)) return false;
    if (!_matchesPriceFilters(listing, filters)) return false;
    if (!_matchesAutoFilters(listing, filters)) return false;
    if (!_matchesLocationFilter(listing, filters)) return false;

    return true;
  }

  bool _matchesSearch(Listing listing, String search) {
    final tokens = _tokenize(search);
    if (tokens.isEmpty) return true;

    final haystack = _buildSearchHaystack(listing);
    return tokens.every(haystack.contains);
  }

  bool _matchesAutoFilters(Listing listing, ListingFeedFilters filters) {
    final car = listing.car;
    final hasAutoSpecFilters = filters.autoBrand.trim().isNotEmpty ||
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
        filters.onlyUncrashed;

    if (filters.onlyWithPhoto &&
        listing.photoUrls.isEmpty &&
        listing.photoItems.isEmpty) {
      return false;
    }

    if (!hasAutoSpecFilters) return true;
    if (car == null) return false;

    if (filters.autoBrand.trim().isNotEmpty &&
        !_containsNormalized(car.brand, filters.autoBrand)) {
      return false;
    }

    if (filters.autoModel.trim().isNotEmpty &&
        !_containsNormalized(car.model, filters.autoModel)) {
      return false;
    }

    if (filters.autoCondition.trim().isNotEmpty &&
        !_containsNormalized(car.condition ?? '', filters.autoCondition)) {
      return false;
    }

    if (filters.autoYearFrom != null &&
        (car.year == null || car.year! < filters.autoYearFrom!)) {
      return false;
    }

    if (filters.autoYearTo != null &&
        (car.year == null || car.year! > filters.autoYearTo!)) {
      return false;
    }

    if (filters.autoMileageFrom != null &&
        (car.mileageKm == null || car.mileageKm! < filters.autoMileageFrom!)) {
      return false;
    }

    if (filters.autoMileageTo != null &&
        (car.mileageKm == null || car.mileageKm! > filters.autoMileageTo!)) {
      return false;
    }

    if (filters.autoTransmission.trim().isNotEmpty &&
        !_containsNormalized(
            car.transmission ?? '', filters.autoTransmission)) {
      return false;
    }

    if (filters.autoDrive.trim().isNotEmpty &&
        !_containsNormalized(car.drive ?? '', filters.autoDrive)) {
      return false;
    }

    if (filters.autoBodyType.trim().isNotEmpty &&
        !_containsNormalized(car.bodyType ?? '', filters.autoBodyType)) {
      return false;
    }

    if (filters.autoFuel.trim().isNotEmpty &&
        !_containsNormalized(car.fuel ?? '', filters.autoFuel)) {
      return false;
    }

    if (filters.autoColor.trim().isNotEmpty &&
        !_containsNormalized(car.color ?? '', filters.autoColor)) {
      return false;
    }

    if (filters.autoEngineVolumeFrom != null &&
        (car.engineVolume == null ||
            car.engineVolume! < filters.autoEngineVolumeFrom!)) {
      return false;
    }

    if (filters.autoEngineVolumeTo != null &&
        (car.engineVolume == null ||
            car.engineVolume! > filters.autoEngineVolumeTo!)) {
      return false;
    }

    if (filters.autoOwners != null &&
        (car.owners == null || car.owners! != filters.autoOwners!)) {
      return false;
    }

    if (filters.autoCleared != null && car.isCleared != filters.autoCleared) {
      return false;
    }

    if (filters.onlyUncrashed && !_looksUncrashed(listing)) {
      return false;
    }

    return true;
  }

  bool _matchesLocationFilter(Listing listing, ListingFeedFilters filters) {
    final locationQuery = filters.location.trim();
    if (locationQuery.isEmpty) return true;

    if (filters.radiusKm == null) return true;

    return _matchesLocationText(listing, locationQuery);
  }

  int _compareSimilarListings(Listing a, Listing b, Listing base) {
    final diff = _similarityScore(b, base) - _similarityScore(a, base);
    if (diff != 0) return diff;
    return _compareFeedListings(a, b);
  }

  int _compareFeedListings(Listing a, Listing b) {
    final aPublished = a.publishedAt;
    final bPublished = b.publishedAt;
    if (aPublished != null || bPublished != null) {
      if (aPublished == null) return 1;
      if (bPublished == null) return -1;
      final publishedDiff = bPublished.compareTo(aPublished);
      if (publishedDiff != 0) return publishedDiff;
    }

    final createdDiff = b.createdAt.compareTo(a.createdAt);
    if (createdDiff != 0) return createdDiff;
    return b.id.compareTo(a.id);
  }

  int _similarityScore(Listing candidate, Listing base) {
    var score = 0;

    if (candidate.category == base.category) {
      score += 150;
    }
    if (candidate.subcategory.trim().isNotEmpty &&
        candidate.subcategory == base.subcategory) {
      score += 90;
    }
    if (_normalizeText(candidate.cityShort) == _normalizeText(base.cityShort)) {
      score += 55;
    } else if (_matchesLocationText(candidate, base.cityFull)) {
      score += 30;
    }

    final basePrice = base.price <= 0 ? 0 : base.price;
    if (basePrice > 0 && candidate.price > 0) {
      final ratio = (candidate.price - basePrice).abs() / basePrice;
      if (ratio <= 0.10) {
        score += 60;
      } else if (ratio <= 0.25) {
        score += 42;
      } else if (ratio <= 0.50) {
        score += 24;
      }
    }

    final baseTitleTokens = _tokenize(base.title).toSet();
    final candidateTitleTokens = _tokenize(candidate.title).toSet();
    score += baseTitleTokens.intersection(candidateTitleTokens).length * 6;

    if (candidate.ownerId == base.ownerId) {
      score -= 20;
    }

    return score;
  }

  String _buildSearchHaystack(Listing listing) {
    final values = <String>[
      listing.title,
      listing.description,
      listing.category,
      listing.subcategory,
      listing.city,
      listing.cityShort,
      listing.cityFull,
      listing.ownerName,
      listing.car?.brand ?? '',
      listing.car?.model ?? '',
      listing.car?.generation ?? '',
      listing.car?.bodyType ?? '',
      listing.car?.fuel ?? '',
      listing.car?.transmission ?? '',
      listing.car?.drive ?? '',
      listing.car?.condition ?? '',
      listing.car?.color ?? '',
      listing.car?.note ?? '',
    ];

    return _normalizeText(values.join(' '));
  }

  bool _looksUncrashed(Listing listing) {
    final carCond = _normalizeText(listing.car?.condition ?? '');
    final text = _normalizeText('${listing.title} ${listing.description}');
    final source = '$carCond $text';

    final positive = source.contains('не бит') ||
        source.contains('без дтп') ||
        source.contains('не крашен') ||
        source.contains('родной окрас');
    final negative = source.contains('бит') ||
        source.contains('дтп') ||
        source.contains('крашен') ||
        source.contains('после авар');
    return positive && !negative;
  }

  bool _matchesLocationText(Listing listing, String query) {
    final q = _normalizeText(query);
    if (q.isEmpty) return false;

    final candidates = <String>[
      listing.city,
      listing.cityShort,
      listing.cityFull,
      listing.location.region,
      listing.location.district,
      listing.location.locality,
      listing.location.subLocality,
      listing.location.raw,
    ].map(_normalizeText).where((e) => e.isNotEmpty).toList();

    for (final candidate in candidates) {
      if (candidate == q || candidate.contains(q) || q.contains(candidate)) {
        return true;
      }
    }

    return false;
  }

  bool _containsNormalized(String source, String query) {
    final normalizedSource = _normalizeText(source);
    final normalizedQuery = _normalizeText(query);
    if (normalizedQuery.isEmpty) return true;
    return normalizedSource.contains(normalizedQuery);
  }

  List<String> _tokenize(String text) {
    return _normalizeText(text)
        .split(' ')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool _isAllCategory(String category) {
    final value = category.trim();
    return value.isEmpty || value == 'Все';
  }

  String _normalizeText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _matchesPriceFilters(Listing listing, ListingFeedFilters filters) {
    if (filters.priceFrom != null && listing.price < filters.priceFrom!) {
      return false;
    }
    if (filters.priceTo != null && listing.price > filters.priceTo!) {
      return false;
    }
    return true;
  }

  String _filtersCacheKey(ListingFeedFilters filters) {
    return [
      filters.category,
      filters.search,
      filters.subcategory,
      filters.priceFrom ?? '',
      filters.priceTo ?? '',
      filters.location,
      filters.preferLocationFirst,
      filters.radiusKm,
      filters.autoBrand,
      filters.autoModel,
      filters.autoCondition,
      filters.autoYearFrom ?? '',
      filters.autoYearTo ?? '',
      filters.autoMileageFrom ?? '',
      filters.autoMileageTo ?? '',
      filters.autoTransmission,
      filters.autoDrive,
      filters.autoBodyType,
      filters.autoFuel,
      filters.autoColor,
      filters.autoEngineVolumeFrom ?? '',
      filters.autoEngineVolumeTo ?? '',
      filters.autoOwners ?? '',
      filters.autoCleared ?? '',
      filters.onlyUncrashed,
      filters.onlyWithPhoto,
    ].join('|');
  }

  Future<List<Listing>> _fetchListings(ListingFeedFilters filters) async {
    final key = _filtersCacheKey(filters);
    final cached = _timewebCache[key];
    final cachedAt = _timewebCachedAt[key];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return List<Listing>.from(cached);
    }
    final existing = _timewebInFlight[key];
    if (existing != null) return existing;
    final future = () async {
      final aggregated = <Listing>[];
      final seenIds = <String>{};
      String? nextCursor;
      var hasMore = true;

      while (hasMore) {
        final page = await getListingsPage(
          category: filters.category,
          search: filters.search,
          filters: filters,
          limit: 50,
          cursor: nextCursor,
        );
        for (final item in page.items) {
          if (seenIds.add(item.id)) {
            aggregated.add(item);
          }
        }
        hasMore = page.hasMore;
        nextCursor = page.nextCursor;
        if (!hasMore || (nextCursor ?? '').isEmpty) {
          break;
        }
      }

      final filtered = List<Listing>.from(aggregated);
      _timewebCache[key] = filtered;
      _timewebCachedAt[key] = DateTime.now();
      return filtered;
    }();
    _timewebInFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_timewebInFlight[key], future)) {
        _timewebInFlight.remove(key);
      }
    }
  }

  Future<List<Listing>> _fetchMyListings(
    String requestedUserId, {
    Set<String>? statuses,
    bool forceRefresh = false,
  }) async {
    final uid = requestedUserId.trim();
    if (uid.isEmpty) {
      _debugPrivateTab('MyListings load skipped reason=no_user');
      return const <Listing>[];
    }
    if (_myListingsCacheUserId != null && _myListingsCacheUserId != uid) {
      _clearMyListingsCache();
    }
    final cached = _myListingsCache;
    if (!forceRefresh &&
        cached != null &&
        _myListingsCachedAt != null &&
        DateTime.now().difference(_myListingsCachedAt!) < _cacheTtl) {
      return List<Listing>.from(cached);
    }
    final existing = _myListingsInFlight;
    if (existing != null && _myListingsInFlightUserId == uid) {
      _debugPrivateTab('MyListings load skipped reason=in_flight user=$uid');
      return existing;
    }
    final future = () async {
      _debugPrivateTab('MyListings load start user=$uid');
      try {
        // ApiClient owns the transport timeout and starts it only after
        // auth-gate recovery and the actual HTTP send.
        final statusList = (statuses == null || statuses.isEmpty)
            ? const <String?>[null]
            : statuses.toList(growable: false);
        final collected = <Listing>[];
        for (final status in statusList) {
          String? cursor;
          var hasMore = true;
          while (hasMore) {
            final response = await _api.myListings(
              status: status,
              limit: 50,
              cursor: cursor,
            );
            collected.addAll(_extractItems(response));
            cursor = (response['nextCursor'] ?? response['next_cursor'])
                ?.toString()
                .trim();
            if ((cursor ?? '').isEmpty) cursor = null;
            hasMore = response['hasMore'] == true && cursor != null;
          }
        }
        final items = _sanitizeMyListings(
          collected,
          currentUserId: uid,
        );
        _cacheListings(items);
        final latestUser = requestedUserId.trim();
        if (latestUser == uid) {
          _myListingsCache = List<Listing>.from(items);
          _myListingsCachedAt = DateTime.now();
          _myListingsCacheUserId = uid;
        }
        _lastMyListingsError = null;
        _lastMyListingsErrorUserId = uid;
        _debugPrivateTab(
          items.isEmpty
              ? 'MyListings load empty'
              : 'MyListings load success count=${items.length}',
        );
        return items;
      } catch (error) {
        _lastMyListingsError = error;
        _lastMyListingsErrorUserId = uid;
        _debugPrivateTab('MyListings load error message=$error user=$uid');
        return List<Listing>.from(_myListingsCache ?? const <Listing>[]);
      } finally {
        _debugPrivateTab('MyListings load finally loading=false user=$uid');
      }
    }();
    _myListingsInFlight = future;
    _myListingsInFlightUserId = uid;
    try {
      return await future;
    } finally {
      if (identical(_myListingsInFlight, future)) {
        _myListingsInFlight = null;
        _myListingsInFlightUserId = null;
        _debugPrivateTab('MyListings inFlight cleared user=$uid');
      }
    }
  }

  Future<List<Listing>> _fetchListingsByOwner(
    String ownerId, {
    bool forceRefresh = false,
  }) async {
    final id = ownerId.trim();
    if (id.isEmpty) return const <Listing>[];
    final cached = _ownerListingsCache[id];
    final cachedAt = _ownerListingsCachedAt[id];
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return List<Listing>.from(cached);
    }
    final existing = _ownerListingsInFlight[id];
    if (existing != null) return existing;
    final future = () async {
      final response = await _api.list(
        queryParameters: {
          'ownerId': id,
        },
      );
      final items = _dedupeAndSortListings(_extractItems(response));
      _cacheListings(items);
      _ownerListingsCache[id] = List<Listing>.from(items);
      _ownerListingsCachedAt[id] = DateTime.now();
      return items;
    }();
    _ownerListingsInFlight[id] = future;
    try {
      return await future;
    } finally {
      if (identical(_ownerListingsInFlight[id], future)) {
        _ownerListingsInFlight.remove(id);
      }
    }
  }

  List<Listing> _dedupeAndSortListings(List<Listing> items) {
    final byId = <String, Listing>{};
    for (final item in items) {
      byId[item.id] = item;
    }
    final unique = byId.values.toList()..sort(_compareFeedListings);
    return unique;
  }

  List<Listing> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <Listing>[];
    return raw
        .whereType<Map>()
        .map(
          (item) => Listing.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  String? _extractNextCursor(Map<String, dynamic> response) {
    final cursor =
        (response['nextCursor'] ?? response['next_cursor'])?.toString().trim();
    return (cursor ?? '').isEmpty ? null : cursor;
  }

  void _emitRefresh({bool clearCaches = true}) {
    if (clearCaches) {
      _clearCachedCollections();
    }
    if (!_refreshController.isClosed) {
      _refreshController.add(null);
    }
  }

  void _clearCachedCollections() {
    _timewebCache.clear();
    _timewebCachedAt.clear();
    _timewebInFlight.clear();
    _feedPageInFlight.clear();
    _clearMyListingsCache();
    _ownerListingsCache.clear();
    _ownerListingsCachedAt.clear();
    _ownerListingsInFlight.clear();
  }

  void _clearMyListingsCache() {
    _myListingsCache = null;
    _myListingsCachedAt = null;
    _myListingsCacheUserId = null;
    _myListingsInFlight = null;
    _myListingsInFlightUserId = null;
    _lastMyListingsError = null;
    _lastMyListingsErrorUserId = null;
  }

  void _cacheListings(List<Listing> items) {
    for (final listing in items) {
      _listingById[listing.id] = listing;
    }
  }

  void _syncMyListingsPageCache(
    String uid, {
    required Set<String> statuses,
    required List<Listing> items,
    required bool reset,
  }) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty || statuses.isEmpty) return;
    if (_myListingsCacheUserId != null &&
        _myListingsCacheUserId != normalizedUid) {
      _clearMyListingsCache();
    }

    final existing = _myListingsCache ?? const <Listing>[];
    final next = <Listing>[];
    final seen = <String>{};
    for (final item in existing) {
      if (reset && statuses.contains(item.status)) continue;
      if (seen.add(item.id)) next.add(item);
    }
    for (final item in items) {
      if (item.ownerId.trim() != normalizedUid) continue;
      if (!statuses.contains(item.status)) continue;
      final currentIndex = next.indexWhere((cached) => cached.id == item.id);
      if (currentIndex >= 0) {
        next[currentIndex] = item;
      } else if (seen.add(item.id)) {
        next.add(item);
      }
    }
    _myListingsCache = _dedupeAndSortListings(next);
    _myListingsCachedAt = DateTime.now();
    _myListingsCacheUserId = normalizedUid;
  }

  Listing? _extractListingFromResponse(Map<String, dynamic> response) {
    final raw = response['listing'];
    if (raw is! Map) return null;
    return Listing.fromMap(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  void _upsertListingInCaches(Listing listing) {
    _listingById[listing.id] = listing;
    _replaceListingInCollectionCaches(listing);
  }

  void refreshFeedAfterPromotion({Listing? listing}) {
    if (listing != null) {
      _upsertListingInCaches(listing);
    }
    _timewebCache.clear();
    _timewebCachedAt.clear();
    _timewebInFlight.clear();
    _feedPageInFlight.clear();
    if (!_refreshController.isClosed) {
      _refreshController.add(null);
    }
    if (listing != null) {
      unawaited(_refreshListingFromBackend(listing.id));
    }
  }

  void _replaceListingInCollectionCaches(Listing listing) {
    if (_myListingsCache != null) {
      final currentUserId = _myListingsCacheUserId?.trim() ?? '';
      final includeInMyListings =
          currentUserId.isNotEmpty && listing.ownerId.trim() == currentUserId;
      _myListingsCache = _replaceListingInFeed(
        _myListingsCache!,
        listing,
        includeListing: includeInMyListings,
      );
      _myListingsCachedAt = DateTime.now();
    }

    final ownerCache = _ownerListingsCache[listing.ownerId];
    if (ownerCache != null) {
      _ownerListingsCache[listing.ownerId] =
          _replaceListingInCollection(ownerCache, listing);
      _ownerListingsCachedAt[listing.ownerId] = DateTime.now();
    }

    for (final entry in _timewebCache.entries.toList()) {
      final filters = _filtersFromKey(entry.key);
      final shouldBeVisible =
          filters != null && _matchesFilters(listing, filters);
      _timewebCache[entry.key] = _replaceListingInFeed(
        entry.value,
        listing,
        includeListing: shouldBeVisible,
      );
      _timewebCachedAt[entry.key] = DateTime.now();
    }
  }

  List<Listing> _replaceListingInCollection(
    List<Listing> source,
    Listing listing,
  ) {
    final next = source.where((item) => item.id != listing.id).toList();
    next.add(listing);
    next.sort(_compareFeedListings);
    return next;
  }

  List<Listing> _replaceListingInFeed(
    List<Listing> source,
    Listing listing, {
    required bool includeListing,
  }) {
    final currentIndex = source.indexWhere((item) => item.id == listing.id);
    if (!includeListing) {
      if (currentIndex < 0) {
        return List<Listing>.from(source);
      }
      return source.where((item) => item.id != listing.id).toList();
    }

    if (currentIndex < 0) {
      return <Listing>[listing, ...source];
    }

    final next = List<Listing>.from(source);
    next[currentIndex] = listing;
    return next;
  }

  ListingFeedFilters? _filtersFromKey(String key) {
    final parts = key.split('|');
    if (parts.length == 11) {
      return ListingFeedFilters(
        category: parts[0],
        search: parts[1],
        subcategory: parts[2],
        location: parts[3],
        preferLocationFirst: parts[4] == 'true',
        radiusKm: int.tryParse(parts[5]),
        autoBrand: parts[6],
        autoModel: parts[7],
        autoCondition: parts[8],
        autoMileageTo: int.tryParse(parts[9]),
        onlyUncrashed: parts[10] == 'true',
      );
    }
    if (parts.length != 26) return null;
    return ListingFeedFilters(
      category: parts[0],
      search: parts[1],
      subcategory: parts[2],
      priceFrom: int.tryParse(parts[3]),
      priceTo: int.tryParse(parts[4]),
      location: parts[5],
      preferLocationFirst: parts[6] == 'true',
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
      onlyUncrashed: parts[24] == 'true',
      onlyWithPhoto: parts[25] == 'true',
    );
  }

  List<Listing> _sanitizeMyListings(
    List<Listing> items, {
    required String currentUserId,
  }) {
    final normalizedUserId = currentUserId.trim();
    if (normalizedUserId.isEmpty) {
      return const <Listing>[];
    }
    final filtered =
        items.where((item) => item.ownerId.trim() == normalizedUserId).toList();
    return _dedupeAndSortListings(filtered);
  }

  _MyListingsCursor _decodeMyListingsCursor(String? cursor) {
    final value = cursor?.trim() ?? '';
    if (value.isEmpty) return const _MyListingsCursor(statusIndex: 0);
    try {
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(value)));
      final raw = jsonDecode(decoded);
      if (raw is! Map) return const _MyListingsCursor(statusIndex: 0);
      final statusIndex = raw['statusIndex'];
      final pageCursor = raw['cursor']?.toString().trim();
      return _MyListingsCursor(
        statusIndex: statusIndex is num ? statusIndex.toInt() : 0,
        cursor: (pageCursor ?? '').isEmpty ? null : pageCursor,
      );
    } catch (_) {
      return _MyListingsCursor(statusIndex: 0, cursor: value);
    }
  }

  String _encodeMyListingsCursor(int statusIndex, String? cursor) {
    return base64UrlEncode(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'statusIndex': statusIndex,
          if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
        }),
      ),
    );
  }

  Future<void> _refreshListingFromBackend(String listingId) async {
    final id = listingId.trim();
    if (id.isEmpty) return;
    try {
      final response = await _api.getById(id);
      final listing = _extractListingFromResponse(response);
      if (listing == null) return;
      _upsertListingInCaches(listing);
      _emitRefresh(clearCaches: false);
    } catch (_) {
      // Keep immediate local state even if background sync failed.
    }
  }

  void _debugSource(String message) {
    debugPrint(message);
  }

  void resetSession() {
    _listingById.clear();
    _feedPageInFlight.clear();
    _clearCachedCollections();
  }

  void _debugPrivateTab(String message) {
    assert(() {
      debugPrint(message);
      return true;
    }());
  }

  void _debugCreateListingStart({
    required String ownerId,
    required String title,
    required int photoCount,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      'Listing create start ownerId=$ownerId photoCount=$photoCount titleLen=${title.trim().length}',
    );
  }

  void _logPhotoUploadError({
    required String listingId,
    required int index,
    required Object error,
  }) {
    if (error is ApiException) {
      debugPrint(
        'Listing photo upload failed listing=$listingId index=$index '
        'status=${error.statusCode} details=${error.details}',
      );
      return;
    }
    debugPrint(
      'Listing photo upload failed listing=$listingId index=$index error=$error',
    );
  }
}

class _MyListingsCursor {
  const _MyListingsCursor({
    required this.statusIndex,
    this.cursor,
  });

  final int statusIndex;
  final String? cursor;
}
