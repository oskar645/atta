import 'dart:async';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/saved_searches_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/saved_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'session reset drops saved-search cache and ignores in-flight A response',
      () async {
    final api = _PendingSavedSearchesApi();
    final service = SavedSearchService(api: api);
    final first = service.refreshSavedSearches('A');
    api.pending.removeAt(0).complete({
      'items': [
        {'id': 'private-a', 'user_id': 'A'}
      ]
    });
    expect(await first, hasLength(1));
    expect(service.peekSavedSearches('A'), hasLength(1));
    final stale = service.refreshSavedSearches('A');
    service.resetSession();
    expect(service.peekSavedSearches('A'), isEmpty);
    final next = service.refreshSavedSearches('B');
    api.pending.removeAt(0).complete({
      'items': [
        {'id': 'private-a', 'user_id': 'A'}
      ]
    });
    api.pending.removeAt(0).complete({
      'items': [
        {'id': 'private-b', 'user_id': 'B'}
      ]
    });
    expect(await stale, isEmpty);
    expect((await next).single.id, 'private-b');
    expect(service.peekSavedSearches('A'), isEmpty);
    expect(service.peekSavedSearches('B').single.id, 'private-b');
  });

  test('saved search query key restores new filters without schema columns',
      () {
    final service = SavedSearchService();
    const filters = ListingFeedFilters(
      category: 'Авто',
      search: 'кроссовер',
      subcategory: 'Легковые автомобили',
      priceFrom: 1000000,
      priceTo: 2000000,
      location: 'Москва',
      preferLocationFirst: true,
      radiusKm: 10,
      autoBrand: 'Haval',
      autoModel: 'Dargo X',
      autoCondition: 'Не битая',
      autoYearFrom: 2022,
      autoYearTo: 2025,
      autoMileageFrom: 5000,
      autoMileageTo: 50000,
      autoTransmission: 'Робот',
      autoDrive: 'Полный',
      autoBodyType: 'Кроссовер',
      autoFuel: 'Бензин',
      autoColor: 'Белый',
      autoEngineVolumeFrom: 1.8,
      autoEngineVolumeTo: 2.2,
      autoOwners: 1,
      autoCleared: true,
      onlyUncrashed: true,
      onlyWithPhoto: true,
    );

    final saved = SavedSearch.fromMap({
      'id': 'search-1',
      'user_id': 'user-1',
      'title': 'Haval Dargo X',
      'query_key': service.buildQueryKey(search: 'кроссовер', filters: filters),
      'category': 'Авто',
      'search': 'кроссовер',
      'subcategory': 'Легковые автомобили',
      'location': 'Москва',
      'prefer_location_first': true,
      'radius_km': 10,
      'auto_brand': 'Haval',
      'auto_model': 'Dargo X',
      'auto_condition': 'Не битая',
      'auto_mileage_to': 50000,
      'only_uncrashed': true,
      'alerts_enabled': true,
      'created_at': '2026-08-09T10:00:00.000Z',
      'updated_at': '2026-08-09T10:00:00.000Z',
    });

    final restored = saved.toFilters();
    expect(restored.priceFrom, 1000000);
    expect(restored.priceTo, 2000000);
    expect(restored.autoYearFrom, 2022);
    expect(restored.autoMileageFrom, 5000);
    expect(restored.autoDrive, 'полный');
    expect(restored.autoCleared, true);
    expect(restored.onlyWithPhoto, true);
  });

  test('old saved search rows remain compatible', () {
    final service = SavedSearchService();
    expect(
      service.buildQueryKey(
        search: 'toyota',
        filters: const ListingFeedFilters(
          category: 'Авто',
          search: 'toyota',
          autoBrand: 'Toyota',
          autoModel: 'Camry',
          autoMileageTo: 50000,
        ),
      ),
      'toyota|авто|все||0||toyota|camry||50000|0',
    );

    final saved = SavedSearch.fromMap({
      'id': 'search-1',
      'user_id': 'user-1',
      'title': 'Toyota',
      'query_key': 'toyota|авто|все||0||toyota|camry||50000|0',
      'category': 'Авто',
      'search': 'toyota',
      'subcategory': 'Все',
      'auto_brand': 'Toyota',
      'auto_model': 'Camry',
      'auto_mileage_to': 50000,
      'created_at': '2026-08-09T10:00:00.000Z',
      'updated_at': '2026-08-09T10:00:00.000Z',
    });

    final restored = saved.toFilters();
    expect(restored.autoBrand, 'Toyota');
    expect(restored.autoModel, 'Camry');
    expect(restored.autoMileageTo, 50000);
    expect(restored.priceFrom, isNull);
    expect(restored.onlyWithPhoto, isFalse);
  });
}

class _PendingSavedSearchesApi extends SavedSearchesApi {
  _PendingSavedSearchesApi() : super(ApiClient(tokenStorage: TokenStorage()));
  final pending = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> list() {
    final request = Completer<Map<String, dynamic>>();
    pending.add(request);
    return request.future;
  }
}
