import 'package:atta/src/services/api/api_client.dart';

class NotificationsApi {
  const NotificationsApi(this.client);

  final ApiClient client;

  Future<Map<String, dynamic>> registerDevice({
    required String token,
    required String platform,
    String deviceUid = '',
    String appVersion = '',
    String buildNumber = '',
    String locale = '',
  }) async {
    final response = await client.post(
      '/notifications/devices',
      authorized: true,
      body: <String, dynamic>{
        'token': token,
        'platform': platform,
        if (deviceUid.trim().isNotEmpty) 'device_uid': deviceUid.trim(),
        if (appVersion.trim().isNotEmpty) 'app_version': appVersion.trim(),
        if (buildNumber.trim().isNotEmpty) 'build_number': buildNumber.trim(),
        if (locale.trim().isNotEmpty) 'locale': locale.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> unregisterDevice({
    required String token,
  }) async {
    final response = await client.delete(
      '/notifications/devices',
      authorized: true,
      body: <String, dynamic>{
        'token': token,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
