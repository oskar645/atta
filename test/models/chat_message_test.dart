import 'package:atta/src/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromMap keeps text and image aliases from backend payload', () {
    final message = ChatMessage.fromMap(<String, dynamic>{
      'id': 'message-1',
      'chatId': 'chat-1',
      'senderId': 'user-2',
      'body': 'Текст из body',
      'messageType': 'IMAGE',
      'mediaUrl': 'https://cdn.example.com/chat.jpg',
      'createdAt': '2026-06-19T10:00:00.000Z',
      'updatedAt': '2026-06-19T10:00:01.000Z',
    });

    expect(message.text, 'Текст из body');
    expect(message.type, 'image');
    expect(message.imageUrl, 'https://cdn.example.com/chat.jpg');
    expect(message.updatedAt, isNotNull);
  });
}
