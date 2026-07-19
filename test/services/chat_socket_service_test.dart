import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('expected websocket close errors are treated as benign', () {
    expect(
      ChatSocketService.isExpectedSocketCloseError(
        _FakeWebSocketConnectionClosed(),
      ),
      isTrue,
    );
    expect(
      ChatSocketService.isExpectedSocketCloseError(
        Exception('Connection Closed'),
      ),
      isTrue,
    );
    expect(
      ChatSocketService.isExpectedSocketCloseError(
        Exception('socket timeout'),
      ),
      isFalse,
    );
    expect(
      ChatSocketService.isServerInitiatedDisconnectReason(
        'io server disconnect',
      ),
      isTrue,
    );
  });

  test('connect twice keeps one socket instance', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect();
    await service.connect();

    expect(factory.createdSockets, hasLength(1));
    expect(factory.createdSockets.single.connectCalls, 1);
  });

  test('force reconnect recreates a socket after a network change', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'initial');
    await service.forceReconnect(reason: 'network_changed');

    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.last.connectCalls, 1);
  });

  test('explicit network recovery can retry a server-disconnected socket',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'initial');
    factory.createdSockets.single.emitDisconnect('io server disconnect');

    await service.forceReconnect(reason: 'network_changed');

    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.last.connectCalls, 1);
  });

  test('same skipped connected log is throttled', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'chat.ensureReady');
    await service.connect(reason: 'chat.ensureReady');
    await service.connect(reason: 'chat.ensureReady');
    await service.connect(reason: 'chat.ensureReady');

    expect(
      service.debugHistory
          .where(
            (entry) => entry.contains(
              'Socket connect skipped: already connected reason=chat.ensureReady',
            ),
          )
          .length,
      1,
    );
  });

  test('ping when socket connected does not call connect repeatedly', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    await service.ping(reason: 'presence.heartbeat');
    await service.ping(reason: 'presence.heartbeat');
    await service.ping(reason: 'presence.heartbeat');

    expect(factory.createdSockets, hasLength(1));
    expect(factory.createdSockets.single.connectCalls, 1);
  });

  test('concurrent connect calls share one in-flight socket instance',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: false);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    final first = service.connect(reason: 'login');
    final second = service.connect(reason: 'resume');
    await Future<void>.delayed(Duration.zero);

    expect(factory.createdSockets, hasLength(1));
    expect(factory.createdSockets.single.connectCalls, 1);
    expect(
      service.debugHistory.any(
        (entry) => entry.contains('connect already in flight reason=resume'),
      ),
      isTrue,
    );

    factory.createdSockets.single.emitConnect();
    await Future.wait<void>([first, second]);
  });

  test('socket service does not schedule second reconnect timer', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect();
    final socket = factory.createdSockets.single;

    socket.emitDisconnect('network closed');
    socket.emitConnectError(_FakeWebSocketConnectionClosed());

    expect(service.hasPendingReconnect, isTrue);
    expect(service.reconnectScheduleCount, 1);
  });

  test('server initiated disconnect does not schedule reconnect loop',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect();
    final socket = factory.createdSockets.single;

    socket.emitDisconnect('io server disconnect');

    expect(service.hasPendingReconnect, isFalse);
    expect(service.reconnectScheduleCount, 0);
  });

  test(
      'server initiated disconnect sets cooldown and suppresses new connect attempts',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    final socket = factory.createdSockets.single;

    socket.emitDisconnect('io server disconnect');
    await service.connect(reason: 'presence.setOnline');
    await service.connect(reason: 'chat.ensureReady');

    expect(factory.createdSockets, hasLength(1));
    expect(
      service.debugHistory.where(
        (entry) => entry.contains('cooldown after server disconnect'),
      ),
      hasLength(2),
    );
    expect(service.debugHistory.last, contains('reason=chat.ensureReady'));
  });

  test('server disconnect blocks presence heartbeat reconnect attempts',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    final socket = factory.createdSockets.single;

    socket.emitDisconnect('io server disconnect');
    await service.ping(reason: 'presence.heartbeat');
    await service.ping(reason: 'presence.heartbeat');
    await service.ping(reason: 'presence.heartbeat');

    expect(factory.createdSockets, hasLength(1));
    expect(service.hasPendingReconnect, isFalse);
    expect(service.reconnectScheduleCount, 0);
    expect(
      service.debugHistory.any(
        (entry) =>
            entry.contains('server disconnect requires explicit recovery') &&
            entry.contains('reason=presence.heartbeat'),
      ),
      isTrue,
    );
  });

  test('scheduled reconnect preserves the original reason', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.ping(reason: 'presence.heartbeat');

    expect(service.pendingReconnectReason, 'presence.heartbeat');

    await Future<void>.delayed(const Duration(milliseconds: 2200));

    expect(factory.createdSockets, hasLength(1));
    expect(
      service.debugHistory.any(
        (entry) => entry.contains(
          'Socket[1] connect start reason=presence.heartbeat',
        ),
      ),
      isTrue,
    );
    expect(
      service.debugHistory.any((entry) => entry.contains('reason=unspecified')),
      isFalse,
    );
  });

  test('socket service keeps a single heartbeat timer alive', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    await service.connect(reason: 'chat.ensureReady');
    await service.ping(reason: 'presence.heartbeat');
    await service.ping(reason: 'presence.heartbeat');

    expect(service.heartbeatTimerStartCount, 1);
  });

  test('connect registers a single presence.changed listener', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');

    final socket = factory.createdSockets.single;
    expect(socket.listenerCount('presence.changed'), 1);
    expect(socket.listenerCount('user.presence.changed'), 0);
    expect(service.socketListenerCount('presence.changed'), 1);
    expect(
      service.debugHistory.any(
        (entry) => entry.contains(
          'listener registered event=presence.changed count=1',
        ),
      ),
      isTrue,
    );
  });

  test('presence.changed duplicates with same online state are ignored',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );
    final presence = <PresenceSnapshot>[];
    final events = <ChatSocketEvent>[];
    final presenceSub = service.presenceUpdates.listen(presence.add);
    final eventsSub = service.events.listen(events.add);

    await service.connect(reason: 'login');
    final socket = factory.createdSockets.single;
    socket.emitEvent('presence.changed', <String, dynamic>{
      'userId': 'user-1',
      'isOnline': true,
    });
    socket.emitEvent('presence.changed', <String, dynamic>{
      'userId': 'user-1',
      'isOnline': true,
    });
    socket.emitEvent('presence.changed', <String, dynamic>{
      'userId': 'user-1',
      'isOnline': true,
    });
    await Future<void>.delayed(Duration.zero);

    expect(presence, hasLength(1));
    expect(events.where((event) => event.name == 'presence.changed'),
        hasLength(1));
    expect(
      service.debugHistory.any(
        (entry) => entry.contains(
          'Socket presence.changed duplicate ignored user=user-1 online=true',
        ),
      ),
      isTrue,
    );

    await presenceSub.cancel();
    await eventsSub.cancel();
  });

  test('force reconnect removes old presence listener before new one',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    final firstSocket = factory.createdSockets.single;
    await service.forceReconnect(reason: 'presence.resume');

    expect(firstSocket.listenerCount('presence.changed'), 0);
    expect(factory.createdSockets.last.listenerCount('presence.changed'), 1);
  });

  test('normal close during disconnect does not throw uncaught exception',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(
      autoConnect: true,
      disconnectError: _FakeWebSocketConnectionClosed(),
      disposeError: _FakeWebSocketConnectionClosed(),
    );
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect();

    await expectLater(service.disconnect(), completes);
    expect(service.hasPendingReconnect, isFalse);
  });

  test('logout cancels reconnect and clears listeners', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect();
    final socket = factory.createdSockets.single;
    socket.emitDisconnect('network closed');
    expect(service.hasPendingReconnect, isTrue);

    await service.resetSession();

    expect(service.hasPendingReconnect, isFalse);
    expect(socket.clearListenersCalls, greaterThan(0));
  });

  test('login after logout creates only one socket for the new session',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect();
    await service.resetSession();
    await _saveSession(storage);
    await service.connect();

    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.last.connectCalls, 1);
  });
}

Future<void> _saveSession(TokenStorage storage) {
  return storage.saveSession(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    currentUser: const AuthUser(uid: 'user-1'),
  );
}

class _FakeSocketFactory {
  _FakeSocketFactory({
    this.autoConnect = false,
    this.disconnectError,
    this.disposeError,
  });

  final bool autoConnect;
  final Object? disconnectError;
  final Object? disposeError;
  final List<_FakeChatSocketClient> createdSockets = <_FakeChatSocketClient>[];

  ChatSocketClient create(String url, Map<String, dynamic> auth) {
    final socket = _FakeChatSocketClient(
      autoConnect: autoConnect,
      disconnectError: disconnectError,
      disposeError: disposeError,
    );
    createdSockets.add(socket);
    return socket;
  }
}

class _FakeChatSocketClient implements ChatSocketClient {
  _FakeChatSocketClient({
    this.autoConnect = false,
    this.disconnectError,
    this.disposeError,
  });

  final bool autoConnect;
  final Object? disconnectError;
  final Object? disposeError;
  final Map<String, List<void Function(dynamic)>> _eventHandlers =
      <String, List<void Function(dynamic)>>{};
  final List<void Function(dynamic)> _connectHandlers =
      <void Function(dynamic)>[];
  final List<void Function(dynamic)> _disconnectHandlers =
      <void Function(dynamic)>[];
  final List<void Function(dynamic)> _connectErrorHandlers =
      <void Function(dynamic)>[];
  final List<void Function(dynamic)> _errorHandlers =
      <void Function(dynamic)>[];

  int connectCalls = 0;
  int disconnectCalls = 0;
  int disposeCalls = 0;
  int clearListenersCalls = 0;
  bool _connected = false;

  @override
  bool get connected => _connected;

  @override
  void clearListeners() {
    clearListenersCalls += 1;
    _eventHandlers.clear();
    _connectHandlers.clear();
    _disconnectHandlers.clear();
    _connectErrorHandlers.clear();
    _errorHandlers.clear();
  }

  @override
  void connect() {
    connectCalls += 1;
    if (autoConnect) {
      _connected = true;
      for (final handler
          in List<void Function(dynamic)>.from(_connectHandlers)) {
        handler(null);
      }
    }
  }

  @override
  void disconnect() {
    disconnectCalls += 1;
    _connected = false;
    if (disconnectError != null) {
      throw disconnectError!;
    }
    for (final handler
        in List<void Function(dynamic)>.from(_disconnectHandlers)) {
      handler('client disconnect');
    }
  }

  @override
  void dispose() {
    disposeCalls += 1;
    if (disposeError != null) {
      throw disposeError!;
    }
  }

  @override
  void emit(String event, [Map<String, dynamic>? payload]) {}

  void emitConnectError(Object error) {
    for (final handler
        in List<void Function(dynamic)>.from(_connectErrorHandlers)) {
      handler(error);
    }
  }

  void emitConnect() {
    _connected = true;
    for (final handler in List<void Function(dynamic)>.from(_connectHandlers)) {
      handler(null);
    }
  }

  void emitDisconnect(dynamic reason) {
    _connected = false;
    for (final handler
        in List<void Function(dynamic)>.from(_disconnectHandlers)) {
      handler(reason);
    }
  }

  void emitEvent(String event, Object? payload) {
    for (final handler in List<void Function(dynamic)>.from(
        _eventHandlers[event] ?? const [])) {
      handler(payload);
    }
  }

  @override
  void on(String event, void Function(dynamic payload) handler) {
    _eventHandlers.putIfAbsent(event, () => <void Function(dynamic)>[]).add(
          handler,
        );
  }

  @override
  void off(String event) {
    _eventHandlers.remove(event);
  }

  int listenerCount(String event) => _eventHandlers[event]?.length ?? 0;

  @override
  void onConnect(void Function(dynamic payload) handler) {
    _connectHandlers.add(handler);
  }

  @override
  void onConnectError(void Function(dynamic error) handler) {
    _connectErrorHandlers.add(handler);
  }

  @override
  void onDisconnect(void Function(dynamic payload) handler) {
    _disconnectHandlers.add(handler);
  }

  @override
  void onError(void Function(dynamic error) handler) {
    _errorHandlers.add(handler);
  }
}

class _FakeWebSocketConnectionClosed implements Exception {
  @override
  String toString() => 'Connection Closed';
}
