import 'package:atta/src/services/api/api_client.dart';

class SavedSearchesApi {
  const SavedSearchesApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> list() async {
    final response = await _client.get('/saved-searches', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> save(Map<String, dynamic> body) async {
    final response = await _client.post(
      '/saved-searches',
      authorized: true,
      body: body,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> remove(String id) async {
    final response = await _client.delete(
      '/saved-searches/$id',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.patch(
      '/saved-searches/$id',
      authorized: true,
      body: body,
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
