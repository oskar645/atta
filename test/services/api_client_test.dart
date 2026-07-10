import 'dart:async';
import 'dart:convert';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.configureAuthHandlers();
  });

  test('expired access token refreshes and retries request', () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'expired-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final httpClient = _FakeHttpClient();
    final client = ApiClient(
      tokenStorage: storage,
      httpClient: httpClient,
    );

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

    final response = await client.get('/secure', authorized: true);

    expect(response['ok'], true);
    expect(refreshCalls, 1);
    expect(httpClient.calls, hasLength(2));
    expect(
        httpClient.calls.last.headers['Authorization'], 'Bearer fresh-token');
  });

  test('failed refresh logs out safely', () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'expired-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final client = ApiClient(
      tokenStorage: storage,
      httpClient: _FakeHttpClient(),
    );
    var expiredCalls = 0;

    ApiClient.configureAuthHandlers(
      onRefreshSession: () async => false,
      onSessionExpired: () async {
        expiredCalls += 1;
        await storage.clear();
      },
    );

    await expectLater(
      () => client.get('/secure', authorized: true),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'session_expired',
        ),
      ),
    );
    expect(expiredCalls, 1);
    expect(await storage.readAccessToken(), isNull);
    expect(await storage.readRefreshToken(), isNull);
  });

  test('network error during refresh does not clear session', () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'expired-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final client = ApiClient(
      tokenStorage: storage,
      httpClient: _FakeHttpClient(),
    );
    var expiredCalls = 0;

    ApiClient.configureAuthHandlers(
      onRefreshSession: () async => true,
      onSessionExpired: () async {
        expiredCalls += 1;
        await storage.clear();
      },
    );

    await expectLater(
      () => client.get('/secure', authorized: true),
      throwsA(
        isA<ApiException>().having(
          (e) => e.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
    expect(expiredCalls, 0);
    expect(await storage.readAccessToken(), isNotNull);
    expect(await storage.readRefreshToken(), isNotNull);
  });

  test('concurrent 401 requests share one refresh and both retry', () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'expired-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final httpClient = _FakeHttpClient();
    final client = ApiClient(
      tokenStorage: storage,
      httpClient: httpClient,
    );

    var refreshCalls = 0;
    final refreshCompleter = Completer<void>();
    ApiClient.configureAuthHandlers(
      onRefreshSession: () async {
        refreshCalls += 1;
        await refreshCompleter.future;
        await storage.saveSession(
          accessToken: 'fresh-token',
          refreshToken: 'refresh-token',
          currentUser: const AuthUser(uid: 'user-1'),
        );
        return true;
      },
      onSessionExpired: () async {},
    );

    final first = client.get('/auth/me', authorized: true);
    final second = client.get('/viewed-listings', authorized: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    refreshCompleter.complete();

    final results =
        await Future.wait<dynamic>(<Future<dynamic>>[first, second]);

    expect(refreshCalls, 1);
    expect(results, everyElement(containsPair('ok', true)));
    expect(httpClient.calls, hasLength(4));
    expect(
      httpClient.calls
          .where(
              (call) => call.headers['Authorization'] == 'Bearer fresh-token')
          .length,
      2,
    );
  });

  test('request started during refresh waits for new token before sending',
      () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'expired-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final httpClient = _FakeHttpClient();
    final client = ApiClient(
      tokenStorage: storage,
      httpClient: httpClient,
    );

    var refreshCalls = 0;
    final refreshCompleter = Completer<void>();
    ApiClient.configureAuthHandlers(
      onRefreshSession: () async {
        refreshCalls += 1;
        await refreshCompleter.future;
        await storage.saveSession(
          accessToken: 'fresh-token',
          refreshToken: 'refresh-token',
          currentUser: const AuthUser(uid: 'user-1'),
        );
        return true;
      },
      onSessionExpired: () async {},
    );

    final first = client.get('/secure', authorized: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = client.get('/notifications', authorized: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    refreshCompleter.complete();

    final results =
        await Future.wait<dynamic>(<Future<dynamic>>[first, second]);

    expect(refreshCalls, 1);
    expect(results, everyElement(containsPair('ok', true)));
    expect(httpClient.calls, hasLength(3));
    expect(
      httpClient.calls.where((call) => call.url.path == '/notifications'),
      hasLength(1),
    );
    expect(
      httpClient.calls
          .where(
              (call) => call.headers['Authorization'] == 'Bearer fresh-token')
          .length,
      2,
    );
  });

  test('startup auth gate delays first private request until session is ready',
      () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'fresh-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final httpClient = _FakeHttpClient();
    final client = ApiClient(
      tokenStorage: storage,
      httpClient: httpClient,
    );

    final authReady = Completer<void>();
    ApiClient.configureAuthHandlers(
      onRefreshSession: () async => true,
      onSessionExpired: () async {},
      onAwaitAuthorizedSession: () => authReady.future,
    );

    final request = client.get('/favorites', authorized: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(httpClient.calls, isEmpty);

    authReady.complete();
    final response = await request;

    expect(response['ok'], true);
    expect(httpClient.calls, hasLength(1));
    expect(
      httpClient.calls.single.headers['Authorization'],
      'Bearer fresh-token',
    );
  });

  test('timeout shows Russian network hint', () async {
    final client = ApiClient(
      tokenStorage: TokenStorage(),
      httpClient: _TimeoutHttpClient(),
    );

    await expectLater(
      () => client.get('/slow-endpoint'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'timeout').having(
              (e) => e.message,
              'message',
              'Проверьте интернет-соединение и попробуйте снова.',
            ),
      ),
    );
  });
}

class _FakeHttpClient extends http.BaseClient {
  final List<http.BaseRequest> calls = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request);
    final auth = request.headers['Authorization'];
    final body = auth == 'Bearer fresh-token'
        ? jsonEncode(<String, dynamic>{'ok': true})
        : jsonEncode(<String, dynamic>{'message': 'expired'});
    final statusCode = auth == 'Bearer fresh-token' ? 200 : 401;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      headers: const <String, String>{
        'content-type': 'application/json',
      },
    );
  }
}

class _TimeoutHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Future<http.StreamedResponse>.error(
      TimeoutException('request timed out'),
    );
  }
}
