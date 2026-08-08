import 'dart:async';

import 'package:atta/src/services/api/admin_api.dart';
import 'package:atta/src/services/api/api_client.dart';
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

  test('block mutations accept successful 201 responses without body',
      () async {
    final storage = TokenStorage();
    await storage.saveSession(
      accessToken: 'admin-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'admin-1', isAdmin: true),
    );
    final httpClient = _EmptyCreatedHttpClient();
    final api = AdminApi(
      ApiClient(
        tokenStorage: storage,
        httpClient: httpClient,
      ),
    );

    await expectLater(
      api.blockUser('user-1', duration: '7d', reason: 'spam'),
      completion(containsPair('ok', true)),
    );
    await expectLater(
      api.unblock('block-1', reason: 'appeal accepted'),
      completion(containsPair('ok', true)),
    );
    await expectLater(
      api.updateBlock('block-1', permanent: true, reason: 'repeat violation'),
      completion(containsPair('ok', true)),
    );

    expect(httpClient.paths, <String>[
      '/admin/users/user-1/block',
      '/admin/blocks/block-1/unblock',
      '/admin/blocks/block-1',
    ]);
  });
}

class _EmptyCreatedHttpClient extends http.BaseClient {
  final List<String> paths = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    paths.add(request.url.path);
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      201,
      headers: const <String, String>{
        'content-type': 'application/json',
      },
    );
  }
}
