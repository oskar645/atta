import 'dart:async';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/notifications_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/push_notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/push');
  const events = MethodChannel('atta/push_notification_taps');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (_) async => null);
  });
  test(
      'same device token registers again for B and late token result A is discarded',
      () async {
    final storage = TokenStorage();
    Future<void> login(String id) async {
      storage.beginSessionChange();
      await storage.saveSession(
          accessToken: '$id-access',
          refreshToken: '$id-refresh',
          currentUser: AuthUser(uid: id));
    }

    final api = _DevicesApi(storage);
    final tokenA = Completer<String>();
    var requests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestToken') {
        requests++;
        return requests == 1 ? tokenA.future : 'same-device-token';
      }
      return null;
    });
    final service = PushNotificationService(
        channel: channel, platformSupported: true, tokenStorage: storage);
    await login('A');
    final bindingA = service.bindForUser(api: api, userId: 'A');
    await Future<void>.delayed(Duration.zero);
    await service.unbind(api: api);
    await login('B');
    await service.bindForUser(api: api, userId: 'B');
    tokenA.complete('same-device-token');
    await bindingA;
    expect(api.registered, ['B']);
    await service.unbind(api: api);
    expect(api.unregistered, ['B']);
    await login('A');
    await service.bindForUser(api: api, userId: 'A');
    expect(api.registered, ['B', 'A']);
    await service.dispose();
  });

  test('push switch defaults on and stays off for the same user', () async {
    final storage = TokenStorage();
    storage.beginSessionChange();
    await storage.saveSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      currentUser: const AuthUser(uid: 'A'),
    );
    final api = _DevicesApi(storage);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestToken') return 'device-token';
      return null;
    });
    final service = PushNotificationService(
      channel: channel,
      platformSupported: true,
      tokenStorage: storage,
    );
    expect(await service.isEnabledForUser('A'), true);
    await service.bindForUser(api: api, userId: 'A');
    expect(api.registered, ['A']);
    await service.setEnabledForUser(api: api, userId: 'A', enabled: false);
    expect(api.unregistered, ['A']);
    await service.bindForUser(api: api, userId: 'A');
    expect(api.registered, ['A']);
    expect(await service.isEnabledForUser('A'), false);
    expect(await service.isEnabledForUser('B'), true);
    await service.setEnabledForUser(api: api, userId: 'A', enabled: true);
    expect(api.registered, ['A', 'A']);
    await service.dispose();
  });
}

class _DevicesApi extends NotificationsApi {
  _DevicesApi(this.storage) : super(ApiClient(tokenStorage: storage));
  final TokenStorage storage;
  final registered = <String>[];
  final unregistered = <String>[];
  bool enabled = true;

  @override
  Future<bool> getPushPreference(String userId) async => enabled;

  @override
  Future<bool> setPushPreference(String userId, bool value) async {
    enabled = value;
    return enabled;
  }

  @override
  Future<Map<String, dynamic>> registerDevice(
      {required String token,
      required String platform,
      String deviceUid = '',
      String appVersion = '',
      String buildNumber = '',
      String locale = ''}) async {
    registered.add((await storage.readCurrentUser())!.uid);
    return {};
  }

  @override
  Future<Map<String, dynamic>> unregisterDevice({required String token}) async {
    unregistered.add((await storage.readCurrentUser())!.uid);
    return {};
  }
}
