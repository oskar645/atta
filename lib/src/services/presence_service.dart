import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:flutter/foundation.dart';

class PresenceService {
  PresenceService({
    ChatSocketService? socketService,
    ApiClient? apiClient,
  })  : _socketService = socketService,
        _apiClient = apiClient ?? ApiClient(tokenStorage: _tokenStorage);

  final ChatSocketService? _socketService;
  final ApiClient _apiClient;
  static final TokenStorage _tokenStorage = TokenStorage();

  StreamSubscription<PresenceSnapshot>? _presenceSub;
  final Map<String, bool> _presenceMap = {};
  final Map<String, StreamController<bool>> _controllers = {};
  final Map<String, Stream<bool>> _streams = {};
  final Map<String, DateTime> _lastFetchAt = {};
  final Map<String, Future<void>> _presenceFetchInFlight = {};

  static const Duration _fallbackPresenceTtl = Duration(minutes: 1);

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  StreamController<bool> _controllerFor(String uid) {
    return _controllers.putIfAbsent(
      uid,
      () => StreamController<bool>.broadcast(
        onListen: () {
          _emitPresence(uid, _presenceMap[uid] ?? false);
          unawaited(_loadTimewebPresence(uid));
        },
        onCancel: () async {
          final controller = _controllers[uid];
          if (controller == null || controller.hasListener) {
            return;
          }
          _controllers.remove(uid);
          _streams.remove(uid);
          _lastFetchAt.remove(uid);
          _presenceFetchInFlight.remove(uid);
          await controller.close();
        },
      ),
    );
  }

  void _emitPresence(String uid, bool value) {
    final controller = _controllers[uid];
    if (controller == null || controller.isClosed) {
      return;
    }
    controller.add(value);
  }

  void _debugSource(String message) {
    if (!kDebugMode || message == 'Presence source: Timeweb') {
      return;
    }
    debugPrint(message);
  }

  void _ensureSocketSubscription() {
    if (_presenceSub != null) return;
    _debugLog('Presence listener registered event=presence.changed count=1');
    _presenceSub = _socketService?.presenceUpdates.listen((snapshot) {
      final userId = snapshot.userId.trim();
      if (userId.isEmpty) return;
      _debugSource('Presence source: Timeweb');
      _debugSource('Socket event: presence.changed');
      final previous = _presenceMap[userId];
      if (previous == snapshot.isOnline) {
        _lastFetchAt[userId] = DateTime.now();
        _debugLog(
          'Presence state unchanged user=$userId online=${snapshot.isOnline}',
        );
        return;
      }
      _presenceMap[userId] = snapshot.isOnline;
      _lastFetchAt[userId] = DateTime.now();
      _debugLog(
        'Presence state updated user=$userId online=${snapshot.isOnline}',
      );
      _emitPresence(userId, snapshot.isOnline);
    });
  }

  Future<void> setOnline({
    required String uid,
    required bool isOnline,
  }) async {
    _debugSource('Presence source: Timeweb');
    _ensureSocketSubscription();
    _debugLog('Presence online sent user=$uid online=$isOnline');
    await _socketService?.setPresence(
      isOnline,
      reason: isOnline ? 'presence.setOnline' : 'presence.setOffline',
    );
    final previous = _presenceMap[uid];
    _presenceMap[uid] = isOnline;
    _debugLog('Presence online confirmed user=$uid online=$isOnline');
    if (previous == isOnline) {
      _debugLog('Presence state unchanged user=$uid online=$isOnline');
      return;
    }
    _emitPresence(uid, isOnline);
  }

  Future<void> heartbeat(String uid) async {
    _debugSource('Presence source: Timeweb');
    _ensureSocketSubscription();
    _debugLog('Presence heartbeat user=$uid');
    await _socketService?.ping(reason: 'presence.heartbeat');
  }

  Future<void> recoverAfterResume(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    _ensureSocketSubscription();
    _debugLog(
      'Presence reconnect after resume user=$id socketConnected=${_socketService?.isConnected == true}',
    );
    await _socketService?.forceReconnect(reason: 'presence.resume');
    await setOnline(uid: id, isOnline: true);
    await heartbeat(id);
  }

  Future<void> resetSession() async {
    final presenceSub = _presenceSub;
    if (presenceSub != null) {
      _debugLog('Presence listener removed event=presence.changed count=0');
      await presenceSub.cancel();
      _presenceSub = null;
    }
    _presenceMap.clear();
    _streams.clear();
    _lastFetchAt.clear();
    _presenceFetchInFlight.clear();
    for (final controller in _controllers.values) {
      if (!controller.isClosed) {
        controller.add(false);
      }
    }
    await _socketService?.resetSession();
  }

  Future<void> _loadTimewebPresence(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    final lastFetchAt = _lastFetchAt[id];
    if (lastFetchAt != null &&
        DateTime.now().difference(lastFetchAt) < _fallbackPresenceTtl) {
      _emitPresence(id, _presenceMap[id] ?? false);
      return;
    }
    final existing = _presenceFetchInFlight[id];
    if (existing != null) return existing;

    final future = _loadTimewebPresenceInternal(id);
    _presenceFetchInFlight[id] = future;
    try {
      await future;
    } finally {
      if (identical(_presenceFetchInFlight[id], future)) {
        _presenceFetchInFlight.remove(id);
      }
    }
  }

  Future<void> _loadTimewebPresenceInternal(String uid) async {
    _ensureSocketSubscription();
    try {
      _debugSource('Presence source: Timeweb');
      final response =
          await _apiClient.get('/presence/$uid', authorized: true) as Map;
      final snapshot = PresenceSnapshot.fromMap(
        Map<String, dynamic>.from(response),
      );
      _presenceMap[uid] = snapshot.isOnline;
      _lastFetchAt[uid] = DateTime.now();
      _emitPresence(uid, snapshot.isOnline);
    } catch (_) {
      _emitPresence(uid, _presenceMap[uid] ?? false);
    }
  }

  bool? peekIsOnline(String uid) {
    final normalized = uid.trim();
    if (normalized.isEmpty) return null;
    return _presenceMap[normalized];
  }

  Stream<bool> streamIsOnline(
    String uid, {
    Duration staleAfter = const Duration(minutes: 2),
  }) {
    final normalized = uid.trim();
    if (normalized.isEmpty) return Stream<bool>.value(false);
    _ensureSocketSubscription();
    return _streams.putIfAbsent(
      normalized,
      () => _controllerFor(normalized).stream.distinct(),
    );
  }
}
