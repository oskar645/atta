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
  final Map<String, DateTime> _lastFetchAt = {};
  final Map<String, Future<void>> _presenceFetchInFlight = {};

  static const Duration _fallbackPresenceTtl = Duration(minutes: 1);

  StreamController<bool> _controllerFor(String uid) {
    return _controllers.putIfAbsent(
      uid,
      () => StreamController<bool>.broadcast(
        onListen: () {
          _controllers[uid]?.add(_presenceMap[uid] ?? false);
          unawaited(_loadTimewebPresence(uid));
        },
      ),
    );
  }

  void _debugSource(String message) {
    if (!kDebugMode ||
        message == 'Presence source: Timeweb' ||
        message.startsWith('Socket event:')) {
      return;
    }
    debugPrint(message);
  }

  void _ensureSocketSubscription() {
    if (_presenceSub != null) return;
    _presenceSub = _socketService?.presenceUpdates.listen((snapshot) {
      final userId = snapshot.userId.trim();
      if (userId.isEmpty) return;
      _debugSource('Presence source: Timeweb');
      _debugSource('Socket event: presence.changed');
      _presenceMap[userId] = snapshot.isOnline;
      _lastFetchAt[userId] = DateTime.now();
      _controllers[userId]?.add(snapshot.isOnline);
    });
  }

  Future<void> setOnline({
    required String uid,
    required bool isOnline,
  }) async {
    _debugSource('Presence source: Timeweb');
    _ensureSocketSubscription();
    await _socketService?.connect();
    await _socketService?.setPresence(isOnline);
    _presenceMap[uid] = isOnline;
    _controllerFor(uid).add(isOnline);
  }

  Future<void> heartbeat(String uid) async {
    _debugSource('Presence source: Timeweb');
    _ensureSocketSubscription();
    await _socketService?.connect();
    await _socketService?.ping();
  }

  Future<void> resetSession() async {
    await _presenceSub?.cancel();
    _presenceSub = null;
    _presenceMap.clear();
    _lastFetchAt.clear();
    _presenceFetchInFlight.clear();
    for (final controller in _controllers.values) {
      controller.add(false);
    }
    await _socketService?.resetSession();
  }

  Future<void> _loadTimewebPresence(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    final lastFetchAt = _lastFetchAt[id];
    if (lastFetchAt != null &&
        DateTime.now().difference(lastFetchAt) < _fallbackPresenceTtl) {
      _controllers[id]?.add(_presenceMap[id] ?? false);
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
      await _socketService?.connect();
      final response =
          await _apiClient.get('/presence/$uid', authorized: true) as Map;
      final snapshot = PresenceSnapshot.fromMap(
        Map<String, dynamic>.from(response),
      );
      _presenceMap[uid] = snapshot.isOnline;
      _lastFetchAt[uid] = DateTime.now();
      _controllers[uid]?.add(snapshot.isOnline);
    } catch (_) {
      _controllers[uid]?.add(_presenceMap[uid] ?? false);
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
    if (uid.trim().isEmpty) return Stream<bool>.value(false);
    _ensureSocketSubscription();
    return _controllerFor(uid).stream.distinct();
  }
}
