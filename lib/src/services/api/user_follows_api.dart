import 'package:atta/src/services/api/api_client.dart';

class UserFollowsApi {
  const UserFollowsApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> list() async {
    final response = await _client.get('/user-follows', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> follow(String sellerId) async {
    final response = await _client.post(
      '/user-follows/$sellerId',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> unfollow(String sellerId) async {
    final response = await _client.delete(
      '/user-follows/$sellerId',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> countFollowers(String sellerId) async {
    final response = await _client.get(
      '/user-follows/seller/$sellerId/count',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
