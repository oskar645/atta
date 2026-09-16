import 'dart:async';
import 'dart:convert';

import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const accessTokenKey = 'timeweb_access_token';
  const refreshTokenKey = 'timeweb_refresh_token';
  const currentUserKey = 'timeweb_current_user';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('migrates legacy tokens into secure storage and removes old copies',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      accessTokenKey: 'legacy-access',
      refreshTokenKey: 'legacy-refresh',
    });
    final storage = TokenStorage();

    expect(await storage.readAccessToken(), 'legacy-access');
    expect(await storage.readRefreshToken(), 'legacy-refresh');

    const secureStorage = FlutterSecureStorage();
    expect(await secureStorage.read(key: accessTokenKey), 'legacy-access');
    expect(await secureStorage.read(key: refreshTokenKey), 'legacy-refresh');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(accessTokenKey), isNull);
    expect(prefs.getString(refreshTokenKey), isNull);
  });

  test('already authorized user remains authorized during token migration',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      accessTokenKey: 'legacy-access',
      refreshTokenKey: 'legacy-refresh',
      currentUserKey: jsonEncode(
        const AuthUser(
          uid: 'user-1',
          email: 'user@example.com',
          displayName: 'ATTA User',
        ).toJson(),
      ),
    });
    final storage = TokenStorage();

    final user = await storage.readCurrentUser();
    final accessToken = await storage.readAccessToken();
    final refreshToken = await storage.readRefreshToken();

    expect(user?.uid, 'user-1');
    expect(accessToken, 'legacy-access');
    expect(refreshToken, 'legacy-refresh');
  });

  test('clear removes tokens from secure and legacy storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      accessTokenKey: 'legacy-access',
      refreshTokenKey: 'legacy-refresh',
      currentUserKey: jsonEncode(const AuthUser(uid: 'user-1').toJson()),
    });
    const secureStorage = FlutterSecureStorage();
    await secureStorage.write(key: accessTokenKey, value: 'secure-access');
    await secureStorage.write(key: refreshTokenKey, value: 'secure-refresh');

    await TokenStorage().clear();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(accessTokenKey), isNull);
    expect(prefs.getString(refreshTokenKey), isNull);
    expect(prefs.getString(currentUserKey), isNull);
    expect(await secureStorage.read(key: accessTokenKey), isNull);
    expect(await secureStorage.read(key: refreshTokenKey), isNull);
  });
  test(
      'in-flight A write finishes before B commit; queued stale clear is ignored',
      () async {
    final storage = TokenStorage();
    final generationA = storage.beginSessionChange();
    final started = Completer<void>();
    final release = Completer<void>();
    final oldWrite = storage.mutateSession(generationA, () async {
      started.complete();
      await release.future;
      await storage.saveSession(
          accessToken: 'a',
          refreshToken: 'a',
          currentUser: const AuthUser(uid: 'a'));
    });
    await started.future;
    final generationB = storage.beginSessionChange();
    final newWrite = storage.mutateSession(
        generationB,
        () => storage.saveSession(
            accessToken: 'b',
            refreshToken: 'b',
            currentUser: const AuthUser(uid: 'b')));
    final staleClear = storage.mutateSession(generationA, storage.clear);
    release.complete();
    await Future.wait([oldWrite, newWrite, staleClear]);
    expect((await storage.readCurrentUser())?.uid, 'b');
    expect(await storage.readAccessToken(), 'b');
    expect(await storage.readRefreshToken(), 'b');
  });
}
