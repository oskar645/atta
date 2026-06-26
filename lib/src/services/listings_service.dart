// lib/src/services/listings_service.dart
import 'dart:async';
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
  final String location;
  final bool preferLocationFirst;
  final int? radiusKm;
  final String autoBrand;
  final String autoModel;
  final String autoCondition;
  final int? autoMileageTo;
  final bool onlyUncrashed;
  const ListingFeedFilters({
    required this.category,
    required this.search,
    this.subcategory = 'Все',
    this.location = '',
    this.preferLocationFirst = false,
    this.radiusKm,
    this.autoBrand = '',
    this.autoModel = '',
    this.autoCondition = '',
    this.autoMileageTo,
    this.onlyUncrashed = false,
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
  final Map<String, List<Listing>> _ownerListingsCache =
      <String, List<Listing>>{};
  final Map<String, DateTime> _ownerListingsCachedAt = <String, DateTime>{};
  final Map<String, Future<List<Listing>>> _ownerListingsInFlight =
      <String, Future<List<Listing>>>{};

  static const Duration _cacheTtl = Duration(seconds: 20);

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
    yield await _fetchMyListings();
    await for (final _ in _refreshController.stream) {
      yield await _fetchMyListings();
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
    final key = [
      effectiveFilters.category,
      effectiveFilters.search,
      effectiveFilters.subcategory,
      effectiveFilters.location,
      effectiveFilters.preferLocationFirst,
      effectiveFilters.radiusKm,
      effectiveFilters.autoBrand,
      effectiveFilters.autoModel,
      effectiveFilters.autoCondition,
      effectiveFilters.autoMileageTo,
      effectiveFilters.onlyUncrashed,
    ].join('|');
    return List<Listing>.from(_timewebCache[key] ?? const <Listing>[]);
  }

  Future<List<Listing>> getMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
  }) async {
    _debugSource('Listings source: Timeweb');
    final items = await _fetchMyListings();
    return items.where((item) => statuses.contains(item.status)).toList();
  }

  List<Listing> peekMyListingsByStatuses({
    required Set<String> statuses,
  }) {
    final items = List<Listing>.from(_myListingsCache ?? const <Listing>[]);
    return items.where((item) => statuses.contains(item.status)).toList();
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
    String? realEstateType,
    String? clothesType,
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
      if (realEstateType != null && realEstateType.trim().isNotEmpty)
        'real_estate_type': realEstateType.trim(),
      if (clothesType != null && clothesType.trim().isNotEmpty)
        'clothes_type': clothesType.trim(),
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

  Future<Listing?> updateListing({
    required String listingId,
    required String title,
    required String description,
    required int price,
    required String phone,
    required bool phoneHidden,
    required String city,
    required Map<String, bool> delivery,
    CarSpecs? car,
  }) async {
    _debugSource('Listings source: Timeweb');
    final response = await _api.update(
      listingId,
      {
        'title': title,
        'description': description,
        'price': price,
        'phone': phone,
        'phone_hidden': phoneHidden,
        'city': city,
        'address': city,
        'delivery': delivery,
        if (car != null) 'car': car.toMap(),
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
  }) async {
    if (ApiConfig.useTimewebBackend) {
      final prepared = await _imagePreparationService.prepareListingImage(file);
      final response = await _mediaApi.uploadListingPhoto(
        listingId: listingId,
        bytes: prepared.bytes,
        fileName: 'listing.jpg',
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
      final listing = Listing.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      _upsertListingInCaches(listing);
      _emitRefresh(clearCaches: false);
      return listing;
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
          state: 'uploading',
          listingId: listingId,
        ),
      );
      try {
        latestListing = await uploadListingPhoto(
          listingId: listingId,
          file: file,
          sortOrder: targetSortOrder,
        );
        uploadedCount += 1;
        onStatusChanged?.call(
          ListingPhotoUploadStatus(
            file: file,
            index: targetSortOrder,
            state: 'uploaded',
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
      return 'Файл слишком большой. Выберите фото меньшего размера.';
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
    final hasAutoFilters = filters.autoBrand.trim().isNotEmpty ||
        filters.autoModel.trim().isNotEmpty ||
        filters.autoCondition.trim().isNotEmpty ||
        filters.autoMileageTo != null ||
        filters.onlyUncrashed;

    if (!hasAutoFilters) return true;
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
        !_containsNormalized(car.condition, filters.autoCondition)) {
      return false;
    }

    if (filters.autoMileageTo != null &&
        car.mileageKm > filters.autoMileageTo!) {
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

  Future<List<Listing>> _fetchListings(ListingFeedFilters filters) async {
    final key = [
      filters.category,
      filters.search,
      filters.subcategory,
      filters.location,
      filters.preferLocationFirst,
      filters.radiusKm,
      filters.autoBrand,
      filters.autoModel,
      filters.autoCondition,
      filters.autoMileageTo,
      filters.onlyUncrashed,
    ].join('|');
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
      final response = await _api.list(
        queryParameters: {
          if (!_isAllCategory(filters.category)) 'category': filters.category,
          if (filters.search.trim().isNotEmpty) 'search': filters.search.trim(),
          if (filters.location.trim().isNotEmpty)
            'city': filters.location.trim(),
        },
      );
      final items = _extractItems(response);
      final filtered =
          items.where((item) => _matchesFilters(item, filters)).toList();
      filtered.sort(_compareFeedListings);
      _cacheListings(items);
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

  Future<List<Listing>> _fetchMyListings() async {
    final cached = _myListingsCache;
    if (cached != null &&
        _myListingsCachedAt != null &&
        DateTime.now().difference(_myListingsCachedAt!) < _cacheTtl) {
      return List<Listing>.from(cached);
    }
    final existing = _myListingsInFlight;
    if (existing != null) return existing;
    final currentUser = await _tokenStorage.readCurrentUser();
    final uid = currentUser?.uid ?? '';
    if (uid.isEmpty) return const <Listing>[];
    final future = () async {
      final response = await _api.list(
        queryParameters: {
          'ownerId': uid,
        },
      );
      final items = _extractItems(response);
      _cacheListings(items);
      _myListingsCache = List<Listing>.from(items);
      _myListingsCachedAt = DateTime.now();
      return items;
    }();
    _myListingsInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_myListingsInFlight, future)) {
        _myListingsInFlight = null;
      }
    }
  }

  Future<List<Listing>> _fetchListingsByOwner(String ownerId) async {
    final cached = _ownerListingsCache[ownerId];
    final cachedAt = _ownerListingsCachedAt[ownerId];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return List<Listing>.from(cached);
    }
    final existing = _ownerListingsInFlight[ownerId];
    if (existing != null) return existing;
    final future = () async {
      final response = await _api.list(
        queryParameters: {
          'ownerId': ownerId,
        },
      );
      final items = _extractItems(response);
      _cacheListings(items);
      _ownerListingsCache[ownerId] = List<Listing>.from(items);
      _ownerListingsCachedAt[ownerId] = DateTime.now();
      return items;
    }();
    _ownerListingsInFlight[ownerId] = future;
    try {
      return await future;
    } finally {
      if (identical(_ownerListingsInFlight[ownerId], future)) {
        _ownerListingsInFlight.remove(ownerId);
      }
    }
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
    _myListingsCache = null;
    _myListingsCachedAt = null;
    _ownerListingsCache.clear();
    _ownerListingsCachedAt.clear();
  }

  void _cacheListings(List<Listing> items) {
    for (final listing in items) {
      _listingById[listing.id] = listing;
    }
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

  void _replaceListingInCollectionCaches(Listing listing) {
    if (_myListingsCache != null) {
      _myListingsCache =
          _replaceListingInCollection(_myListingsCache!, listing);
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
    final next = source.where((item) => item.id != listing.id).toList();
    if (includeListing) {
      next.add(listing);
      next.sort(_compareFeedListings);
    }
    return next;
  }

  ListingFeedFilters? _filtersFromKey(String key) {
    final parts = key.split('|');
    if (parts.length != 11) return null;
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
    _clearCachedCollections();
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
