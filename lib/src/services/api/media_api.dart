import 'dart:typed_data';

import 'package:atta/src/services/api/api_client.dart';

class MediaApi {
  const MediaApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final response = await _client.postMultipart(
      '/media/avatar',
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> uploadListingPhoto({
    required String listingId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    int? sortOrder,
  }) async {
    final response = await _client.postMultipart(
      '/media/listings/$listingId/photos',
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      fields: sortOrder == null
          ? null
          : <String, String>{
              'sort_order': '$sortOrder',
              'sortOrder': '$sortOrder',
            },
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> deleteListingPhoto({
    required String listingId,
    required String photoId,
  }) async {
    final response = await _client.delete(
      '/media/listings/$listingId/photos/$photoId',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> uploadChatImage({
    required String chatId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final response = await _client.postMultipart(
      '/media/chats/$chatId/images',
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> uploadFeedAdImage({
    required String feedAdId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final response = await _client.postMultipart(
      '/media/feed-ads/$feedAdId/image',
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
