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

  test('timeout shows Russian network or VPN hint', () async {
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
              'Проверьте интернет или VPN, затем попробуйте снова.',
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
