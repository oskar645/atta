import 'dart:async';

import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

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
  ChatSocketService({TokenStorage? tokenStorage})
      : _tokenStorage = tokenStorage ?? TokenStorage();

  final TokenStorage _tokenStorage;
  final _events = StreamController<ChatSocketEvent>.broadcast();
  final _presence = StreamController<PresenceSnapshot>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final Set<String> _joinedChats = <String>{};

  io.Socket? _socket;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _connecting = false;
  bool _disconnectRequested = false;
  final bool _disposed = false;
  bool _lastConnectionValue = false;
  DateTime? _lastConnectAttemptAt;
  DateTime? _lastFailureLoggedAt;
  int _reconnectAttempt = 0;

  static const Duration _connectRetryCooldown = Duration(seconds: 5);
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

  @visibleForTesting
  static bool isExpectedSocketCloseError(Object error) {
    final type = error.runtimeType.toString();
    if (type == 'WebSocketConnectionClosed') {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('websocketconnectionclosed') ||
        message.contains('connection closed');
  }

  void _debugLog(String message) {
    if (!ApiConfig.useTimewebBackend || !kDebugMode) return;
    debugPrint(message);
  }

  Future<void> connect() async {
    if (!ApiConfig.useTimewebBackend ||
        _disposed ||
        isConnected ||
        _connecting) {
      return;
    }
    final lastAttemptAt = _lastConnectAttemptAt;
    if (lastAttemptAt != null &&
        DateTime.now().difference(lastAttemptAt) < _connectRetryCooldown) {
      return;
    }
    _connecting = true;
    _disconnectRequested = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _lastConnectAttemptAt = DateTime.now();
    try {
      final token = await _tokenStorage.readAccessToken();
      if (token == null || token.trim().isEmpty) return;

      final existingSocket = _socket;
      if (existingSocket != null) {
        if (existingSocket.connected) {
          _emitConnection(true);
          return;
        }
        existingSocket.connect();
        return;
      }

      final socket = io.io(
        ApiConfig.baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .disableReconnection()
            .setAuth({'token': token.trim()})
            .build(),
      );

      socket.onConnect((_) {
        _socket = socket;
        _reconnectAttempt = 0;
        _emitConnection(true);
        for (final chatId in _joinedChats) {
          socket.emit('chat.join', {'chatId': chatId});
        }
        _startPing();
      });
      socket.onDisconnect((_) {
        _stopPing();
        if (identical(_socket, socket)) {
          _socket = null;
        }
        _emitConnection(false);
        if (_disconnectRequested || _disposed) {
          _disposeSocket(socket);
          return;
        }
        _disposeSocket(socket);
        _scheduleReconnect();
      });
      socket.onConnectError((error) {
        _stopPing();
        if (identical(_socket, socket)) {
          _socket = null;
        }
        _emitConnection(false);
        _logFailedConnection(error);
        _disposeSocket(socket);
        if (!_disconnectRequested && !_disposed) {
          _scheduleReconnect();
        }
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

      socket.connect();
      _socket = socket;
    } finally {
      _connecting = false;
    }
  }

  Future<void> disconnect() async {
    _disconnectRequested = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _stopPing();
    final socket = _socket;
    _socket = null;
    _emitConnection(false);
    _runSocketOperation(
      () => socket?.disconnect(),
      debugContext: 'disconnect',
      ignoreExpectedCloseError: true,
    );
    _disposeSocket(socket);
    _connecting = false;
  }

  Future<void> resetSession() async {
    _joinedChats.clear();
    await disconnect();
  }

  Future<void> reconnect() async {
    if (_disposed) return;
    if (isConnected || _connecting) return;
    _runSocketOperation(
      () => _socket?.disconnect(),
      debugContext: 'reconnect.disconnect',
      ignoreExpectedCloseError: true,
    );
    _disposeSocket(_socket);
    _socket = null;
    _lastConnectAttemptAt = null;
    await connect();
  }

  Future<void> joinChat(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _joinedChats.add(id);
    await connect();
    _safeEmit('chat.join', {'chatId': id});
  }

  void leaveChat(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    _joinedChats.remove(id);
    _safeEmit('chat.leave', {'chatId': id});
  }

  Future<void> setPresence(bool isOnline) async {
    await connect();
    _safeEmit('presence.set', {'isOnline': isOnline});
  }

  Future<void> ping() async {
    await connect();
    _safeEmit('presence.ping');
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
    _pingTimer?.cancel();
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

  void _scheduleReconnect() {
    if (_reconnectTimer != null || _disconnectRequested || _disposed) {
      return;
    }
    final delay = _reconnectBackoffSteps[
        _reconnectAttempt.clamp(0, _reconnectBackoffSteps.length - 1)];
    if (_reconnectAttempt < _reconnectBackoffSteps.length - 1) {
      _reconnectAttempt += 1;
    }
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_disconnectRequested || _disposed || isConnected || _connecting) {
        return;
      }
      _lastConnectAttemptAt = null;
      await connect();
    });
  }

  void _safeEmit(String event, [Map<String, dynamic>? payload]) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      return;
    }
    try {
      if (payload == null) {
        socket.emit(event);
      } else {
        socket.emit(event, payload);
      }
    } catch (error) {
      if (identical(_socket, socket)) {
        _socket = null;
      }
      _emitConnection(false);
      _logFailedConnection(error);
      _disposeSocket(socket);
      if (!_disconnectRequested && !_disposed) {
        _scheduleReconnect();
      }
    }
  }

  void _disposeSocket(io.Socket? socket) {
    _runSocketOperation(
      () => socket?.dispose(),
      debugContext: 'dispose',
      ignoreExpectedCloseError: true,
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
      rethrow;
    }
  }
}
