// lib/src/services/listings_service.dart
import 'dart:io';

import 'package:chestore2/src/models/car_specs.dart';
import 'package:chestore2/src/models/listing.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

class ListingsService {
  final SupabaseClient _client = Supabase.instance.client;
  final _uuid = const Uuid();

  static const String _bucket = 'listing-photos';

  Stream<List<Listing>> streamListings({
    required String category,
    required String search,
    ListingFeedFilters? filters,
  }) {
    final effectiveFilters = filters ??
        ListingFeedFilters(
          category: category,
          search: search,
        );

    final stream = (_isAllCategory(effectiveFilters.category)
            ? _client.from('listings').stream(primaryKey: ['id'])
            : _client
                .from('listings')
                .stream(primaryKey: ['id'])
                .eq('category', effectiveFilters.category))
        .order('created_at', ascending: false);

    return stream.map((rows) {
      final items = rows.map((r) => Listing.fromMap(r)).toList();
      final filtered = items.where((x) => _matchesFilters(x, effectiveFilters)).toList();
      filtered.sort((a, b) => _compareListings(a, b, effectiveFilters));
      return filtered;
    });
  }

  Stream<List<Listing>> streamMyListings(String uid) {
    final stream = _client
        .from('listings')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return stream.map((rows) {
      final items = rows.map((r) => Listing.fromMap(r)).toList();
      return items.where((x) => x.ownerId == uid).toList();
    });
  }

  Stream<int> streamMyListingsCount(String uid) {
    return streamMyListings(uid).map((items) => items.length);
  }

  Stream<List<Listing>> streamListingsByOwner(String ownerId) {
    return streamListingsByOwnerAll(ownerId).map(
      (items) => items.where((x) => x.status == 'approved').toList(),
    );
  }

  Stream<List<Listing>> streamListingsByOwnerAll(String ownerId) {
    final stream = _client
        .from('listings')
        .stream(primaryKey: ['id'])
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false);

    return stream.map((rows) => rows.map((r) => Listing.fromMap(r)).toList());
  }

  Stream<List<Listing>> streamSimilarListings(
    Listing base, {
    int limit = 10,
  }) {
    final stream = _client
        .from('listings')
        .stream(primaryKey: ['id'])
        .eq('status', 'approved')
        .order('created_at', ascending: false);

    return stream.map((rows) {
      final items = rows
          .map((r) => Listing.fromMap(r))
          .where((x) => x.id != base.id)
          .where((x) => x.category == base.category)
          .toList();

      items.sort((a, b) => _compareSimilarListings(a, b, base));
      return items.take(limit).toList();
    });
  }

  Stream<List<Listing>> streamMyListingsByStatuses(
    String uid, {
    required Set<String> statuses,
  }) {
    return streamMyListings(uid).map(
      (items) => items.where((x) => statuses.contains(x.status)).toList(),
    );
  }

  Future<Listing?> getLatestApprovedListingByOwner(String ownerId) async {
    final row = await _client
        .from('listings')
        .select('*')
        .eq('owner_id', ownerId)
        .eq('status', 'approved')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    return Listing.fromMap(row);
  }

  Future<void> createListing({
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
  }) async {
    final listingId = _uuid.v4();

    final urls = <String>[];

    if (!kIsWeb) {
      for (var i = 0; i < photos.length; i++) {
        try {
          final file = photos[i];
          final ext = file.path.split('.').last.toLowerCase();

          final safeExt =
              (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp')
                  ? ext
                  : 'jpg';

          final path = '$listingId/$i.$safeExt';
          final bytes = await file.readAsBytes();

          final contentType = switch (safeExt) {
            'png' => 'image/png',
            'webp' => 'image/webp',
            _ => 'image/jpeg',
          };

          await _client.storage.from(_bucket).uploadBinary(
                path,
                bytes,
                fileOptions: FileOptions(
                  cacheControl: '3600',
                  upsert: false,
                  contentType: contentType,
                ),
              );

          final publicUrl = _client.storage.from(_bucket).getPublicUrl(path);

          debugPrint('PHOTO URL [$i]: $publicUrl');
          urls.add(publicUrl);
        } catch (e) {
          debugPrint('Ошибка загрузки фото $i: $e');
        }
      }
    } else {
      urls.add('https://via.placeholder.com/400');
    }

    final now = DateTime.now().toUtc();

    final data = <String, dynamic>{
      'id': listingId,
      'owner_id': ownerId,
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
      'delivery': delivery,
      'photo_urls': urls,
      'car': car?.toMap(),
      'deal_type': dealType,
      'real_estate_type': realEstateType,
      'clothes_type': clothesType,
      'view_count': 0,
      'status': 'pending',
      'rejection_reason': null,
      'created_at': now.toIso8601String(),
      'updated_at': null,
    };

    await _client.from('listings').insert(data);
  }

  Future<void> deleteListing({required Listing listing}) async {
    await archiveListing(
      listingId: listing.id,
      status: 'archived',
      note: 'Снято владельцем с публикации.',
    );
  }

  Future<void> archiveListing({
    required String listingId,
    required String status,
    String? note,
  }) async {
    final normalizedStatus = status.trim().isEmpty ? 'archived' : status.trim();
    final normalizedNote = (note ?? '').trim();
    await _client.from('listings').update({
      'status': normalizedStatus,
      'rejection_reason': normalizedNote.isEmpty ? null : normalizedNote,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', listingId);
  }

  Future<void> incrementView(String listingId) async {
    try {
      await _client.rpc('increment_listing_view', params: {'p_listing_id': listingId});
      return;
    } catch (_) {
      final row = await _client
          .from('listings')
          .select('view_count')
          .eq('id', listingId)
          .maybeSingle();

      var current = 0;
      if (row != null && row['view_count'] is num) {
        current = (row['view_count'] as num).toInt();
      }

      await _client.from('listings').update({'view_count': current + 1}).eq('id', listingId);
    }
  }

  Future<Listing?> getListingById(String id) async {
    final row = await _client.from('listings').select('*').eq('id', id).maybeSingle();
    if (row == null) return null;
    return Listing.fromMap(row);
  }

  Future<void> updateListing({
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
    final now = DateTime.now().toUtc().toIso8601String();

    final data = <String, dynamic>{
      'title': title,
      'description': description,
      'price': price,
      'phone': phone,
      'phone_hidden': phoneHidden,
      'city': city,
      'delivery': delivery,
      'car': car?.toMap(),
      'status': 'pending',
      'rejection_reason': null,
      'updated_at': now,
    };

    await _client.from('listings').update(data).eq('id', listingId);
  }

  bool _matchesFilters(Listing listing, ListingFeedFilters filters) {
    if (listing.status != 'approved') return false;

    if (!_isAllCategory(filters.category) && listing.category != filters.category) {
      return false;
    }

    final subcategory = filters.subcategory.trim();
    if (subcategory.isNotEmpty && subcategory != 'Все' && listing.subcategory != subcategory) {
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

    if (filters.autoMileageTo != null && car.mileageKm > filters.autoMileageTo!) {
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

  int _compareListings(Listing a, Listing b, ListingFeedFilters filters) {
    final diff = _scoreListing(b, filters) - _scoreListing(a, filters);
    if (diff != 0) return diff;
    return b.createdAt.compareTo(a.createdAt);
  }

  int _compareSimilarListings(Listing a, Listing b, Listing base) {
    final diff = _similarityScore(b, base) - _similarityScore(a, base);
    if (diff != 0) return diff;
    return b.createdAt.compareTo(a.createdAt);
  }

  int _scoreListing(Listing listing, ListingFeedFilters filters) {
    var score = 0;
    final search = _normalizeText(filters.search);
    final location = _normalizeText(filters.location);

    if (search.isNotEmpty) {
      final title = _normalizeText(listing.title);
      final description = _normalizeText(listing.description);
      final category = _normalizeText(listing.category);
      final subcategory = _normalizeText(listing.subcategory);
      final city = _normalizeText(listing.cityFull);
      final brand = _normalizeText(listing.car?.brand ?? '');
      final model = _normalizeText(listing.car?.model ?? '');

      if (title == search) score += 150;
      if (title.startsWith(search)) score += 120;
      if (title.contains(search)) score += 100;
      if (brand == search || model == search) score += 90;
      if (brand.contains(search) || model.contains(search)) score += 70;
      if (subcategory.contains(search)) score += 55;
      if (category.contains(search)) score += 40;
      if (city.contains(search)) score += 35;
      if (description.contains(search)) score += 15;

      for (final token in _tokenize(filters.search)) {
        if (title.contains(token)) score += 20;
        if (brand.contains(token) || model.contains(token)) score += 16;
        if (subcategory.contains(token)) score += 12;
        if (category.contains(token)) score += 8;
        if (city.contains(token)) score += 8;
        if (description.contains(token)) score += 4;
      }
    }

    if (filters.preferLocationFirst &&
        location.isNotEmpty &&
        _matchesLocationText(listing, filters.location)) {
      score += 200;
      if (_normalizeText(listing.cityShort) == location) {
        score += 40;
      }
    }

    score += listing.viewCount > 0 ? (listing.viewCount ~/ 25) : 0;
    return score;
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
}
