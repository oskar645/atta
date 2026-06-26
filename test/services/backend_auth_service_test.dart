import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/auth_api.dart';
import 'package:atta/src/services/api/users_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/backend_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('signIn preserves cached currentUser fields when /auth/me is sparse',
      () async {
    final service = BackendAuthService(
      authApi: _FakeAuthApi(),
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    final user = await service.signIn(
      email: 'user@example.com',
      password: 'secret',
    );

    expect(user.uid, 'user-1');
    expect(user.email, 'user@example.com');
    expect(user.displayName, 'ATTA User');
    expect(service.currentUser?.displayName, 'ATTA User');
  });

  test('signOut clears Timeweb session without requiring legacy session',
      () async {
    final authApi = _FakeAuthApi();
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    await service.signIn(
      email: 'user@example.com',
      password: 'secret',
    );
    expect(service.currentUser, isNotNull);

    await service.signOut();

    expect(service.currentUser, isNull);
    expect(authApi.logoutCalled, isTrue);
  });

  test('startPhoneVerification reads compatible call fields', () async {
    final service = BackendAuthService(
      authApi: _FakeAuthApi(),
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    final result = await service.startPhoneVerification(
      phone: '+79281234567',
      purpose: 'login',
    );

    expect(result.verificationId, 'verification-1');
    expect(result.callToPhone, '78005008275');
    expect(result.callToPhonePretty, '+7 (800) 500-82-75');
    expect(result.hasCallToPhone, isTrue);
  });

  test('signInWithPhone keeps phone and phoneVerified in cached user',
      () async {
    final service = BackendAuthService(
      authApi: _FakeAuthApi(),
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    await service.signInWithPhone(
      phone: '+79281234567',
      password: '12345678',
    );

    expect(service.currentUser?.phone, '+79281234567');
    expect(service.currentUser?.phoneVerified, isTrue);
  });

  test('signInWithPhone forwards verificationCheckId to backend', () async {
    final authApi = _FakeAuthApi();
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    await service.signInWithPhone(
      phone: '+79281234567',
      password: '12345678',
      verificationCheckId: 'verification-42',
    );

    expect(authApi.lastLoginPhoneVerificationCheckId, 'verification-42');
  });

  test('signInWithPhone works without verificationCheckId for password login',
      () async {
    final authApi = _FakeAuthApi();
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    await service.signInWithPhone(
      phone: '+79281234567',
      password: '12345678',
    );

    expect(authApi.lastLoginPhoneVerificationCheckId, isNull);
  });

  test('userMessageForError maps backend auth code to russian text', () {
    final service = BackendAuthService(
      authApi: _FakeAuthApi(),
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    final message = service.userMessageForError(
      const ApiException(
        'Bad request',
        statusCode: 400,
        code: 'INVALID_PHONE_OR_PASSWORD',
      ),
      isSignIn: true,
    );

    expect(message, 'Неверный номер телефона или пароль');
  });

  test('AuthUser.fromJson reads Timeweb aliases for phone and avatar', () {
    final user = AuthUser.fromJson(<String, dynamic>{
      'id': 'user-1',
      'display_name': 'ATTA User',
      'normalized_phone': '79281234567',
      'isPhoneVerified': true,
      'avatar_url': 'https://example.com/avatar.jpg',
      'role': 'admin',
    });

    expect(user.uid, 'user-1');
    expect(user.displayName, 'ATTA User');
    expect(user.phone, '79281234567');
    expect(user.phoneVerified, isTrue);
    expect(user.photoUrl, 'https://example.com/avatar.jpg');
    expect(user.isAdmin, isTrue);
  });

  test('signIn appends cache buster to avatar from updated_at', () async {
    final service = BackendAuthService(
      authApi: _FakeAuthApi(),
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    final user = await service.signIn(
      email: 'user@example.com',
      password: 'secret',
    );

    expect(
      user.photoUrl,
      'https://example.com/avatar.jpg?v=2026-06-20T10%3A00%3A00.000Z',
    );
  });

  test('refreshSession clears session when refresh fails', () async {
    final authApi = _FakeAuthApi()
      ..refreshError = const ApiException(
        'expired',
        statusCode: 401,
      );
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    await service.signIn(
      email: 'user@example.com',
      password: 'secret',
    );

    final refreshed = await service.refreshSession();

    expect(refreshed, isFalse);
    expect(service.currentUser, isNull);
  });
}

class _FakeAuthApi extends AuthApi {
  _FakeAuthApi()
      : super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );

  bool logoutCalled = false;
  String? lastLoginPhoneVerificationCheckId;
  Object? refreshError;

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    return <String, dynamic>{
      'auth': <String, dynamic>{
        'access_token': 'access-token',
        'refresh_token': 'refresh-token',
      },
      'user': <String, dynamic>{
        'id': 'user-1',
        'email': email,
        'display_name': 'ATTA User',
        'avatar_url': 'https://example.com/avatar.jpg',
        'updated_at': '2026-06-20T10:00:00.000Z',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> me() async {
    return <String, dynamic>{
      'user': <String, dynamic>{
        'id': 'user-1',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> logout({
    required String refreshToken,
  }) async {
    logoutCalled = true;
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> refresh({
    required String refreshToken,
  }) async {
    if (refreshError != null) {
      throw refreshError!;
    }
    return <String, dynamic>{
      'auth': <String, dynamic>{
        'access_token': 'new-access-token',
        'refresh_token': 'new-refresh-token',
      },
      'user': <String, dynamic>{
        'id': 'user-1',
        'email': 'user@example.com',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> startPhoneVerification({
    required String phone,
    required String purpose,
  }) async {
    return <String, dynamic>{
      'verificationCheckId': 'verification-1',
      'call_phone': '78005008275',
      'call_phone_pretty': '+7 (800) 500-82-75',
      'message': 'Позвоните на указанный номер для подтверждения',
    };
  }

  @override
  Future<Map<String, dynamic>> loginPhone({
    required String phone,
    required String password,
    String verificationCheckId = '',
  }) async {
    lastLoginPhoneVerificationCheckId =
        verificationCheckId.isEmpty ? null : verificationCheckId;
    return <String, dynamic>{
      'auth': <String, dynamic>{
        'access_token': 'access-token',
        'refresh_token': 'refresh-token',
      },
      'user': <String, dynamic>{
        'id': 'user-1',
        'phone': phone,
        'phone_verified': true,
        'display_name': 'ATTA User',
      },
    };
  }
}

class _FakeUsersApi extends UsersApi {
  _FakeUsersApi()
      : super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );
}
