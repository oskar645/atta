import 'dart:typed_data';

import 'package:atta/src/services/api/api_client.dart';

class SupportApi {
  const SupportApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> listMyTickets() async {
    final response = await _client.get('/support/tickets', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createTicket({
    required String name,
    String text = '',
    String? imageUrl,
  }) async {
    final normalizedText = text.trim();
    final response = await _client.post(
      '/support/tickets',
      authorized: true,
      body: {
        'name': name,
        if (normalizedText.isNotEmpty) 'text': normalizedText,
        if ((imageUrl ?? '').trim().isNotEmpty) 'image_url': imageUrl,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createBlockAppeal({
    required String text,
    String? imageUrl,
  }) async {
    final response = await _client.post(
      '/support/block-appeals',
      authorized: true,
      body: {
        if (text.trim().isNotEmpty) 'text': text.trim(),
        if ((imageUrl ?? '').trim().isNotEmpty) 'image_url': imageUrl,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getTicket(String ticketId) async {
    final response =
        await _client.get('/support/tickets/$ticketId', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> sendMessage({
    required String ticketId,
    String text = '',
    String? imageUrl,
  }) async {
    final normalizedText = text.trim();
    final response = await _client.post(
      '/support/tickets/$ticketId/messages',
      authorized: true,
      body: {
        if (normalizedText.isNotEmpty) 'text': normalizedText,
        if ((imageUrl ?? '').trim().isNotEmpty) 'image_url': imageUrl,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    String? ticketId,
  }) async {
    final response = await _client.postMultipart(
      (ticketId ?? '').trim().isEmpty
          ? '/support/images'
          : '/support/images?ticketId=${Uri.encodeQueryComponent(ticketId!.trim())}',
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> adminList({int? limit, String? cursor}) async {
    final response = await _client.get(
      '/admin/support',
      authorized: true,
      queryParameters: {
        if (limit != null) 'limit': limit,
        if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> adminTicket(String ticketId) async {
    final response =
        await _client.get('/admin/support/$ticketId', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> adminSendMessage({
    required String ticketId,
    String text = '',
    String? imageUrl,
  }) async {
    final normalizedText = text.trim();
    final response = await _client.post(
      '/admin/support/$ticketId/messages',
      authorized: true,
      body: {
        if (normalizedText.isNotEmpty) 'text': normalizedText,
        if ((imageUrl ?? '').trim().isNotEmpty) 'image_url': imageUrl,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> adminClose(String ticketId) async {
    final response = await _client.patch(
      '/admin/support/$ticketId/close',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> adminContactUser({
    required String userId,
    String? name,
    required String subject,
    required String text,
  }) async {
    final response = await _client.post(
      '/admin/support/contact-user',
      authorized: true,
      body: {
        'user_id': userId,
        if ((name ?? '').trim().isNotEmpty) 'name': name!.trim(),
        'subject': subject.trim(),
        'text': text.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
