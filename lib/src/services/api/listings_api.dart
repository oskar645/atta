import 'package:atta/src/services/api/api_client.dart';

class ListingsApi {
  const ListingsApi(this.client);

  final ApiClient client;

  Future<Map<String, dynamic>> list({
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await client.get(
      '/listings',
      queryParameters: queryParameters,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> myListings({
    String? status,
    int? limit,
    String? cursor,
  }) async {
    final response = await client.get(
      '/listings/my',
      authorized: true,
      queryParameters: {
        if ((status ?? '').trim().isNotEmpty) 'status': status!.trim(),
        if (limit != null) 'limit': limit,
        if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> vipListings({
    int? limit,
    String? cursor,
    String? category,
  }) async {
    final response = await client.get(
      '/listings/vip',
      sendAuthIfAvailable: true,
      queryParameters: {
        if (limit != null) 'limit': limit,
        if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
        if ((category ?? '').trim().isNotEmpty) 'category': category!.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getById(String id) async {
    final response = await client.get(
      '/listings/$id',
      sendAuthIfAvailable: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    final response = await client.post(
      '/listings',
      authorized: true,
      body: body,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> body,
  ) async {
    final response = await client.patch(
      '/listings/$id',
      authorized: true,
      body: body,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> archive(
    String id, {
    String? status,
    String? note,
  }) async {
    final response = await client.post(
      '/listings/$id/archive',
      authorized: true,
      body: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> deleteListing(String id) async {
    final response = await client.delete(
      '/listings/$id',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> incrementView(
    String id, {
    String? viewerUserId,
    String? viewerDeviceId,
  }) async {
    final response = await client.post(
      '/listings/$id/view',
      sendAuthIfAvailable: true,
      body: {
        if (viewerUserId != null && viewerUserId.trim().isNotEmpty)
          'viewer_user_id': viewerUserId.trim(),
        if (viewerDeviceId != null && viewerDeviceId.trim().isNotEmpty)
          'viewer_device_id': viewerDeviceId.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
