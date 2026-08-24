import 'dart:async';
import 'dart:convert';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/favorites_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

  test('rapid repeated taps for one listing do not fire duplicate requests',
      () async {
    final completer = Completer<void>();
    final api = _FakeFavoritesApi(favoriteIds: <String>{})
      ..onAdd = (_, __) => completer.future;
    final service = FavoritesService(api: api);

    await service.refreshFavoriteIds('user-1');

    final futures = List<Future<void>>.generate(
      5,
      (_) => service.toggleFavorite(
        uid: 'user-1',
        listingId: 'listing-7',
        makeFavorite: true,
      ),
    );

    expect(api.addCalls, 1);

    completer.complete();
    await Future.wait(futures);

    expect(api.addCalls, 1);
    expect(service.peekFavoriteIds('user-1'), <String>{'listing-7'});
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

  test('remove and add again moves favorite to top order', () async {
    final api = _FakeFavoritesApi(
      favoriteIds: <String>{'listing-b', 'listing-a'},
    );
    final service = FavoritesService(api: api);

    await service.refreshFavoriteIds('user-1');
    expect(
      service.peekFavoriteIds('user-1').toList(),
      <String>['listing-b', 'listing-a'],
    );

    await service.toggleFavorite(
      uid: 'user-1',
      listingId: 'listing-a',
      makeFavorite: false,
    );
    await service.toggleFavorite(
      uid: 'user-1',
      listingId: 'listing-a',
      makeFavorite: true,
    );

    expect(
      service.peekFavoriteIds('user-1').toList(),
      <String>['listing-a', 'listing-b'],
    );
  });

  test('favorites refresh timeout returns cached ids and clears inFlight',
      () async {
    final api = _FakeFavoritesApi(
      favoriteIds: <String>{'listing-1'},
    );
    final service = FavoritesService(api: api);

    await service.refreshFavoriteIds('user-1');
    api.listError = TimeoutException('Future not completed');

    final ids = await service.refreshFavoriteIds('user-1');

    expect(ids, <String>{'listing-1'});
    expect(service.peekFavoriteIds('user-1'), <String>{'listing-1'});
    expect(service.lastRefreshErrorForUser('user-1'), isA<TimeoutException>());

    api.listError = null;
    final refreshed = await service.refreshFavoriteIds('user-1');
    expect(refreshed, <String>{'listing-1'});
    expect(service.lastRefreshErrorForUser('user-1'), isNull);
  });

  test('streamFavoriteIds timeout does not emit stream error', () async {
    final api = _FakeFavoritesApi(favoriteIds: <String>{'listing-1'});
    final service = FavoritesService(api: api);
    final listCompleter = Completer<Map<String, dynamic>>();
    api.listCompleter = listCompleter;

    final refresh = service.refreshFavoriteIds('user-1');
    final firstStreamValue = service.streamFavoriteIds('user-1').first;

    listCompleter.completeError(TimeoutException('Future not completed'));

    await expectLater(refresh, completion(isEmpty));
    await expectLater(firstStreamValue, completion(isEmpty));
    expect(service.lastRefreshErrorForUser('user-1'), isA<TimeoutException>());
  });

  test('simultaneous load calls create one request', () async {
    final api = _FakeFavoritesApi(favoriteIds: <String>{'listing-1'});
    final service = FavoritesService(api: api);
    final listCompleter = Completer<Map<String, dynamic>>();
    api.listCompleter = listCompleter;

    final first = service.refreshFavoriteIds('user-1', reason: 'vpn_change');
    final second = service.refreshFavoriteIds('user-1', reason: 'vpn_change');

    expect(api.listCalls, 1);

    listCompleter.complete(<String, dynamic>{
      'favorite_ids': <String>['listing-1'],
    });

    expect(await first, <String>{'listing-1'});
    expect(await second, <String>{'listing-1'});
    expect(api.listCalls, 1);
  });

  test('force refresh after timeout starts a new favorites request', () async {
    final api = _FakeFavoritesApi(favoriteIds: <String>{'listing-1'});
    final service = FavoritesService(api: api);

    api.listError = TimeoutException('Future not completed');
    final failedSafe = await service.refreshFavoriteIds('user-1');
    expect(failedSafe, isEmpty);
    expect(api.listCalls, 1);

    api.listError = null;
    final recovered = await service.forceRefreshFavoriteIds('user-1');

    expect(recovered, <String>{'listing-1'});
    expect(api.listCalls, 2);
    expect(service.lastRefreshErrorForUser('user-1'), isNull);
  });

  test('favorites 401 performs one refresh and retries with new token',
      () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'expired-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final httpClient = _FavoritesAuthRetryHttpClient();
    final client = ApiClient(
      tokenStorage: storage,
      httpClient: httpClient,
    );
    final service = FavoritesService(api: FavoritesApi(client));

    var refreshCalls = 0;
    ApiClient.configureAuthHandlers(
      onRefreshSession: () async {
        refreshCalls += 1;
        await storage.saveSession(
          accessToken: 'fresh-token',
          refreshToken: 'refresh-token',
          currentUser: const AuthUser(uid: 'user-1'),
        );
        return true;
      },
      onSessionExpired: () async {},
    );

    final ids = await service.refreshFavoriteIds('user-1');

    expect(ids, <String>{'listing-1'});
    expect(refreshCalls, 1);
    expect(httpClient.calls, hasLength(2));
    expect(
      httpClient.calls.last.headers['Authorization'],
      'Bearer fresh-token',
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
  int addCalls = 0;
  int listCalls = 0;
  Future<void> Function(String listingId, Set<String> current)? onAdd;
  Object? addError;
  Object? listError;
  Completer<Map<String, dynamic>>? listCompleter;

  Set<String> get favoriteIds => Set<String>.from(_favoriteIds);

  @override
  Future<Map<String, dynamic>> list({int? limit, String? cursor}) async {
    listCalls += 1;
    final completer = listCompleter;
    if (completer != null) {
      listCompleter = null;
      return completer.future;
    }
    if (listError != null) {
      throw listError!;
    }
    return <String, dynamic>{
      'favorite_ids': _favoriteIds.toList(),
    };
  }

  @override
  Future<Map<String, dynamic>> add(String listingId) async {
    addCalls += 1;
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

class _FavoritesAuthRetryHttpClient extends http.BaseClient {
  final List<http.BaseRequest> calls = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request);
    final auth = request.headers['Authorization'];
    final success = auth == 'Bearer fresh-token';
    final body = success
        ? jsonEncode(<String, dynamic>{
            'favorite_ids': <String>['listing-1'],
          })
        : jsonEncode(<String, dynamic>{'message': 'expired'});
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      success ? 200 : 401,
      headers: const <String, String>{
        'content-type': 'application/json',
      },
    );
  }
}
