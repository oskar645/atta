import 'package:atta/src/services/api/api_client.dart';

class WalletApi {
  const WalletApi(this.client);

  final ApiClient client;

  Future<Map<String, dynamic>> getWallet() async {
    final response = await client.get('/wallet', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getTransactions() async {
    final response = await client.get('/wallet/transactions', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> checkAccrual() async {
    final response = await client.post(
      '/wallet/accrue/check',
      authorized: true,
      body: const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> startYookassaTopUp(int amountRub) async {
    final response = await client.post(
      '/payments/yookassa/create',
      authorized: true,
      body: <String, dynamic>{
        'amountRub': amountRub,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getPaymentStatus(String paymentId) async {
    final response = await client.get(
      '/payments/$paymentId/status',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
