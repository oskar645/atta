import 'package:atta/src/services/api/api_client.dart';

class ShowcaseApi {
  const ShowcaseApi(this.client);

  final ApiClient client;

  Future<Map<String, dynamic>> getShowcase({
    int? limit,
    String? cursor,
    String? category,
    String? search,
  }) async {
    final response = await client.get(
      '/showcase',
      queryParameters: {
        if (limit != null) 'limit': limit,
        if ((cursor ?? '').trim().isNotEmpty) 'cursor': cursor!.trim(),
        if ((category ?? '').trim().isNotEmpty) 'category': category!.trim(),
        if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
      },
    );
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
