import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('streamIsOnline loads presence from Timeweb endpoint', () async {
    final service = PresenceService(
      socketService: _FakeChatSocketService(),
      apiClient: _FakeApiClient(
        onGet: (
          path, {
          queryParameters,
          authorized = false,
          sendAuthIfAvailable = false,
        }) async {
          expect(path, '/presence/user-1');
          expect(authorized, true);
          return <String, dynamic>{
            'userId': 'user-1',
            'isOnline': true,
          };
        },
      ),
    );

    final values = await service.streamIsOnline('user-1').take(2).toList();
    expect(values, <bool>[false, true]);
  });

  test('setOnline and heartbeat use Timeweb socket bridge', () async {
    final socket = _FakeChatSocketService();
    final service = PresenceService(
      socketService: socket,
      apiClient: _FakeApiClient(
        onGet: (
          path, {
          queryParameters,
          authorized = false,
          sendAuthIfAvailable = false,
        }) async {
          return <String, dynamic>{
            'userId': 'user-1',
            'isOnline': false,
          };
        },
      ),
    );

    await service.setOnline(uid: 'user-1', isOnline: true);
    await service.heartbeat('user-1');

    expect(socket.connectCalls, 2);
    expect(socket.lastSetPresence, true);
    expect(socket.pingCalls, 1);
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    required this.onGet,
  }) : super(tokenStorage: TokenStorage());

  final Future<dynamic> Function(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authorized,
    bool sendAuthIfAvailable,
  }) onGet;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authorized = false,
    bool sendAuthIfAvailable = false,
  }) {
    return onGet(
      path,
      queryParameters: queryParameters,
      authorized: authorized,
      sendAuthIfAvailable: sendAuthIfAvailable,
    );
  }
}

class _FakeChatSocketService extends ChatSocketService {
  _FakeChatSocketService();

  final StreamController<PresenceSnapshot> _presenceController =
      StreamController<PresenceSnapshot>.broadcast();
  int connectCalls = 0;
  int pingCalls = 0;
  bool? lastSetPresence;

  @override
  Stream<PresenceSnapshot> get presenceUpdates => _presenceController.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  Future<void> setPresence(bool isOnline) async {
    lastSetPresence = isOnline;
  }

  @override
  Future<void> ping() async {
    pingCalls++;
  }
}
