import 'package:atta/src/services/api/api_client.dart';

class InAppNotificationsApi {
  const InAppNotificationsApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> list() async {
    final response = await _client.get('/notifications', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> markRead(String notificationId) async {
    final response = await _client.patch(
      '/notifications/$notificationId/read',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> markAllRead() async {
    final response = await _client.patch(
      '/notifications/read-all',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> markAllSeen() async {
    final response = await _client.patch(
      '/notifications/seen-all',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> deleteById(String notificationId) async {
    final response = await _client.delete(
      '/notifications/$notificationId',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> sendUser({
    required String userId,
    String? title,
    String? body,
    String type = 'update',
    Map<String, dynamic>? payload,
  }) async {
    final response = await _client.post(
      '/admin/notifications/send-user',
      authorized: true,
      body: {
        'user_id': userId,
        if (title != null) 'title': title,
        if (body != null) 'body': body,
        'type': type,
        if (payload != null) 'payload': payload,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> sendAll({
    String? title,
    String? body,
    String type = 'update',
    Map<String, dynamic>? payload,
  }) async {
    final response = await _client.post(
      '/admin/notifications/send-all',
      authorized: true,
      body: {
        if (title != null) 'title': title,
        if (body != null) 'body': body,
        'type': type,
        if (payload != null) 'payload': payload,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
