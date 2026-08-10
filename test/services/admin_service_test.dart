import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/auth_api.dart';
import 'package:atta/src/services/api/admin_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('streamIsAdmin uses cached session user without /auth/me requests',
      () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'user-1',
        isAdmin: true,
      ),
    );
    final authApi = _FakeAuthApi();
    final service = AdminService(authApi: authApi);

    final first = await service.streamIsAdmin('user-1').first;
    final second = await service.streamIsAdmin('user-1').first;

    expect(first, isTrue);
    expect(second, isTrue);
    expect(authApi.meCalls, 0);
  });

  test('seen admin section does not light again after restart without new data',
      () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'admin-1',
        isAdmin: true,
      ),
    );
    final api = _FakeAdminApi();
    final service = AdminService(api: api);
    service.bindAdminUser('admin-1');

    await service.refreshAdminAttention(force: true);
    expect(await service.streamPendingModerationCount().first, 2);

    await service.markSectionSeen(AdminService.moderationSection);
    expect(await service.streamPendingModerationCount().first, 0);

    final restarted = AdminService(api: api);
    restarted.bindAdminUser('admin-1');
    await restarted.refreshAdminAttention(force: true);

    expect(await restarted.streamPendingModerationCount().first, 0);
  });

  test('refreshAdminAttention skips admin endpoints for non-admin session',
      () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'user-1',
        isAdmin: false,
      ),
    );
    final api = _FakeAdminApi();
    final service = AdminService(api: api);
    service.activateSession();
    service.bindAdminUser('user-1');

    await service.refreshAdminAttention(force: true);

    expect(api.listingsCalls, 0);
    expect(api.reportsCalls, 0);
    expect(api.supportCalls, 0);
  });

  test('streamNeedsAttention refreshes admin attention on listen', () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'admin-1',
        isAdmin: true,
      ),
    );
    final api = _FakeAdminApi();
    final service = AdminService(api: api);
    service.activateSession();
    service.bindAdminUser('admin-1');

    final value = await service.streamNeedsAttention().firstWhere(
          (value) => value,
        );

    expect(value, isTrue);
    expect(api.listingsCalls, 1);
    expect(api.reportsCalls, 1);
    expect(api.supportCalls, 1);
  });

  test('new pending listing after seen lights moderation badge again',
      () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'admin-1',
        isAdmin: true,
      ),
    );
    final api = _FakeAdminApi();
    final service = AdminService(api: api);
    service.activateSession();
    service.bindAdminUser('admin-1');

    await service.refreshAdminAttention(force: true);
    await service.markSectionSeen(AdminService.moderationSection);
    expect(await service.streamPendingModerationCount().first, 0);

    api.pendingItems = <Map<String, dynamic>>[
      ...api.pendingItems,
      <String, dynamic>{
        'id': 'listing-3',
        'status': 'pending',
        'created_at': '2026-07-03T12:00:00.000Z',
      },
    ];
    await service.refreshAdminAttention(force: true);

    expect(await service.streamPendingModerationCount().first, 3);
    expect(await service.streamOpenReportsCount().first, 0);
    expect(await service.streamUnreadSupportForAdminCount().first, 0);
  });

  test('referral searches use separate cache keys and force refresh', () async {
    final api = _FakeAdminApi();
    final service = AdminService(api: api);

    final resultA = await service.referrals(search: 'Alice');
    final resultB = await service.referrals(search: 'Bob');
    final refreshedA = await service.referrals(
      search: 'Alice',
      forceRefresh: true,
    );

    expect(resultA['items'], [
      {'id': 'referral-user:Alice'}
    ]);
    expect(resultB['items'], [
      {'id': 'referral-user:Bob'}
    ]);
    expect(refreshedA['items'], [
      {'id': 'referral-user:Alice'}
    ]);
    expect(api.referralSearches, ['Alice', 'Bob', 'Alice']);
  });
}

class _FakeAuthApi extends AuthApi {
  _FakeAuthApi() : super(ApiClient(tokenStorage: TokenStorage()));

  int meCalls = 0;

  @override
  Future<Map<String, dynamic>> me() async {
    meCalls += 1;
    return <String, dynamic>{
      'user': <String, dynamic>{
        'id': 'user-1',
        'role': 'admin',
      },
      'isAdmin': true,
    };
  }
}

class _FakeAdminApi extends AdminApi {
  _FakeAdminApi() : super(ApiClient(tokenStorage: TokenStorage()));

  int listingsCalls = 0;
  int reportsCalls = 0;
  int supportCalls = 0;
  final List<String> referralSearches = <String>[];
  List<Map<String, dynamic>> pendingItems = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'listing-1',
      'status': 'pending',
      'updated_at': '2026-07-03T10:00:00.000Z',
    },
    <String, dynamic>{
      'id': 'listing-2',
      'status': 'pending',
      'updated_at': '2026-07-03T11:00:00.000Z',
    },
  ];

  @override
  Future<Map<String, dynamic>> listings({
    String? status,
    int? limit,
    String? cursor,
  }) async {
    listingsCalls += 1;
    return <String, dynamic>{
      'items': pendingItems,
      'total': pendingItems.length,
      'pendingModeration': pendingItems.length,
    };
  }

  @override
  Future<Map<String, dynamic>> reports({int? limit, String? cursor}) async {
    reportsCalls += 1;
    return <String, dynamic>{'items': const <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> support() async {
    supportCalls += 1;
    return <String, dynamic>{'items': const <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> referrals({
    String? period,
    String? from,
    String? to,
    String? search,
    String? userId,
    int? limit,
    String? cursor,
  }) async {
    final key = (search?.trim().isNotEmpty ?? false)
        ? search!.trim()
        : (userId?.trim() ?? '');
    referralSearches.add(key);
    return <String, dynamic>{
      'items': [
        <String, dynamic>{'id': 'referral-user:$key'},
      ],
    };
  }
}
