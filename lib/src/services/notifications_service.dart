import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsService {
  final SupabaseClient _db = Supabase.instance.client;
  static final Map<String, DateTime> _lastSeenGlobalAt = <String, DateTime>{};
  static final StreamController<String> _unreadRecalc =
      StreamController<String>.broadcast();
  static const String savedSearchNotificationTitle =
      'Новое объявление по вашему поиску';

  Stream<T> _safeStream<T>({
    required Stream<List<Map<String, dynamic>>> source,
    required T Function(List<Map<String, dynamic>> rows) mapData,
    required T Function() fallback,
  }) {
    return Stream<T>.multi((controller) {
      var latestRows = <Map<String, dynamic>>[];

      final sub = source.listen(
        (rows) {
          latestRows = rows.map((r) => Map<String, dynamic>.from(r)).toList();
          controller.add(mapData(latestRows));
        },
        onError: (_) {
          controller.add(latestRows.isEmpty ? fallback() : mapData(latestRows));
        },
      );

      controller.onCancel = () async {
        await sub.cancel();
      };
    });
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

  Future<bool> _userExists(String userId) async {
    final rows =
        await _db.from('users').select('id').eq('id', userId).limit(1);
    return rows.isNotEmpty;
  }

  DateTime _parseCreatedAt(dynamic raw) {
    if (raw is DateTime) return raw.toUtc();
    if (raw is String) {
      return DateTime.tryParse(raw)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
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
    final stream = _db.from('user_notifications').stream(primaryKey: ['id']);

    return _safeStream<List<Map<String, dynamic>>>(
      source: stream,
      mapData: (rows) => _sortNewestFirst(
        rows.where((r) => r['scope'] == 'global').toList(),
      ),
      fallback: () => <Map<String, dynamic>>[],
    );
  }

  Stream<List<Map<String, dynamic>>> streamPersonal(String userId) {
    final stream = _db.from('user_notifications').stream(primaryKey: ['id']);

    return _safeStream<List<Map<String, dynamic>>>(
      source: stream,
      mapData: (rows) => _sortNewestFirst(
        rows
            .where(
              (r) =>
                  r['scope'] == 'personal' &&
                  r['user_id']?.toString() == userId,
            )
            .toList(),
      ),
      fallback: () => <Map<String, dynamic>>[],
    );
  }

  Stream<int> streamUnreadPersonalCount(String userId) {
    final stream = _db.from('user_notifications').stream(primaryKey: ['id']);

    return _safeStream<int>(
      source: stream,
      mapData: (rows) => rows.where((r) {
        final isPersonal = r['scope'] == 'personal';
        final sameUser = r['user_id']?.toString() == userId;
        final unread = r['is_read'] != true;
        return isPersonal && sameUser && unread;
      }).length,
      fallback: () => 0,
    );
  }

  bool isSavedSearchNotification(Map<String, dynamic> row) {
    final scope = (row['scope'] ?? '').toString();
    final title = (row['title'] ?? '').toString().trim();
    return scope == 'personal' && title == savedSearchNotificationTitle;
  }

  Stream<int> streamUnreadSavedSearchCount(String userId) {
    final stream = _db.from('user_notifications').stream(primaryKey: ['id']);

    return _safeStream<int>(
      source: stream,
      mapData: (rows) => rows.where((r) {
        final sameUser = r['user_id']?.toString() == userId;
        final unread = r['is_read'] != true;
        return sameUser && unread && isSavedSearchNotification(r);
      }).length,
      fallback: () => 0,
    );
  }

  Stream<int> streamUnreadBadgeCount(String userId) {
    final dbStream = _db.from('user_notifications').stream(primaryKey: ['id']);

    return Stream<int>.multi((controller) {
      var latestRows = <Map<String, dynamic>>[];

      void emit() {
        controller.add(_computeUnreadBadgeCount(latestRows, userId));
      }

      final dbSub = dbStream.listen(
        (rows) {
          latestRows = rows.map((r) => Map<String, dynamic>.from(r)).toList();
          emit();
        },
        onError: (_) => emit(),
      );

      final recalcSub = _unreadRecalc.stream.where((id) => id == userId).listen(
            (_) => emit(),
            onError: (_) => emit(),
          );

      controller.onCancel = () async {
        await dbSub.cancel();
        await recalcSub.cancel();
      };
    });
  }

  Future<void> markAllSeen(String userId) async {
    _lastSeenGlobalAt[userId] = DateTime.now().toUtc();
    _unreadRecalc.add(userId);
    await markAllPersonalRead(userId);
  }

  Future<void> markPersonalReadById(String notificationId) async {
    final row = await _db
        .from('user_notifications')
        .select('id, user_id')
        .eq('id', notificationId)
        .maybeSingle();

    await _db
        .from('user_notifications')
        .update({'is_read': true})
        .eq('id', notificationId);

    final uid = row?['user_id']?.toString();
    if (uid != null && uid.isNotEmpty) {
      _unreadRecalc.add(uid);
    }
  }

  Future<void> markAllPersonalRead(String userId) async {
    await _db
        .from('user_notifications')
        .update({'is_read': true})
        .eq('scope', 'personal')
        .eq('user_id', userId);
    _unreadRecalc.add(userId);
  }

  Future<void> markSavedSearchNotificationsRead(String userId) async {
    await _db
        .from('user_notifications')
        .update({'is_read': true})
        .eq('scope', 'personal')
        .eq('user_id', userId)
        .eq('title', savedSearchNotificationTitle)
        .eq('is_read', false);
    _unreadRecalc.add(userId);
  }

  Future<void> deleteById(String notificationId) async {
    final row = await _db
        .from('user_notifications')
        .select('id, user_id')
        .eq('id', notificationId)
        .maybeSingle();

    await _db.from('user_notifications').delete().eq('id', notificationId);

    final uid = row?['user_id']?.toString();
    if (uid != null && uid.isNotEmpty) {
      _unreadRecalc.add(uid);
    }
  }

  Future<void> sendGlobal({
    required String title,
    required String body,
  }) async {
    await _db.from('user_notifications').insert({
      'user_id': null,
      'scope': 'global',
      'title': title,
      'body': body,
      'is_read': false,
    });
  }

  Future<void> sendPersonal({
    required String userId,
    required String title,
    required String body,
  }) async {
    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(userId);
    if (!isUuid) {
      throw const FormatException('Invalid user_id format (UUID expected)');
    }

    final exists = await _userExists(userId);
    if (!exists) {
      throw StateError('User with this user_id was not found');
    }

    await _db.from('user_notifications').insert({
      'user_id': userId,
      'scope': 'personal',
      'title': title,
      'body': body,
      'is_read': false,
    });
  }
}
