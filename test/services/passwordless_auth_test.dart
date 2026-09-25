import 'package:atta/src/services/auth/pending_passwordless_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:convert';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/auth_api.dart';
import 'package:atta/src/services/api/users_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/backend_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const payload = {
  'auth': {
    'access_token': 'access-passwordless',
    'refresh_token': 'refresh-passwordless'
  },
  'user': {
    'id': 'original-user',
    'display_name': 'Анна',
    'phone': '79281234567'
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiClient.configureAuthHandlers();
  });

  test('passwordless start forwards invite only at challenge creation',
      () async {
    final client = ApiClient(
        tokenStorage: TokenStorage(),
        httpClient: MockClient((request) async {
          expect(request.url.path, endsWith('/auth/passwordless/start'));
          expect(jsonDecode(request.body), {
            'phone': '79281234567',
            'referralCode': 'invite',
            'referralId': 'open-id',
          });
          return http.Response('{}', 200);
        }));
    final backend = BackendAuthService(
        authApi: AuthApi(client),
        usersApi: UsersApi(client),
        tokenStorage: TokenStorage());
    await backend.startPasswordless(
        phone: '79281234567',
        referralCode: ' invite ',
        referralId: ' open-id ');
  });

  test(
      'recovery email reconciles a lost first response without duplicate semantics',
      () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    var requests = 0;
    final client = ApiClient(
      tokenStorage: storage,
      httpClient: MockClient((request) async {
        requests++;
        expect(request.url.path, '/auth/recovery-email/start');
        expect(jsonDecode(request.body), {'email': 'member@example.com'});
        if (requests == 1) throw http.ClientException('lost response');
        return http.Response(
            jsonEncode({
              'challengeId': 'same-challenge',
              'maskedEmail': 'm***@example.com',
              'expiresIn': 600,
              'resendAfter': 60,
            }),
            200,
            headers: {'content-type': 'application/json'});
      }),
    );

    final result =
        await AuthApi(client).startRecoveryEmail(' member@example.com ');

    expect(requests, 2);
    expect(result['challengeId'], 'same-challenge');
  });

  for (final registration in [false, true]) {
    test(
        'passwordless registration=$registration uses exact API contract and existing token storage/events',
        () async {
      await PendingPasswordlessStorage().save({
        'challenge': 'challenge',
        'phone': '79281234567',
        'callToPhone': '78005553535',
        'expiresAt':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      });
      final requests = <http.Request>[];
      final storage = TokenStorage();
      final client = ApiClient(
          tokenStorage: storage,
          httpClient: MockClient((request) async {
            requests.add(request);
            final path = request.url.path;
            final response = path.endsWith('/start')
                ? {
                    'status': 'pending',
                    'challenge': 'challenge',
                    'callToPhone': '78005553535',
                    'expiresAt': DateTime.now()
                        .add(const Duration(minutes: 5))
                        .toIso8601String()
                  }
                : path.endsWith('/check') && registration
                    ? {
                        'status': 'registration_required',
                        'registrationToken': 'registration',
                        'expiresAt': DateTime.now()
                            .add(const Duration(minutes: 2))
                            .toIso8601String()
                      }
                    : payload;
            return http.Response(jsonEncode(response), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }));
      final backend = BackendAuthService(
          authApi: AuthApi(client),
          usersApi: UsersApi(client),
          tokenStorage: storage);
      final events = <AuthSessionEventType>[];
      final sub =
          backend.onAuthStateChange.listen((event) => events.add(event.type));
      final start = await backend.startPasswordless(phone: '79281234567');
      final check = await backend.checkPasswordless(
          challenge: start['challenge'] as String, isActive: () => true);
      if (registration) {
        expect(backend.currentUser, isNull);
        await backend.completePasswordless(
            registrationToken: check['registrationToken'] as String,
            displayName: ' Анна ',
            acceptedLegal: true,
            acceptedPersonalData: true,
            isActive: () => true);
      }
      await Future<void>.delayed(Duration.zero);
      expect(await PendingPasswordlessStorage().read(), isNull);
      expect(backend.currentUser?.uid, 'original-user');
      expect(await storage.readAccessToken(), 'access-passwordless');
      expect(await storage.readRefreshToken(), 'refresh-passwordless');
      expect((await storage.readCurrentUser())?.uid, 'original-user');
      expect(events, [AuthSessionEventType.signedIn]);
      // The ordinary consume path may also schedule Android restore sync.
      final authRequests = requests
          .where((r) => r.url.path.startsWith('/auth/passwordless/'))
          .toList();
      expect(authRequests.map((r) => r.url.path), [
        '/auth/passwordless/start',
        '/auth/passwordless/check',
        if (registration) '/auth/passwordless/complete',
      ]);
      expect(jsonDecode(authRequests[0].body), {'phone': '79281234567'});
      expect(jsonDecode(authRequests[1].body), {'challenge': 'challenge'});
      for (final request in authRequests) {
        expect(request.method, 'POST');
        expect(request.headers.containsKey('authorization'), false);
        expect(jsonDecode(request.body), isNot(contains('password')));
      }
      if (registration) {
        final body = jsonDecode(authRequests.last.body) as Map;
        expect(body['displayName'], 'Анна');
        expect(body['registrationToken'], 'registration');
        expect(body['acceptedLegal'], true);
        expect(body['acceptedPersonalData'], true);
        expect(body.containsKey('phone'), false);
      }
      await sub.cancel();
    });
  }

  for (final complete in [false, true]) {
    test(
        'late ${complete ? 'complete' : 'check'} after cancellation never stores auth',
        () async {
      final storage = TokenStorage();
      final response = Completer<http.Response>();
      final client = ApiClient(
          tokenStorage: storage,
          httpClient: MockClient((_) => response.future));
      final backend = BackendAuthService(
          authApi: AuthApi(client),
          usersApi: UsersApi(client),
          tokenStorage: storage);
      var active = true;
      final pending = complete
          ? backend.completePasswordless(
              registrationToken: 'registration',
              displayName: 'Анна',
              acceptedLegal: true,
              acceptedPersonalData: true,
              isActive: () => active)
          : backend.checkPasswordless(
              challenge: 'challenge', isActive: () => active);
      active = false;
      response.complete(http.Response(jsonEncode(payload), 200,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      await pending;
      expect(backend.currentUser, isNull);
      expect(await storage.readCurrentUser(), isNull);
    });
  }

  test('late auth response cannot restore session after logout', () async {
    final storage = TokenStorage();
    final response = Completer<http.Response>();
    final client = ApiClient(
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/check')) return response.future;
          return http.Response('{}', 200);
        }));
    final backend = BackendAuthService(
        authApi: AuthApi(client),
        usersApi: UsersApi(client),
        tokenStorage: storage);
    final pending =
        backend.checkPasswordless(challenge: 'challenge', isActive: () => true);
    await backend.signOut();
    response.complete(http.Response(jsonEncode(payload), 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await pending;
    expect(backend.currentUser, isNull);
    expect(await storage.readCurrentUser(), isNull);
  });

  for (final complete in [false, true]) {
    test(
        'malformed auth from ${complete ? 'complete' : 'check'} cannot overwrite tokens',
        () async {
      final storage = TokenStorage();
      await storage.saveSession(
          accessToken: 'old-access',
          refreshToken: 'old-refresh',
          currentUser: const AuthUser(uid: 'old-user'));
      final client = ApiClient(
          tokenStorage: storage,
          httpClient: MockClient((_) async =>
              http.Response('{"auth":{},"user":{"id":"new-user"}}', 200)));
      final backend = BackendAuthService(
          authApi: AuthApi(client),
          usersApi: UsersApi(client),
          tokenStorage: storage);
      final pending = complete
          ? backend.completePasswordless(
              registrationToken: 'registration',
              displayName: 'Anna',
              acceptedLegal: true,
              acceptedPersonalData: true,
              isActive: () => true)
          : backend.checkPasswordless(
              challenge: 'challenge', isActive: () => true);
      await expectLater(pending, throwsA(isA<ApiException>()));
      expect(await storage.readAccessToken(), 'old-access');
      expect(await storage.readRefreshToken(), 'old-refresh');
      expect((await storage.readCurrentUser())?.uid, 'old-user');
    });
  }

  for (final header in ['70', 'invalid']) {
    test(
        'Retry-After $header is exposed without losing existing API error code',
        () async {
      final client = ApiClient(
          tokenStorage: TokenStorage(),
          httpClient: MockClient((_) async => http.Response(
              '{"code":"RATE_LIMIT","message":"limited"}', 429,
              headers: {'retry-after': header})));
      await expectLater(
          AuthApi(client).checkPasswordless(challenge: 'challenge'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', 429)
                .having((e) => e.code, 'code', 'RATE_LIMIT')
                .having((e) => e.retryAfter, 'retryAfter',
                    header == '70' ? const Duration(seconds: 70) : null),
          ));
    });
  }
}
