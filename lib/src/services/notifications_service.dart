import 'dart:async';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/in_app_notifications_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';

class NotificationsService {
  NotificationsService({
    InAppNotificationsApi? api,
    Duration pollInterval = const Duration(seconds: 8),
  }) : _api = api ?? InAppNotificationsApi(_apiClient);

  final InAppNotificationsApi _api;
  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);
  static final Map<String, DateTime> _lastSeenGlobalAt = <String, DateTime>{};
  static final StreamController<String> _refreshSignals =
      StreamController<String>.broadcast();
  final Map<String, Stream<List<Map<String, dynamic>>>> _timewebListStreams =
      <String, Stream<List<Map<String, dynamic>>>>{};
  final Map<String, Stream<int>> _timewebCountStreams = <String, Stream<int>>{};
  final Map<String, List<Map<String, dynamic>>> _serverRowsByUser =
      <String, List<Map<String, dynamic>>>{};
  final Map<String, Map<String, Map<String, dynamic>>> _realtimeRowsByUser =
      <String, Map<String, Map<String, dynamic>>>{};
  final Map<String, Future<void>> _refreshByUserInFlight =
      <String, Future<void>>{};
  final Map<String, DateTime> _lastSuccessfulRefreshAt = <String, DateTime>{};
  String? _activeUserId;
  int _sessionVersion = 0;
  static const String savedSearchNotificationTitle =
      'Новое объявление по вашему поиску';
  static const Duration _cacheTtl = Duration(seconds: 30);
  static const Duration _requestTimeout = Duration(seconds: 10);

  void _debugSource(String message) {
    if (!kDebugMode ||
        message == 'Notifications source: Timeweb' ||
        message ==
            'Notifications source: Timeweb unauthorized, resetting state') {
      return;
    }
    debugPrint(message);
  }

  void activateSession(String userId) {
    final normalized = userId.trim().isEmpty ? null : userId.trim();
    if (_activeUserId != normalized) {
      _clearCachedStreams();
    }
    _activeUserId = normalized;
  }

  void resetSession() {
    _activeUserId = null;
    _sessionVersion++;
    _clearCachedStreams();
  }

  Future<void> preload(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty) return Future.value();
    return _refreshUserNotifications(normalized, force: false).catchError(
      (error) {
        if (_isUnauthorized(error)) {
          _debugSource(
            'Notifications source: Timeweb unauthorized, resetting state',
          );
          resetSession();
          return;
        }
        throw error;
      },
    );
  }

  Future<void> refreshActiveSession({bool force = false}) async {
    final userId = _activeUserId;
    if (userId == null || userId.isEmpty) return;
    await _refreshUserNotifications(userId, force: force).catchError((error) {
      if (_isUnauthorized(error)) {
        _debugSource(
          'Notifications source: Timeweb unauthorized, resetting state',
        );
        resetSession();
        return;
      }
      throw error;
    });
    _refreshSignals.add(userId);
  }

  List<Map<String, dynamic>> peekGlobal() {
    final userId = _activeUserId;
    if (userId == null) return const <Map<String, dynamic>>[];
    return _sortNewestFirst(
      _mergedRowsForUser(userId)
          .where((row) => (row['scope'] ?? '').toString() == 'global')
          .map(Map<String, dynamic>.from)
          .toList(),
    );
  }

  List<Map<String, dynamic>> peekPersonal(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty) return const <Map<String, dynamic>>[];
    return _sortNewestFirst(
      _mergedRowsForUser(normalized)
          .where((row) =>
              (row['scope'] ?? '').toString() == 'personal' &&
              row['user_id']?.toString() == normalized)
          .map(Map<String, dynamic>.from)
          .toList(),
    );
  }

  void ingestRealtimeNotification({
    required String userId,
    required Map<String, dynamic> notification,
  }) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;

    final normalized = _normalizeNotification(
      normalizedUserId,
      notification,
    );
    final id = (normalized['id'] ?? '').toString().trim();
    if (id.isEmpty) return;

    final rows = _realtimeRowsByUser.putIfAbsent(
      normalizedUserId,
      () => <String, Map<String, dynamic>>{},
    );
    rows[id] = normalized;
    _refreshSignals.add(normalizedUserId);
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  int _computeUnreadBadgeCount(
    List<Map<String, dynamic>> rows,
    String userId,
  ) {
    final seenAt = _lastSeenGlobalAt[userId];
    var total = 0;

    for (final r in rows) {
      final scope = (r['scope'] ?? '').toString();
      if (scope == 'personal') {
        final sameUser = r['user_id']?.toString() == userId;
        final unread = r['is_read'] != true;
        if (sameUser && unread) total++;
        continue;
      }

      if (scope == 'global') {
        if (seenAt == null) {
          total++;
          continue;
        }

        final raw = r['created_at'];
        DateTime? created;
        if (raw is DateTime) created = raw.toUtc();
        if (raw is String) created = DateTime.tryParse(raw)?.toUtc();
        if (created != null && created.isAfter(seenAt)) {
          total++;
        }
      }
    }

    return total;
  }

  DateTime _parseCreatedAt(dynamic raw) {
    if (raw is DateTime) return raw.toUtc();
    if (raw is String) {
      return DateTime.tryParse(raw)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  bool _isGlobalUnread(Map<String, dynamic> row, String userId) {
    if ((row['scope'] ?? '').toString() != 'global') {
      return false;
    }
    final seenAt = _lastSeenGlobalAt[userId];
    if (seenAt == null) {
      return true;
    }
    return _parseCreatedAt(row['created_at']).isAfter(seenAt);
  }

  List<Map<String, dynamic>> _sortNewestFirst(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final bCreatedAt = _parseCreatedAt(b['created_at']);
      final aCreatedAt = _parseCreatedAt(a['created_at']);
      return bCreatedAt.compareTo(aCreatedAt);
    });
    return rows;
  }

  Stream<List<Map<String, dynamic>>> streamGlobal() {
    if (_activeUserId == null) {
      return Stream<List<Map<String, dynamic>>>.value(
        const <Map<String, dynamic>>[],
      );
    }
    _debugSource('Notifications source: Timeweb');
    return _timewebListStreams.putIfAbsent(
      'global',
      () => _createTimewebNotificationsStream(
        key: 'global',
        filter: (rows) => rows
            .where((row) => (row['scope'] ?? '').toString() == 'global')
            .toList(),
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> streamPersonal(String userId) {
    if (_activeUserId == null || _activeUserId != userId) {
      return Stream<List<Map<String, dynamic>>>.value(
        const <Map<String, dynamic>>[],
      );
    }
    _debugSource('Notifications source: Timeweb');
    return _timewebListStreams.putIfAbsent(
      'personal:$userId',
      () => _createTimewebNotificationsStream(
        key: 'personal:$userId',
        filter: (rows) => rows
            .where((row) =>
                (row['scope'] ?? '').toString() == 'personal' &&
                row['user_id']?.toString() == userId)
            .toList(),
      ),
    );
  }

  Stream<int> streamUnreadPersonalCount(String userId) {
    _debugSource('Notifications source: Timeweb');
    return streamPersonal(userId).map(
      (rows) => rows.where((row) => row['is_read'] != true).length,
    );
  }

  Stream<int> streamUnreadGlobalCount(String userId) {
    _debugSource('Notifications source: Timeweb');
    return streamGlobal().map(
      (rows) => rows.where((row) => _isGlobalUnread(row, userId)).length,
    );
  }

  bool isSavedSearchNotification(Map<String, dynamic> row) {
    final scope = (row['scope'] ?? '').toString();
    final title = (row['title'] ?? '').toString().trim();
    return scope == 'personal' && title == savedSearchNotificationTitle;
  }

  Stream<int> streamUnreadSavedSearchCount(String userId) {
    _debugSource('Notifications source: Timeweb');
    return streamPersonal(userId).map(
      (rows) => rows.where((r) {
        final unread = r['is_read'] != true;
        return unread && isSavedSearchNotification(r);
      }).length,
    );
  }

  Stream<int> streamUnreadBadgeCount(String userId) {
    _debugSource('Notifications source: Timeweb');
    return _timewebCountStreams.putIfAbsent(
      'badge:$userId',
      () => _createTimewebNotificationsStream(
        key: 'badge:$userId',
        filter: (rows) => rows,
      ).map((rows) => _computeUnreadBadgeCount(rows, userId)),
    );
  }

  Future<void> markAllSeen(String userId) async {
    _lastSeenGlobalAt[userId] = DateTime.now().toUtc();
    _refreshSignals.add(userId);
    await markAllPersonalRead(userId);
  }

  Future<void> markPersonalReadById(String notificationId) async {
    _debugSource('Notifications source: Timeweb');
    await _api.markRead(notificationId);
    _markRealtimeNotificationRead(notificationId);
  }

  Future<void> markAllPersonalRead(String userId) async {
    _debugSource('Notifications source: Timeweb');
    await _api.markAllRead();
    final mergedRows = _mergedRowsForUser(userId);
    for (final row in mergedRows.where((item) {
      return (item['scope'] ?? '').toString() == 'personal' &&
          item['user_id']?.toString() == userId &&
          item['is_read'] != true;
    })) {
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      _markRealtimeNotificationRead(id);
    }
    final cachedRows = _serverRowsByUser[userId];
    if (cachedRows != null) {
      for (final row in cachedRows) {
        if ((row['scope'] ?? '').toString() == 'personal' &&
            row['user_id']?.toString() == userId) {
          row['is_read'] = true;
        }
      }
    }
    _refreshSignals.add(userId);
  }

  Future<void> markSavedSearchNotificationsRead(String userId) async {
    _debugSource('Notifications source: Timeweb');
    final rows = await streamPersonal(userId).first;
    for (final row in rows.where(
        (item) => item['is_read'] != true && isSavedSearchNotification(item))) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      await _api.markRead(id);
      _markRealtimeNotificationRead(id);
    }
    _refreshSignals.add(userId);
  }

  Future<void> deleteById(String notificationId) async {
    _debugSource('Notifications source: Timeweb');
    await _api.deleteById(notificationId);
    _removeRealtimeNotification(notificationId);
  }

  Future<void> sendGlobal({
    required String title,
    required String body,
  }) async {
    _debugSource('Notifications source: Timeweb');
    await _api.sendAll(title: title, body: body);
  }

  Future<void> sendPersonal({
    required String userId,
    required String title,
    required String body,
  }) async {
    _debugSource('Notifications source: Timeweb');
    await _api.sendUser(userId: userId, title: title, body: body);
  }

  Stream<List<Map<String, dynamic>>> _createTimewebNotificationsStream({
    required String key,
    required List<Map<String, dynamic>> Function(
            List<Map<String, dynamic>> rows)
        filter,
  }) {
    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      var closed = false;
      final sessionVersion = _sessionVersion;
      StreamSubscription<String>? refreshSub;

      void emitCached() {
        if (closed ||
            sessionVersion != _sessionVersion ||
            _activeUserId == null) {
          return;
        }
        final rows = _sortNewestFirst(
          filter(_mergedRowsForUser(_activeUserId!)),
        );
        if (rows.isNotEmpty ||
            _lastSuccessfulRefreshAt.containsKey(_activeUserId!)) {
          controller.add(rows);
        }
      }

      Future<void> emit() async {
        if (closed ||
            sessionVersion != _sessionVersion ||
            _activeUserId == null) {
          return;
        }
        try {
          await _refreshUserNotifications(_activeUserId!, force: false);
          final rows = _sortNewestFirst(
            filter(_mergedRowsForUser(_activeUserId!)),
          );
          if (!closed && sessionVersion == _sessionVersion) {
            controller.add(rows);
          }
        } catch (error) {
          if (_isUnauthorized(error)) {
            if (!closed && sessionVersion == _sessionVersion) {
              controller.add(const <Map<String, dynamic>>[]);
            }
            resetSession();
            closed = true;
            return;
          }
          if (!closed && sessionVersion == _sessionVersion) {
            controller.addError(error);
          }
        }
      }

      emitCached();
      emit();
      refreshSub = _refreshSignals.stream.listen((signal) {
        if (signal == '*' || signal == _activeUserId) {
          emitCached();
        }
      });
      controller.onCancel = () {
        closed = true;
        refreshSub?.cancel();
      };
    }).asBroadcastStream();
  }

  bool _isUnauthorized(Object error) {
    return error is ApiException &&
        (error.isUnauthorized || error.code == 'local_unauthorized');
  }

  void _clearCachedStreams() {
    _timewebListStreams.clear();
    _timewebCountStreams.clear();
    _serverRowsByUser.clear();
    _realtimeRowsByUser.clear();
    _refreshByUserInFlight.clear();
    _lastSuccessfulRefreshAt.clear();
  }

  Future<void> _refreshUserNotifications(
    String userId, {
    required bool force,
  }) async {
    final lastRefreshAt = _lastSuccessfulRefreshAt[userId];
    if (!force &&
        lastRefreshAt != null &&
        DateTime.now().difference(lastRefreshAt) < _cacheTtl) {
      return;
    }

    final existing = _refreshByUserInFlight[userId];
    if (existing != null) return existing;

    final future = () async {
      final response = await _api.list().timeout(_requestTimeout);
      _serverRowsByUser[userId] = _extractItems(response);
      _lastSuccessfulRefreshAt[userId] = DateTime.now();
    }();
    _refreshByUserInFlight[userId] = future;

    try {
      await future;
    } finally {
      if (identical(_refreshByUserInFlight[userId], future)) {
        _refreshByUserInFlight.remove(userId);
      }
    }
  }

  Map<String, dynamic> _normalizeNotification(
    String userId,
    Map<String, dynamic> notification,
  ) {
    final row = Map<String, dynamic>.from(notification);
    final payload = row['payload'] is Map
        ? Map<String, dynamic>.from(row['payload'] as Map)
        : <String, dynamic>{};
    final chatId = (row['chatId'] ?? row['chat_id'] ?? payload['chatId'] ?? '')
        .toString()
        .trim();
    final senderName =
        (row['senderName'] ?? row['sender_name'] ?? payload['senderName'] ?? '')
            .toString()
            .trim();
    final senderAvatar = (row['senderAvatarUrl'] ??
            row['sender_avatar_url'] ??
            payload['senderAvatarUrl'] ??
            '')
        .toString()
        .trim();
    final title = (row['title'] ?? '').toString().trim().isNotEmpty
        ? (row['title'] ?? '').toString().trim()
        : senderName.isNotEmpty
            ? 'Новое сообщение от $senderName'
            : 'Новое сообщение';

    return <String, dynamic>{
      ...row,
      'id': (row['id'] ?? '').toString(),
      'user_id': (row['user_id'] ?? row['userId'] ?? userId).toString(),
      'scope': (row['scope'] ?? 'personal').toString().toLowerCase(),
      'title': title,
      'body': (row['body'] ?? '').toString(),
      'type': (row['type'] ?? 'chat_message').toString().toLowerCase(),
      'is_read': row['is_read'] == true,
      'created_at': (row['created_at'] ??
              row['createdAt'] ??
              DateTime.now().toUtc().toIso8601String())
          .toString(),
      'payload': payload,
      'chat_id': chatId,
      'chatId': chatId,
      'sender_name': senderName,
      'senderName': senderName,
      'sender_avatar_url': senderAvatar,
      'senderAvatarUrl': senderAvatar,
    };
  }

  List<Map<String, dynamic>> _mergedRowsForUser(String userId) {
    final rowsById = <String, Map<String, dynamic>>{};

    for (final row
        in _serverRowsByUser[userId] ?? const <Map<String, dynamic>>[]) {
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      rowsById[id] = Map<String, dynamic>.from(row);
    }

    final realtimeRows = _realtimeRowsByUser[userId];
    if (realtimeRows != null) {
      for (final entry in realtimeRows.entries) {
        final existing = rowsById[entry.key] ?? const <String, dynamic>{};
        rowsById[entry.key] = <String, dynamic>{
          ...existing,
          ...entry.value,
        };
      }
    }

    return rowsById.values.toList();
  }

  void _markRealtimeNotificationRead(String notificationId) {
    var touchedUserId = '';
    for (final entry in _realtimeRowsByUser.entries) {
      final row = entry.value[notificationId];
      if (row == null) continue;
      row['is_read'] = true;
      touchedUserId = entry.key;
    }
    if (touchedUserId.isNotEmpty) {
      _refreshSignals.add(touchedUserId);
    }
  }

  void _removeRealtimeNotification(String notificationId) {
    var touchedUserId = '';
    for (final entry in _realtimeRowsByUser.entries) {
      if (entry.value.remove(notificationId) != null) {
        touchedUserId = entry.key;
      }
    }
    if (touchedUserId.isNotEmpty) {
      _refreshSignals.add(touchedUserId);
    }
  }
}
