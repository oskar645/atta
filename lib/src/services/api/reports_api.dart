import 'package:atta/src/services/api/api_client.dart';

class ReportsApi {
  const ReportsApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> create({
    required String listingId,
    required String listingOwnerId,
    required String reason,
    required String comment,
  }) async {
    final response = await _client.post(
      '/reports',
      authorized: true,
      body: {
        'listingId': listingId,
        'listingOwnerId': listingOwnerId,
        'reason': reason,
        'comment': comment,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listAdmin() async {
    final response = await _client.get('/admin/reports', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> resolve(
    String reportId, {
    String? comment,
  }) async {
    final response = await _client.patch(
      '/admin/reports/$reportId/resolve',
      authorized: true,
      body: {
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> reject(
    String reportId, {
    String? comment,
  }) async {
    final response = await _client.patch(
      '/admin/reports/$reportId/reject',
      authorized: true,
      body: {
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> reopen(String reportId) async {
    final response = await _client.patch(
      '/admin/reports/$reportId/reopen',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> hide(String reportId) async {
    final response = await _client.delete(
      '/admin/reports/$reportId',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
