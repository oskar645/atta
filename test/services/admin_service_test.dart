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

  test('streamNeedsAttention does not auto-load admin endpoints on listen',
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

    final value = await service.streamNeedsAttention().first;

    expect(value, isFalse);
    expect(api.listingsCalls, 0);
    expect(api.reportsCalls, 0);
    expect(api.supportCalls, 0);
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

  @override
  Future<Map<String, dynamic>> listings({String? status}) async {
    listingsCalls += 1;
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
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
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> reports() async {
    reportsCalls += 1;
    return <String, dynamic>{'items': const <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> support() async {
    supportCalls += 1;
    return <String, dynamic>{'items': const <Map<String, dynamic>>[]};
  }
}
