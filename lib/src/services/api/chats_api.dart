import 'package:atta/src/services/api/api_client.dart';

class ChatsApi {
  const ChatsApi(this.client);

  final ApiClient client;

  Future<Map<String, dynamic>> listChats({
    int? limit,
    String? cursor,
  }) async {
    final response = await client.get(
      '/chats',
      authorized: true,
      queryParameters: {
        if (limit != null) 'limit': limit,
        if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createChat({
    required String listingId,
    required String sellerId,
  }) async {
    final response = await client.post(
      '/chats',
      authorized: true,
      body: {
        'listingId': listingId,
        'sellerId': sellerId,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getChat(String chatId) async {
    final response = await client.get('/chats/$chatId', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listMessages(
    String chatId, {
    int? limit,
    String? cursor,
  }) async {
    final response = await client.get(
      '/chats/$chatId/messages',
      authorized: true,
      queryParameters: {
        if (limit != null) 'limit': limit,
        if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String text,
    String? clientMessageId,
  }) async {
    final response = await client.post(
      '/chats/$chatId/messages',
      authorized: true,
      body: {
        'text': text,
        if (clientMessageId != null && clientMessageId.trim().isNotEmpty)
          'clientMessageId': clientMessageId.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> markChatRead(String chatId) async {
    final response = await client.post(
      '/chats/$chatId/read',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> markMessageDelivered(String messageId) async {
    final response = await client.post(
      '/messages/$messageId/delivered',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> markMessageRead(String messageId) async {
    final response = await client.post(
      '/messages/$messageId/read',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> peerBlockStatus(String chatId) async {
    final response =
        await client.get('/chats/$chatId/peer-block', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> blockPeer(String chatId) async {
    final response = await client.post(
      '/chats/$chatId/peer-block',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> unblockPeer(String chatId) async {
    final response =
        await client.delete('/chats/$chatId/peer-block', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> hideChatForMe(String chatId) async {
    final response = await client.post(
      '/chats/$chatId/hide',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> deleteChat(String chatId) async {
    final response = await client.delete('/chats/$chatId', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> deleteMessage(String messageId) async {
    final response = await client.delete(
      '/messages/$messageId',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
