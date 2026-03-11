// lib/src/models/message.dart

class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.imageUrl,
    this.deliveredAt,
    this.readAt,
  });

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

    return ChatMessage(
      id: row['id']?.toString() ?? '',
      chatId: (row['chat_id'] ?? '').toString(),
      senderId: (row['sender_id'] ?? '').toString(),
      text: (row['text'] ?? '').toString(),
      imageUrl: row['image_url']?.toString(),
      createdAt: parseDt(row['created_at']),
      deliveredAt: parseNullableDt(row['delivered_at']),
      readAt: parseNullableDt(row['read_at']),
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
