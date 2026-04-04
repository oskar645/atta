import 'dart:async';

import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SavedSearch {
  final String id;
  final String userId;
  final String title;
  final String queryKey;
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
    required this.location,
    required this.preferLocationFirst,
    required this.radiusKm,
    required this.autoBrand,
    required this.autoModel,
    required this.autoCondition,
    required this.autoMileageTo,
    required this.onlyUncrashed,
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

    return SavedSearch(
      id: (row['id'] ?? '').toString(),
      userId: (row['user_id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      queryKey: (row['query_key'] ?? '').toString(),
      category: (row['category'] ?? '').toString(),
      search: (row['search'] ?? '').toString(),
      subcategory: (row['subcategory'] ?? '').toString(),
      location: (row['location'] ?? '').toString(),
      preferLocationFirst: row['prefer_location_first'] == true,
      radiusKm: parseNullableInt(row['radius_km']),
      autoBrand: (row['auto_brand'] ?? '').toString(),
      autoModel: (row['auto_model'] ?? '').toString(),
      autoCondition: (row['auto_condition'] ?? '').toString(),
      autoMileageTo: parseNullableInt(row['auto_mileage_to']),
      onlyUncrashed: row['only_uncrashed'] == true,
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
      location: location,
      preferLocationFirst: preferLocationFirst,
      radiusKm: radiusKm,
      autoBrand: autoBrand,
      autoModel: autoModel,
      autoCondition: autoCondition,
      autoMileageTo: autoMileageTo,
      onlyUncrashed: onlyUncrashed,
    );
  }
}

class SavedSearchService {
  static const String missingTableMessage =
      'Таблица saved_searches ещё не создана в Supabase. Сначала примените SQL-патч.';

  final SupabaseClient _db = Supabase.instance.client;
  final ListingsService _listings = ListingsService();
  final NotificationsService _notifications = NotificationsService();
  final Uuid _uuid = const Uuid();

  bool _isMissingTableError(Object error) {
    if (error is! PostgrestException) return false;
    final code = (error.code ?? '').toUpperCase();
    final message = error.message.toLowerCase();
    return code == 'PGRST205' ||
        message.contains("could not find the table 'public.saved_searches'") ||
        message.contains('schema cache') &&
            message.contains('saved_searches') &&
            message.contains('table');
  }

  bool isMissingTableError(Object error) => _isMissingTableError(error);

  Stream<List<SavedSearch>> streamSavedSearches(String userId) {
    final stream = _db.from('saved_searches').stream(primaryKey: ['id']);

    return Stream<List<SavedSearch>>.multi((controller) {
      final sub = stream.listen(
        (rows) {
          final items = rows
              .where((row) => row['user_id']?.toString() == userId)
              .map((row) => SavedSearch.fromMap(Map<String, dynamic>.from(row)))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          controller.add(items);
        },
        onError: (_) => controller.add(<SavedSearch>[]),
      );

      controller.onCancel = () async {
        await sub.cancel();
      };
    });
  }

  String buildQueryKey({
    required String search,
    required ListingFeedFilters filters,
  }) {
    String norm(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

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

  bool canSaveSearch({
    required String search,
    required ListingFeedFilters filters,
  }) {
    return search.trim().isNotEmpty ||
        (filters.category.trim().isNotEmpty && filters.category != 'Все') ||
        (filters.subcategory.trim().isNotEmpty &&
            filters.subcategory != 'Все') ||
        filters.location.trim().isNotEmpty ||
        filters.autoBrand.trim().isNotEmpty ||
        filters.autoModel.trim().isNotEmpty ||
        filters.autoCondition.trim().isNotEmpty ||
        filters.autoMileageTo != null ||
        filters.onlyUncrashed;
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
    if (filters.subcategory.trim().isNotEmpty &&
        filters.subcategory != 'Все') {
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
    if (filters.autoMileageTo != null) {
      parts.add('до ${filters.autoMileageTo} км');
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
    final now = DateTime.now().toUtc().toIso8601String();
    final queryKey = buildQueryKey(search: search, filters: filters);

    try {
      await _db.from('saved_searches').upsert({
        'id': _uuid.v4(),
        'user_id': userId,
        'title': buildTitle(search: search, filters: filters),
        'query_key': queryKey,
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
        'updated_at': now,
        'created_at': now,
      }, onConflict: 'user_id,query_key');
    } catch (e) {
      if (_isMissingTableError(e)) {
        throw StateError(missingTableMessage);
      }
      rethrow;
    }
  }

  Future<void> deleteSavedSearch({
    required String userId,
    required String queryKey,
  }) async {
    try {
      await _db
          .from('saved_searches')
          .delete()
          .eq('user_id', userId)
          .eq('query_key', queryKey);
    } catch (e) {
      if (_isMissingTableError(e)) return;
      rethrow;
    }
  }

  Future<void> setAlertsEnabled({
    required String savedSearchId,
    required bool enabled,
  }) async {
    try {
      await _db.from('saved_searches').update({
        'alerts_enabled': enabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', savedSearchId);
    } catch (e) {
      if (_isMissingTableError(e)) {
        throw StateError(missingTableMessage);
      }
      rethrow;
    }
  }

  Future<void> notifyMatchesForApprovedListing(
    Map<String, dynamic> rawListing,
  ) async {
    final listingRow = Map<String, dynamic>.from(rawListing);
    listingRow['status'] = 'approved';
    final listing = Listing.fromMap(listingRow);

    final rows = await (() async {
      try {
        return await _db
            .from('saved_searches')
            .select('*')
            .eq('alerts_enabled', true);
      } catch (e) {
        if (_isMissingTableError(e)) return <dynamic>[];
        rethrow;
      }
    })();

    final searches = (rows as List)
        .map((row) => SavedSearch.fromMap(Map<String, dynamic>.from(row)))
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
