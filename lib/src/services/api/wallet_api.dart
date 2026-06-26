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
}
