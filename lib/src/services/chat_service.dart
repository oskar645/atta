import 'dart:io';

import 'package:atta/src/models/chat.dart';
import 'package:atta/src/models/message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ChatService {
  final SupabaseClient _db = Supabase.instance.client;
  final _uuid = const Uuid();

  static const String _chatImagesBucket = 'chat_images';

  Stream<List<Chat>> streamMyChats(String uid) {
    final stream = _db
        .from('chats')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false);

    return stream.map((rows) {
      final out = <Chat>[];

      for (final r in rows) {
        final buyerId = (r['buyer_id'] ?? '').toString();
        final sellerId = (r['seller_id'] ?? '').toString();
        if (buyerId != uid && sellerId != uid) continue;

        out.add(Chat.fromMap(Map<String, dynamic>.from(r)));
      }

      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return out;
    });
  }

  Stream<int> streamUnreadTotal(String uid) {
    final stream = _db.from('chats').stream(primaryKey: ['id']);

    return stream.map((rows) {
      var total = 0;

      for (final r in rows) {
        final buyerId = (r['buyer_id'] ?? '').toString();
        final sellerId = (r['seller_id'] ?? '').toString();
        if (buyerId != uid && sellerId != uid) continue;

        final unreadForBuyer = (r['unread_for_buyer'] as num?)?.toInt() ?? 0;
        final unreadForSeller = (r['unread_for_seller'] as num?)?.toInt() ?? 0;
        total += uid == buyerId ? unreadForBuyer : unreadForSeller;
      }

      return total;
    });
  }

  Stream<List<ChatMessage>> streamMessages(String chatId) {
    final stream = _db
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return stream.map((rows) {
      final out = <ChatMessage>[];
      for (final r in rows) {
        if ((r['chat_id'] ?? '').toString() != chatId) continue;
        out.add(ChatMessage.fromMap(Map<String, dynamic>.from(r)));
      }
      return out;
    });
  }

  Future<String> getOrCreateChat({
    required String listingId,
    required String listingTitle,
    required String buyerId,
    required String sellerId,
  }) async {
    final existing = await _db
        .from('chats')
        .select('id')
        .eq('listing_id', listingId)
        .eq('buyer_id', buyerId)
        .eq('seller_id', sellerId)
        .maybeSingle();

    if (existing != null && existing['id'] != null) {
      return existing['id'].toString();
    }

    final newId = _uuid.v4();

    await _db.from('chats').insert({
      'id': newId,
      'listing_id': listingId,
      'listing_title': listingTitle,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'last_message': '',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'unread_for_buyer': 0,
      'unread_for_seller': 0,
    });

    return newId;
  }

  Future<void> markChatRead({
    required String chatId,
    required String uid,
  }) async {
    final chat = await _db
        .from('chats')
        .select('buyer_id, seller_id')
        .eq('id', chatId)
        .maybeSingle();

    if (chat == null) return;

    final buyerId = (chat['buyer_id'] ?? '').toString();
    final sellerId = (chat['seller_id'] ?? '').toString();

    await _markIncomingMessagesDelivered(chatId: chatId, uid: uid);
    await _markIncomingMessagesRead(chatId: chatId, uid: uid);

    if (uid == buyerId) {
      await _db.from('chats').update({'unread_for_buyer': 0}).eq('id', chatId);
    } else if (uid == sellerId) {
      await _db.from('chats').update({'unread_for_seller': 0}).eq('id', chatId);
    }
  }

  Future<void> markChatDelivered({
    required String chatId,
    required String uid,
  }) async {
    await _markIncomingMessagesDelivered(chatId: chatId, uid: uid);
  }

  Future<void> markChatsDelivered({
    required Iterable<String> chatIds,
    required String uid,
  }) async {
    final ids = chatIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    for (final chatId in ids) {
      await markChatDelivered(chatId: chatId, uid: uid);
    }
  }

  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final chat = await _db
        .from('chats')
        .select('buyer_id, seller_id, unread_for_buyer, unread_for_seller')
        .eq('id', chatId)
        .maybeSingle();

    if (chat == null) throw Exception('Чат не найден');

    final buyerId = (chat['buyer_id'] ?? '').toString();
    final sellerId = (chat['seller_id'] ?? '').toString();

    await _db.from('chat_messages').insert({
      'id': _uuid.v4(),
      'chat_id': chatId,
      'sender_id': senderId,
      'text': trimmed,
      'image_url': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'delivered_at': null,
      'read_at': null,
    });

    var unreadForBuyer = (chat['unread_for_buyer'] as num?)?.toInt() ?? 0;
    var unreadForSeller = (chat['unread_for_seller'] as num?)?.toInt() ?? 0;

    if (senderId == buyerId) {
      unreadForSeller += 1;
    } else if (senderId == sellerId) {
      unreadForBuyer += 1;
    }

    await _db.from('chats').update({
      'last_message': trimmed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'unread_for_buyer': unreadForBuyer,
      'unread_for_seller': unreadForSeller,
    }).eq('id', chatId);
  }

  Future<void> sendImage({
    required String chatId,
    required String senderId,
    required File file,
  }) async {
    final chat = await _db
        .from('chats')
        .select('buyer_id, seller_id, unread_for_buyer, unread_for_seller')
        .eq('id', chatId)
        .maybeSingle();

    if (chat == null) throw Exception('Чат не найден');

    final buyerId = (chat['buyer_id'] ?? '').toString();
    final sellerId = (chat['seller_id'] ?? '').toString();
    final fileId = _uuid.v4();
    final extension = _pickImageExtension(file.path);
    final contentType = _contentTypeForExtension(extension);
    final path = '$chatId/$fileId.$extension';

    final bytes = await file.readAsBytes();
    await _db.storage.from(_chatImagesBucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        cacheControl: '3600',
        upsert: false,
        contentType: contentType,
      ),
    );

    await _db.from('chat_messages').insert({
      'id': _uuid.v4(),
      'chat_id': chatId,
      'sender_id': senderId,
      'text': '',
      'image_url': path,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'delivered_at': null,
      'read_at': null,
    });

    var unreadForBuyer = (chat['unread_for_buyer'] as num?)?.toInt() ?? 0;
    var unreadForSeller = (chat['unread_for_seller'] as num?)?.toInt() ?? 0;

    if (senderId == buyerId) {
      unreadForSeller += 1;
    } else if (senderId == sellerId) {
      unreadForBuyer += 1;
    }

    await _db.from('chats').update({
      'last_message': 'Фото',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'unread_for_buyer': unreadForBuyer,
      'unread_for_seller': unreadForSeller,
    }).eq('id', chatId);
  }

  String _pickImageExtension(String path) {
    final normalized = path.trim().toLowerCase();
    final dot = normalized.lastIndexOf('.');
    if (dot == -1 || dot == normalized.length - 1) return 'jpg';

    final ext = normalized.substring(dot + 1);
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'jpg';
      case 'png':
      case 'webp':
      case 'gif':
      case 'heic':
      case 'heif':
        return ext;
      default:
        return 'jpg';
    }
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }

  Future<String> resolveMessageImageUrl(String rawValue) async {
    final value = rawValue.trim();
    if (value.isEmpty) return '';

    final normalizedPath = _extractChatImagePath(value);
    if (normalizedPath == null) {
      return value;
    }

    return _db.storage.from(_chatImagesBucket).createSignedUrl(
          normalizedPath,
          60 * 60 * 24 * 30,
        );
  }

  String? _extractChatImagePath(String value) {
    if (!value.contains('://')) {
      return value;
    }

    const marker = '/chat_images/';
    final idx = value.indexOf(marker);
    if (idx == -1) return null;

    final path = value.substring(idx + marker.length).trim();
    return path.isEmpty ? null : path;
  }

  Future<void> deleteChat({
    required String chatId,
    required String uid,
  }) async {
    final chat = await _db
        .from('chats')
        .select('buyer_id, seller_id')
        .eq('id', chatId)
        .maybeSingle();

    if (chat == null) return;

    final buyerId = (chat['buyer_id'] ?? '').toString();
    final sellerId = (chat['seller_id'] ?? '').toString();

    if (uid != buyerId && uid != sellerId) {
      throw Exception('Нет доступа к удалению чата');
    }

    await _db.from('chat_messages').delete().eq('chat_id', chatId);
    await _db.from('chats').delete().eq('id', chatId);
  }

  Future<void> _markIncomingMessagesDelivered({
    required String chatId,
    required String uid,
  }) async {
    final rows = await _db
        .from('chat_messages')
        .select('id, delivered_at, sender_id')
        .eq('chat_id', chatId)
        .neq('sender_id', uid);

    final now = DateTime.now().toUtc().toIso8601String();
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (row['delivered_at'] != null) continue;
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      await _db.from('chat_messages').update({'delivered_at': now}).eq('id', id);
    }
  }

  Future<void> _markIncomingMessagesRead({
    required String chatId,
    required String uid,
  }) async {
    final rows = await _db
        .from('chat_messages')
        .select('id, delivered_at, read_at, sender_id')
        .eq('chat_id', chatId)
        .neq('sender_id', uid);

    final now = DateTime.now().toUtc().toIso8601String();
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;

      final patch = <String, dynamic>{};
      if (row['delivered_at'] == null) {
        patch['delivered_at'] = now;
      }
      if (row['read_at'] == null) {
        patch['read_at'] = now;
      }
      if (patch.isEmpty) continue;

      await _db.from('chat_messages').update(patch).eq('id', id);
    }
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
    required String uid,
  }) async {
    final msg = await _db
        .from('chat_messages')
        .select('id, chat_id, sender_id')
        .eq('id', messageId)
        .maybeSingle();

    if (msg == null) return;
    if ((msg['chat_id'] ?? '').toString() != chatId) return;
    if ((msg['sender_id'] ?? '').toString() != uid) {
      throw Exception('Можно удалить только свое сообщение');
    }

    await _db.from('chat_messages').delete().eq('id', messageId);
  }
}
