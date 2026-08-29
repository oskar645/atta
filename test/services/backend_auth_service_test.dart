import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/auth_api.dart';
import 'package:atta/src/services/api/users_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/backend_auth_service.dart';
import 'package:atta/src/services/restore_credentials_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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

  test('signUpWithVerifiedPhone forwards referralCode to backend', () async {
    final authApi = _FakeAuthApi();
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    await service.signUpWithVerifiedPhone(
      phone: '+79281234567',
      password: '12345678',
      displayName: 'ATTA User',
      verificationCheckId: 'verification-1',
      referralCode: 'REFERRAL_CODE_999',
    );

    expect(authApi.lastSignupPhoneReferralCode, 'REFERRAL_CODE_999');
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
      'referral_code': 'REFERRAL_CODE_ABC',
      'role': 'admin',
    });

    expect(user.uid, 'user-1');
    expect(user.displayName, 'ATTA User');
    expect(user.phone, '79281234567');
    expect(user.phoneVerified, isTrue);
    expect(user.photoUrl, 'https://example.com/avatar.jpg');
    expect(user.referralCode, 'REFERRAL_CODE_ABC');
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

  test('signIn normalizes relative avatar_url to backend media url', () async {
    final service = BackendAuthService(
      authApi: _RelativeAvatarAuthApi(),
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    final user = await service.signIn(
      email: 'user@example.com',
      password: 'secret',
    );

    expect(
      user.photoUrl,
      'https://attamarket.online/media/object?category=avatars&key=avatars%2Fuser-1%2Fphoto.jpg&v=2026-06-20T10%3A00%3A00.000Z',
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

  test('refreshSession keeps cached session on network refresh error',
      () async {
    final authApi = _FakeAuthApi()
      ..refreshError = const ApiException(
        'Проверьте интернет-соединение и попробуйте снова.',
        code: 'network',
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

    expect(refreshed, isTrue);
    expect(service.currentUser, isNotNull);
    expect(service.currentUser?.uid, 'user-1');
  });

  test('restoreSessionOnResume refreshes expired access token without logout',
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
    authApi.meError = const ApiException(
      'expired',
      statusCode: 401,
    );
    authApi.failMeCalls = 1;

    final user = await service.restoreSessionOnResume(force: true);

    expect(user, isNotNull);
    expect(service.currentUser, isNotNull);
    expect(authApi.refreshCalls, 1);
    expect(authApi.meCalls, greaterThanOrEqualTo(2));
  });

  test('restoreSessionOnResume keeps user signed in on network error',
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
    authApi.meError = const ApiException(
      'Проверьте интернет-соединение и попробуйте снова.',
      code: 'network',
    );

    final user = await service.restoreSessionOnResume(force: true);

    expect(user, isNotNull);
    expect(service.currentUser, isNotNull);
    expect(authApi.refreshCalls, 0);
  });

  test('concurrent restoreSessionOnResume performs one shared auth check',
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
    authApi.meResponse = <String, dynamic>{
      'user': <String, dynamic>{
        'id': 'user-1',
        'email': 'user@example.com',
      },
    };
    authApi.meDelay = const Duration(milliseconds: 40);

    final results = await Future.wait([
      service.restoreSessionOnResume(force: true),
      service.restoreSessionOnResume(force: true),
      service.restoreSessionOnResume(force: true),
    ]);

    expect(results.every((user) => user?.uid == 'user-1'), isTrue);
    expect(authApi.meCalls, 2);
  });

  test(
      'ensureInitialized restores cached session without waiting for auth gate',
      () async {
    final authApi = _FakeAuthApi()..meDelay = const Duration(milliseconds: 200);
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: storage,
    );

    final stopwatch = Stopwatch()..start();
    await service.ensureInitialized();
    stopwatch.stop();

    expect(service.currentUser?.uid, 'user-1');
    expect(stopwatch.elapsedMilliseconds, lessThan(120));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(authApi.meCalls, 0);
  });

  test('ensureInitialized runs one proactive refresh for expired cached token',
      () async {
    final authApi = _FakeAuthApi()
      ..refreshDelay = const Duration(milliseconds: 40);
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: _jwtWithExpOffset(const Duration(seconds: -30)),
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: storage,
    );

    await service.ensureInitialized();
    expect(service.currentUser?.uid, 'user-1');

    await service.awaitPrivateAuthReady();

    expect(authApi.refreshCalls, 1);
    // Refresh itself supplies and persists the current user. Calling /auth/me
    // while this bootstrap gate is active would wait for itself forever.
    expect(authApi.meCalls, 0);
  });

  test('refreshSession uses the user returned by refresh without /auth/me',
      () async {
    final authApi = _FakeAuthApi()
      ..meResponse = <String, dynamic>{
        'user': <String, dynamic>{
          'id': 'user-1',
          'email': 'user@example.com',
          'role': 'admin',
        },
        'isAdmin': true,
      };
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

    expect(refreshed, isTrue);
    // signIn already hydrated the user once. Refresh must not add another
    // /auth/me request while it is the private-auth gate.
    expect(authApi.meCalls, 1);
    expect(service.currentUser?.isAdmin, isTrue);
  });

  test('concurrent refreshSession performs one shared refresh request',
      () async {
    final authApi = _FakeAuthApi()
      ..refreshDelay = const Duration(milliseconds: 40);
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
    );

    await service.signIn(
      email: 'user@example.com',
      password: 'secret',
    );

    final results = await Future.wait([
      service.refreshSession(),
      service.refreshSession(),
      service.refreshSession(),
    ]);

    expect(results, everyElement(isTrue));
    expect(authApi.refreshCalls, 1);
  });

  test('ensureInitialized clears cached session when proactive refresh fails',
      () async {
    final authApi = _FakeAuthApi()
      ..refreshError = const ApiException(
        'expired',
        statusCode: 401,
      );
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: _jwtWithExpOffset(const Duration(seconds: -30)),
      refreshToken: 'expired-refresh',
      currentUser: const AuthUser(
        uid: 'user-1',
        phone: '79288888645',
        isAdmin: true,
      ),
    );
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: tokenStorage,
    );

    await service.ensureInitialized();
    await service.awaitPrivateAuthReady();
    expect(service.currentUser, isNull);
  });

  test('syncCurrentUserFromProfile updates live user and emits userUpdated',
      () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'user-1',
        email: 'user@example.com',
        displayName: 'Old Name',
        phone: '+79281234567',
        phoneVerified: true,
        photoUrl: 'https://example.com/avatar.jpg',
        referralCode: 'REFERRAL_CODE_ABC',
        isAdmin: true,
      ),
    );
    final service = BackendAuthService(
      authApi: _FakeAuthApi(),
      usersApi: _FakeUsersApi(),
      tokenStorage: tokenStorage,
    );
    await service.ensureInitialized();

    final eventFuture = service.onAuthStateChange.first;
    final user = await service.syncCurrentUserFromProfile(
      'user-1',
      <String, dynamic>{
        'display_name': 'New Name',
      },
    );

    expect(user?.displayName, 'New Name');
    expect(service.currentUser?.displayName, 'New Name');
    expect(service.currentUser?.uid, 'user-1');
    expect(service.currentUser?.email, 'user@example.com');
    expect(service.currentUser?.phone, '+79281234567');
    expect(service.currentUser?.phoneVerified, isTrue);
    expect(service.currentUser?.photoUrl, 'https://example.com/avatar.jpg');
    expect(service.currentUser?.referralCode, 'REFERRAL_CODE_ABC');
    expect(service.currentUser?.isAdmin, isTrue);

    final savedUser = await tokenStorage.readCurrentUser();
    expect(savedUser?.displayName, 'New Name');
    expect((await tokenStorage.readAccessToken()), 'access-token');
    expect((await tokenStorage.readRefreshToken()), 'refresh-token');

    final event = await eventFuture;
    expect(event.type, AuthSessionEventType.userUpdated);
  });

  test('valid local session does not run restore credential authentication',
      () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final restoreCredentials = _FakeRestoreCredentialsService();
    final service = BackendAuthService(
      authApi: _FakeAuthApi(),
      usersApi: _FakeUsersApi(),
      tokenStorage: tokenStorage,
      restoreCredentialsService: restoreCredentials,
    );

    await service.ensureInitialized();

    expect(service.currentUser?.uid, 'user-1');
    expect(restoreCredentials.getCalls, 0);
  });

  test('no local session restores through Android restore credential',
      () async {
    final authApi = _FakeAuthApi();
    final tokenStorage = TokenStorage();
    final restoreCredentials = _FakeRestoreCredentialsService(
      getResult: const RestoreCredentialResult(
        status: RestoreCredentialStatus.success,
        responseJson: <String, dynamic>{
          'id': 'restore-credential-1',
          'response': <String, dynamic>{
            'clientDataJSON': 'client-data',
          },
        },
      ),
    );
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: tokenStorage,
      restoreCredentialsService: restoreCredentials,
    );

    await service.ensureInitialized();

    expect(authApi.restoreAuthenticationOptionsCalls, 1);
    expect(authApi.restoreAuthenticateCalls, 1);
    expect(service.currentUser?.uid, 'restored-user');
    expect(await tokenStorage.readAccessToken(), 'restore-access-token');
    expect(
        await tokenStorage.readRestoreCredentialId(), 'restore-credential-1');
  });

  test('missing Android restore credential falls back to normal login',
      () async {
    final authApi = _FakeAuthApi();
    final tokenStorage = TokenStorage();
    final restoreCredentials = _FakeRestoreCredentialsService(
      getResult: const RestoreCredentialResult(
        status: RestoreCredentialStatus.notAvailable,
        reason: 'no_credential',
      ),
    );
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: tokenStorage,
      restoreCredentialsService: restoreCredentials,
    );

    await service.ensureInitialized();

    expect(service.currentUser, isNull);
    expect(authApi.restoreAuthenticateCalls, 0);
    expect(await tokenStorage.readAccessToken(), isNull);
  });

  test('successful ordinary login schedules restore credential creation',
      () async {
    final authApi = _FakeAuthApi();
    final tokenStorage = TokenStorage();
    final restoreCredentials = _FakeRestoreCredentialsService(
      createResult: const RestoreCredentialResult(
        status: RestoreCredentialStatus.success,
        responseJson: <String, dynamic>{
          'id': 'created-restore-credential',
        },
      ),
    );
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: tokenStorage,
      restoreCredentialsService: restoreCredentials,
    );

    await service.signIn(email: 'user@example.com', password: 'secret');
    await Future<void>.delayed(Duration.zero);

    expect(authApi.restoreRegistrationOptionsCalls, 1);
    expect(authApi.restoreRegisterCalls, 1);
    expect(
      await tokenStorage.readRestoreCredentialId(),
      'created-restore-credential',
    );
  });

  test('restore credential creation failure does not break login', () async {
    final authApi = _FakeAuthApi();
    final restoreCredentials = _FakeRestoreCredentialsService(
      createResult: const RestoreCredentialResult(
        status: RestoreCredentialStatus.error,
        reason: 'native_error',
      ),
    );
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: TokenStorage(),
      restoreCredentialsService: restoreCredentials,
    );

    final user =
        await service.signIn(email: 'user@example.com', password: 'secret');
    await Future<void>.delayed(Duration.zero);

    expect(user.uid, 'user-1');
    expect(authApi.restoreRegisterCalls, 0);
  });

  test(
      'logout clears restore state and local tokens even if native clear fails',
      () async {
    final authApi = _FakeAuthApi();
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    await tokenStorage.markRestoreCredentialSynced('restore-credential-1');
    final restoreCredentials = _FakeRestoreCredentialsService(
      clearThrows: true,
    );
    final service = BackendAuthService(
      authApi: authApi,
      usersApi: _FakeUsersApi(),
      tokenStorage: tokenStorage,
      restoreCredentialsService: restoreCredentials,
    );

    await service.ensureInitialized();
    await service.signOut();

    expect(restoreCredentials.clearCalls, 1);
    expect(
        authApi.restoreRevokeCredentialIds, contains('restore-credential-1'));
    expect(await tokenStorage.readAccessToken(), isNull);
    expect(await tokenStorage.readRestoreCredentialId(), isNull);
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
  String? lastSignupPhoneReferralCode;
  Object? refreshError;
  Object? meError;
  Map<String, dynamic>? meResponse;
  int meCalls = 0;
  int refreshCalls = 0;
  int failMeCalls = 0;
  Duration meDelay = Duration.zero;
  Duration refreshDelay = Duration.zero;
  int restoreRegistrationOptionsCalls = 0;
  int restoreRegisterCalls = 0;
  int restoreAuthenticationOptionsCalls = 0;
  int restoreAuthenticateCalls = 0;
  final List<String> restoreRevokeCredentialIds = <String>[];

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
    meCalls += 1;
    if (meDelay > Duration.zero) {
      await Future<void>.delayed(meDelay);
    }
    if (failMeCalls > 0) {
      failMeCalls -= 1;
      final error = meError!;
      if (failMeCalls == 0) {
        meError = null;
      }
      throw error;
    }
    if (meError != null) {
      throw meError!;
    }
    return meResponse ??
        <String, dynamic>{
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
    refreshCalls += 1;
    if (refreshDelay > Duration.zero) {
      await Future<void>.delayed(refreshDelay);
    }
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

  @override
  Future<Map<String, dynamic>> signupPhone({
    required String phone,
    required String password,
    required String displayName,
    required String verificationCheckId,
    String referralCode = '',
    String referralId = '',
  }) async {
    lastSignupPhoneReferralCode =
        referralCode.trim().isEmpty ? null : referralCode.trim();
    return <String, dynamic>{
      'auth': <String, dynamic>{
        'access_token': 'access-token',
        'refresh_token': 'refresh-token',
      },
      'user': <String, dynamic>{
        'id': 'user-2',
        'phone': phone,
        'phone_verified': true,
        'display_name': displayName,
        'referral_code': 'OWN_REFERRAL_CODE',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> restoreCredentialRegistrationOptions() async {
    restoreRegistrationOptionsCalls += 1;
    return <String, dynamic>{
      'challenge': 'registration-challenge',
      'rp': <String, dynamic>{'id': 'attamarket.online', 'name': 'ATTA'},
    };
  }

  @override
  Future<Map<String, dynamic>> registerRestoreCredential({
    required Map<String, dynamic> responseJson,
  }) async {
    restoreRegisterCalls += 1;
    return <String, dynamic>{
      'registered': true,
      'credential_id': responseJson['id'] ?? 'registered-credential',
    };
  }

  @override
  Future<Map<String, dynamic>> restoreCredentialAuthenticationOptions() async {
    restoreAuthenticationOptionsCalls += 1;
    return <String, dynamic>{
      'challenge': 'authentication-challenge',
      'rpId': 'attamarket.online',
    };
  }

  @override
  Future<Map<String, dynamic>> authenticateWithRestoreCredential({
    required Map<String, dynamic> responseJson,
  }) async {
    restoreAuthenticateCalls += 1;
    return <String, dynamic>{
      'auth': <String, dynamic>{
        'access_token': 'restore-access-token',
        'refresh_token': 'restore-refresh-token',
      },
      'user': <String, dynamic>{
        'id': 'restored-user',
        'display_name': 'Restored User',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> revokeRestoreCredential({
    String credentialId = '',
  }) async {
    restoreRevokeCredentialIds.add(credentialId);
    return <String, dynamic>{'revoked': 1};
  }
}

class _FakeRestoreCredentialsService extends RestoreCredentialsService {
  _FakeRestoreCredentialsService({
    this.createResult = const RestoreCredentialResult(
      status: RestoreCredentialStatus.notAvailable,
      reason: 'not_configured',
    ),
    this.getResult = const RestoreCredentialResult(
      status: RestoreCredentialStatus.notAvailable,
      reason: 'not_configured',
    ),
    this.clearThrows = false,
  });

  final RestoreCredentialResult createResult;
  final RestoreCredentialResult getResult;
  final bool clearThrows;
  int createCalls = 0;
  int getCalls = 0;
  int clearCalls = 0;

  @override
  bool get isAndroidRuntime => true;

  @override
  Future<RestoreCredentialResult> create(
    Map<String, dynamic> requestJson,
  ) async {
    createCalls += 1;
    return createResult;
  }

  @override
  Future<RestoreCredentialResult> get(Map<String, dynamic> requestJson) async {
    getCalls += 1;
    return getResult;
  }

  @override
  Future<RestoreCredentialResult> clear() async {
    clearCalls += 1;
    if (clearThrows) {
      throw PlatformException(code: 'clear_failed');
    }
    return const RestoreCredentialResult(
      status: RestoreCredentialStatus.success,
    );
  }
}

String _jwtWithExpOffset(Duration offset) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode(<String, dynamic>{
        'exp':
            DateTime.now().toUtc().add(offset).millisecondsSinceEpoch ~/ 1000,
      }),
    ),
  );
  return '$header.$payload.signature';
}

class _FakeUsersApi extends UsersApi {
  _FakeUsersApi()
      : super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );
}

class _RelativeAvatarAuthApi extends _FakeAuthApi {
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
        'avatar_url':
            '/media/object?category=avatars&key=avatars%2Fuser-1%2Fphoto.jpg',
        'updated_at': '2026-06-20T10:00:00.000Z',
      },
    };
  }
}
