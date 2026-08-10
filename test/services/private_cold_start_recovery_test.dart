import 'dart:async';
import 'dart:convert';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/auth_api.dart';
import 'package:atta/src/services/api/chats_api.dart';
import 'package:atta/src/services/api/favorites_api.dart';
import 'package:atta/src/services/api/listings_api.dart';
import 'package:atta/src/services/api/users_api.dart';
import 'package:atta/src/services/api/wallet_api.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/backend_auth_service.dart';
import 'package:atta/src/services/chat_service.dart';
import 'package:atta/src/services/favorites_service.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.configureAuthHandlers();
  });

  test('10 cold starts recover auth and load private REST without socket',
      () async {
    for (var i = 0; i < 10; i++) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = TokenStorage();
      await storage.saveSession(
        accessToken: _jwtWithExpOffset(const Duration(seconds: -30)),
        refreshToken: 'refresh-token-$i',
        currentUser: const AuthUser(uid: 'user-1'),
      );

      final httpClient = _PrivateScreensHttpClient();
      final apiClient = ApiClient(
        tokenStorage: storage,
        httpClient: httpClient,
      );
      final authApi = _RefreshOnlyAuthApi();
      final auth = BackendAuthService(
        authApi: authApi,
        usersApi: UsersApi(apiClient),
        tokenStorage: storage,
      );
      ApiClient.configureAuthHandlers(
        onRefreshSession: auth.refreshSession,
        onSessionExpired: auth.expireSession,
        onAwaitAuthorizedSession: auth.awaitPrivateAuthReady,
      );

      await auth.ensureInitialized();
      expect(auth.currentUser?.uid, 'user-1');

      final favorites = FavoritesService(api: FavoritesApi(apiClient));
      final listings = ListingsService(api: ListingsApi(apiClient));
      final chats = ChatService(api: ChatsApi(apiClient));
      final wallet = WalletService(api: WalletApi(apiClient))
        ..activateSession('user-1');
      final profile = ProfileService(
        tokenStorage: storage,
        usersApi: UsersApi(apiClient),
      );

      await Future.wait<dynamic>([
        auth.awaitPrivateAuthReady(),
        favorites.refreshFavoriteIds('user-1', reason: 'cold_start_test'),
        listings.refreshMyListings('user-1'),
        chats.refreshInbox('user-1'),
        wallet.getWallet(forceRefresh: true),
        profile.getProfile('user-1', forceRefresh: true),
      ]).timeout(const Duration(seconds: 3));

      await auth.awaitPrivateAuthReady().timeout(
            const Duration(milliseconds: 50),
          );
      expect(authApi.refreshCalls, 1);
      expect(authApi.meCalls, 0);
      expect(httpClient.socketConnectAttempts, 0);
      expect(httpClient.callsByPath['/favorites'], 1);
      expect(httpClient.callsByPath['/listings/my'], 1);
      expect(httpClient.callsByPath['/chats'], 1);
      expect(httpClient.callsByPath['/wallet'], 1);
      expect(httpClient.callsByPath['/users/me'], 1);
      expect(httpClient.expiredTokenCalls, 0);
      expect(
        httpClient.calls.every(
          (request) => request.headers['Authorization'] == 'Bearer fresh-token',
        ),
        isTrue,
      );
    }
  });

  test('stale private auth gate is cleared after 20 seconds', () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: _jwtWithExpOffset(const Duration(seconds: -30)),
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final service = BackendAuthService(
      authApi: _HangingRefreshAuthApi(),
      usersApi: UsersApi(ApiClient(tokenStorage: storage)),
      tokenStorage: storage,
    );

    fakeAsync((async) {
      var initialized = false;
      service.ensureInitialized().then((_) => initialized = true);
      async.flushMicrotasks();
      expect(initialized, isTrue);

      Object? error;
      var completed = false;
      service.awaitPrivateAuthReady().then<void>(
        (_) {
          completed = true;
        },
        onError: (Object caught) {
          error = caught;
          completed = true;
        },
      );
      async.elapse(const Duration(seconds: 19, milliseconds: 999));
      expect(completed, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(completed, isTrue);
      expect(
        error,
        isA<ApiException>().having(
          (exception) => exception.code,
          'code',
          'auth_recovery_timeout',
        ),
      );

      var secondWaitCompleted = false;
      service.awaitPrivateAuthReady().then<void>((_) {
        secondWaitCompleted = true;
      });
      async.flushMicrotasks();
      expect(secondWaitCompleted, isTrue);
    });
  });
}

class _RefreshOnlyAuthApi extends AuthApi {
  _RefreshOnlyAuthApi() : super(ApiClient(tokenStorage: TokenStorage()));

  int refreshCalls = 0;
  int meCalls = 0;

  @override
  Future<Map<String, dynamic>> refresh({
    required String refreshToken,
  }) async {
    refreshCalls += 1;
    return <String, dynamic>{
      'auth': <String, dynamic>{
        'access_token': 'fresh-token',
        'refresh_token': 'fresh-refresh-token',
      },
      'user': <String, dynamic>{
        'id': 'user-1',
        'email': 'user@example.com',
        'display_name': 'ATTA User',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> me() async {
    meCalls += 1;
    return <String, dynamic>{
      'user': <String, dynamic>{'id': 'user-1'},
    };
  }
}

class _HangingRefreshAuthApi extends _RefreshOnlyAuthApi {
  @override
  Future<Map<String, dynamic>> refresh({
    required String refreshToken,
  }) {
    refreshCalls += 1;
    return Completer<Map<String, dynamic>>().future;
  }
}

class _PrivateScreensHttpClient extends http.BaseClient {
  final List<http.BaseRequest> calls = <http.BaseRequest>[];
  final Map<String, int> callsByPath = <String, int>{};
  int expiredTokenCalls = 0;
  int socketConnectAttempts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request);
    callsByPath.update(request.url.path, (value) => value + 1,
        ifAbsent: () => 1);
    if (request.headers['Authorization'] == 'Bearer expired-token') {
      expiredTokenCalls += 1;
    }
    final path = request.url.path;
    final body = switch (path) {
      '/favorites' => <String, dynamic>{
          'favorite_ids': ['listing-1']
        },
      '/listings/my' => <String, dynamic>{
          'items': [_listingFixture()],
        },
      '/chats' => <String, dynamic>{'items': <Map<String, dynamic>>[]},
      '/wallet' => _walletFixture(),
      '/users/me' => <String, dynamic>{
          'user': <String, dynamic>{
            'id': 'user-1',
            'email': 'user@example.com',
            'display_name': 'ATTA User',
          },
        },
      _ => <String, dynamic>{'ok': true},
    };
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

Map<String, dynamic> _listingFixture() {
  return <String, dynamic>{
    'id': 'listing-1',
    'owner_id': 'user-1',
    'title': 'Test listing',
    'description': 'Описание',
    'category': 'Авто',
    'subcategory': 'Седан',
    'price': 1000,
    'city': 'Москва',
    'photo_urls': const <String>[],
    'status': 'approved',
    'created_at': '2026-06-20T10:00:00.000Z',
    'published_at': '2026-06-20T10:00:00.000Z',
  };
}

Map<String, dynamic> _walletFixture() {
  return <String, dynamic>{
    'balance': 100,
    'max_balance': 1000,
    'welcome_bonus': 100,
    'daily_bonus_amount': 15,
    'can_claim_daily_bonus': false,
    'days_until_next_accrual': 0,
    'seconds_until_next_accrual': 0,
  };
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
