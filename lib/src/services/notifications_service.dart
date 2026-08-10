import 'dart:async';
import 'dart:io';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/in_app_notifications_api.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/image_preparation_service.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:flutter/foundation.dart';

class NotificationsService {
  NotificationsService({
    InAppNotificationsApi? api,
    MediaApi? mediaApi,
    ImagePreparationService? imagePreparationService,
  })  : _api = api ?? InAppNotificationsApi(_apiClient),
        _mediaApi = mediaApi ?? MediaApi(_apiClient),
        _imagePreparationService =
            imagePreparationService ?? ImagePreparationService();

  final InAppNotificationsApi _api;
  final MediaApi _mediaApi;
  final ImagePreparationService _imagePreparationService;
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
  final Map<String, DateTime> _lastRefreshAttemptAt = <String, DateTime>{};
  String? _activeUserId;
  int _sessionVersion = 0;
  static const String savedSearchNotificationTitle =
      'Новое объявление по вашему поиску';
  static const Duration _cacheTtl = Duration(seconds: 30);
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const Duration _refreshThrottle = Duration(seconds: 2);
  static const Set<String> _excludedNotificationTypes = <String>{
    'chat_message',
    'message',
    'chat',
  };

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
    final previousUserId = _activeUserId;
    if (previousUserId != null && previousUserId.isNotEmpty) {
      _lastSeenGlobalAt.remove(previousUserId);
      _lastRefreshAttemptAt.remove(previousUserId);
    }
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
          .where((row) =>
              (row['scope'] ?? '').toString() == 'global' &&
              !_isExcludedNotification(row))
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
              row['user_id']?.toString() == normalized &&
              !_isExcludedNotification(row))
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
    if (_isExcludedNotification(normalized)) return;
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
      if (_isExcludedNotification(r)) continue;
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
    if (_isExcludedNotification(row)) {
      return false;
    }
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

  bool _isExcludedNotification(Map<String, dynamic> row) {
    final type = (row['type'] ?? '').toString().trim().toLowerCase();
    return _excludedNotificationTypes.contains(type);
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
            .where((row) =>
                (row['scope'] ?? '').toString() == 'global' &&
                !_isExcludedNotification(row))
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
                row['user_id']?.toString() == userId &&
                !_isExcludedNotification(row))
            .toList(),
      ),
    );
  }

  Stream<int> streamUnreadPersonalCount(String userId) {
    final normalized = userId.trim();
    if (_activeUserId == null || _activeUserId != normalized) {
      return Stream<int>.value(0);
    }
    _debugSource('Notifications source: Timeweb');
    return _timewebCountStreams.putIfAbsent(
      'personal:$normalized',
      () => _createTimewebNotificationsStream(
        key: 'personal-unread:$normalized',
        filter: (rows) => rows
            .where((row) =>
                (row['scope'] ?? '').toString() == 'personal' &&
                row['user_id']?.toString() == normalized &&
                !_isExcludedNotification(row))
            .toList(),
      )
          .map(
            (rows) => rows.where((row) => row['is_read'] != true).length,
          )
          .asBroadcastStream(),
    );
  }

  Stream<int> streamUnreadGlobalCount(String userId) {
    _debugSource('Notifications source: Timeweb');
    return streamGlobal()
        .map(
          (rows) => rows.where((row) => _isGlobalUnread(row, userId)).length,
        )
        .asBroadcastStream();
  }

  bool isSavedSearchNotification(Map<String, dynamic> row) {
    final scope = (row['scope'] ?? '').toString();
    final title = (row['title'] ?? '').toString().trim();
    return scope == 'personal' && title == savedSearchNotificationTitle;
  }

  Stream<int> streamUnreadSavedSearchCount(String userId) {
    _debugSource('Notifications source: Timeweb');
    return streamPersonal(userId)
        .map(
          (rows) => rows.where((r) {
            final unread = r['is_read'] != true;
            return unread && isSavedSearchNotification(r);
          }).length,
        )
        .asBroadcastStream();
  }

  Stream<int> streamUnreadBadgeCount(String userId) {
    _debugSource('Notifications source: Timeweb');
    return _timewebCountStreams.putIfAbsent(
      'badge:$userId',
      () => _createTimewebNotificationsStream(
        key: 'badge:$userId',
        filter: (rows) => rows,
      )
          .map((rows) => _computeUnreadBadgeCount(rows, userId))
          .asBroadcastStream(),
    );
  }

  Future<void> markAllSeen(String userId) async {
    final response = await _api.markAllSeen();
    _syncGlobalSeenAt(
      userId,
      response['global_seen_at'] ?? response['globalSeenAt'],
    );
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

  Future<void> markPersonalReadById(String notificationId) async {
    _debugSource('Notifications source: Timeweb');
    await _api.markRead(notificationId);
    final touchedUserId = _markNotificationReadInCaches(notificationId);
    if (touchedUserId.isNotEmpty) {
      _refreshSignals.add(touchedUserId);
    }
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
      _markNotificationReadInCaches(id);
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
      _markNotificationReadInCaches(id);
    }
    _refreshSignals.add(userId);
  }

  Future<void> deleteById(String notificationId) async {
    _debugSource('Notifications source: Timeweb');
    await _api.deleteById(notificationId);
    final touchedUserId = _removeNotificationFromCaches(notificationId);
    if (touchedUserId.isNotEmpty) {
      _refreshSignals.add(touchedUserId);
    }
  }

  Future<void> sendGlobal({
    String? title,
    String? body,
    Map<String, dynamic>? payload,
  }) async {
    _debugSource('Notifications source: Timeweb');
    await _api.sendAll(title: title, body: body, payload: payload);
  }

  Future<void> sendPersonal({
    required String userId,
    String? title,
    String? body,
    Map<String, dynamic>? payload,
  }) async {
    _debugSource('Notifications source: Timeweb');
    await _api.sendUser(
      userId: userId,
      title: title,
      body: body,
      payload: payload,
    );
  }

  Future<String> uploadNotificationImage(File file) async {
    try {
      final prepared =
          await _imagePreparationService.prepareNotificationImage(file);
      final response = await _mediaApi.uploadNotificationImage(
        bytes: prepared.bytes,
        fileName: prepared.fileName,
        contentType: prepared.contentType,
      );
      final rawUrl =
          (response['url'] ?? response['imageUrl'] ?? '').toString().trim();
      final resolution = resolveMediaUrl(
        rawUrl,
        categoryHint: 'misc',
      );
      if (kDebugMode) {
        debugPrint(
          'Notification upload response imageUrl=$rawUrl resolved=${resolution.resolvedUrl} category=notification provider=${resolution.provider}',
        );
      }
      return resolution.resolvedUrl;
    } on ApiException catch (error) {
      if (error.isNotFound) {
        throw const ApiException(
          'Не удалось загрузить фото для уведомления. Попробуйте позже.',
          statusCode: 404,
          code: 'notification_upload_not_available',
        );
      }
      throw ApiException(
        'Не удалось загрузить фото для уведомления. Попробуйте другое фото.',
        statusCode: error.statusCode,
        code: error.code,
        details: error.details,
      );
    }
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
    _lastRefreshAttemptAt.clear();
  }

  Future<void> _refreshUserNotifications(
    String userId, {
    required bool force,
  }) async {
    final now = DateTime.now();
    final lastAttemptAt = _lastRefreshAttemptAt[userId];
    if (force &&
        lastAttemptAt != null &&
        now.difference(lastAttemptAt) < _refreshThrottle) {
      final existing = _refreshByUserInFlight[userId];
      if (existing != null) {
        return existing;
      }
      final lastRefreshAt = _lastSuccessfulRefreshAt[userId];
      if (lastRefreshAt != null &&
          now.difference(lastRefreshAt) < _refreshThrottle) {
        return;
      }
    }

    final lastRefreshAt = _lastSuccessfulRefreshAt[userId];
    if (!force &&
        lastRefreshAt != null &&
        now.difference(lastRefreshAt) < _cacheTtl) {
      return;
    }

    final existing = _refreshByUserInFlight[userId];
    if (existing != null) return existing;
    _lastRefreshAttemptAt[userId] = now;

    final future = () async {
      final response = await _api.list().timeout(_requestTimeout);
      _syncGlobalSeenAt(
        userId,
        response['global_seen_at'] ?? response['globalSeenAt'],
      );
      _serverRowsByUser[userId] = _extractItems(response)
          .where((row) => !_isExcludedNotification(row))
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
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
      'type': (row['type'] ?? 'generic').toString().toLowerCase(),
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

  String _markNotificationReadInCaches(String notificationId) {
    var touchedUserId = '';
    for (final entry in _serverRowsByUser.entries) {
      for (final row in entry.value) {
        final id = (row['id'] ?? '').toString().trim();
        if (id != notificationId) continue;
        row['is_read'] = true;
        touchedUserId = entry.key;
      }
    }
    for (final entry in _realtimeRowsByUser.entries) {
      final row = entry.value[notificationId];
      if (row == null) continue;
      row['is_read'] = true;
      touchedUserId = entry.key;
    }
    return touchedUserId;
  }

  String _removeNotificationFromCaches(String notificationId) {
    var touchedUserId = '';
    for (final entry in _serverRowsByUser.entries) {
      final before = entry.value.length;
      entry.value.removeWhere(
        (row) => (row['id'] ?? '').toString().trim() == notificationId,
      );
      if (entry.value.length != before) {
        touchedUserId = entry.key;
      }
    }
    for (final entry in _realtimeRowsByUser.entries) {
      if (entry.value.remove(notificationId) != null) {
        touchedUserId = entry.key;
      }
    }
    return touchedUserId;
  }

  void _syncGlobalSeenAt(String userId, dynamic raw) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    if (raw == null) {
      _lastSeenGlobalAt.remove(normalizedUserId);
      return;
    }
    final value = raw.toString().trim();
    if (value.isEmpty) {
      _lastSeenGlobalAt.remove(normalizedUserId);
      return;
    }
    final parsed = DateTime.tryParse(value)?.toUtc();
    if (parsed == null) {
      _lastSeenGlobalAt.remove(normalizedUserId);
      return;
    }
    _lastSeenGlobalAt[normalizedUserId] = parsed;
  }

  @visibleForTesting
  bool get hasActivePollingTimer => false;
}
