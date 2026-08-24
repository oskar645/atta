import 'dart:async';
import 'dart:convert';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.configureAuthHandlers();
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

  test('socket.io options force a fresh manager and keep manual reconnect', () {
    final options = ChatSocketService.buildSocketOptionsForTesting(
      <String, dynamic>{'token': 'access-token'},
    );

    expect(options['transports'], <String>['websocket']);
    expect(options['autoConnect'], isFalse);
    expect(options['reconnection'], isFalse);
    expect(options['forceNew'], isTrue);
    expect(options.containsKey('multiplex'), isFalse);
    expect(options['timeout'], 10000);
    expect(options['auth'], <String, dynamic>{'token': 'access-token'});
  });

  test('disconnect then connect creates a fresh socket and manager attempt',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage, accessToken: 'first-token');
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'initial');
    final firstSocket = factory.createdSockets.single;
    await service.disconnect();
    await _saveSession(storage, accessToken: 'second-token');

    await service.connect(reason: 'after-disconnect');

    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.first, same(firstSocket));
    expect(factory.createdSockets.last, isNot(same(firstSocket)));
    expect(factory.createdSockets.last.auth['token'], 'second-token');
    expect(firstSocket.disposeCalls, 1);
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
    expect(
        factory.createdSockets.last, isNot(same(factory.createdSockets.first)));
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

  test('server initiated disconnect schedules first controlled retry',
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

    expect(service.hasPendingReconnect, isTrue);
    expect(service.reconnectScheduleCount, 1);
    expect(
      service.debugHistory.any(
        (entry) => entry.contains(
          'reconnect scheduled after server disconnect delay=1s',
        ),
      ),
      isTrue,
    );
    expect(
      service.debugHistory.any((entry) => entry.contains('cooldown=30s')),
      isFalse,
    );
  });

  test(
      'server initiated disconnect keeps connect non-blocking while retry is scheduled',
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
        (entry) => entry.contains('reconnect already scheduled'),
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
    expect(service.hasPendingReconnect, isTrue);
    expect(service.reconnectScheduleCount, 1);
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

  test('successive server disconnects use 1s 2s 3s retry before normal backoff',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    factory.createdSockets.last.emitDisconnect('io server disconnect');
    expect(
      service.debugHistory.any((entry) => entry.contains('delay=1s')),
      isTrue,
    );

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(factory.createdSockets, hasLength(2));
    factory.createdSockets.last.emitDisconnect('io server disconnect');
    expect(
      service.debugHistory.any((entry) => entry.contains('delay=2s')),
      isTrue,
    );

    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(factory.createdSockets, hasLength(3));
    factory.createdSockets.last.emitDisconnect('io server disconnect');
    expect(
      service.debugHistory.any((entry) => entry.contains('delay=3s')),
      isTrue,
    );

    await Future<void>.delayed(const Duration(milliseconds: 3100));
    expect(factory.createdSockets, hasLength(4));
    factory.createdSockets.last.emitDisconnect('io server disconnect');

    expect(service.hasPendingReconnect, isTrue);
    expect(
      service.debugHistory.any((entry) => entry.contains('normal_backoff')),
      isTrue,
    );
  });

  test('repeated server disconnects keep reconnecting instead of cooldown',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    for (final delay in const <Duration>[
      Duration(milliseconds: 1100),
      Duration(milliseconds: 2100),
      Duration(milliseconds: 3100),
    ]) {
      factory.createdSockets.last.emitDisconnect('io server disconnect');
      await Future<void>.delayed(delay);
    }

    factory.createdSockets.last.emitDisconnect('io server disconnect');
    expect(service.hasPendingReconnect, isTrue);
    expect(
      service.debugHistory.any((entry) => entry.contains('normal_backoff')),
      isTrue,
    );

    await service.forceReconnect(reason: 'presence.resume');
    factory.createdSockets.last.emitDisconnect('io server disconnect');

    expect(
      service.debugHistory.any((entry) => entry.contains('cooldown=')),
      isFalse,
    );
  });

  test('connect waits for auth refresh gate before reading socket token',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final authReady = Completer<void>();
    ApiClient.configureAuthHandlers(
      onAwaitAuthorizedSession: () => authReady.future,
    );
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    final connect = service.connect(reason: 'chat.ensureReady');
    await Future<void>.delayed(Duration.zero);

    expect(factory.createdSockets, isEmpty);

    authReady.complete();
    await connect;

    expect(factory.createdSockets, hasLength(1));
    expect(factory.createdSockets.single.connectCalls, 1);
  });

  test('socket connect reads the current access token', () async {
    final storage = TokenStorage();
    await _saveSession(storage, accessToken: 'old-token');
    await _saveSession(storage, accessToken: 'current-token');
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');

    expect(factory.createdSockets, hasLength(1));
    expect(factory.createdSockets.single.auth['token'], 'current-token');
  });

  test('expired token refreshes before socket connect uses auth token',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage, accessToken: _jwt(expired: true));
    final factory = _FakeSocketFactory(autoConnect: true);
    var refreshCalls = 0;
    ApiClient.configureAuthHandlers(
      onRefreshSession: () async {
        refreshCalls += 1;
        await _saveSession(storage, accessToken: 'fresh-token');
        return true;
      },
      onSessionExpired: () async => storage.clear(),
    );
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');

    expect(refreshCalls, 1);
    expect(factory.createdSockets, hasLength(1));
    expect(factory.createdSockets.single.auth['token'], 'fresh-token');
  });

  test('forceReconnect after network change uses refreshed token', () async {
    final storage = TokenStorage();
    await _saveSession(storage, accessToken: 'initial-token');
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'initial');
    await _saveSession(storage, accessToken: 'network-token');
    await service.forceReconnect(reason: 'network.changed');

    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.first.auth['token'], 'initial-token');
    expect(factory.createdSockets.last.auth['token'], 'network-token');
  });

  test('fresh token is passed to every new socket connect attempt', () async {
    final storage = TokenStorage();
    await _saveSession(storage, accessToken: 'token-1');
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'initial');
    await _saveSession(storage, accessToken: 'token-2');
    await service.forceReconnect(reason: 'vpn.off');
    await _saveSession(storage, accessToken: 'token-3');
    await service.forceReconnect(reason: 'wifi.mobile');

    expect(
      factory.createdSockets.map((socket) => socket.auth['token']),
      <String>['token-1', 'token-2', 'token-3'],
    );
  });

  test('timed out stale attempt is disposed and cannot break new success',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage, accessToken: 'initial-token');
    final factory = _FakeSocketFactory(autoConnect: false);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
      connectAttemptTimeout: const Duration(milliseconds: 1),
    );

    await service.connect(reason: 'initial-timeout');
    final staleSocket = factory.createdSockets.single;

    expect(staleSocket.disposeCalls, 1);
    expect(staleSocket.clearListenersCalls, greaterThan(0));
    expect(service.hasPendingReconnect, isTrue);

    await _saveSession(storage, accessToken: 'network-token');
    final reconnect = service.forceReconnect(reason: 'network.changed');
    await Future<void>.delayed(Duration.zero);
    final nextSocket = factory.createdSockets.last;
    nextSocket.emitConnect();
    await reconnect;

    staleSocket.emitConnect();
    staleSocket.emitConnectError(TimeoutException('late stale error'));

    expect(factory.createdSockets, hasLength(2));
    expect(nextSocket.connected, isTrue);
    expect(service.isConnected, isTrue);
    expect(service.hasPendingReconnect, isFalse);
    expect(nextSocket.auth['token'], 'network-token');
  });

  test('resume recovery reconnect uses current token', () async {
    final storage = TokenStorage();
    await _saveSession(storage, accessToken: 'initial-token');
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'initial');
    factory.createdSockets.single.ackError =
        TimeoutException('stale transport');
    await _saveSession(storage, accessToken: 'resume-token');

    await service.recoverAfterResume(reason: 'presence.resume');

    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.last.auth['token'], 'resume-token');
  });

  test('auth rejection runs one refresh and one clean reconnect', () async {
    final storage = TokenStorage();
    await _saveSession(storage, accessToken: 'stale-token');
    final factory = _FakeSocketFactory(autoConnect: true);
    var refreshCalls = 0;
    ApiClient.configureAuthHandlers(
      onRefreshSession: () async {
        refreshCalls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await _saveSession(storage, accessToken: 'fresh-token');
        return true;
      },
      onSessionExpired: () async => storage.clear(),
    );
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    final connect = service.connect(reason: 'login');
    await Future<void>.delayed(Duration.zero);
    final socket = factory.createdSockets.single;

    socket.emitError(<String, dynamic>{
      'message': 'Access token is invalid or expired',
    });
    socket.emitError(<String, dynamic>{
      'message': 'Access token is invalid or expired',
    });
    socket.emitDisconnect('io server disconnect');
    await connect;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(refreshCalls, 1);
    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.last.auth['token'], 'fresh-token');
    expect(factory.createdSockets.last.connectCalls, 1);
  });

  test('stable connection resets server disconnect retry counter', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    factory.createdSockets.last.emitDisconnect('io server disconnect');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(factory.createdSockets, hasLength(2));

    await Future<void>.delayed(const Duration(milliseconds: 8200));
    factory.createdSockets.last.emitDisconnect('io server disconnect');

    expect(
      service.debugHistory
          .where(
            (entry) => entry.contains(
              'reconnect scheduled after server disconnect delay=1s',
            ),
          )
          .length,
      2,
    );
  });

  test('concurrent resume recoveries share one reconnect attempt', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: true);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    await service.connect(reason: 'login');
    factory.createdSockets.single.ackError =
        TimeoutException('stale transport');

    final first = service.recoverAfterResume(reason: 'presence.resume');
    final second = service.recoverAfterResume(reason: 'chat.handleAppResumed');
    await Future.wait<void>(<Future<void>>[first, second]);

    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.last.connectCalls, 1);
    expect(
      service.debugHistory.any(
        (entry) => entry.contains('Socket recovery joined'),
      ),
      isTrue,
    );
  });

  test('concurrent force reconnect calls share one recovery flow', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: false);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    final firstConnect = service.connect(reason: 'initial');
    await Future<void>.delayed(Duration.zero);
    factory.createdSockets.single.emitConnect();
    await firstConnect;

    final first = service.forceReconnect(reason: 'network.one');
    final second = service.forceReconnect(reason: 'network.two');
    await Future<void>.delayed(Duration.zero);

    expect(service.hasRecoveryInFlight, isTrue);
    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.last.connectCalls, 1);
    expect(
      service.debugHistory.any(
        (entry) => entry.contains('Socket recovery joined reason=network.two'),
      ),
      isTrue,
    );

    factory.createdSockets.last.emitConnect();
    await Future.wait<void>(<Future<void>>[first, second]);

    expect(service.hasRecoveryInFlight, isFalse);
    expect(factory.createdSockets, hasLength(2));
  });

  test('resume and network recovery do not create two replacement sockets',
      () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: false);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    final initial = service.connect(reason: 'initial');
    await Future<void>.delayed(Duration.zero);
    factory.createdSockets.single.emitConnect();
    await initial;

    final network = service.forceReconnect(reason: 'network.changed');
    final resume = service.recoverAfterResume(reason: 'app.resume');
    await Future<void>.delayed(Duration.zero);

    expect(factory.createdSockets, hasLength(2));
    expect(factory.createdSockets.last.connectCalls, 1);

    factory.createdSockets.last.emitConnect();
    await Future.wait<void>(<Future<void>>[network, resume]);

    expect(factory.createdSockets, hasLength(2));
  });

  test('join waits for active recovery before emitting room join', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: false);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    final initial = service.connect(reason: 'initial');
    await Future<void>.delayed(Duration.zero);
    factory.createdSockets.single.emitConnect();
    await initial;

    final reconnect = service.forceReconnect(reason: 'network.changed');
    await Future<void>.delayed(Duration.zero);
    final join = service.joinChat('chat-1', reason: 'network.rejoin');
    await Future<void>.delayed(Duration.zero);

    expect(factory.createdSockets.last.emittedEvents, isEmpty);

    factory.createdSockets.last.emitConnect();
    await Future.wait<void>(<Future<void>>[reconnect, join]);

    expect(factory.createdSockets.last.emittedEvents, contains('chat.join'));
  });

  test('auth rejection suppresses automatic server disconnect retry', () async {
    final storage = TokenStorage();
    await _saveSession(storage);
    final factory = _FakeSocketFactory(autoConnect: false);
    final service = ChatSocketService(
      tokenStorage: storage,
      socketFactory: factory.create,
    );

    final connect = service.connect(reason: 'login');
    await Future<void>.delayed(Duration.zero);
    final socket = factory.createdSockets.single;

    socket.emitError(<String, dynamic>{
      'message': 'Access token is invalid or expired',
    });
    socket.emitDisconnect('io server disconnect');
    await connect;
    await service.connect(reason: 'chat.ensureReady');

    expect(service.hasPendingReconnect, isFalse);
    expect(service.reconnectScheduleCount, 0);
    expect(factory.createdSockets, hasLength(1));
    expect(
      service.debugHistory.any(
        (entry) => entry.contains('server disconnect auth_or_missing_user'),
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

Future<void> _saveSession(
  TokenStorage storage, {
  String accessToken = 'access-token',
}) {
  return storage.saveSession(
    accessToken: accessToken,
    refreshToken: 'refresh-token',
    currentUser: const AuthUser(uid: 'user-1'),
  );
}

String _jwt({required bool expired}) {
  final exp = DateTime.now()
          .toUtc()
          .add(expired ? -const Duration(minutes: 1) : const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000;
  String encode(Map<String, dynamic> value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${encode(<String, dynamic>{'alg': 'none'})}.'
      '${encode(<String, dynamic>{'exp': exp})}.signature';
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
      auth: Map<String, dynamic>.from(auth),
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
    required this.auth,
    this.autoConnect = false,
    this.disconnectError,
    this.disposeError,
  });

  final Map<String, dynamic> auth;
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
  final List<String> emittedEvents = <String>[];
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
  void emit(String event, [Map<String, dynamic>? payload]) {
    emittedEvents.add(event);
  }

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

  void emitError(Object error) {
    for (final handler in List<void Function(dynamic)>.from(_errorHandlers)) {
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
