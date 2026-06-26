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
    String type,
  ) async {
    final response = await client.post(
      '/listings/$listingId/promotions',
      authorized: true,
      body: {
        'type': type,
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
