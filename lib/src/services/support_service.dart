import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupportService {
  final SupabaseClient _db = Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  static const String _autoReplyText =
      'Здравствуйте! Мы получили ваше обращение и уже передали его модераторам. '
      'Обычно ответ приходит в ближайшее время. Если понадобятся уточнения, '
      'мы напишем вам здесь.';

  /// Получить или создать тикет пользователя
  Future<String?> getOrCreateMyTicketId({required String uid}) async {
    final row = await _db
        .from('support_tickets')
        .select('id')
        .eq('id', uid)
        .maybeSingle();

    return row == null ? null : uid;
  }

  /// Создание тикета + первое сообщение
  Future<String> createTicketAndSendFirstMessage({
    required String uid,
    required String name,
    required String text,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    /// создаём или обновляем тикет
    await _db.from('support_tickets').upsert({
      'id': uid,
      'uid': uid,
      'user_id': uid,
      'name': name,

      /// ✅ ВАЖНО — поле subject обязательно в базе
      'subject': 'Обращение в поддержку',

      'status': 'open',
      'created_at': now,
      'updated_at': now,
      'last_message': text,
      'unread_for_admin': true,
    }, onConflict: 'id');

    /// первое сообщение
    await _db.from('support_messages').insert({
      'id': _uuid.v4(),
      'ticket_id': uid,
      'sender': 'user',
      'text': text,
      'created_at': now,
    });

    await _db.from('support_messages').insert({
      'id': _uuid.v4(),
      'ticket_id': uid,
      'sender': 'admin',
      'text': _autoReplyText,
      'created_at': now,
    });

    return uid;
  }

  /// Отправка сообщения пользователем
  Future<void> sendMessage({
    required String ticketId,
    required String text,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await _db.from('support_messages').insert({
      'id': _uuid.v4(),
      'ticket_id': ticketId,
      'sender': 'user',
      'text': text,
      'created_at': now,
    });

    await _db.from('support_tickets').update({
      'updated_at': now,
      'last_message': text,
      'unread_for_admin': true,
    }).eq('id', ticketId);
  }

  /// Стрим сообщений тикета
  Stream<List<Map<String, dynamic>>> streamMessages(String ticketId) {
    final stream = _db
        .from('support_messages')
        .stream(primaryKey: ['id'])
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: false);

    return stream.map(
      (rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList(),
    );
  }

  /// Стрим тикетов для админа
  Stream<List<Map<String, dynamic>>> streamTicketsForAdmin() {
    final stream = _db
        .from('support_tickets')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false);

    return stream.map(
      (rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList(),
    );
  }

  /// Ответ администратора
  Future<void> adminReply({
    required String ticketId,
    required String text,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await _db.from('support_messages').insert({
      'id': _uuid.v4(),
      'ticket_id': ticketId,
      'sender': 'admin',
      'text': text,
      'created_at': now,
    });

    await _db.from('support_tickets').update({
      'updated_at': now,
      'last_message': text,
      'unread_for_admin': false,
    }).eq('id', ticketId);
  }

  /// Админ прочитал
  Future<void> markReadByAdmin(String ticketId) async {
    await _db.from('support_tickets').update({
      'unread_for_admin': false,
    }).eq('id', ticketId);
  }
}
