import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/auth_api.dart';
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
