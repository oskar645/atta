import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/favorites_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('toggleFavorite updates Timeweb cache optimistically', () async {
    final api = _FakeFavoritesApi(
      favoriteIds: <String>{'listing-1'},
    );
    final service = FavoritesService(api: api);

    await service.refreshFavoriteIds('user-1');
    expect(service.peekFavoriteIds('user-1'), <String>{'listing-1'});

    final completer = Completer<void>();
    api.onAdd = (_, __) => completer.future;

    final operation = service.toggleFavorite(
      uid: 'user-1',
      listingId: 'listing-2',
      makeFavorite: true,
    );

    expect(
      service.peekFavoriteIds('user-1'),
      <String>{'listing-1', 'listing-2'},
    );

    completer.complete();
    await operation;

    expect(
      service.peekFavoriteIds('user-1'),
      <String>{'listing-1', 'listing-2'},
    );
  });

  test('removing favorite updates cache immediately', () async {
    final service = FavoritesService(
      api: _FakeFavoritesApi(
        favoriteIds: <String>{'listing-1', 'listing-2'},
      ),
    );

    await service.refreshFavoriteIds('user-1');
    final future = service.toggleFavorite(
      uid: 'user-1',
      listingId: 'listing-2',
      makeFavorite: false,
    );

    expect(service.peekFavoriteIds('user-1'), <String>{'listing-1'});
    await future;
    expect(service.peekFavoriteIds('user-1'), <String>{'listing-1'});
  });

  test('rapid favorite toggles keep final state correct', () async {
    final api = _FakeFavoritesApi(favoriteIds: <String>{});
    final service = FavoritesService(api: api);

    await service.refreshFavoriteIds('user-1');
    final addFuture = service.toggleFavorite(
      uid: 'user-1',
      listingId: 'listing-9',
      makeFavorite: true,
    );
    final removeFuture = service.toggleFavorite(
      uid: 'user-1',
      listingId: 'listing-9',
      makeFavorite: false,
    );

    await Future.wait([addFuture, removeFuture]);

    expect(service.peekFavoriteIds('user-1'), isEmpty);
    expect(api.favoriteIds, isEmpty);
  });

  test('favorite toggle rolls back on backend error', () async {
    final api = _FakeFavoritesApi(favoriteIds: <String>{})
      ..addError = const ApiException('Ошибка', statusCode: 500);
    final service = FavoritesService(api: api);

    await expectLater(
      service.toggleFavorite(
        uid: 'user-1',
        listingId: 'listing-5',
        makeFavorite: true,
      ),
      throwsA(isA<ApiException>()),
    );

    expect(service.peekFavoriteIds('user-1'), isEmpty);
  });
}

class _FakeFavoritesApi extends FavoritesApi {
  _FakeFavoritesApi({
    required Set<String> favoriteIds,
  })  : _favoriteIds = Set<String>.from(favoriteIds),
        super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );

  final Set<String> _favoriteIds;
  Future<void> Function(String listingId, Set<String> current)? onAdd;
  Object? addError;

  Set<String> get favoriteIds => Set<String>.from(_favoriteIds);

  @override
  Future<Map<String, dynamic>> list() async {
    return <String, dynamic>{
      'favorite_ids': _favoriteIds.toList(),
    };
  }

  @override
  Future<Map<String, dynamic>> add(String listingId) async {
    await onAdd?.call(listingId, _favoriteIds);
    if (addError != null) {
      throw addError!;
    }
    _favoriteIds.add(listingId);
    return <String, dynamic>{
      'listing_id': listingId,
    };
  }

  @override
  Future<Map<String, dynamic>> remove(String listingId) async {
    _favoriteIds.remove(listingId);
    return <String, dynamic>{
      'deleted': true,
    };
  }
}
