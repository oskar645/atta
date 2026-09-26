import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/viewed_listings_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/listing_history_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('viewed listings persist after restart for same user', () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final api = _FakeViewedListingsApi(
      listedIds: const <String>['server-1'],
    );

    final service = ListingHistoryService(
      tokenStorage: storage,
      api: api,
    );
    await Future<void>.delayed(Duration.zero);
    expect(api.listCalls, 0);
    await service.activateSession();

    await service.markViewed('local-1');
    expect(service.viewedIdsNewestFirst, contains('local-1'));

    final restored = ListingHistoryService(
      tokenStorage: storage,
      api: api,
    );
    await Future<void>.delayed(Duration.zero);
    expect(api.listCalls, 1);
    await restored.activateSession();

    expect(restored.viewedIdsNewestFirst.first, 'local-1');
    expect(restored.viewedIdsNewestFirst, contains('server-1'));
  });

  test('viewed listings do not mix between users', () async {
    final storage = TokenStorage();
    final api = _FakeViewedListingsApi(
      listedIdsByUser: <String, List<String>>{
        'user-1': const <String>['server-user-1'],
        'user-2': const <String>['server-user-2'],
      },
    );

    await storage.saveSession(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final firstUser = ListingHistoryService(
      tokenStorage: storage,
      api: api,
    );
    await Future<void>.delayed(Duration.zero);
    await firstUser.activateSession();
    await firstUser.markViewed('local-user-1');

    await storage.saveSession(
      accessToken: 'access-2',
      refreshToken: 'refresh-2',
      currentUser: const AuthUser(uid: 'user-2'),
    );
    final secondUser = ListingHistoryService(
      tokenStorage: storage,
      api: api,
    );
    await Future<void>.delayed(Duration.zero);
    await secondUser.activateSession();

    expect(secondUser.viewedIdsNewestFirst, contains('server-user-2'));
    expect(secondUser.viewedIdsNewestFirst, isNot(contains('local-user-1')));
    expect(secondUser.viewedIdsNewestFirst, isNot(contains('server-user-1')));
  });

  test('activateSession is throttled and does not spam viewed listings sync',
      () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final api = _FakeViewedListingsApi(
      listedIds: const <String>['server-1'],
    );

    final service = ListingHistoryService(
      tokenStorage: storage,
      api: api,
    );
    final calls = await Future.wait<void>(<Future<void>>[
      service.activateSession(),
      service.activateSession(),
    ]);

    expect(calls, hasLength(2));
    expect(api.listCalls, 1);
    await service.activateSession();
    expect(api.listCalls, 1);
  });

  test('viewed tab uses synced service cache with cursor pagination', () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final api = _FakeViewedListingsApi(
      listedIds: const <String>['server-1', 'server-2', 'server-3'],
    );
    final service = ListingHistoryService(tokenStorage: storage, api: api);

    await service.activateSession();
    final first = await service.getViewedListingsPage(limit: 2);
    final second = await service.getViewedListingsPage(
      limit: 2,
      cursor: first.nextCursor,
    );

    expect(first.ids, hasLength(2));
    expect(first.hasMore, isTrue);
    expect(second.ids, hasLength(1));
    expect(second.hasMore, isFalse);
    expect(api.listCalls, 1);
  });
}

class _FakeViewedListingsApi extends ViewedListingsApi {
  _FakeViewedListingsApi({
    List<String>? listedIds,
    Map<String, List<String>>? listedIdsByUser,
  })  : _listedIds = listedIds,
        _listedIdsByUser = listedIdsByUser,
        super(ApiClient(tokenStorage: TokenStorage()));

  final List<String>? _listedIds;
  final Map<String, List<String>>? _listedIdsByUser;
  final List<String> markedIds = <String>[];
  int listCalls = 0;

  @override
  Future<Map<String, dynamic>> list({int? limit, String? cursor}) async {
    listCalls += 1;
    final storage = TokenStorage();
    final user = await storage.readCurrentUser();
    final uid = user?.uid ?? '';
    final ids = _listedIdsByUser?[uid] ?? _listedIds ?? const <String>[];
    return <String, dynamic>{
      'items': ids
          .map(
            (id) => <String, dynamic>{
              'listing_id': id,
              'viewed_at': '2026-07-02T10:00:00.000Z',
            },
          )
          .toList(growable: false),
    };
  }

  @override
  Future<Map<String, dynamic>> mark(String listingId) async {
    markedIds.add(listingId);
    return <String, dynamic>{
      'viewed': true,
      'listing_id': listingId,
    };
  }
}
