import 'dart:async';

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

  test('heartbeat does not call connect when server-disconnected', () async {
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
      service.debugHistory.where(
        (entry) => entry.contains('reason=presence.heartbeat'),
      ),
      isEmpty,
    );
  });

  test('heartbeat does not create an infinite skipped-connect log loop',
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

    expect(
      service.debugHistory.where(
        (entry) =>
            entry.contains('Socket connect skipped') &&
            entry.contains('reason=presence.heartbeat'),
      ),
      isEmpty,
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

    await service.ping(reason: 'presence.ping');

    expect(service.pendingReconnectReason, 'presence.ping');

    await Future<void>.delayed(const Duration(milliseconds: 2200));

    expect(factory.createdSockets, hasLength(1));
    expect(
      service.debugHistory.any(
        (entry) => entry.contains(
          'Socket[1] connect start reason=presence.ping',
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
    expect(service.hasHeartbeatTimer, isTrue);
  });

  test('explicit recovery restores socket after server disconnect', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    factory.createdSockets.single.emitDisconnect('io server disconnect');

    await service.forceReconnect(reason: 'presence.resume');

    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.last.connected, isTrue);
    expect(factory.createdSockets.last.connectCalls, 1);
  });

  test('successful reconnect starts heartbeat again', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    expect(service.heartbeatTimerStartCount, 1);
    factory.createdSockets.single.emitDisconnect('io server disconnect');
    expect(service.hasHeartbeatTimer, isFalse);

    await service.forceReconnect(reason: 'presence.resume');

    expect(service.heartbeatTimerStartCount, 2);
    expect(service.hasHeartbeatTimer, isTrue);
  });

  test('app resume recovery keeps one active heartbeat timer', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    await service.forceReconnect(reason: 'presence.resume');

    expect(service.hasHeartbeatTimer, isTrue);
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

  test('force reconnect restores realtime listeners once', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    final firstSocket = factory.createdSockets.single;
    await service.forceReconnect(reason: 'chat.handleAppResumed');
    final nextSocket = factory.createdSockets.last;

    for (final event in const <String>[
      'message.new',
      'message.sent',
      'unread.changed',
      'presence.changed',
    ]) {
      expect(firstSocket.listenerCount(event), 0);
      expect(nextSocket.listenerCount(event), 1);
      expect(service.socketListenerCount(event), 1);
    }
  });

  test('resume probe recreates stale socket even when connected is true',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'initial');
    final firstSocket = factory.createdSockets.single
      ..ackError = TimeoutException('stale transport');

    await service.recoverAfterResume(reason: 'presence.resume');

    expect(firstSocket.emitWithAckCalls, 1);
    expect(firstSocket.clearListenersCalls, greaterThan(0));
    expect(firstSocket.disposeCalls, 1);
    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.last.connected, isTrue);
    expect(
      service.debugHistory.any(
        (entry) => entry.contains('transport probe result=false'),
      ),
      isTrue,
    );
  });

  test('connect recreates stale same-user socket before retry cooldown',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'initial');
    final firstSocket = factory.createdSockets.single;
    firstSocket.setConnectedForTest(false);

    await service.connect(reason: 'chat.ensureReady');

    expect(factory.createdSockets, hasLength(2));
    expect(firstSocket.clearListenersCalls, greaterThan(0));
    expect(firstSocket.disposeCalls, 1);
    expect(factory.createdSockets.last.connectCalls, 1);
    expect(
      service.debugHistory.any(
        (entry) => entry.contains('Socket stale instance replaced'),
      ),
      isTrue,
    );
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
  int emitWithAckCalls = 0;
  bool ackEnabled = true;
  Object? ackError;
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

  @override
  Future<dynamic> emitWithAck(
    String event, [
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 3),
  ]) async {
    emitWithAckCalls += 1;
    if (ackError != null) {
      throw ackError!;
    }
    if (!ackEnabled) {
      return Completer<dynamic>().future;
    }
    return <String, dynamic>{'ok': true};
  }

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

  void setConnectedForTest(bool value) {
    _connected = value;
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
