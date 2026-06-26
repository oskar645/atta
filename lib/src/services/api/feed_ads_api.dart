import 'package:atta/src/services/api/api_client.dart';

class FeedAdsApi {
  const FeedAdsApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> list({String placement = 'home'}) async {
    final response = await _client.get(
      '/feed-ads',
      queryParameters: {'placement': placement},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> active({String placement = 'home'}) async {
    final response = await _client.get(
      '/feed-ads/active',
      queryParameters: {'placement': placement},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> adminList({String placement = 'home'}) async {
    final response = await _client.get(
      '/admin/feed-ads',
      authorized: true,
      queryParameters: {'placement': placement},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    final response = await _client.post(
      '/admin/feed-ads',
      authorized: true,
      body: body,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.patch(
      '/admin/feed-ads/$id',
      authorized: true,
      body: body,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> activate(String id) async {
    final response = await _client.post(
      '/admin/feed-ads/$id/activate',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> deactivate(String id) async {
    final response = await _client.post(
      '/admin/feed-ads/$id/deactivate',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> remove(String id) async {
    final response = await _client.delete(
      '/admin/feed-ads/$id',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> recordImpression(String id) async {
    final response = await _client.post(
      '/feed-ads/$id/impression',
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> recordClick(String id) async {
    final response = await _client.post(
      '/feed-ads/$id/click',
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
