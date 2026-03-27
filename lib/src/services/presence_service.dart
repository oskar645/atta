import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PresenceService {
  final SupabaseClient _db = Supabase.instance.client;
  bool _didLogNetworkIssue = false;

  Future<void> setOnline({
    required String uid,
    required bool isOnline,
  }) async {
    await _upsertPresence(uid: uid, isOnline: isOnline);
  }

  Future<void> heartbeat(String uid) async {
    await _upsertPresence(uid: uid, isOnline: true);
  }

  Future<void> _upsertPresence({
    required String uid,
    required bool isOnline,
  }) async {
    if (uid.trim().isEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();

    try {
      await _db.from('user_presence').upsert({
        'user_id': uid,
        'is_online': isOnline,
        'last_seen': now,
        'updated_at': now,
      }, onConflict: 'user_id');
      _didLogNetworkIssue = false;
    } on SocketException catch (e) {
      _logNetworkIssueOnce(e);
    } on http.ClientException catch (e) {
      _logNetworkIssueOnce(e);
    } catch (e) {
      debugPrint('Presence upsert failed: $e');
    }
  }

  void _logNetworkIssueOnce(Object error) {
    if (!kDebugMode || _didLogNetworkIssue) return;
    _didLogNetworkIssue = true;
    debugPrint('Presence temporarily unavailable: $error');
  }

  Stream<bool> streamIsOnline(
    String uid, {
    Duration staleAfter = const Duration(minutes: 2),
  }) {
    if (uid.trim().isEmpty) return Stream<bool>.value(false);

    return _db
        .from('user_presence')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', uid)
        .map((rows) {
      if (rows.isEmpty) return false;
      final row = rows.first;
      final isOnline = row['is_online'] == true;
      if (!isOnline) return false;

      final raw = (row['last_seen'] ?? '').toString();
      final lastSeen = DateTime.tryParse(raw)?.toUtc();
      if (lastSeen == null) return isOnline;

      final cutoff = DateTime.now().toUtc().subtract(staleAfter);
      return lastSeen.isAfter(cutoff);
    });
  }
}
