import 'package:atta/src/services/api/api_client.dart';

class ShowcaseApi {
  const ShowcaseApi(this.client);

  final ApiClient client;

  Future<Map<String, dynamic>> getShowcase() async {
    final response = await client.get('/showcase');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> recordImpression(String promotionId) async {
    final response = await client.post(
      '/showcase/$promotionId/impression',
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> recordClick(String promotionId) async {
    final response = await client.post(
      '/showcase/$promotionId/click',
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
