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

  test('recoverAfterResume probes socket, sends online, then heartbeat',
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

    expect(socket.recoverAfterResumeCalls, 1);
    expect(socket.lastRecoverAfterResumeReason, 'presence.resume');
    expect(socket.lastSetPresence, true);
    expect(socket.lastSetPresenceReason, 'presence.setOnline');
    expect(socket.pingCalls, 1);
    expect(socket.lastPingReason, 'presence.heartbeat');
    expect(service.peekIsOnline('user-1'), true);
  });

  test('successful socket reconnect refreshes own and tracked presence',
      () async {
    final socket = _FakeChatSocketService()..connected = true;
    final onlineByUser = <String, bool>{
      'user-1': true,
      'user-2': false,
    };
    final api = _FakeApiClient(
      onGet: (
        path, {
        queryParameters,
        authorized = false,
        sendAuthIfAvailable = false,
      }) async {
        final userId = path.split('/').last;
        return <String, dynamic>{
          'userId': userId,
          'isOnline': onlineByUser[userId] ?? false,
        };
      },
    );
    final service = PresenceService(
      socketService: socket,
      apiClient: api,
    );

    await service.setOnline(uid: 'user-1', isOnline: true);
    final values = <bool>[];
    final sub = service.streamIsOnline('user-2').listen(values.add);
    await Future<void>.delayed(Duration.zero);

    onlineByUser['user-2'] = true;
    socket.addConnectionChange(true);
    await Future<void>.delayed(Duration.zero);

    expect(socket.setPresenceCalls, 2);
    expect(socket.lastSetPresence, true);
    expect(socket.lastSetPresenceReason, 'presence.setOnline');
    expect(api.getCalls, greaterThanOrEqualTo(2));
    expect(values, containsAllInOrder(<bool>[false, true]));
    expect(service.peekIsOnline('user-2'), true);

    await sub.cancel();
  });

  test('two clients sync online, offline, and reconnect immediately', () async {
    final hub = _PresenceHub();
    final socketA = _HubChatSocketService(hub, userId: 'user-a')
      ..connected = true;
    final socketB = _HubChatSocketService(hub, userId: 'user-b')
      ..connected = true;
    final api = _FakeApiClient(
      onGet: (
        path, {
        queryParameters,
        authorized = false,
        sendAuthIfAvailable = false,
      }) async {
        final userId = path.split('/').last;
        return <String, dynamic>{
          'userId': userId,
          'isOnline': hub.isOnline(userId),
        };
      },
    );
    final clientA = PresenceService(socketService: socketA, apiClient: api);
    final clientB = PresenceService(socketService: socketB, apiClient: api);

    final aOwnValues = <bool>[];
    final bSeesAValues = <bool>[];
    final ownSub = clientA.streamIsOnline('user-a').listen(aOwnValues.add);
    final peerSub = clientB.streamIsOnline('user-a').listen(bSeesAValues.add);
    await Future<void>.delayed(Duration.zero);

    await clientA.setOnline(uid: 'user-a', isOnline: true);
    await Future<void>.delayed(Duration.zero);

    expect(aOwnValues, containsAllInOrder(<bool>[false, true]));
    expect(bSeesAValues, containsAllInOrder(<bool>[false, true]));
    expect(clientA.peekIsOnline('user-a'), true);
    expect(clientB.peekIsOnline('user-a'), true);

    await clientA.setOnline(uid: 'user-a', isOnline: false);
    await Future<void>.delayed(Duration.zero);

    expect(bSeesAValues, containsAllInOrder(<bool>[false, true, false]));
    expect(clientA.peekIsOnline('user-a'), false);
    expect(clientB.peekIsOnline('user-a'), false);

    await clientA.recoverAfterResume('user-a');
    await Future<void>.delayed(Duration.zero);

    expect(socketA.recoverAfterResumeCalls, 1);
    expect(socketA.pingCalls, 1);
    expect(aOwnValues, containsAllInOrder(<bool>[false, true, false, true]));
    expect(
      bSeesAValues,
      containsAllInOrder(<bool>[false, true, false, true]),
    );
    expect(clientA.peekIsOnline('user-a'), true);
    expect(clientB.peekIsOnline('user-a'), true);

    await ownSub.cancel();
    await peerSub.cancel();
  });

  test('setOnline updates local state before socket emit completes', () async {
    final socket = _FakeChatSocketService()
      ..setPresenceCompleter = Completer<void>();
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

    final future = service.setOnline(uid: 'user-1', isOnline: true);
    await Future<void>.delayed(Duration.zero);

    expect(values, containsAllInOrder(<bool>[false, true]));
    expect(service.peekIsOnline('user-1'), true);

    socket.setPresenceCompleter!.complete();
    await future;
    await sub.cancel();
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
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  int connectCalls = 0;
  int forceReconnectCalls = 0;
  int recoverAfterResumeCalls = 0;
  int pingCalls = 0;
  int setPresenceCalls = 0;
  bool connected = false;
  bool? lastSetPresence;
  String? lastSetPresenceReason;
  String? lastForceReconnectReason;
  String? lastRecoverAfterResumeReason;
  String? lastPingReason;
  Completer<void>? setPresenceCompleter;

  @override
  Stream<PresenceSnapshot> get presenceUpdates => _presenceController.stream;

  @override
  Stream<bool> get connectionChanges => _connectionController.stream;

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
  Future<void> recoverAfterResume({String reason = 'resume'}) async {
    recoverAfterResumeCalls++;
    lastRecoverAfterResumeReason = reason;
  }

  @override
  Future<void> setPresence(bool isOnline,
      {String reason = 'presence.set'}) async {
    setPresenceCalls++;
    lastSetPresence = isOnline;
    lastSetPresenceReason = reason;
    final completer = setPresenceCompleter;
    if (completer != null) {
      await completer.future;
    }
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

  void addConnectionChange(bool connected) {
    this.connected = connected;
    _connectionController.add(connected);
  }
}

class _PresenceHub {
  final List<_HubChatSocketService> _clients = <_HubChatSocketService>[];
  final Map<String, bool> _online = <String, bool>{};

  void register(_HubChatSocketService client) {
    _clients.add(client);
  }

  bool isOnline(String userId) => _online[userId] == true;

  void setPresence(String userId, bool isOnline) {
    _online[userId] = isOnline;
    final snapshot = PresenceSnapshot(userId: userId, isOnline: isOnline);
    for (final client in _clients) {
      client.deliverPresence(snapshot);
    }
  }
}

class _HubChatSocketService extends _FakeChatSocketService {
  _HubChatSocketService(this.hub, {required this.userId}) {
    hub.register(this);
  }

  final _PresenceHub hub;
  final String userId;

  @override
  Future<void> forceReconnect({String reason = 'manual'}) async {
    await super.forceReconnect(reason: reason);
    connected = true;
    addConnectionChange(true);
  }

  @override
  Future<void> setPresence(bool isOnline,
      {String reason = 'presence.set'}) async {
    await super.setPresence(isOnline, reason: reason);
    hub.setPresence(userId, isOnline);
  }

  void deliverPresence(PresenceSnapshot snapshot) {
    _presenceController.add(snapshot);
  }
}
