import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:atta/src/services/presence_service.dart';
import 'package:flutter/material.dart';
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

  test('streamIsOnline does not force socket reconnect for fallback GET',
      () async {
    final socket = _FakeChatSocketService()..connected = true;
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
            'isOnline': true,
          };
        },
      ),
    );

    await service.streamIsOnline('user-1').take(2).toList();

    expect(socket.connectCalls, 0);
  });

  test('setOnline and heartbeat use Timeweb socket bridge', () async {
    final socket = _FakeChatSocketService()..connected = true;
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

    expect(socket.connectCalls, 0);
    expect(socket.lastSetPresence, true);
    expect(socket.lastSetPresenceReason, 'presence.setOnline');
    expect(socket.pingCalls, 1);
    expect(socket.lastPingReason, 'presence.heartbeat');
  });

  test('recoverAfterResume force reconnects, sends online, then heartbeat',
      () async {
    final socket = _FakeChatSocketService()..connected = true;
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

    await service.recoverAfterResume('user-1');

    expect(socket.forceReconnectCalls, 1);
    expect(socket.lastForceReconnectReason, 'presence.resume');
    expect(socket.lastSetPresence, true);
    expect(socket.lastSetPresenceReason, 'presence.setOnline');
    expect(socket.pingCalls, 1);
    expect(socket.lastPingReason, 'presence.heartbeat');
    expect(service.peekIsOnline('user-1'), true);
  });

  test('recoverAfterResume ignores blank user id', () async {
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

    await service.recoverAfterResume(' ');

    expect(socket.forceReconnectCalls, 0);
    expect(socket.lastSetPresence, isNull);
    expect(socket.pingCalls, 0);
  });

  test(
      'presence heartbeat when socket connected does not call connect repeatedly',
      () async {
    final socket = _FakeChatSocketService()..connected = true;
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

    await service.heartbeat('user-1');
    await service.heartbeat('user-1');
    await service.heartbeat('user-1');

    expect(socket.connectCalls, 0);
    expect(socket.pingCalls, 3);
  });

  test('presence heartbeat skips socket ping when disconnected', () async {
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

    await service.heartbeat('user-1');
    await service.heartbeat('user-1');

    expect(socket.connectCalls, 0);
    expect(socket.pingCalls, 0);
  });

  test('presence stream ignores unchanged online state', () async {
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

    final values = <bool>[];
    final sub = service.streamIsOnline('user-1').listen(values.add);
    await Future<void>.delayed(Duration.zero);

    socket.addPresence(userId: 'user-1', isOnline: true);
    socket.addPresence(userId: 'user-1', isOnline: true);
    await Future<void>.delayed(Duration.zero);

    expect(values, <bool>[false, true]);
    await sub.cancel();
  });

  test('presence service keeps a single socket subscription', () async {
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

    final sub = service.streamIsOnline('user-1').listen((_) {});
    await service.heartbeat('user-1');
    await service.recoverAfterResume('user-1');

    expect(socket.presenceListenerCount, 1);
    await sub.cancel();
  });

  test('streamIsOnline returns cached stream for same user', () {
    final service = PresenceService(
      socketService: _FakeChatSocketService(),
      apiClient: _FakeApiClient(
        onGet: (
          path, {
          queryParameters,
          authorized = false,
          sendAuthIfAvailable = false,
        }) async {
          return <String, dynamic>{
            'userId': 'user-1',
            'isOnline': true,
          };
        },
      ),
    );

    expect(
      identical(
        service.streamIsOnline('user-1'),
        service.streamIsOnline('user-1'),
      ),
      isTrue,
    );
  });

  testWidgets(
      'presence stream survives mount unmount remount without exception',
      (tester) async {
    final apiClient = _FakeApiClient(
      onGet: (
        path, {
        queryParameters,
        authorized = false,
        sendAuthIfAvailable = false,
      }) async {
        return <String, dynamic>{
          'userId': 'user-1',
          'isOnline': true,
        };
      },
    );
    final service = PresenceService(
      socketService: _FakeChatSocketService(),
      apiClient: apiClient,
    );

    await tester.pumpWidget(
      MaterialApp(home: _PresenceProbe(service: service)),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(home: _PresenceProbe(service: service)),
    );
    await tester.pumpAndSettle();

    expect(apiClient.getCalls, 2);
    expect(tester.takeException(), isNull);
  });
}

class _PresenceProbe extends StatelessWidget {
  const _PresenceProbe({required this.service});

  final PresenceService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: service.streamIsOnline('user-1'),
      builder: (context, snapshot) => Text('${snapshot.data ?? false}'),
    );
  }
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
  int getCalls = 0;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authorized = false,
    bool sendAuthIfAvailable = false,
  }) {
    getCalls += 1;
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
  int forceReconnectCalls = 0;
  int pingCalls = 0;
  bool connected = false;
  bool? lastSetPresence;
  String? lastSetPresenceReason;
  String? lastForceReconnectReason;
  String? lastPingReason;

  @override
  Stream<PresenceSnapshot> get presenceUpdates => _presenceController.stream;

  int get presenceListenerCount => _presenceController.hasListener ? 1 : 0;

  @override
  bool get isConnected => connected;

  @override
  bool get canSendPresenceHeartbeat => connected;

  @override
  Future<void> connect({String reason = 'unspecified'}) async {
    connectCalls++;
  }

  @override
  Future<void> forceReconnect({String reason = 'manual'}) async {
    forceReconnectCalls++;
    lastForceReconnectReason = reason;
  }

  @override
  Future<void> setPresence(bool isOnline,
      {String reason = 'presence.set'}) async {
    lastSetPresence = isOnline;
    lastSetPresenceReason = reason;
  }

  @override
  Future<void> ping({String reason = 'presence.ping'}) async {
    pingCalls++;
    lastPingReason = reason;
  }

  void addPresence({
    required String userId,
    required bool isOnline,
  }) {
    _presenceController.add(
      PresenceSnapshot(userId: userId, isOnline: isOnline),
    );
  }
}
