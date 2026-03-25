import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:atta/src/services/notifications_service.dart';

class ReportsService {
  final SupabaseClient _db = Supabase.instance.client;
  final Uuid _uuid = const Uuid();
  final NotificationsService _notifications = NotificationsService();

  bool _isMissingColumnError(Object error) {
    if (error is PostgrestException) {
      final code = (error.code ?? '').toUpperCase();
      final msg = error.message.toLowerCase();
      // 42703: postgres undefined_column
      // PGRST204: column is missing in PostgREST schema cache
      return code == '42703' || code == 'PGRST204' || msg.contains('column');
    }
    return false;
  }

  Future<void> reportListing({
    required String listingId,
    required String listingOwnerId,
    required String reporterId,
    required String reason,
    required String comment,
  }) async {
    await _db.from('reports').insert({
      'listing_id': listingId,
      'listing_owner_id': listingOwnerId,
      'reporter_id': reporterId,
      'reason': reason,
      'comment': comment.trim(),
      'status': 'open',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'handled_at': null,
      'handled_by': null,
      'admin_note': null,
      'admin_uid': null,
      'decision': null,
      'admin_comment': null,
      'closed_at': null,
    });
  }

  Stream<List<Map<String, dynamic>>> streamOpenReports() {
    final stream = _db
        .from('reports')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return stream.map((rows) {
      return rows
          .where((r) => (r['status'] ?? '').toString() == 'open')
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    });
  }

  Future<void> closeReportDecision({
    required String reportId,
    required String adminUid,
    required String decision,
    String? adminComment,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final comment =
        (adminComment ?? '').trim().isEmpty ? null : adminComment!.trim();

    try {
      await _db.from('reports').update({
        'status': 'closed',
        'admin_uid': adminUid,
        'decision': decision,
        'admin_comment': comment,
        'closed_at': now,
        'handled_at': now,
        'handled_by': adminUid,
        'admin_note': comment,
      }).eq('id', reportId);
    } catch (e) {
      if (!_isMissingColumnError(e)) rethrow;
      try {
        await _db.from('reports').update({
          'status': 'closed',
          'handled_at': now,
          'handled_by': adminUid,
          'admin_note': comment,
        }).eq('id', reportId);
      } catch (e2) {
        if (!_isMissingColumnError(e2)) rethrow;
        // Final fallback for old/minimal reports schema.
        await _db.from('reports').update({
          'status': 'closed',
        }).eq('id', reportId);
      }
    }
  }

  Future<void> deleteListingById(
    String listingId, {
    String? reason,
  }) async {
    final note = (reason ?? '').trim();
    await _db.from('listings').update({
      'status': 'deleted',
      'rejection_reason': note.isEmpty ? 'Объявление удалено администратором.' : note,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', listingId);
  }

  Future<void> notifyOwnerViaSupport({
    required String ownerUid,
    required String ownerName,
    required String messageFromAdmin,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await _db.from('support_tickets').upsert({
      'id': ownerUid,
      'uid': ownerUid,
      'user_id': ownerUid,
      'name': ownerName,
      'subject': 'Moderation',
      'status': 'open',
      'created_at': now,
      'updated_at': now,
      'last_message': messageFromAdmin,
      'unread_for_admin': false,
    }, onConflict: 'id');

    await _db.from('support_messages').insert({
      'id': _uuid.v4(),
      'ticket_id': ownerUid,
      'sender': 'admin',
      'text': messageFromAdmin,
      'created_at': now,
    });
  }

  Future<void> notifyOwnerPersonal({
    required String ownerUid,
    required String title,
    required String body,
  }) async {
    await _notifications.sendPersonal(
      userId: ownerUid,
      title: title,
      body: body,
    );
  }
}

