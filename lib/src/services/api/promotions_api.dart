import 'package:atta/src/services/api/api_client.dart';

class PromotionsApi {
  const PromotionsApi(this.client);

  final ApiClient client;

  Future<Map<String, dynamic>> getPlans() async {
    final response = await client.get('/promotions/plans');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> promoteListing(
    String listingId,
    String type, {
    int days = 1,
    String? idempotencyKey,
  }) async {
    final response = await client.post(
      '/listings/$listingId/promotions',
      authorized: true,
      body: {
        'type': type,
        if (type == 'bump' || type == 'showcase' || type == 'vip') 'days': days,
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getListingPromotions(String listingId) async {
    final response = await client.get(
      '/listings/$listingId/promotions',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
