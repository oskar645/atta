import 'package:atta/src/services/api/api_client.dart';

class UsersApi {
  const UsersApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> me() async {
    final response = await _client.get('/users/me', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> data) async {
    final response = await _client.patch(
      '/users/me',
      authorized: true,
      body: data,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> publicProfile(String userId) async {
    final response = await _client.get('/users/public/$userId');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> adminUsersList() async {
    final response = await _client.get('/users/admin/list', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }
}
