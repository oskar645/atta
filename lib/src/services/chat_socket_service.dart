import 'dart:async';

import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

typedef ChatSocketClientFactory = ChatSocketClient Function(
  String url,
  Map<String, dynamic> auth,
);

abstract class ChatSocketClient {
  bool get connected;

  void connect();

  void disconnect();

  void dispose();

  void emit(String event, [Map<String, dynamic>? payload]);

  void on(String event, void Function(dynamic payload) handler);

  void onConnect(void Function(dynamic payload) handler);

  void onDisconnect(void Function(dynamic payload) handler);

  void onConnectError(void Function(dynamic error) handler);

  void onError(void Function(dynamic error) handler);

  void clearListeners();
}

class _SocketIoChatSocketClient implements ChatSocketClient {
  _SocketIoChatSocketClient({
    required String url,
    required Map<String, dynamic> auth,
  }) : _socket = io.io(
          url,
          io.OptionBuilder()
              .setTransports(['websocket'])
              .disableAutoConnect()
              .disableReconnection()
              .setAuth(auth)
              .build(),
        );

  final io.Socket _socket;

  @override
  bool get connected => _socket.connected;

  @override
  void clearListeners() {
    try {
      (_socket as dynamic).clearListeners();
    } catch (_) {
      // Best-effort cleanup for stale socket instances.
    }
  }

  @override
  void connect() => _socket.connect();

  @override
  void disconnect() => _socket.disconnect();

  @override
  void dispose() => _socket.dispose();

  @override
  void emit(String event, [Map<String, dynamic>? payload]) {
    if (payload == null) {
      _socket.emit(event);
      return;
    }
    _socket.emit(event, payload);
  }

  @override
  void on(String event, void Function(dynamic payload) handler) {
    _socket.on(event, handler);
  }

  @override
  void onConnect(void Function(dynamic payload) handler) {
    _socket.onConnect(handler);
  }

  @override
  void onConnectError(void Function(dynamic error) handler) {
    _socket.onConnectError(handler);
  }

  @override
  void onDisconnect(void Function(dynamic payload) handler) {
    _socket.onDisconnect(handler);
  }

  @override
  void onError(void Function(dynamic error) handler) {
    _socket.onError(handler);
  }
}

class ChatSocketEvent {
  ChatSocketEvent(this.name, this.payload);

  final String name;
  final Map<String, dynamic> payload;
}

class PresenceSnapshot {
  PresenceSnapshot({
    required this.userId,
    required this.isOnline,
    this.lastSeen,
  });

  final String userId;
  final bool isOnline;
  final DateTime? lastSeen;

  factory PresenceSnapshot.fromMap(Map<String, dynamic> map) {
    return PresenceSnapshot(
      userId: (map['userId'] ?? map['user_id'] ?? '').toString(),
      isOnline: map['isOnline'] == true || map['is_online'] == true,
      lastSeen: DateTime.tryParse(
        (map['lastSeen'] ?? map['last_seen'] ?? '').toString(),
      ),
    );
  }
}

class ChatSocketService {
  ChatSocketService({
    TokenStorage? tokenStorage,
    ChatSocketClientFactory? socketFactory,
  })  : _tokenStorage = tokenStorage ?? TokenStorage(),
        _socketFactory = socketFactory ?? _defaultSocketFactory;

  final TokenStorage _tokenStorage;
  final ChatSocketClientFactory _socketFactory;
  final _events = StreamController<ChatSocketEvent>.broadcast();
  final _presence = StreamController<PresenceSnapshot>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final Set<String> _joinedChats = <String>{};

  ChatSocketClient? _socket;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _connecting = false;
  bool _disconnecting = false;
  bool _disconnectRequested = false;
  bool _disposed = false;
  bool _lastConnectionValue = false;
  DateTime? _lastConnectAttemptAt;
  DateTime? _lastFailureLoggedAt;
  DateTime? _serverDisconnectCooldownUntil;
  String? _serverDisconnectCooldownUserId;
  Duration _nextServerDisconnectCooldown = _serverDisconnectCooldownMin;
  String? _socketOwnerUserId;
  String? _reconnectReason;
  String? _reconnectUserId;
  int _reconnectAttempt = 0;
  int _reconnectScheduleCount = 0;
  int _heartbeatTimerStartCount = 0;
  int _socketInstanceSequence = 0;
  int _connectAttemptSequence = 0;
  int? _activeSocketInstanceId;
  Completer<void>? _connectCompleter;
  final List<String> _debugHistory = <String>[];
  final Map<String, DateTime> _lastDebugLogAtByKey = <String, DateTime>{};

  static ChatSocketClient _defaultSocketFactory(
    String url,
    Map<String, dynamic> auth,
  ) {
    return _SocketIoChatSocketClient(url: url, auth: auth);
  }

  static const Duration _connectRetryCooldown = Duration(seconds: 5);
  static const Duration _serverDisconnectCooldownMin = Duration(seconds: 30);
  static const Duration _serverDisconnectCooldownMax = Duration(minutes: 5);
  static const Duration _skipLogThrottle = Duration(seconds: 45);
  static const List<Duration> _reconnectBackoffSteps = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  Stream<ChatSocketEvent> get events => _events.stream;
  Stream<PresenceSnapshot> get presenceUpdates => _presence.stream;
  Stream<bool> get connectionChanges => _connected.stream;
  bool get isConnected => _socket?.connected == true;
  bool get isConnecting => _connectCompleter != null || _connecting;

  static bool isExpectedSocketCloseError(Object error) {
    final type = error.runtimeType.toString();
    if (type == 'WebSocketConnectionClosed') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('websocketconnectionclosed') ||
        message.contains('connection closed');
  }

  @visibleForTesting
  static bool isServerInitiatedDisconnectReason(Object? reason) {
    final normalized = reason?.toString().trim().toLowerCase() ?? '';
    return normalized == 'io server disconnect';
  }

  void _debugLog(String message) {
    if (_debugHistory.length >= 200) {
      _debugHistory.removeAt(0);
    }
    _debugHistory.add(message);
    if (!ApiConfig.useTimewebBackend || !kDebugMode) return;
    debugPrint(message);
  }

  void _debugLogThrottled({
    required String key,
    required String message,
    Duration throttle = _skipLogThrottle,
  }) {
    final now = DateTime.now();
    final lastAt = _lastDebugLogAtByKey[key];
    if (lastAt != null && now.difference(lastAt) < throttle) {
      return;
    }
    _lastDebugLogAtByKey[key] = now;
    _debugLog(message);
  }

  String _stateLabel() {
    if (isConnected) return 'connected';
    if (_connectCompleter != null) return 'connecting';
    if (_disconnecting) return 'disconnecting';
    return 'disconnected';
  }

  bool _isServerDisconnectCooldownActiveFor(String userId) {
    final cooldownUntil = _serverDisconnectCooldownUntil;
    if (cooldownUntil == null) return false;
    if (DateTime.now().isAfter(cooldownUntil)) {
      _serverDisconnectCooldownUntil = null;
      _serverDisconnectCooldownUserId = null;
      return false;
    }
    return _serverDisconnectCooldownUserId == userId;
  }

  void _clearServerDisconnectCooldown() {
    _serverDisconnectCooldownUntil = null;
    _serverDisconnectCooldownUserId = null;
  }

  void _resetServerDisconnectBackoff() {
    _nextServerDisconnectCooldown = _serverDisconnectCooldownMin;
  }

  Duration _consumeServerDisconnectCooldown() {
    final cooldown = _nextServerDisconnectCooldown;
    final nextSeconds =
        (cooldown.inSeconds * 2).clamp(
              _serverDisconnectCooldownMin.inSeconds,
              _serverDisconnectCooldownMax.inSeconds,
            )
            as int;
    _nextServerDisconnectCooldown = Duration(seconds: nextSeconds);
    return cooldown;
  }

  void _cancelReconnectTimer({bool resetReason = true}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (resetReason) {
      _reconnectReason = null;
      _reconnectUserId = null;
    }
  }

  void _completeConnectAttempt() {
    _connecting = false;
    final completer = _connectCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _connectCompleter = null;
  }

  void _logConnectSkip({
    required String reason,
    required String skip,
    required String userId,
  }) {
    final state = _stateLabel();
    _debugLogThrottled(
      key: 'connect-skip|$skip|$reason|$userId|$state',
      message:
          'Socket connect skipped: $skip reason=$reason user=${userId.isEmpty ? "-" : userId} state=$state',
    );
  }

  Future<void> connect({String reason = 'unspecified'}) async {
    if (!ApiConfig.useTimewebBackend || _disposed) {
      return;
    }

    final currentUser = await _tokenStorage.readCurrentUser();
    final userId = currentUser?.uid.trim() ?? '';
    if (userId.isEmpty) {
      _logConnectSkip(
        reason: reason,
        skip: 'missing user',
        userId: userId,
      );
      return;
    }

    if (isConnected && _socketOwnerUserId == userId) {
      _emitConnection(true);
      _logConnectSkip(
        reason: reason,
        skip: 'already connected',
        userId: userId,
      );
      return;
    }
    if (_reconnectTimer != null) {
      _logConnectSkip(
        reason: reason,
        skip: 'reconnect already scheduled',
        userId: userId,
      );
      return;
    }
    if (_disconnecting) {
      _logConnectSkip(
        reason: reason,
        skip: 'disconnect in progress',
        userId: userId,
      );
      return;
    }
    final existingAttempt = _connectCompleter;
    if (existingAttempt != null) {
      _logConnectSkip(
        reason: reason,
        skip: 'connect already in flight',
        userId: userId,
      );
      return existingAttempt.future;
    }
    if (_isServerDisconnectCooldownActiveFor(userId)) {
      final cooldownUntil = _serverDisconnectCooldownUntil!;
      _logConnectSkip(
        reason: reason,
        skip:
            'cooldown after server disconnect until=${cooldownUntil.toIso8601String()}',
        userId: userId,
      );
      return;
    }

    final connectCompleter = Completer<void>();
    _connectCompleter = connectCompleter;
    _connecting = true;
    _disconnecting = false;
    _disconnectRequested = false;
    _cancelReconnectTimer();
    try {
      final lastAttemptAt = _lastConnectAttemptAt;
      if (lastAttemptAt != null &&
          DateTime.now().difference(lastAttemptAt) < _connectRetryCooldown) {
        _logConnectSkip(
          reason: reason,
          skip: 'connect retry cooldown',
          userId: userId,
        );
        _completeConnectAttempt();
        return;
      }

      final token = await _tokenStorage.readAccessToken();
      if (token == null || token.trim().isEmpty) {
        _logConnectSkip(
          reason: reason,
          skip: 'missing access token',
          userId: userId,
        );
        _completeConnectAttempt();
        return;
      }

      final existingSocket = _socket;
      if (existingSocket != null && _socketOwnerUserId == userId) {
        _logConnectSkip(
          reason: reason,
          skip: 'existing socket still present',
          userId: userId,
        );
        _completeConnectAttempt();
        return;
      }
      if (existingSocket != null) {
        _abandonSocket(
          existingSocket,
          reason: 'replace-stale-before-connect',
        );
        _disposeSocket(
          existingSocket,
          debugContext: 'replace-stale-before-connect.dispose',
        );
        _socket = null;
        _activeSocketInstanceId = null;
        _socketOwnerUserId = null;
      }

      _lastConnectAttemptAt = DateTime.now();
      _socketOwnerUserId = userId;
      final socket = _socketFactory(
        ApiConfig.websocketUrl,
        <String, dynamic>{'token': token.trim()},
      );
      final socketInstanceId = ++_socketInstanceSequence;
      final connectAttempt = ++_connectAttemptSequence;
      _debugLog(
        'Socket[$socketInstanceId] connect start reason=$reason user=$userId state=${_stateLabel()} attempt=$connectAttempt',
      );

      socket.onConnect((_) {
        _socket = socket;
        _disconnecting = false;
        _reconnectAttempt = 0;
        _resetServerDisconnectBackoff();
        _activeSocketInstanceId = socketInstanceId;
        _clearServerDisconnectCooldown();
        _debugLog('Socket[$socketInstanceId] connected');
        _emitConnection(true);
        for (final chatId in _joinedChats) {
          _safeEmit('chat.join', {'chatId': chatId});
        }
        _startPing();
        _completeConnectAttempt();
      });
      socket.onDisconnect((socketReason) {
        _handleSocketClosed(
          socket,
          socketInstanceId: socketInstanceId,
          debugContext: 'disconnect',
          details: socketReason,
        );
      });
      socket.onConnectError((error) {
        _logFailedConnection(error);
        _handleSocketClosed(
          socket,
          socketInstanceId: socketInstanceId,
          debugContext: 'connect_error',
          details: error,
        );
      });
      socket.onError((error) {
        _logFailedConnection(error);
      });

      for (final eventName in const [
        'message.new',
        'message.sent',
        'message.delivered',
        'message.read',
        'notification.new',
        'chat.updated',
        'unread.changed',
        'presence.changed',
        'user.presence.changed',
      ]) {
        socket.on(eventName, (payload) {
          final map = payload is Map
              ? Map<String, dynamic>.from(payload)
              : <String, dynamic>{};
          _events.add(ChatSocketEvent(eventName, map));
          if (eventName == 'presence.changed' ||
              eventName == 'user.presence.changed') {
            _presence.add(PresenceSnapshot.fromMap(map));
          }
        });
      }

      _runSocketOperation(
        () => socket.connect(),
        debugContext: 'connect',
        ignoreExpectedCloseError: true,
      );
      _socket = socket;
      _activeSocketInstanceId = socketInstanceId;
      return connectCompleter.future;
    } finally {
      if (_connectCompleter == connectCompleter && connectCompleter.isCompleted) {
        _connectCompleter = null;
      }
    }
  }

  Future<void> disconnect() async {
    if (_disconnecting) {
      return;
    }
    _disconnecting = true;
    _disconnectRequested = true;
    _cancelReconnectTimer();
    _reconnectAttempt = 0;
    _stopPing();
    _lastConnectAttemptAt = null;
    _clearServerDisconnectCooldown();
    _resetServerDisconnectBackoff();
    final socket = _socket;
    _socket = null;
    _activeSocketInstanceId = null;
    _socketOwnerUserId = null;
    _emitConnection(false);
    _debugLog('Socket disconnect requested');
    _runSocketOperation(
      () => socket?.clearListeners(),
      debugContext: 'clear-listeners',
      ignoreExpectedCloseError: true,
    );
    _runSocketOperation(
      () => socket?.disconnect(),
      debugContext: 'disconnect',
      ignoreExpectedCloseError: true,
    );
    _disposeSocket(socket, debugContext: 'dispose-after-disconnect');
    _connecting = false;
    _disconnecting = false;
    _completeConnectAttempt();
  }

  Future<void> resetSession() async {
    _joinedChats.clear();
    await disconnect();
  }

  Future<void> reconnect({String reason = 'manual'}) async {
    if (_disposed || _disconnecting) return;
    final currentUser = await _tokenStorage.readCurrentUser();
    final userId = currentUser?.uid.trim() ?? _socketOwnerUserId ?? '';
    if (userId.isEmpty) {
      _logConnectSkip(
        reason: reason,
        skip: 'missing user',
        userId: userId,
      );
      return;
    }
    if (isConnected || _connecting) {
      _logConnectSkip(
        reason: reason,
        skip: 'reconnect ignored because socket is already active',
        userId: _socketOwnerUserId ?? '',
      );
      return;
    }
    if (_reconnectTimer != null) {
      _logConnectSkip(
        reason: reason,
        skip: 'reconnect already scheduled',
        userId: userId,
      );
      return;
    }
    if (_isServerDisconnectCooldownActiveFor(userId)) {
      _logConnectSkip(
        reason: reason,
        skip: 'cooldown after server disconnect',
        userId: userId,
      );
      return;
    }
    _debugLog(
      'Socket reconnect requested reason=$reason user=$userId state=${_stateLabel()}',
    );
    _cancelReconnectTimer();
    _stopPing();
    _runSocketOperation(
      () => _socket?.clearListeners(),
      debugContext: 'reconnect.clear-listeners',
      ignoreExpectedCloseError: true,
    );
    _runSocketOperation(
      () => _socket?.disconnect(),
      debugContext: 'reconnect.disconnect',
      ignoreExpectedCloseError: true,
    );
    _disposeSocket(_socket, debugContext: 'reconnect.dispose');
    _socket = null;
    _activeSocketInstanceId = null;
    _socketOwnerUserId = null;
    _lastConnectAttemptAt = null;
    await connect(reason: reason);
  }

  Future<void> joinChat(String chatId, {String reason = 'chat.join'}) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _joinedChats.add(id);
    await connect(reason: reason);
    _safeEmit('chat.join', {'chatId': id});
  }

  void leaveChat(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _joinedChats.remove(id);
    _safeEmit('chat.leave', {'chatId': id});
  }

  Future<void> setPresence(bool isOnline, {String reason = 'presence.set'}) async {
    if (isConnected) {
      _safeEmit('presence.set', {'isOnline': isOnline});
      return;
    }
    await connect(reason: reason);
    _safeEmit('presence.set', {'isOnline': isOnline});
  }

  Future<void> ping({String reason = 'presence.ping'}) async {
    if (isConnected) {
      _safeEmit('presence.ping');
      return;
    }
    if (isConnecting || _disconnecting || _disconnectRequested || _disposed) {
      _logConnectSkip(
        reason: reason,
        skip: 'ping ignored while socket is not ready',
        userId: _socketOwnerUserId ?? '',
      );
      return;
    }
    final currentUser = await _tokenStorage.readCurrentUser();
    final userId = currentUser?.uid.trim() ?? '';
    if (userId.isEmpty) {
      _logConnectSkip(
        reason: reason,
        skip: 'missing user',
        userId: userId,
      );
      return;
    }
    if (_isServerDisconnectCooldownActiveFor(userId)) {
      _logConnectSkip(
        reason: reason,
        skip: 'cooldown after server disconnect',
        userId: userId,
      );
      return;
    }
    _scheduleReconnect(reason: reason, userId: userId);
  }

  void sendDelivered(String messageId) {
    final id = messageId.trim();
    if (id.isEmpty) return;
    _safeEmit('message.delivered', {'messageId': id});
  }

  void sendRead(String messageId) {
    final id = messageId.trim();
    if (id.isEmpty) return;
    _safeEmit('message.read', {'messageId': id});
  }

  void _startPing() {
    if (_pingTimer != null) {
      return;
    }
    _heartbeatTimerStartCount += 1;
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _safeEmit('presence.ping');
    });
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _logFailedConnection(Object? error) {
    final now = DateTime.now();
    final lastFailureAt = _lastFailureLoggedAt;
    if (lastFailureAt != null &&
        now.difference(lastFailureAt) < _connectRetryCooldown) {
      return;
    }
    _lastFailureLoggedAt = now;
    _debugLog('Socket connect_error: ${error.toString()}');
  }

  void _emitConnection(bool value) {
    if (_lastConnectionValue == value) return;
    _lastConnectionValue = value;
    _connected.add(value);
  }

  void _scheduleReconnect({
    String reason = 'auto',
    required String userId,
  }) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      _logConnectSkip(
        reason: reason,
        skip: 'missing user',
        userId: normalizedUserId,
      );
      return;
    }
    if (_reconnectTimer != null || _disconnectRequested || _disposed) {
      return;
    }
    if (isConnected || isConnecting || _disconnecting) {
      _logConnectSkip(
        reason: reason,
        skip: 'reconnect ignored because socket is already active',
        userId: normalizedUserId,
      );
      return;
    }
    if (_isServerDisconnectCooldownActiveFor(normalizedUserId)) {
      _logConnectSkip(
        reason: reason,
        skip: 'cooldown after server disconnect',
        userId: normalizedUserId,
      );
      return;
    }
    final delay = _reconnectBackoffSteps[
        _reconnectAttempt.clamp(0, _reconnectBackoffSteps.length - 1)];
    final attemptNumber = _reconnectAttempt + 1;
    if (_reconnectAttempt < _reconnectBackoffSteps.length - 1) {
      _reconnectAttempt += 1;
    }
    _reconnectScheduleCount += 1;
    _reconnectReason = reason;
    _reconnectUserId = normalizedUserId;
    _debugLog(
      'Socket reconnect scheduled in ${delay.inSeconds}s attempt=$attemptNumber reason=$reason',
    );
    _reconnectTimer = Timer(delay, () async {
      final scheduledReason = _reconnectReason ?? reason;
      final scheduledUserId = _reconnectUserId ?? normalizedUserId;
      _cancelReconnectTimer();
      if (_disconnectRequested || _disposed || isConnected || _connecting) {
        return;
      }
      if (_isServerDisconnectCooldownActiveFor(scheduledUserId)) {
        _logConnectSkip(
          reason: scheduledReason,
          skip: 'cooldown after server disconnect',
          userId: scheduledUserId,
        );
        return;
      }
      _lastConnectAttemptAt = null;
      await connect(reason: scheduledReason);
    });
  }

  void _safeEmit(String event, [Map<String, dynamic>? payload]) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      return;
    }
    try {
      socket.emit(event, payload);
    } catch (error) {
      if (identical(_socket, socket)) {
        _socket = null;
        _activeSocketInstanceId = null;
      }
      _emitConnection(false);
      _logFailedConnection(error);
      _abandonSocket(socket, reason: 'emit:$event');
      if (!_disconnectRequested && !_disposed) {
        _scheduleReconnect(
          reason: 'emit:$event',
          userId: _socketOwnerUserId ?? '',
        );
      }
    }
  }

  void _disposeSocket(
    ChatSocketClient? socket, {
    required String debugContext,
  }) {
    if (socket == null) return;
    _runSocketOperation(
      () => socket.clearListeners(),
      debugContext: '$debugContext.clear-listeners',
      ignoreExpectedCloseError: true,
    );
    _runSocketOperation(
      () => socket.dispose(),
      debugContext: debugContext,
      ignoreExpectedCloseError: true,
    );
  }

  void _abandonSocket(
    ChatSocketClient socket, {
    required String reason,
  }) {
    _runSocketOperation(
      () => socket.clearListeners(),
      debugContext: 'abandon:$reason',
      ignoreExpectedCloseError: true,
    );
  }

  void _handleSocketClosed(
    ChatSocketClient socket, {
    required int socketInstanceId,
    required String debugContext,
    Object? details,
  }) {
    _stopPing();
    final ownerUserId = _socketOwnerUserId;
    if (identical(_socket, socket)) {
      _socket = null;
      _activeSocketInstanceId = null;
      _socketOwnerUserId = null;
    }
    _emitConnection(false);
    _debugLog(
      'Socket[$socketInstanceId] $debugContext: ${details?.toString() ?? ''}',
    );
    _abandonSocket(socket, reason: debugContext);
    _completeConnectAttempt();
    if (_disconnectRequested || _disposed || _disconnecting) {
      return;
    }
    if (debugContext == 'disconnect' &&
        isServerInitiatedDisconnectReason(details)) {
      _cancelReconnectTimer();
      _reconnectAttempt = 0;
      final cooldown = _consumeServerDisconnectCooldown();
      _serverDisconnectCooldownUntil = DateTime.now().add(cooldown);
      _serverDisconnectCooldownUserId = ownerUserId;
      _debugLog(
        'Socket[$socketInstanceId] reconnect suppressed after server disconnect cooldown=${cooldown.inSeconds}s',
      );
      return;
    }
    _scheduleReconnect(
      reason: debugContext,
      userId: ownerUserId ?? '',
    );
  }

  void _runSocketOperation(
    void Function() action, {
    required String debugContext,
    required bool ignoreExpectedCloseError,
  }) {
    try {
      action();
    } catch (error) {
      if (ignoreExpectedCloseError && isExpectedSocketCloseError(error)) {
        _debugLog('Socket $debugContext ignored expected close: $error');
        return;
      }
      _debugLog('Socket $debugContext soft-failed: $error');
    }
  }

  @visibleForTesting
  bool get hasPendingReconnect => _reconnectTimer != null;

  @visibleForTesting
  bool get isDisconnecting => _disconnecting;

  @visibleForTesting
  int get reconnectScheduleCount => _reconnectScheduleCount;

  @visibleForTesting
  int get heartbeatTimerStartCount => _heartbeatTimerStartCount;

  @visibleForTesting
  String? get pendingReconnectReason => _reconnectReason;

  @visibleForTesting
  List<String> get debugHistory => List<String>.unmodifiable(_debugHistory);
}
