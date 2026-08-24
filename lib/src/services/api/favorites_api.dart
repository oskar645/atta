import 'package:atta/src/services/api/api_client.dart';

class FavoritesApi {
  const FavoritesApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> list({int? limit, String? cursor}) async {
    final response = await _client.get(
      '/favorites',
      authorized: true,
      queryParameters: {
        if (limit != null) 'limit': limit,
        if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> add(String listingId) async {
    final response = await _client.post(
      '/favorites/$listingId',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> remove(String listingId) async {
    final response = await _client.delete(
      '/favorites/$listingId',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
