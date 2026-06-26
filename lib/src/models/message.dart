// lib/src/models/message.dart
import 'package:atta/src/utils/media_url.dart';

class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final String type;
  final String status;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final String? clientMessageId;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    this.type = 'text',
    this.status = 'sent',
    required this.createdAt,
    this.imageUrl,
    this.updatedAt,
    this.deliveredAt,
    this.readAt,
    this.clientMessageId,
  });

  bool get hasText => text.trim().isNotEmpty;
  bool get hasImage => (imageUrl ?? '').trim().isNotEmpty;
  bool get hasVisibleContent => hasText || hasImage;
  String get stableKey {
    final localId = clientMessageId?.trim() ?? '';
    return localId.isNotEmpty ? localId : id;
  }

  factory ChatMessage.fromMap(Map<String, dynamic> row) {
    DateTime parseDt(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? parseNullableDt(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    String firstNonEmpty(List<dynamic> values, [String fallback = '']) {
      for (final value in values) {
        final text = (value ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
      return fallback;
    }

    final rawType = firstNonEmpty(
      <dynamic>[
        row['type'],
        row['message_type'],
        row['messageType'],
      ],
      'text',
    ).toLowerCase();
    final type = rawType == 'image' || rawType == 'system' ? rawType : 'text';
    final imageUrl = resolvePublicMediaUrl(
      firstNonEmpty(
        <dynamic>[
          row['image_url'],
          row['imageUrl'],
          row['media_url'],
          row['mediaUrl'],
          row['attachment_url'],
          row['attachmentUrl'],
        ],
      ),
      categoryHint: 'chats',
    );

    final clientMessageId = firstNonEmpty(
      <dynamic>[
        row['client_message_id'],
        row['clientMessageId'],
      ],
    );

    return ChatMessage(
      id: row['id']?.toString() ?? '',
      chatId: (row['chat_id'] ?? row['chatId'] ?? '').toString(),
      senderId: (row['sender_id'] ?? row['senderId'] ?? '').toString(),
      text: firstNonEmpty(
        <dynamic>[
          row['text'],
          row['body'],
          row['content'],
          row['message'],
        ],
      ),
      type: type,
      status: (row['status'] ??
              (row['read_at'] != null || row['readAt'] != null
                  ? 'read'
                  : (row['delivered_at'] != null || row['deliveredAt'] != null)
                      ? 'delivered'
                      : 'sent'))
          .toString()
          .toLowerCase(),
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
      createdAt: parseDt(row['created_at'] ?? row['createdAt']),
      updatedAt: parseNullableDt(row['updated_at'] ?? row['updatedAt']),
      deliveredAt: parseNullableDt(row['delivered_at'] ?? row['deliveredAt']),
      readAt: parseNullableDt(row['read_at'] ?? row['readAt']),
      clientMessageId: clientMessageId.isEmpty ? null : clientMessageId,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? text,
    String? type,
    String? status,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deliveredAt,
    DateTime? readAt,
    String? clientMessageId,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      type: type ?? this.type,
      status: status ?? this.status,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      clientMessageId: clientMessageId ?? this.clientMessageId,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'chat_id': chatId,
      'sender_id': senderId,
      'text': text,
      'image_url': imageUrl,
      'created_at': createdAt.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
    };
  }
}
