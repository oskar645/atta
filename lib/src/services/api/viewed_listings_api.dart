import 'package:atta/src/services/api/api_client.dart';

class ViewedListingsApi {
  const ViewedListingsApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> list() async {
    final response = await _client.get('/viewed-listings', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> mark(String listingId) async {
    final response = await _client.post(
      '/viewed-listings/$listingId',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
