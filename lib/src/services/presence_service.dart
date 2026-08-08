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
  StreamSubscription<bool>? _connectionSub;
  final Map<String, PresenceSnapshot> _presenceMap = {};
  final Map<String, StreamController<PresenceSnapshot>> _controllers = {};
  final Map<String, Stream<PresenceSnapshot>> _streams = {};
  final Map<String, Stream<bool>> _onlineStreams = {};
  final Map<String, DateTime> _lastFetchAt = {};
  final Map<String, Future<void>> _presenceFetchInFlight = {};
  Future<void>? _presenceRecoveryInFlight;
  String? _activeUserId;

  static const Duration _fallbackPresenceTtl = Duration(minutes: 1);

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  StreamController<PresenceSnapshot> _controllerFor(String uid) {
    return _controllers.putIfAbsent(
      uid,
      () => StreamController<PresenceSnapshot>.broadcast(
        onListen: () {
          _emitPresence(
            uid,
            _presenceMap[uid] ?? PresenceSnapshot(userId: uid, isOnline: false),
          );
          unawaited(_loadTimewebPresence(uid));
        },
        onCancel: () async {
          final controller = _controllers[uid];
          if (controller == null || controller.hasListener) {
            return;
          }
          _controllers.remove(uid);
          _streams.remove(uid);
          _onlineStreams.remove(uid);
          _lastFetchAt.remove(uid);
          _presenceFetchInFlight.remove(uid);
          await controller.close();
        },
      ),
    );
  }

  void _emitPresence(String uid, PresenceSnapshot value) {
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
    if (_presenceSub == null) {
      _debugLog('Presence listener registered event=presence.changed count=1');
      _presenceSub = _socketService?.presenceUpdates.listen((snapshot) {
        final userId = snapshot.userId.trim();
        if (userId.isEmpty) return;
        _debugSource('Presence source: Timeweb');
        _debugSource('Socket event: presence.changed');
        final previous = _presenceMap[userId];
        if (previous != null &&
            previous.isOnline == snapshot.isOnline &&
            _sameDateTime(previous.lastSeen, snapshot.lastSeen)) {
          _lastFetchAt[userId] = DateTime.now();
          _debugLog(
            'Presence state unchanged user=$userId online=${snapshot.isOnline}',
          );
          return;
        }
        _presenceMap[userId] = snapshot;
        _lastFetchAt[userId] = DateTime.now();
        _debugLog(
          'Presence state updated user=$userId online=${snapshot.isOnline}',
        );
        _emitPresence(userId, snapshot);
      });
    }
    if (_connectionSub != null) return;
    _connectionSub = _socketService?.connectionChanges.listen((connected) {
      if (!connected) return;
      final uid = _activeUserId?.trim() ?? '';
      if (uid.isEmpty) return;
      unawaited(
        _refreshAfterSocketConnected(uid, reason: 'socket.connected'),
      );
    });
  }

  Future<void> setOnline({
    required String uid,
    required bool isOnline,
  }) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    if (isOnline) {
      _activeUserId = id;
    }
    _debugSource('Presence source: Timeweb');
    _ensureSocketSubscription();
    _debugLog('Presence online sent user=$id online=$isOnline');
    final previous = _presenceMap[id];
    final snapshot = PresenceSnapshot(userId: id, isOnline: isOnline);
    _presenceMap[id] = snapshot;
    if (previous?.isOnline == isOnline &&
        _sameDateTime(previous?.lastSeen, snapshot.lastSeen)) {
      _debugLog('Presence state unchanged user=$id online=$isOnline');
    } else {
      _emitPresence(id, snapshot);
    }
    await _socketService?.setPresence(
      isOnline,
      reason: isOnline ? 'presence.setOnline' : 'presence.setOffline',
    );
    _debugLog('Presence online confirmed user=$id online=$isOnline');
  }

  Future<void> heartbeat(String uid) async {
    _debugSource('Presence source: Timeweb');
    _ensureSocketSubscription();
    if (_socketService?.canSendPresenceHeartbeat != true) {
      return;
    }
    _debugLog('Presence heartbeat user=$uid');
    await _socketService?.ping(reason: 'presence.heartbeat');
  }

  Future<void> recoverAfterResume(String uid) async {
    await _recoverPresence(uid, reason: 'presence.resume', recoverSocket: true);
  }

  Future<void> recoverAfterNetworkChange(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    _activeUserId = id;
    _ensureSocketSubscription();
    _debugLog(
      'Presence network recovery armed user=$id socketConnected=${_socketService?.isConnected == true}',
    );
  }

  Future<void> _recoverPresence(
    String uid, {
    required String reason,
    required bool recoverSocket,
  }) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    _activeUserId = id;
    _ensureSocketSubscription();
    _debugLog(
      'Presence reconnect requested reason=$reason user=$id socketConnected=${_socketService?.isConnected == true}',
    );
    if (recoverSocket) {
      await _socketService?.recoverAfterResume(reason: reason);
    }
    await _refreshAfterSocketConnected(id, reason: reason);
  }

  Future<void> _refreshAfterSocketConnected(
    String uid, {
    required String reason,
  }) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    final existing = _presenceRecoveryInFlight;
    if (existing != null) return existing;

    final future = () async {
      _debugLog('Presence refresh after reconnect reason=$reason user=$id');
      await setOnline(uid: id, isOnline: true);
      await heartbeat(id);
      await _refreshTrackedPresence();
    }();
    _presenceRecoveryInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_presenceRecoveryInFlight, future)) {
        _presenceRecoveryInFlight = null;
      }
    }
  }

  Future<void> resetSession() async {
    final presenceSub = _presenceSub;
    if (presenceSub != null) {
      _debugLog('Presence listener removed event=presence.changed count=0');
      await presenceSub.cancel();
      _presenceSub = null;
    }
    await _connectionSub?.cancel();
    _connectionSub = null;
    _activeUserId = null;
    _presenceRecoveryInFlight = null;
    _presenceMap.clear();
    _streams.clear();
    _onlineStreams.clear();
    _lastFetchAt.clear();
    _presenceFetchInFlight.clear();
    for (final controller in _controllers.values) {
      if (!controller.isClosed) {
        controller.add(PresenceSnapshot(userId: '', isOnline: false));
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
      _emitPresence(
        id,
        _presenceMap[id] ?? PresenceSnapshot(userId: id, isOnline: false),
      );
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

  Future<void> _refreshTrackedPresence() async {
    final activeUserId = _activeUserId?.trim() ?? '';
    final ids = <String>{
      ..._controllers.keys,
      ..._presenceMap.keys,
    }..removeWhere((id) => id.isEmpty || id == activeUserId);
    for (final id in ids) {
      _lastFetchAt.remove(id);
      await _loadTimewebPresence(id);
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
      _presenceMap[uid] = snapshot;
      _lastFetchAt[uid] = DateTime.now();
      _emitPresence(uid, snapshot);
    } catch (_) {
      _emitPresence(
        uid,
        _presenceMap[uid] ?? PresenceSnapshot(userId: uid, isOnline: false),
      );
    }
  }

  bool? peekIsOnline(String uid) {
    final normalized = uid.trim();
    if (normalized.isEmpty) return null;
    return _presenceMap[normalized]?.isOnline;
  }

  PresenceSnapshot? peekPresence(String uid) {
    final normalized = uid.trim();
    if (normalized.isEmpty) return null;
    return _presenceMap[normalized];
  }

  Stream<PresenceSnapshot> streamPresence(
    String uid, {
    PresenceSnapshot? seed,
  }) {
    final normalized = uid.trim();
    if (normalized.isEmpty) {
      return Stream<PresenceSnapshot>.value(
        PresenceSnapshot(userId: '', isOnline: false),
      );
    }
    if (seed != null && _presenceMap[normalized] == null) {
      _presenceMap[normalized] = seed;
    }
    _ensureSocketSubscription();
    return _streams.putIfAbsent(
      normalized,
      () => _controllerFor(normalized).stream.distinct(_samePresence),
    );
  }

  Stream<bool> streamIsOnline(
    String uid, {
    Duration staleAfter = const Duration(minutes: 2),
  }) {
    final normalized = uid.trim();
    if (normalized.isEmpty) return Stream<bool>.value(false);
    return _onlineStreams.putIfAbsent(
      normalized,
      () => streamPresence(normalized)
          .map((snapshot) => snapshot.isOnline)
          .distinct(),
    );
  }

  bool _samePresence(PresenceSnapshot left, PresenceSnapshot right) {
    return left.userId == right.userId &&
        left.isOnline == right.isOnline &&
        _sameDateTime(left.lastSeen, right.lastSeen);
  }

  bool _sameDateTime(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == right;
    return left.toUtc().isAtSameMomentAs(right.toUtc());
  }
}
