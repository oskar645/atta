import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
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

  @override
  Future<Map<String, dynamic>> list() async {
    return <String, dynamic>{
      'favorite_ids': _favoriteIds.toList(),
    };
  }

  @override
  Future<Map<String, dynamic>> add(String listingId) async {
    await onAdd?.call(listingId, _favoriteIds);
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
